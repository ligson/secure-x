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
      final message = _friendlyError(error);
      _statusMessage = message;
      if (_isUnauthorizedError(error)) {
        await _clearSessionAfterUnauthorized(message);
      }
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
      final message = _friendlyError(error);
      _statusMessage = message;
      if (_isUnauthorizedError(error)) {
        await _clearSessionAfterUnauthorized(message);
      }
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  bool _isUnauthorizedError(Object error) {
    return error is DioException && error.response?.statusCode == 401;
  }

  Future<void> _clearSessionAfterUnauthorized(String message) async {
    _stopPendingChatPolling();
    _cancelPendingChatArchiveSync();
    try {
      await _realtimeChatService.disconnect();
    } catch (error) {
      appLog('会话失效后断开实时连接失败', error);
    }

    _token = null;
    _user = null;
    _vaultKey = null;
    _folders = [];
    _fileFolders = [];
    _items = [];
    _files = [];
    _friends = [];
    _friendRemarks = {};
    _incomingFriendRequests = [];
    _outgoingFriendRequests = [];
    _chatConversations = [];
    _loadedChatConversationIds.clear();
    _loadingChatConversationIds.clear();
    _chatConversationLoadTasks.clear();
    _chatIdentity = null;
    _clearChatDeviceRegistrationCache();
    _chatFriendOnline.clear();
    _historyRequestedPeerIds.clear();
    _realtimeConfig = null;
    await _clearPersistedToken();
    _statusMessage = message;
    _markAppShellChanged();
    notifyListeners();
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
          totpSecret: data['totpSecret'] as String? ?? '',
          totpIssuer: data['totpIssuer'] as String? ?? '',
          totpAccount: data['totpAccount'] as String? ?? '',
          totpAlgorithm: data['totpAlgorithm'] as String? ?? 'SHA1',
          totpDigits: data['totpDigits'] as int? ?? 6,
          totpPeriod: data['totpPeriod'] as int? ?? 30,
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

    final friendResponse = await _apiClient.listFriends(
      baseUrl: _baseUrl,
      token: _token!,
    );
    _friendRemarks = await _decryptFriendRemarks(friendResponse.aliases);
    _friends = friendResponse.friends
        .map(
          (friend) =>
              friend.copyWith(remarkName: _friendRemarks[friend.id] ?? ''),
        )
        .toList();
    _applyFriendDisplayInfoToConversations();
    final requests = await _apiClient.listFriendRequests(
      baseUrl: _baseUrl,
      token: _token!,
    );
    _incomingFriendRequests = requests['incoming'] ?? [];
    _outgoingFriendRequests = requests['outgoing'] ?? [];
    await _refreshRealtimePresenceSnapshot(
      userIds: _friends.map((friend) => friend.id).toList(),
    );
    _markFriendsChanged();
  }

  Future<Map<String, String>> _decryptFriendRemarks(
    List<FriendAliasRecord> aliases,
  ) async {
    if (_vaultKey == null || aliases.isEmpty) {
      return {};
    }

    final remarks = <String, String>{};
    for (final alias in aliases) {
      if (alias.friendId.isEmpty || alias.payload.isEmpty) {
        continue;
      }
      try {
        final data = await _cryptoService.decryptJson(
          alias.payload,
          _vaultKey!,
        );
        final remarkName = (data['remarkName'] as String? ?? '').trim();
        if (remarkName.isNotEmpty) {
          remarks[alias.friendId] = remarkName;
        }
      } catch (error) {
        appLog('好友备注解密失败：friendId=${alias.friendId}', error);
      }
    }
    return remarks;
  }

  void _applyFriendDisplayInfoToConversations() {
    if (_chatConversations.isEmpty) {
      return;
    }
    final friendById = {for (final friend in _friends) friend.id: friend};
    _chatConversations = _chatConversations.map((conversation) {
      final updatedFriend = conversation.friend == null
          ? null
          : friendById[conversation.friend!.id] ?? conversation.friend;
      final updatedMembers = conversation.members
          .map((member) => friendById[member.id] ?? member)
          .toList();
      if (updatedFriend == conversation.friend &&
          listEquals(updatedMembers, conversation.members)) {
        return conversation;
      }
      return conversation.copyWith(
        friend: updatedFriend,
        members: updatedMembers,
      );
    }).toList();
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
    _loadedChatConversationIds.clear();
    _loadingChatConversationIds.clear();
    _chatConversationLoadTasks.clear();
    final friendById = {for (final friend in _friends) friend.id: friend};
    final incrementalLoaded = await _loadIncrementalChatArchive(friendById);
    if (!incrementalLoaded) {
      final remoteLoaded = await _mergeRemoteChatArchive(friendById);
      final localMerged = await _mergeLocalChatSnapshot(
        friendById,
        mergeAsFallback: !remoteLoaded,
      );
      final legacyMerged = !remoteLoaded && !localMerged
          ? await _mergeLegacyLocalChatSnapshot(friendById)
          : false;
      if (localMerged && remoteLoaded) {
        await _persistChatSnapshot();
      }
      if (remoteLoaded || localMerged || legacyMerged) {
        _queueAllChatConversationsForArchiveMigration();
        _scheduleChatArchiveSync(await _encryptedChatSummaryPayload());
      }
    }
    await _mergeServerGroupsIntoChatConversations();
    _sortChatConversations();
    _markChatChanged();
    unawaited(_openRealtimePeersForHistorySync());
  }

  Future<void> _persistChatSnapshot() async {
    if (_user == null || _vaultKey == null) {
      return;
    }

    final summaryEncrypted = await _encryptedChatSummaryPayload();
    await _writeLocalChatSummaryCache(summaryEncrypted);
    await _writeLoadedChatDetailCaches();
    _scheduleChatArchiveSync(summaryEncrypted);
    _sortChatConversations();
  }

  Future<File> _chatSummaryStoreFile() async {
    final directory = await _chatStoreBaseDirectory();
    return File(
      '${directory.path}/securex-$_storageNamespace/chat-summary-${_user!.id}.json',
    );
  }

  Future<File> _legacyChatStoreFile() async {
    final directory = await _chatStoreBaseDirectory();
    return File(
      '${directory.path}/securex-$_storageNamespace/chat-${_user!.id}.json',
    );
  }

  Future<Directory> _chatDetailDirectory() async {
    final directory = await _chatStoreBaseDirectory();
    return Directory(
      '${directory.path}/securex-$_storageNamespace/chat-details-${_user!.id}',
    );
  }

  Future<File> _chatDetailStoreFile(String conversationId) async {
    final directory = await _chatDetailDirectory();
    final safeId = conversationId.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]+'), '_');
    return File('${directory.path}/$safeId.json');
  }

  Future<Directory> _chatStoreBaseDirectory() async {
    final devDataDir = _devDataDir.trim();
    if (devDataDir.isEmpty || Platform.isMacOS || Platform.isIOS) {
      return getApplicationSupportDirectory();
    }
    return Directory(devDataDir);
  }

  Future<Directory?> _durableClientPreferenceDirectory() async {
    final devDataDir = _devDataDir.trim();
    if (devDataDir.isNotEmpty) {
      return Directory(devDataDir);
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA']?.trim() ?? '';
      if (appData.isNotEmpty) {
        return Directory('$appData/secure-x');
      }
      final userProfile = Platform.environment['USERPROFILE']?.trim() ?? '';
      if (userProfile.isNotEmpty) {
        return Directory('$userProfile/AppData/Roaming/secure-x');
      }
      return null;
    }
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME']?.trim() ?? '';
      if (home.isNotEmpty) {
        return Directory('$home/.secure-x');
      }
      return null;
    }
    return null;
  }

  Future<File?> _durableClientPreferenceFile() async {
    final directory = await _durableClientPreferenceDirectory();
    if (directory == null) {
      return null;
    }
    final suffix = _storageNamespace == 'default' ? '' : '-$_storageNamespace';
    return File('${directory.path}/client-prefs$suffix.json');
  }

  Future<Map<String, dynamic>> _readDurableClientPreferences() async {
    final file = await _durableClientPreferenceFile();
    if (file == null || !await file.exists()) {
      return const {};
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (error) {
      appLog('读取持久客户端配置失败', error);
    }
    return const {};
  }

  Future<void> _writeDurableClientPreferences({
    required String baseUrl,
    required String themeId,
  }) async {
    final file = await _durableClientPreferenceFile();
    if (file == null) {
      return;
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'baseUrl': baseUrl,
          'themeId': themeId,
          'updatedAt': DateTime.now().toIso8601String(),
        }),
      );
    } catch (error) {
      appLog('写入持久客户端配置失败', error);
    }
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

  Future<void> _writeLocalChatSummaryCache(String encrypted) async {
    final file = await _chatSummaryStoreFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(encrypted);
  }

  Future<void> _writeLocalChatDetailCache(
    String conversationId,
    String encrypted,
  ) async {
    final file = await _chatDetailStoreFile(conversationId);
    await file.parent.create(recursive: true);
    await file.writeAsString(encrypted);
  }

  Future<void> _writeLoadedChatDetailCaches() async {
    if (_vaultKey == null) {
      return;
    }
    for (final conversation in _chatConversations) {
      if (!_loadedChatConversationIds.contains(conversation.id)) {
        continue;
      }
      await _writeLocalChatDetailCache(
        conversation.id,
        await _cryptoService.encryptJson(
          _chatConversationSnapshotJson(
            conversation,
            conversation.archiveVersion > 0
                ? conversation.archiveVersion
                : _nextChatArchiveVersion(),
          ),
          _vaultKey!,
        ),
      );
    }
  }

  Future<bool> _mergeLocalChatSnapshot(
    Map<String, PublicUser> friendByID, {
    required bool mergeAsFallback,
  }) async {
    final file = await _chatSummaryStoreFile();
    if (!await file.exists()) {
      return false;
    }
    try {
      final encrypted = await file.readAsString();
      final data = await _cryptoService.decryptJson(encrypted, _vaultKey!);
      if (!mergeAsFallback &&
          (data['conversations'] as List<dynamic>? ?? const []).isEmpty) {
        return false;
      }
      final before = _chatConversations.fold<int>(
        0,
        (total, conversation) => total + conversation.messages.length,
      );
      _mergeChatSnapshotData(data, friendByID);
      final after = _chatConversations.fold<int>(
        0,
        (total, conversation) => total + conversation.messages.length,
      );
      return after > before;
    } catch (error) {
      appLog('本机聊天密文快照解密失败', error);
      return false;
    }
  }

  Future<bool> _mergeLegacyLocalChatSnapshot(
    Map<String, PublicUser> friendByID,
  ) async {
    final file = await _legacyChatStoreFile();
    if (!await file.exists()) {
      return false;
    }
    try {
      final encrypted = await file.readAsString();
      final data = await _cryptoService.decryptJson(encrypted, _vaultKey!);
      _mergeChatSnapshotData(data, friendByID, detailLoaded: true);
      _loadedChatConversationIds.addAll(
        _chatConversations
            .where((conversation) => conversation.id.isNotEmpty)
            .map((conversation) => conversation.id),
      );
      await _writeLocalChatSummaryCache(await _encryptedChatSummaryPayload());
      await _writeLoadedChatDetailCaches();
      return _chatConversations.isNotEmpty;
    } catch (error) {
      appLog('本机旧版聊天整包快照解密失败', error);
      return false;
    }
  }

  Future<bool> _mergeRemoteChatArchive(
    Map<String, PublicUser> friendByID,
  ) async {
    if (_token == null) {
      return false;
    }
    try {
      final archive = await _apiClient.getChatArchive(
        baseUrl: _baseUrl,
        token: _token!,
      );
      if (archive.payload.isEmpty) {
        return false;
      }
      final data = await _cryptoService.decryptJson(
        archive.payload,
        _vaultKey!,
      );
      final before = _chatConversations.fold<int>(
        0,
        (total, conversation) => total + conversation.messages.length,
      );
      _mergeChatSnapshotData(data, friendByID, detailLoaded: true);
      _loadedChatConversationIds.addAll(
        _chatConversations
            .where((conversation) => conversation.id.isNotEmpty)
            .map((conversation) => conversation.id),
      );
      await _writeLocalChatSummaryCache(await _encryptedChatSummaryPayload());
      await _writeLoadedChatDetailCaches();
      final after = _chatConversations.fold<int>(
        0,
        (total, conversation) => total + conversation.messages.length,
      );
      return after > before || _chatConversations.isNotEmpty;
    } catch (error) {
      appLog('服务端聊天归档解密失败', error);
      return false;
    }
  }

  void _mergeChatSnapshotData(
    Map<String, dynamic> data,
    Map<String, PublicUser> friendByID, {
    bool detailLoaded = false,
  }) {
    final conversations = data['conversations'] as List<dynamic>?;
    if (conversations != null) {
      for (final rawEntry in conversations) {
        _mergeConversationSnapshot(
          rawEntry as Map<String, dynamic>,
          friendByID,
          detailLoaded: detailLoaded,
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
      _upsertSnapshotConversation(
        ChatConversation(friend: friend, messages: _sortMessages(entry.value)),
        detailLoaded: detailLoaded,
      );
    }
  }

  void _mergeConversationSnapshot(
    Map<String, dynamic> entry,
    Map<String, PublicUser> friendByID, {
    int archiveVersion = 0,
    bool detailLoaded = false,
  }) {
    final isGroup = entry['isGroup'] as bool? ?? false;
    final messages =
        (entry['messages'] as List<dynamic>? ?? const [])
            .map(
              (message) =>
                  ChatMessage.fromJson(message as Map<String, dynamic>),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final snapshotArchiveVersion = archiveVersion > 0
        ? archiveVersion
        : (entry['archiveVersion'] as num?)?.toInt() ?? 0;
    if (isGroup) {
      final members = (entry['members'] as List<dynamic>? ?? const [])
          .map((member) => PublicUser.fromJson(member as Map<String, dynamic>))
          .where((member) => member.id.isNotEmpty)
          .map((member) => friendByID[member.id] ?? member)
          .toList();
      _upsertSnapshotConversation(
        ChatConversation(
          id: entry['id'] as String? ?? '',
          title: entry['title'] as String? ?? '未命名群聊',
          avatarPreset: entry['avatarPreset'] as String? ?? '',
          members: members,
          adminUserId: entry['adminUserId'] as String? ?? '',
          isGroup: true,
          groupStatus: entry['groupStatus'] as String? ?? 'active',
          isDissolved: entry['isDissolved'] as bool? ?? false,
          dissolvedByUserId: entry['dissolvedByUserId'] as String?,
          dissolvedAt: DateTime.tryParse(entry['dissolvedAt'] as String? ?? ''),
          messages: messages,
          archiveVersion: snapshotArchiveVersion,
        ),
        detailLoaded: detailLoaded,
      );
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
    _upsertSnapshotConversation(
      ChatConversation(
        friend: friend,
        id: entry['id'] as String? ?? '',
        title: snapshotFriend.displayName.isNotEmpty
            ? snapshotFriend.displayName
            : null,
        messages: messages,
        archiveVersion: snapshotArchiveVersion,
      ),
      detailLoaded: detailLoaded,
    );
  }

  Future<String> _encryptedChatSummaryPayload() async {
    final conversations = _chatConversations.map((conversation) {
      return {
        'id': conversation.id,
        'title': conversation.title,
        'avatarPreset': conversation.avatarPreset,
        'isGroup': conversation.isGroup,
        'friendId': conversation.friend?.id ?? '',
        'friend': conversation.friend?.toJson() ?? <String, dynamic>{},
        'adminUserId': conversation.adminUserId,
        'groupStatus': conversation.groupStatus,
        'isDissolved': conversation.isDissolved,
        'dissolvedByUserId': conversation.dissolvedByUserId ?? '',
        'dissolvedAt': conversation.dissolvedAt?.toIso8601String() ?? '',
        'members': conversation.members
            .map((member) => member.toJson())
            .toList(),
        'archiveVersion': conversation.archiveVersion,
        'messages': _chatConversationSummaryMessages(
          conversation,
        ).map((message) => message.toJson()).toList(),
      };
    }).toList();
    return _cryptoService.encryptJson({
      'version': 4,
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
    final conversationVersions = Map<String, int>.from(
      _pendingChatConversationVersions,
    );
    final deletedConversationIds = _pendingDeletedChatConversationIds.toList();
    final hasLegacyPayload = payload != null && payload.isNotEmpty;
    if (_token == null ||
        (!hasLegacyPayload &&
            conversationVersions.isEmpty &&
            deletedConversationIds.isEmpty)) {
      return;
    }
    _chatArchiveSyncTask = _chatArchiveSyncTask.then((_) async {
      if (conversationVersions.isNotEmpty ||
          deletedConversationIds.isNotEmpty) {
        try {
          final upserts = await _buildChatArchiveConversationUpserts(
            conversationVersions,
          );
          await _apiClient.upsertChatArchiveConversations(
            baseUrl: _baseUrl,
            token: _token!,
            conversations: upserts,
            deletedConversationIds: deletedConversationIds,
          );
          for (final entry in conversationVersions.entries) {
            if (_pendingChatConversationVersions[entry.key] == entry.value) {
              _pendingChatConversationVersions.remove(entry.key);
            }
          }
          for (final conversationId in deletedConversationIds) {
            _pendingDeletedChatConversationIds.remove(conversationId);
          }
        } catch (error) {
          appLog('会话归档增量同步失败', error);
        }
      }

      if (hasLegacyPayload) {
        try {
          await _apiClient.upsertChatArchive(
            baseUrl: _baseUrl,
            token: _token!,
            payload: payload,
            version: version,
          );
          if (_pendingChatArchivePayload == payload &&
              _pendingChatArchiveVersion == version) {
            _pendingChatArchivePayload = null;
            _pendingChatArchiveVersion = 0;
          }
        } catch (error) {
          appLog('聊天归档整包同步失败', error);
        }
      }
    });
    await _chatArchiveSyncTask;
  }

  void _cancelPendingChatArchiveSync() {
    _chatArchiveSyncTimer?.cancel();
    _chatArchiveSyncTimer = null;
    _pendingChatArchivePayload = null;
    _pendingChatArchiveVersion = 0;
    _pendingChatConversationVersions.clear();
    _pendingDeletedChatConversationIds.clear();
  }

  Future<bool> _loadIncrementalChatArchive(
    Map<String, PublicUser> friendByID,
  ) async {
    if (_token == null || _vaultKey == null) {
      return false;
    }
    try {
      final manifest = await _apiClient.getChatArchiveManifest(
        baseUrl: _baseUrl,
        token: _token!,
      );
      if (manifest.conversations.isEmpty) {
        return false;
      }
      final remoteConversationIds = <String>{};
      for (final conversation in manifest.conversations) {
        if (conversation.conversationId.isEmpty ||
            conversation.summaryPayload.isEmpty) {
          continue;
        }
        remoteConversationIds.add(conversation.conversationId);
        final data = await _cryptoService.decryptJson(
          conversation.summaryPayload,
          _vaultKey!,
        );
        _mergeConversationSnapshot(
          data,
          friendByID,
          archiveVersion: conversation.version,
          detailLoaded: false,
        );
      }
      await _mergeLocalChatSnapshot(friendByID, mergeAsFallback: false);
      for (final conversation in _chatConversations) {
        if (remoteConversationIds.contains(conversation.id)) {
          continue;
        }
        _markConversationForArchiveSync(
          conversation.id,
          forceNewVersion: conversation.archiveVersion <= 0,
        );
      }
      final encrypted = await _encryptedChatSummaryPayload();
      await _writeLocalChatSummaryCache(encrypted);
      if (_pendingChatConversationVersions.isNotEmpty ||
          _pendingDeletedChatConversationIds.isNotEmpty) {
        _scheduleChatArchiveSync(encrypted);
      }
      return true;
    } catch (error) {
      appLog('加载增量聊天归档失败，回退到整包归档', error);
      _chatConversations = [];
      _loadedChatConversationIds.clear();
      return false;
    }
  }

  Future<void> _ensureChatConversationLoaded(String conversationId) async {
    if (_token == null || _vaultKey == null || conversationId.isEmpty) {
      return;
    }
    if (_loadedChatConversationIds.contains(conversationId)) {
      return;
    }
    final existingTask = _chatConversationLoadTasks[conversationId];
    if (existingTask != null) {
      await existingTask;
      return;
    }
    _loadingChatConversationIds.add(conversationId);
    _markChatChanged();
    notifyListeners();
    final task = () async {
      final friendById = {for (final friend in _friends) friend.id: friend};
      final loadedFromLocal = await _loadChatConversationDetailFromLocal(
        conversationId,
        friendById,
      );
      if (!loadedFromLocal) {
        await _loadChatConversationDetailFromServer(conversationId, friendById);
      }
    }();
    _chatConversationLoadTasks[conversationId] = task;
    try {
      await task;
    } finally {
      _chatConversationLoadTasks.remove(conversationId);
      _loadingChatConversationIds.remove(conversationId);
      _markChatChanged();
      notifyListeners();
    }
  }

  Future<bool> _loadChatConversationDetailFromLocal(
    String conversationId,
    Map<String, PublicUser> friendById,
  ) async {
    final file = await _chatDetailStoreFile(conversationId);
    if (!await file.exists()) {
      return false;
    }
    try {
      final encrypted = await file.readAsString();
      final data = await _cryptoService.decryptJson(encrypted, _vaultKey!);
      final detailVersion = (data['archiveVersion'] as num?)?.toInt() ?? 0;
      final summaryVersion =
          _conversationById(conversationId)?.archiveVersion ?? 0;
      if (summaryVersion > 0 &&
          detailVersion > 0 &&
          detailVersion < summaryVersion) {
        return false;
      }
      _mergeConversationSnapshot(
        data,
        friendById,
        archiveVersion: detailVersion,
        detailLoaded: true,
      );
      return true;
    } catch (error) {
      appLog('本机会话详情缓存解密失败：conversationId=$conversationId', error);
      return false;
    }
  }

  Future<bool> _loadChatConversationDetailFromServer(
    String conversationId,
    Map<String, PublicUser> friendById,
  ) async {
    if (_token == null) {
      return false;
    }
    try {
      final records = await _apiClient.listChatArchiveConversations(
        baseUrl: _baseUrl,
        token: _token!,
        conversationIds: [conversationId],
      );
      if (records.isEmpty || records.first.payload.isEmpty) {
        return false;
      }
      final record = records.first;
      final existingVersion =
          _conversationById(conversationId)?.archiveVersion ?? 0;
      final staleDetail =
          existingVersion > 0 &&
          record.version > 0 &&
          record.version < existingVersion;
      final data = await _cryptoService.decryptJson(record.payload, _vaultKey!);
      _mergeConversationSnapshot(
        data,
        friendById,
        archiveVersion: record.version,
        detailLoaded: true,
      );
      if (staleDetail) {
        appLog(
          '跳过回写旧会话详情缓存：conversationId=$conversationId, serverVersion=${record.version}, localVersion=$existingVersion',
        );
      } else {
        await _writeLocalChatDetailCache(conversationId, record.payload);
      }
      return true;
    } catch (error) {
      appLog('服务端会话详情加载失败：conversationId=$conversationId', error);
      return false;
    }
  }

  void _upsertSnapshotConversation(
    ChatConversation incoming, {
    bool detailLoaded = false,
  }) {
    if (incoming.id.isEmpty) {
      return;
    }
    final conversations = [..._chatConversations];
    final index = conversations.indexWhere(
      (conversation) => conversation.id == incoming.id,
    );
    if (index < 0) {
      conversations.add(incoming);
      _chatConversations = conversations;
      if (detailLoaded) {
        _loadedChatConversationIds.add(incoming.id);
      }
      return;
    }
    final existing = conversations[index];
    final incomingOlderThanExisting =
        incoming.archiveVersion > 0 &&
        existing.archiveVersion > 0 &&
        incoming.archiveVersion < existing.archiveVersion;
    final replaceWithSummary =
        !detailLoaded &&
        incoming.archiveVersion > 0 &&
        incoming.archiveVersion >= existing.archiveVersion;
    final nextIsDissolved = existing.isDissolved || incoming.isDissolved;
    conversations[index] = existing.copyWith(
      title: incoming.title.isEmpty ? existing.title : incoming.title,
      avatarPreset: incoming.avatarPreset.isEmpty
          ? existing.avatarPreset
          : incoming.avatarPreset,
      friend: incoming.friend ?? existing.friend,
      members: incoming.isGroup
          ? _uniqueFriends([...existing.members, ...incoming.members])
          : incoming.members,
      adminUserId: incoming.adminUserId.isEmpty
          ? existing.adminUserId
          : incoming.adminUserId,
      isGroup: incoming.isGroup,
      groupStatus: nextIsDissolved ? 'dissolved' : incoming.groupStatus,
      isDissolved: nextIsDissolved,
      dissolvedByUserId:
          incoming.dissolvedByUserId ?? existing.dissolvedByUserId,
      dissolvedAt: incoming.dissolvedAt ?? existing.dissolvedAt,
      messages: detailLoaded
          ? (incomingOlderThanExisting
                ? _mergeMessages(existing.messages, incoming.messages)
                : _sortMessages(incoming.messages))
          : replaceWithSummary
          ? _sortMessages(incoming.messages)
          : _mergeMessagesReplacingCurrent(
              existing.messages,
              incoming.messages,
            ),
      archiveVersion: incomingOlderThanExisting
          ? existing.archiveVersion
          : incoming.archiveVersion > 0
          ? incoming.archiveVersion
          : existing.archiveVersion,
    );
    if (detailLoaded && incomingOlderThanExisting) {
      appLog(
        '检测到旧会话详情，已按增量合并保留新消息：conversationId=${incoming.id}, incomingVersion=${incoming.archiveVersion}, currentVersion=${existing.archiveVersion}',
      );
    }
    _chatConversations = conversations;
    if (detailLoaded) {
      _loadedChatConversationIds.add(incoming.id);
    } else if (replaceWithSummary) {
      _loadedChatConversationIds.remove(incoming.id);
    }
  }

  List<ChatMessage> _mergeMessagesReplacingCurrent(
    List<ChatMessage> current,
    List<ChatMessage> incoming,
  ) {
    final byId = {for (final message in current) message.id: message};
    for (final message in incoming) {
      byId[message.id] = message;
    }
    return _sortMessages(byId.values.toList());
  }

  void _queueAllChatConversationsForArchiveMigration() {
    for (final conversation in _chatConversations) {
      _markConversationForArchiveSync(
        conversation.id,
        forceNewVersion: conversation.archiveVersion <= 0,
      );
    }
  }

  Future<List<Map<String, dynamic>>> _buildChatArchiveConversationUpserts(
    Map<String, int> conversationVersions,
  ) async {
    final upserts = <Map<String, dynamic>>[];
    for (final entry in conversationVersions.entries) {
      await _ensureChatConversationLoaded(entry.key);
      final conversation = _conversationById(entry.key);
      if (conversation == null) {
        continue;
      }
      final version = entry.value > 0
          ? entry.value
          : (conversation.archiveVersion > 0
                ? conversation.archiveVersion
                : _nextChatArchiveVersion());
      final summaryPayload = await _cryptoService.encryptJson(
        _chatConversationSummaryJson(conversation, version),
        _vaultKey!,
      );
      final payload = await _cryptoService.encryptJson(
        _chatConversationSnapshotJson(conversation, version),
        _vaultKey!,
      );
      upserts.add({
        'conversationId': conversation.id,
        'summaryPayload': summaryPayload,
        'payload': payload,
        'version': version,
      });
    }
    return upserts;
  }

  Map<String, dynamic> _chatConversationSummaryJson(
    ChatConversation conversation,
    int archiveVersion,
  ) {
    return {
      'id': conversation.id,
      'title': conversation.title,
      'avatarPreset': conversation.avatarPreset,
      'isGroup': conversation.isGroup,
      'friendId': conversation.friend?.id ?? '',
      'friend': conversation.friend?.toJson() ?? <String, dynamic>{},
      'adminUserId': conversation.adminUserId,
      'groupStatus': conversation.groupStatus,
      'isDissolved': conversation.isDissolved,
      'dissolvedByUserId': conversation.dissolvedByUserId ?? '',
      'dissolvedAt': conversation.dissolvedAt?.toIso8601String() ?? '',
      'members': conversation.members.map((member) => member.toJson()).toList(),
      'archiveVersion': archiveVersion,
      'messages': _chatConversationSummaryMessages(
        conversation,
      ).map((message) => message.toJson()).toList(),
    };
  }

  Map<String, dynamic> _chatConversationSnapshotJson(
    ChatConversation conversation,
    int archiveVersion,
  ) {
    return {
      'id': conversation.id,
      'title': conversation.title,
      'avatarPreset': conversation.avatarPreset,
      'isGroup': conversation.isGroup,
      'friendId': conversation.friend?.id ?? '',
      'friend': conversation.friend?.toJson() ?? <String, dynamic>{},
      'adminUserId': conversation.adminUserId,
      'groupStatus': conversation.groupStatus,
      'isDissolved': conversation.isDissolved,
      'dissolvedByUserId': conversation.dissolvedByUserId ?? '',
      'dissolvedAt': conversation.dissolvedAt?.toIso8601String() ?? '',
      'members': conversation.members.map((member) => member.toJson()).toList(),
      'archiveVersion': archiveVersion,
      'messages': conversation.messages
          .map((message) => message.toJson())
          .toList(),
    };
  }

  List<ChatMessage> _chatConversationSummaryMessages(
    ChatConversation conversation,
  ) {
    final summary = <ChatMessage>[];
    final seen = <String>{};
    for (final message in conversation.messages) {
      final pending =
          message.status == 'pending' ||
          message.status == 'localOnly' ||
          message.status == 'sent';
      if (pending && seen.add(message.id)) {
        summary.add(message);
      }
    }
    final lastMessage = conversation.lastMessage;
    if (lastMessage != null && seen.add(lastMessage.id)) {
      summary.add(lastMessage);
    }
    return _sortMessages(summary);
  }

  Future<void> _deleteLocalChatDetailCache(String conversationId) async {
    final file = await _chatDetailStoreFile(conversationId);
    if (await file.exists()) {
      await file.delete();
    }
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
      var avatarPreset = secureXDefaultGroupAvatarPreset;
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
          avatarPreset = normalizeSecureXAvatarPreset(
            data['avatarPreset'] as String?,
            group: true,
          );
        } catch (error) {
          appLog('服务端群聊快照解密失败：groupId=${group.id}', error);
        }
      }
      _ensureGroupConversation(
        id: group.id,
        title: title,
        avatarPreset: avatarPreset,
        members: group.members
            .where((member) => member.id != _user!.id)
            .toList(),
        adminUserId: group.adminUserId,
        groupStatus: group.status,
        isDissolved: group.isDissolved,
        dissolvedByUserId: group.dissolvedByUserId,
        dissolvedAt: group.dissolvedAt,
        markDirty: false,
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

  Future<_ChatIdentityFallbackRecord?> _readEncryptedChatIdentityFallback(
    String userId,
  ) async {
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
      final deviceId = (data['deviceId'] as String? ?? '').trim();
      final seed = (data['seedBase64'] as String? ?? '').trim();
      if (seed.isEmpty) {
        return null;
      }
      return _ChatIdentityFallbackRecord(deviceId: deviceId, seedBase64: seed);
    } catch (error) {
      appLog('读取聊天身份本地加密兜底失败：userId=$userId', error);
      return null;
    }
  }

  Future<void> _writeEncryptedChatIdentityFallback(
    String userId,
    String deviceId,
    String seedBase64,
  ) async {
    if (_vaultKey == null ||
        deviceId.trim().isEmpty ||
        seedBase64.trim().isEmpty) {
      return;
    }
    try {
      final file = await _chatIdentityFallbackFile(userId);
      await file.parent.create(recursive: true);
      final encrypted = await _cryptoService.encryptJson({
        'version': 1,
        'deviceId': deviceId.trim(),
        'seedBase64': seedBase64.trim(),
        'updatedAt': DateTime.now().toIso8601String(),
      }, _vaultKey!);
      await file.writeAsString(encrypted);
    } catch (error) {
      appLog('写入聊天身份本地加密兜底失败：userId=$userId', error);
    }
  }

  Future<_ChatIdentityFallbackRecord?> _readRemoteChatIdentityFallback(
    String userId,
  ) async {
    final token = _token;
    if (_vaultKey == null || token == null) {
      return null;
    }
    try {
      final payload = await _apiClient.getChatDeviceRecovery(
        baseUrl: _baseUrl,
        token: token,
      );
      if (payload.trim().isEmpty) {
        return null;
      }
      final data = await _cryptoService.decryptJson(payload, _vaultKey!);
      final deviceId = (data['deviceId'] as String? ?? '').trim();
      final seed = (data['seedBase64'] as String? ?? '').trim();
      if (deviceId.isEmpty || seed.isEmpty) {
        return null;
      }
      return _ChatIdentityFallbackRecord(deviceId: deviceId, seedBase64: seed);
    } catch (error) {
      appLog('读取聊天身份服务端加密恢复包失败：userId=$userId', error);
      return null;
    }
  }

  Future<void> _writeRemoteChatIdentityFallback(
    String userId,
    String deviceId,
    String seedBase64,
  ) async {
    final token = _token;
    if (_vaultKey == null ||
        token == null ||
        userId.trim().isEmpty ||
        deviceId.trim().isEmpty ||
        seedBase64.trim().isEmpty) {
      return;
    }
    try {
      final version = DateTime.now().millisecondsSinceEpoch;
      final payload = await _cryptoService.encryptJson({
        'version': 1,
        'deviceId': deviceId.trim(),
        'seedBase64': seedBase64.trim(),
        'updatedAt': DateTime.now().toIso8601String(),
      }, _vaultKey!);
      await _apiClient.upsertChatDeviceRecovery(
        baseUrl: _baseUrl,
        token: token,
        payload: payload,
        version: version,
      );
    } catch (error) {
      appLog('写入聊天身份服务端加密恢复包失败：userId=$userId', error);
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
    if (_chatIdentity != null) {
      final identity = _chatIdentity!;
      if (registerOnServer) {
        await _registerChatDeviceIfNeeded(identity, token);
      }
      return identity;
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
    final localFallback = await _readEncryptedChatIdentityFallback(user.id);
    var identityDeviceId = existingDeviceId;
    var identitySeed = existingSeed;
    void mergeFallback(_ChatIdentityFallbackRecord? record) {
      if (record == null) {
        return;
      }
      final recordDeviceId = record.deviceId.trim();
      final recordSeed = record.seedBase64.trim();
      if (recordSeed.isEmpty) {
        return;
      }
      if ((identityDeviceId == null || identityDeviceId!.isEmpty) &&
          (identitySeed == null || identitySeed!.isEmpty)) {
        identityDeviceId = recordDeviceId.isEmpty ? null : recordDeviceId;
        identitySeed = recordSeed;
        return;
      }
      if ((identitySeed == null || identitySeed!.isEmpty) &&
          recordDeviceId.isNotEmpty &&
          recordDeviceId == identityDeviceId) {
        identitySeed = recordSeed;
      }
      if ((identityDeviceId == null || identityDeviceId!.isEmpty) &&
          recordDeviceId.isNotEmpty &&
          recordSeed == identitySeed) {
        identityDeviceId = recordDeviceId;
      }
    }

    mergeFallback(localFallback);
    if (identityDeviceId == null ||
        identityDeviceId!.isEmpty ||
        identitySeed == null ||
        identitySeed!.isEmpty) {
      mergeFallback(await _readRemoteChatIdentityFallback(user.id));
    }
    final identity = await _chatProtocol.createIdentity(
      existingDeviceId: identityDeviceId,
      existingSeedBase64: identitySeed,
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
        identitySeed == identity.seedBase64;
    if (!seedAlreadyPersisted) {
      final seedPersisted = await _writeSecureValue(
        seedKey,
        identity.seedBase64,
        allowDebugFallback: false,
        debugFallbackKey: '',
      );
      if (!seedPersisted || identitySeed != identity.seedBase64) {
        await _writeEncryptedChatIdentityFallback(
          user.id,
          identity.deviceId,
          identity.seedBase64,
        );
      }
    }
    await _writeEncryptedChatIdentityFallback(
      user.id,
      identity.deviceId,
      identity.seedBase64,
    );
    await _writeRemoteChatIdentityFallback(
      user.id,
      identity.deviceId,
      identity.seedBase64,
    );

    if (registerOnServer) {
      await _registerChatDeviceIfNeeded(identity, token);
    }
    return identity;
  }

  Future<void> _registerChatDeviceIfNeeded(
    ChatIdentityBundle identity,
    String token,
  ) async {
    if (!_shouldRegisterChatDevice(identity)) {
      return;
    }
    await _apiClient.upsertCurrentChatDevice(
      baseUrl: _baseUrl,
      token: token,
      deviceId: identity.deviceId,
      protocol: _chatProtocol.protocolId,
      protocolVersion: SecureXChatProtocolV1.schemaVersion,
      publicKey: identity.publicKeyBase64,
      appInstance: _storageNamespace,
    );
    _lastChatDeviceRegisteredAt = DateTime.now();
    _lastRegisteredChatDeviceId = identity.deviceId;
    _lastRegisteredChatPublicKey = identity.publicKeyBase64;
    final user = _user;
    if (user != null) {
      await _writeRemoteChatIdentityFallback(
        user.id,
        identity.deviceId,
        identity.seedBase64,
      );
    }
  }

  bool _shouldRegisterChatDevice(ChatIdentityBundle identity) {
    if (_lastRegisteredChatDeviceId != identity.deviceId ||
        _lastRegisteredChatPublicKey != identity.publicKeyBase64) {
      return true;
    }
    final lastRegisteredAt = _lastChatDeviceRegisteredAt;
    if (lastRegisteredAt == null) {
      return true;
    }
    return DateTime.now().difference(lastRegisteredAt) >
        const Duration(minutes: 5);
  }

  void _clearChatDeviceRegistrationCache() {
    _lastChatDeviceRegisteredAt = null;
    _lastRegisteredChatDeviceId = null;
    _lastRegisteredChatPublicKey = null;
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

class _ChatIdentityFallbackRecord {
  const _ChatIdentityFallbackRecord({
    required this.deviceId,
    required this.seedBase64,
  });

  final String deviceId;
  final String seedBase64;
}
