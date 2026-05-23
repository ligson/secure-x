// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'app_controller.dart';

extension AppControllerInternalHelpers on AppController {
  Future<void> _runBusy(Future<void> Function() action) async {
    _busy = true;
    _statusMessage = null;
    notifyListeners();

    try {
      await action();
    } catch (error) {
      _statusMessage = _friendlyError(error);
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<T> _runBusyWithResult<T>(Future<T> Function() action) async {
    _busy = true;
    _statusMessage = null;
    notifyListeners();

    try {
      return await action();
    } catch (error) {
      _statusMessage = _friendlyError(error);
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Stream<Uint8List> _readFileChunks(File file, int chunkSize) async* {
    final reader = await file.open();
    try {
      while (true) {
        final bytes = await reader.read(chunkSize);
        if (bytes.isEmpty) {
          break;
        }
        yield Uint8List.fromList(bytes);
      }
    } finally {
      await reader.close();
    }
  }

  Future<void> _loadVaultSnapshot() async {
    final snapshot = await _apiClient.exportVault(
      baseUrl: _baseUrl,
      token: _token!,
    );

    final folderRecords = (snapshot['folders'] as List<dynamic>? ?? [])
        .map((entry) => FolderRecord.fromJson(entry as Map<String, dynamic>))
        .toList();
    final fileFolderRecords = (snapshot['fileFolders'] as List<dynamic>? ?? [])
        .map(
          (entry) => FileFolderRecord.fromJson(entry as Map<String, dynamic>),
        )
        .toList();
    final itemRecords = (snapshot['items'] as List<dynamic>? ?? [])
        .map((entry) => VaultItemRecord.fromJson(entry as Map<String, dynamic>))
        .toList();
    final fileRecords = (snapshot['files'] as List<dynamic>? ?? [])
        .map(
          (entry) => StoredFileRecord.fromJson(entry as Map<String, dynamic>),
        )
        .toList();

    _folders = await Future.wait(
      folderRecords.map((folder) async {
        final data = await _cryptoService.decryptJson(
          folder.payload,
          _vaultKey!,
        );
        return DecryptedFolder(
          id: folder.id,
          name: data['name'] as String,
          version: folder.version,
          parentFolderId: folder.parentFolderId,
        );
      }),
    );

    _fileFolders = await Future.wait(
      fileFolderRecords.map((folder) async {
        final data = await _cryptoService.decryptJson(
          folder.payload,
          _vaultKey!,
        );
        return DecryptedFileFolder(
          id: folder.id,
          name: data['name'] as String,
          version: folder.version,
          parentFolderId: folder.parentFolderId,
        );
      }),
    );

    _items = (await Future.wait(
      itemRecords.where((item) => item.kind == 'login').map((item) async {
        final data = await _cryptoService.decryptJson(item.payload, _vaultKey!);
        return DecryptedLoginItem(
          id: item.id,
          title: data['title'] as String? ?? '',
          username: data['username'] as String? ?? '',
          password: data['password'] as String? ?? '',
          url: data['url'] as String? ?? '',
          note: data['note'] as String? ?? '',
          version: item.version,
          folderId: item.folderId,
        );
      }),
    )).toList();

    _files = await Future.wait(
      fileRecords.map((file) async {
        final data = await _cryptoService.decryptJson(file.payload, _vaultKey!);
        return DecryptedFileRecord(
          id: file.id,
          name: data['name'] as String,
          mimeType: data['mimeType'] as String? ?? 'application/octet-stream',
          originalSize: (data['originalSize'] as num).toInt(),
          fileKey: data['fileKey'] as String,
          cipherSize: file.cipherSize,
          version: file.version,
          chunkCipherSizes: (data['chunkCipherSizes'] as List<dynamic>? ?? [])
              .map((value) => (value as num).toInt())
              .toList(),
          folderId: file.folderId,
        );
      }),
    );
  }

  Future<void> _loadFriendsSnapshot() async {
    if (_token == null) {
      return;
    }

    _friends = await _apiClient.listFriends(baseUrl: _baseUrl, token: _token!);
    final requests = await _apiClient.listFriendRequests(
      baseUrl: _baseUrl,
      token: _token!,
    );
    _incomingFriendRequests = requests['incoming'] ?? [];
    _outgoingFriendRequests = requests['outgoing'] ?? [];
    _markFriendsChanged();
  }

  Future<void> _loadChatSnapshot() async {
    if (_user == null || _vaultKey == null) {
      return;
    }

    _realtimeConfig = await _apiClient.realtimeConfig(
      baseUrl: _baseUrl,
      token: _token!,
    );
    await _ensureRealtimeChatConnected();
    _chatConversations = [];
    final friendById = {for (final friend in _friends) friend.id: friend};
    await _mergeLocalChatSnapshot(friendById);
    await _mergeRemoteChatArchive(friendById);
    await _mergeServerGroupsIntoChatConversations();
    _sortChatConversations();
    _markChatChanged();
    unawaited(_openRealtimePeersForHistorySync());
  }

  Future<void> _persistChatSnapshot() async {
    if (_user == null || _vaultKey == null) {
      return;
    }

    final encrypted = await _encryptedChatSnapshotPayload();
    final file = await _chatStoreFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(encrypted);
    _scheduleChatArchiveSync(encrypted);
    _sortChatConversations();
  }

  Future<File> _chatStoreFile() async {
    final directory = await _chatStoreBaseDirectory();
    return File(
      '${directory.path}/securex-$_storageNamespace/chat-${_user!.id}.json',
    );
  }

  Future<Directory> _chatStoreBaseDirectory() async {
    final devDataDir = _devDataDir.trim();
    if (devDataDir.isEmpty || Platform.isMacOS || Platform.isIOS) {
      return getApplicationSupportDirectory();
    }
    return Directory(devDataDir);
  }

  String _storageKey(String key) => 'securex.$_storageNamespace.$key';

  void _sortChatConversations() {
    _chatConversations.sort((a, b) {
      final aTime =
          a.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          b.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
  }

  Future<void> _mergeLocalChatSnapshot(
    Map<String, PublicUser> friendByID,
  ) async {
    final file = await _chatStoreFile();
    if (!await file.exists()) {
      return;
    }
    try {
      final encrypted = await file.readAsString();
      final data = await _cryptoService.decryptJson(encrypted, _vaultKey!);
      _mergeChatSnapshotData(data, friendByID);
    } catch (error) {
      appLog('本机聊天密文快照解密失败', error);
    }
  }

  Future<void> _mergeRemoteChatArchive(
    Map<String, PublicUser> friendByID,
  ) async {
    if (_token == null) {
      return;
    }
    try {
      final archive = await _apiClient.getChatArchive(
        baseUrl: _baseUrl,
        token: _token!,
      );
      if (archive.payload.isEmpty) {
        return;
      }
      final data = await _cryptoService.decryptJson(
        archive.payload,
        _vaultKey!,
      );
      _mergeChatSnapshotData(data, friendByID);
    } catch (error) {
      appLog('服务端聊天归档解密失败', error);
    }
  }

  void _mergeChatSnapshotData(
    Map<String, dynamic> data,
    Map<String, PublicUser> friendByID,
  ) {
    final conversations = data['conversations'] as List<dynamic>?;
    if (conversations != null) {
      for (final rawEntry in conversations) {
        _mergeConversationSnapshot(
          rawEntry as Map<String, dynamic>,
          friendByID,
        );
      }
      return;
    }

    final messages = (data['messages'] as List<dynamic>? ?? const [])
        .map((entry) => ChatMessage.fromJson(entry as Map<String, dynamic>))
        .toList();
    final grouped = <String, List<ChatMessage>>{};
    for (final message in messages) {
      grouped.putIfAbsent(message.friendId, () => []).add(message);
    }
    for (final entry in grouped.entries) {
      final friend = friendByID[entry.key];
      if (friend == null) {
        continue;
      }
      _replaceConversationMessages(friend, (current) {
        return _mergeMessages(current, entry.value);
      });
    }
  }

  void _mergeConversationSnapshot(
    Map<String, dynamic> entry,
    Map<String, PublicUser> friendByID,
  ) {
    final isGroup = entry['isGroup'] as bool? ?? false;
    final messages =
        (entry['messages'] as List<dynamic>? ?? const [])
            .map(
              (message) =>
                  ChatMessage.fromJson(message as Map<String, dynamic>),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (isGroup) {
      final members = (entry['members'] as List<dynamic>? ?? const [])
          .map((member) => PublicUser.fromJson(member as Map<String, dynamic>))
          .where((member) => member.id.isNotEmpty)
          .map((member) => friendByID[member.id] ?? member)
          .toList();
      final conversation = _ensureGroupConversation(
        id: entry['id'] as String? ?? '',
        title: entry['title'] as String? ?? '未命名群聊',
        members: members,
        adminUserId: entry['adminUserId'] as String? ?? '',
      );
      _replaceConversationMessagesById(conversation.id, (current) {
        return _mergeMessages(current, messages);
      });
      return;
    }

    final friendId = entry['friendId'] as String? ?? '';
    final snapshotFriend = PublicUser.fromJson(
      entry['friend'] as Map<String, dynamic>? ?? <String, dynamic>{},
    );
    final friend =
        friendByID[friendId] ??
        (snapshotFriend.id.isNotEmpty ? snapshotFriend : null);
    if (friend == null) {
      return;
    }
    _replaceConversationMessages(friend, (current) {
      return _mergeMessages(current, messages);
    });
  }

  Future<String> _encryptedChatSnapshotPayload() async {
    final conversations = _chatConversations.map((conversation) {
      return {
        'id': conversation.id,
        'title': conversation.title,
        'isGroup': conversation.isGroup,
        'friendId': conversation.friend?.id ?? '',
        'friend': conversation.friend?.toJson() ?? <String, dynamic>{},
        'adminUserId': conversation.adminUserId,
        'members': conversation.members
            .map((member) => member.toJson())
            .toList(),
        'messages': conversation.messages
            .map((message) => message.toJson())
            .toList(),
      };
    }).toList();
    return _cryptoService.encryptJson({
      'version': 3,
      'conversations': conversations,
    }, _vaultKey!);
  }

  void _scheduleChatArchiveSync(String payload) {
    if (_token == null || _vaultKey == null) {
      return;
    }
    _pendingChatArchivePayload = payload;
    _pendingChatArchiveVersion = DateTime.now().millisecondsSinceEpoch;
    _chatArchiveSyncTimer?.cancel();
    _chatArchiveSyncTimer = Timer(const Duration(milliseconds: 900), () {
      _chatArchiveSyncTimer = null;
      unawaited(_flushPendingChatArchiveSync());
    });
  }

  Future<void> _flushPendingChatArchiveSync() async {
    _chatArchiveSyncTimer?.cancel();
    _chatArchiveSyncTimer = null;
    final payload = _pendingChatArchivePayload;
    final version = _pendingChatArchiveVersion;
    if (_token == null || payload == null || payload.isEmpty) {
      return;
    }
    _pendingChatArchivePayload = null;
    _pendingChatArchiveVersion = 0;
    _chatArchiveSyncTask = _chatArchiveSyncTask.then((_) async {
      try {
        await _apiClient.upsertChatArchive(
          baseUrl: _baseUrl,
          token: _token!,
          payload: payload,
          version: version,
        );
      } catch (error) {
        appLog('聊天归档同步失败', error);
      }
    });
    await _chatArchiveSyncTask;
  }

  void _cancelPendingChatArchiveSync() {
    _chatArchiveSyncTimer?.cancel();
    _chatArchiveSyncTimer = null;
    _pendingChatArchivePayload = null;
    _pendingChatArchiveVersion = 0;
  }

  Future<void> _mergeServerGroupsIntoChatConversations() async {
    if (_token == null || _vaultKey == null || _user == null) {
      return;
    }

    final groups = await _apiClient.listGroups(
      baseUrl: _baseUrl,
      token: _token!,
    );
    final serverGroupIDs = groups.map((group) => group.id).toSet();
    _chatConversations = _chatConversations
        .where(
          (conversation) =>
              !conversation.isGroup || serverGroupIDs.contains(conversation.id),
        )
        .toList();

    for (final group in groups) {
      var title = '未命名群聊';
      if (group.snapshotPayload.isNotEmpty) {
        try {
          final data = await _cryptoService.decryptJson(
            group.snapshotPayload,
            _vaultKey!,
          );
          final value = (data['title'] as String? ?? '').trim();
          if (value.isNotEmpty) {
            title = value;
          }
        } catch (error) {
          appLog('服务端群聊快照解密失败：groupId=${group.id}', error);
        }
      }
      _ensureGroupConversation(
        id: group.id,
        title: title,
        members: group.members
            .where((member) => member.id != _user!.id)
            .toList(),
        adminUserId: group.adminUserId,
      );
    }
    _sortChatConversations();
  }

  bool get _supportsDebugTokenFallback => !kReleaseMode && Platform.isMacOS;

  bool get _supportsDebugSecretFallback => !kReleaseMode && Platform.isMacOS;

  Future<String?> _readPersistedToken(SharedPreferences? prefs) async {
    return _readSecureValue(
      _storageKey(AppController._tokenKey),
      prefs: prefs,
      allowDebugFallback: _supportsDebugTokenFallback,
      debugFallbackKey: _storageKey(AppController._debugTokenFallbackKey),
    );
  }

  Future<bool> _persistToken(String token) async {
    return _writeSecureValue(
      _storageKey(AppController._tokenKey),
      token,
      allowDebugFallback: _supportsDebugTokenFallback,
      debugFallbackKey: _storageKey(AppController._debugTokenFallbackKey),
    );
  }

  Future<void> _clearPersistedToken() async {
    await _deleteSecureValue(
      _storageKey(AppController._tokenKey),
      allowDebugFallback: _supportsDebugTokenFallback,
      debugFallbackKey: _storageKey(AppController._debugTokenFallbackKey),
    );
  }

  Future<String?> _readSecureValue(
    String key, {
    SharedPreferences? prefs,
    required bool allowDebugFallback,
    required String debugFallbackKey,
  }) async {
    try {
      final secureValue = await _secureStorage.read(key: key);
      if (secureValue != null && secureValue.isNotEmpty) {
        return secureValue;
      }
    } catch (error) {
      appLog('读取系统安全存储失败：$key', error);
    }

    if (allowDebugFallback) {
      final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
      return resolvedPrefs.getString(debugFallbackKey);
    }

    return null;
  }

  Future<File> _chatIdentityFallbackFile(String userId) async {
    final directory = await _chatStoreBaseDirectory();
    return File(
      '${directory.path}/securex-$_storageNamespace/chat-identity-$userId.json',
    );
  }

  Future<String?> _readEncryptedChatIdentitySeedFallback(String userId) async {
    if (_vaultKey == null) {
      return null;
    }
    try {
      final file = await _chatIdentityFallbackFile(userId);
      if (!await file.exists()) {
        return null;
      }
      final encrypted = await file.readAsString();
      if (encrypted.trim().isEmpty) {
        return null;
      }
      final data = await _cryptoService.decryptJson(encrypted, _vaultKey!);
      final seed = (data['seedBase64'] as String? ?? '').trim();
      return seed.isEmpty ? null : seed;
    } catch (error) {
      appLog('读取聊天身份种子本地加密兜底失败：userId=$userId', error);
      return null;
    }
  }

  Future<void> _writeEncryptedChatIdentitySeedFallback(
    String userId,
    String seedBase64,
  ) async {
    if (_vaultKey == null || seedBase64.trim().isEmpty) {
      return;
    }
    try {
      final file = await _chatIdentityFallbackFile(userId);
      await file.parent.create(recursive: true);
      final encrypted = await _cryptoService.encryptJson({
        'version': 1,
        'seedBase64': seedBase64.trim(),
      }, _vaultKey!);
      await file.writeAsString(encrypted);
    } catch (error) {
      appLog('写入聊天身份种子本地加密兜底失败：userId=$userId', error);
    }
  }

  Future<bool> _writeSecureValue(
    String key,
    String value, {
    required bool allowDebugFallback,
    required String debugFallbackKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _secureStorage.write(key: key, value: value);
      if (allowDebugFallback) {
        await prefs.remove(debugFallbackKey);
      }
      return true;
    } catch (error) {
      appLog('写入系统安全存储失败：$key', error);
      if (allowDebugFallback) {
        await prefs.setString(debugFallbackKey, value);
        return true;
      }
      return false;
    }
  }

  Future<void> _deleteSecureValue(
    String key, {
    required bool allowDebugFallback,
    required String debugFallbackKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _secureStorage.delete(key: key);
    } catch (error) {
      appLog('删除系统安全存储失败：$key', error);
    }
    if (allowDebugFallback) {
      await prefs.remove(debugFallbackKey);
    }
  }

  String _chatDeviceStorageKeyForUser(String userId) =>
      _storageKey('${AppController._chatDeviceIdKey}.$userId');

  String _chatIdentitySeedStorageKeyForUser(String userId) =>
      _storageKey('${AppController._chatIdentitySeedKey}.$userId');

  Future<ChatIdentityBundle?> _ensureChatIdentity({
    bool registerOnServer = false,
  }) async {
    final user = _user;
    final token = _token;
    if (user == null || token == null) {
      return null;
    }
    if (_chatIdentity != null && !registerOnServer) {
      return _chatIdentity;
    }

    final deviceKey = _chatDeviceStorageKeyForUser(user.id);
    final seedKey = _chatIdentitySeedStorageKeyForUser(user.id);
    final existingDeviceId = await _readSecureValue(
      deviceKey,
      allowDebugFallback: _supportsDebugSecretFallback,
      debugFallbackKey: _storageKey(
        '${AppController._debugSecretFallbackPrefix}.$deviceKey',
      ),
    );
    final existingSeed = await _readSecureValue(
      seedKey,
      allowDebugFallback: false,
      debugFallbackKey: '',
    );
    final fallbackSeed =
        existingSeed ?? await _readEncryptedChatIdentitySeedFallback(user.id);
    final identity = await _chatProtocol.createIdentity(
      existingDeviceId: existingDeviceId,
      existingSeedBase64: fallbackSeed,
    );
    _chatIdentity = identity;

    if (existingDeviceId != identity.deviceId) {
      await _writeSecureValue(
        deviceKey,
        identity.deviceId,
        allowDebugFallback: _supportsDebugSecretFallback,
        debugFallbackKey: _storageKey(
          '${AppController._debugSecretFallbackPrefix}.$deviceKey',
        ),
      );
    }
    final seedAlreadyPersisted =
        existingSeed == identity.seedBase64 ||
        fallbackSeed == identity.seedBase64;
    if (!seedAlreadyPersisted) {
      final seedPersisted = await _writeSecureValue(
        seedKey,
        identity.seedBase64,
        allowDebugFallback: false,
        debugFallbackKey: '',
      );
      if (!seedPersisted || fallbackSeed != identity.seedBase64) {
        await _writeEncryptedChatIdentitySeedFallback(
          user.id,
          identity.seedBase64,
        );
      }
    }

    if (registerOnServer) {
      await _apiClient.upsertCurrentChatDevice(
        baseUrl: _baseUrl,
        token: token,
        deviceId: identity.deviceId,
        protocol: _chatProtocol.protocolId,
        protocolVersion: SecureXChatProtocolV1.schemaVersion,
        publicKey: identity.publicKeyBase64,
        appInstance: _storageNamespace,
      );
    }
    return identity;
  }

  String _normalizeBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String? parentFolderIDOrNull(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['message'] is String) {
        final message = (data['message'] as String).trim();
        if (message.isNotEmpty) {
          return _localizedServerMessage(message);
        }
      }
      if (error.type == DioExceptionType.connectionError) {
        return '无法连接到 $_baseUrl，请确认后端已启动完成，并检查该地址的 /healthz 是否可访问。';
      }
      if (error.type == DioExceptionType.connectionTimeout) {
        return '连接 $_baseUrl 超时，请确认后端正在运行。';
      }
      if (error.type == DioExceptionType.receiveTimeout) {
        return '后端响应超时，请稍后重试。';
      }
      if (error.type == DioExceptionType.badCertificate) {
        return '后端证书校验失败，请检查后端地址或证书配置。';
      }
      if (error.response != null) {
        return '请求失败，请稍后重试。';
      }
      return '网络请求失败，请检查后端地址和网络连接。';
    }
    if (error is SecretBoxAuthenticationError ||
        error is FormatException ||
        error is TypeError) {
      return '解锁密码不正确，无法解锁保险库。';
    }
    if (error is PlatformException) {
      final message = error.message ?? error.details?.toString() ?? '';
      if (message.contains('required entitlement isn\'t present') ||
          error.code.contains('-34018')) {
        return 'macOS 安全存储权限暂未就绪，当前会话仍可使用；如果重启后仍复现，请重新启动应用。';
      }
      return '本地平台能力调用失败，请稍后重试。';
    }
    return '操作失败，请稍后重试。';
  }

  String _localizedServerMessage(String message) {
    switch (message) {
      case 'invalid credentials':
        return '用户名、邮箱或登录密码不正确';
      case 'user already exists':
        return '用户名或邮箱已被使用';
      case 'missing authorization header':
        return '请先登录';
      case 'invalid authorization header':
        return '登录凭证格式不正确';
      case 'invalid token':
        return '登录状态已失效，请重新登录';
      default:
        return message;
    }
  }
}
