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
  }

  Future<void> _loadChatSnapshot() async {
    if (_user == null || _vaultKey == null) {
      return;
    }

    _realtimeConfig = await _apiClient.realtimeConfig(
      baseUrl: _baseUrl,
      token: _token!,
    );
    await _connectRealtimeChat();

    final file = await _chatStoreFile();
    if (!await file.exists()) {
      _chatConversations = [];
      unawaited(_openRealtimePeersForHistorySync());
      return;
    }

    try {
      final encrypted = await file.readAsString();
      final data = await _cryptoService.decryptJson(encrypted, _vaultKey!);
      final friendById = {for (final friend in _friends) friend.id: friend};

      final conversations = data['conversations'] as List<dynamic>?;
      if (conversations != null) {
        _chatConversations = conversations
            .map((entry) => entry as Map<String, dynamic>)
            .map((entry) {
              final isGroup = entry['isGroup'] as bool? ?? false;
              final messages =
                  (entry['messages'] as List<dynamic>? ?? const [])
                      .map(
                        (message) => ChatMessage.fromJson(
                          message as Map<String, dynamic>,
                        ),
                      )
                      .toList()
                    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
              if (isGroup) {
                final members = (entry['members'] as List<dynamic>? ?? const [])
                    .map(
                      (member) =>
                          PublicUser.fromJson(member as Map<String, dynamic>),
                    )
                    .where((member) => friendById.containsKey(member.id))
                    .map((member) => friendById[member.id]!)
                    .toList();
                return ChatConversation(
                  id: entry['id'] as String? ?? '',
                  title: entry['title'] as String? ?? '未命名群聊',
                  members: members,
                  adminUserId: entry['adminUserId'] as String? ?? '',
                  isGroup: true,
                  messages: messages,
                );
              }

              final friendId = entry['friendId'] as String? ?? '';
              final friend = friendById[friendId];
              if (friend == null) {
                return null;
              }
              return ChatConversation(friend: friend, messages: messages);
            })
            .whereType<ChatConversation>()
            .toList();
        _sortChatConversations();
        unawaited(_openRealtimePeersForHistorySync());
        return;
      }

      final messages = (data['messages'] as List<dynamic>? ?? [])
          .map((entry) => ChatMessage.fromJson(entry as Map<String, dynamic>))
          .toList();
      final grouped = <String, List<ChatMessage>>{};
      for (final message in messages) {
        grouped.putIfAbsent(message.friendId, () => []).add(message);
      }
      _chatConversations = grouped.entries
          .where((entry) => friendById.containsKey(entry.key))
          .map(
            (entry) => ChatConversation(
              friend: friendById[entry.key]!,
              messages: entry.value
                ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
            ),
          )
          .toList();
      _sortChatConversations();
      unawaited(_openRealtimePeersForHistorySync());
    } catch (error) {
      debugPrint('Chat snapshot decrypt failed: $error');
      _chatConversations = [];
      unawaited(_openRealtimePeersForHistorySync());
    }
  }

  Future<void> _persistChatSnapshot() async {
    if (_user == null || _vaultKey == null) {
      return;
    }

    final conversations = _chatConversations.map((conversation) {
      return {
        'id': conversation.id,
        'title': conversation.title,
        'isGroup': conversation.isGroup,
        'friendId': conversation.friend?.id ?? '',
        'adminUserId': conversation.adminUserId,
        'members': conversation.members
            .map((member) => member.toJson())
            .toList(),
        'messages': conversation.messages
            .map((message) => message.toJson())
            .toList(),
      };
    }).toList();
    final encrypted = await _cryptoService.encryptJson({
      'version': 2,
      'conversations': conversations,
    }, _vaultKey!);
    final file = await _chatStoreFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(encrypted);
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

  bool get _supportsDebugTokenFallback => !kReleaseMode && Platform.isMacOS;

  Future<String?> _readPersistedToken(SharedPreferences? prefs) async {
    try {
      final secureToken = await _secureStorage.read(
        key: _storageKey(AppController._tokenKey),
      );
      if (secureToken != null && secureToken.isNotEmpty) {
        return secureToken;
      }
    } catch (error) {
      debugPrint('Secure token read failed: $error');
    }

    if (_supportsDebugTokenFallback) {
      final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
      return resolvedPrefs.getString(
        _storageKey(AppController._debugTokenFallbackKey),
      );
    }

    return null;
  }

  Future<bool> _persistToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _secureStorage.write(
        key: _storageKey(AppController._tokenKey),
        value: token,
      );
      if (_supportsDebugTokenFallback) {
        await prefs.remove(_storageKey(AppController._debugTokenFallbackKey));
      }
      return true;
    } catch (error) {
      debugPrint('Secure token write failed: $error');
      if (_supportsDebugTokenFallback) {
        await prefs.setString(
          _storageKey(AppController._debugTokenFallbackKey),
          token,
        );
        return true;
      }
      return false;
    }
  }

  Future<void> _clearPersistedToken() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _secureStorage.delete(key: _storageKey(AppController._tokenKey));
    } catch (error) {
      debugPrint('Secure token delete failed: $error');
    }
    if (_supportsDebugTokenFallback) {
      await prefs.remove(_storageKey(AppController._debugTokenFallbackKey));
    }
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
