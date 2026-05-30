// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'app_controller.dart';

const _chatSendSoftTimeout = Duration(seconds: 9);
const _chatDispatchChunkSize = 200;
const _chatAttachmentMaxBytes = 2 * 1024 * 1024;
const _chatVideoAttachmentMaxBytes = 20 * 1024 * 1024;

extension AppControllerChatActions on AppController {
  Future<void> activateConversation(String conversationId) async {
    final id = conversationId.trim();
    if (id.isEmpty) {
      return;
    }
    _activeConversationIds.add(id);
    await _ensureChatConversationLoaded(id);
    await markConversationRead(id);
  }

  void deactivateConversation(String conversationId) {
    final id = conversationId.trim();
    if (id.isEmpty) {
      return;
    }
    _activeConversationIds.remove(id);
  }

  Future<void> markConversationRead(String conversationId) async {
    final id = conversationId.trim();
    if (id.isEmpty) {
      return;
    }
    final conversation = _conversationById(id);
    if (conversation == null) {
      return;
    }
    final hasUnread = conversation.messages.any(
      (message) => !message.sentByMe && !message.isRead,
    );
    if (!hasUnread) {
      return;
    }
    _replaceConversationMessagesById(
      id,
      (messages) => messages
          .map(
            (message) => !message.sentByMe && !message.isRead
                ? message.copyWith(isRead: true)
                : message,
          )
          .toList(),
    );
    await _persistChatSnapshot();
    notifyListeners();
  }

  Future<void> refreshRealtimeConfig() async {
    if (_token == null) {
      return;
    }

    await _runBusy(() async {
      _realtimeConfig = await _apiClient.realtimeConfig(
        baseUrl: _baseUrl,
        token: _token!,
      );
      await _ensureRealtimeChatConnected();
      _statusMessage = _realtimeConfig!.signalingEnabled
          ? '实时聊天配置已加载。'
          : '实时聊天信令暂未启用，消息会先加密缓存在当前设备，并在联网后同步到当前账号的加密归档。';
    });
  }

  Future<void> refreshChatOverview() {
    if (_token == null || _user == null || _vaultKey == null) {
      return Future.value();
    }

    _chatRefreshTask = _chatRefreshTask.then((_) async {
      try {
        await _loadFriendsSnapshot();
        _historyRequestedPeerIds.clear();
        await _loadChatSnapshot();
        await _ensureRealtimeChatConnected(forceReconnect: true);
        final identity = _chatIdentity;
        if (identity != null) {
          await _pullPendingChatMessages(expectedDeviceId: identity.deviceId);
        }
        await _openRealtimePeersForHistorySync();
        _sortChatConversations();
        _markChatChanged();
        _statusMessage = '聊天会话已刷新，已优先同步服务端加密归档。';
      } catch (error) {
        _statusMessage = _friendlyError(error);
      }
      notifyListeners();
    });
    return _chatRefreshTask;
  }

  Future<void> openChatWith(PublicUser friend) async {
    final hadConversation = _findDirectConversation(friend.id) != null;
    _ensureConversation(friend);
    if (!hadConversation) {
      notifyListeners();
    }
    unawaited(_refreshRealtimePresenceSnapshot(userIds: [friend.id]));
    unawaited(_ensureRealtimeChatConnected());
  }

  Future<ChatConversation> createGroupChat({
    required String title,
    required List<PublicUser> members,
  }) async {
    final cleanMembers = _uniqueFriends(members);
    final archiveVersion = _nextChatArchiveVersion();
    final conversation = ChatConversation(
      id: 'group-${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? '未命名群聊' : title.trim(),
      avatarPreset: secureXDefaultGroupAvatarPreset,
      members: cleanMembers,
      adminUserId: _user?.id ?? '',
      isGroup: true,
      messages: [],
      archiveVersion: archiveVersion,
    );
    _queueChatConversationSync(conversation.id, archiveVersion);
    _chatConversations = [..._chatConversations, conversation];
    _sortChatConversations();
    notifyListeners();
    try {
      await _createGroupConversationOnServer(conversation);
    } catch (_) {
      _deleteGroupConversation(conversation.id);
      notifyListeners();
      rethrow;
    }
    await _persistChatSnapshot();
    await openGroupChat(conversation.id);
    _statusMessage = '群聊已创建，群元数据已加密同步到服务端。';
    return conversation;
  }

  Future<void> openGroupChat(String conversationId) async {
    final conversation = _conversationById(conversationId);
    if (conversation == null || !conversation.isGroup) {
      return;
    }
    unawaited(
      _refreshRealtimePresenceSnapshot(
        userIds: conversation.members.map((member) => member.id).toList(),
      ),
    );
    unawaited(_ensureRealtimeChatConnected());
  }

  List<ChatMessage> chatMessagesForConversation(String conversationId) {
    final conversation = _conversationById(conversationId);
    if (conversation == null) {
      return const [];
    }
    return List.unmodifiable(conversation.messages);
  }

  Future<void> ensureChatConversationDetails(String conversationId) async {
    await _ensureChatConversationLoaded(conversationId);
  }

  Future<void> _openRealtimePeersForHistorySync() async {
    if (_token == null || _user == null || _vaultKey == null) {
      return;
    }
    await _ensureRealtimeChatConnected();
    final peers = <String, PublicUser>{
      for (final friend in _friends) friend.id: friend,
    };
    for (final conversation in _chatConversations) {
      for (final member in conversation.members) {
        peers.putIfAbsent(member.id, () => member);
      }
    }
    for (final peer in peers.values) {
      await _requestHistoryFromPeer(peer.id);
    }
  }

  Future<void> updateGroupChat({
    required String conversationId,
    String? title,
    String? avatarPreset,
    List<PublicUser>? members,
    String? adminUserId,
    bool syncServer = true,
  }) async {
    await _ensureChatConversationLoaded(conversationId);
    final conversations = [..._chatConversations];
    final index = conversations.indexWhere(
      (conversation) => conversation.id == conversationId,
    );
    if (index < 0 || !conversations[index].isGroup) {
      return;
    }
    if (conversations[index].isDissolved) {
      _statusMessage = '群聊已解散，无法继续修改群信息。';
      notifyListeners();
      return;
    }
    final currentUserId = _user?.id ?? '';
    final existingConversation = conversations[index];
    final isAdmin = existingConversation.adminUserId == currentUserId;
    final nextTitle = title?.trim();
    final nextAvatarPreset = avatarPreset == null
        ? null
        : normalizeSecureXAvatarPreset(avatarPreset, group: true);
    final nextAdminUserId = adminUserId?.trim();
    final currentMemberIds = existingConversation.members
        .map((member) => member.id)
        .where((id) => id.isNotEmpty)
        .toList();
    final nextMemberIds = (members ?? existingConversation.members)
        .map((member) => member.id)
        .where((id) => id.isNotEmpty)
        .toList();
    final addedMemberIds = nextMemberIds
        .where((id) => !currentMemberIds.contains(id))
        .toList();
    final removedMemberIds = currentMemberIds
        .where((id) => !nextMemberIds.contains(id))
        .toList();
    final titleChanged =
        nextTitle != null &&
        nextTitle.isNotEmpty &&
        nextTitle != existingConversation.title;
    final avatarChanged =
        nextAvatarPreset != null &&
        nextAvatarPreset != existingConversation.avatarPreset;
    final adminChanged =
        nextAdminUserId != null &&
        nextAdminUserId.isNotEmpty &&
        nextAdminUserId != existingConversation.adminUserId;
    if (!isAdmin && (titleChanged || avatarChanged || adminChanged)) {
      _statusMessage = '只有群管理才能修改群名称、群头像或转让群管理。';
      notifyListeners();
      return;
    }
    if (!isAdmin && removedMemberIds.isNotEmpty) {
      _statusMessage = '只有群管理才能移除群成员。';
      notifyListeners();
      return;
    }

    final archiveVersion = _nextChatArchiveVersion();
    conversations[index] = conversations[index].copyWith(
      title: title,
      avatarPreset: nextAvatarPreset,
      members: members == null ? null : _uniqueFriends(members),
      adminUserId: adminUserId,
      archiveVersion: archiveVersion,
    );
    final updatedConversation = conversations[index];
    _queueChatConversationSync(conversationId, archiveVersion);
    _chatConversations = conversations;
    _sortChatConversations();
    notifyListeners();
    if (syncServer) {
      await _updateGroupConversationOnServer(updatedConversation);
    } else {
      await _syncGroupSnapshotForConversation(updatedConversation);
    }
    if (syncServer) {
      await _notifyGroupConversationUpdated(
        before: existingConversation,
        after: updatedConversation,
        addedMemberIds: addedMemberIds,
        removedMemberIds: removedMemberIds,
        titleChanged: titleChanged,
        avatarChanged: avatarChanged,
        adminChanged: adminChanged,
      );
    }
    await _persistChatSnapshot();
  }

  Future<void> renameGroupChat({
    required String conversationId,
    required String title,
  }) async {
    final conversation = _conversationById(conversationId);
    if (conversation == null || !conversation.isGroup) {
      return;
    }
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      _statusMessage = '群名称不能为空。';
      notifyListeners();
      return;
    }
    if ((_user?.id ?? '') != conversation.adminUserId) {
      _statusMessage = '只有群管理才能修改群名称。';
      notifyListeners();
      return;
    }
    if (cleanTitle == conversation.title) {
      _statusMessage = '群名称未发生变化。';
      notifyListeners();
      return;
    }
    await updateGroupChat(conversationId: conversationId, title: cleanTitle);
    _statusMessage = '群名称已更新。';
    notifyListeners();
  }

  Future<void> changeGroupAvatar({
    required String conversationId,
    required String avatarPreset,
  }) async {
    final conversation = _conversationById(conversationId);
    if (conversation == null || !conversation.isGroup) {
      return;
    }
    final normalized = normalizeSecureXAvatarPreset(avatarPreset, group: true);
    if ((_user?.id ?? '') != conversation.adminUserId) {
      _statusMessage = '只有群管理才能修改群头像。';
      notifyListeners();
      return;
    }
    if (normalized == conversation.avatarPreset) {
      _statusMessage = '群头像未发生变化。';
      notifyListeners();
      return;
    }
    await updateGroupChat(
      conversationId: conversationId,
      avatarPreset: normalized,
    );
    _statusMessage = '群头像已更新。';
    notifyListeners();
  }

  Future<void> transferGroupAdmin({
    required String conversationId,
    required String nextAdminUserId,
  }) async {
    final conversation = _conversationById(conversationId);
    if (conversation == null || !conversation.isGroup) {
      return;
    }
    final cleanUserId = nextAdminUserId.trim();
    if (cleanUserId.isEmpty) {
      _statusMessage = '请选择新的群管理。';
      notifyListeners();
      return;
    }
    if ((_user?.id ?? '') != conversation.adminUserId) {
      _statusMessage = '只有当前群管理才能转让群管理。';
      notifyListeners();
      return;
    }
    if (cleanUserId == conversation.adminUserId) {
      _statusMessage = '新的群管理与当前一致。';
      notifyListeners();
      return;
    }
    final memberExists = conversation.members.any(
      (member) => member.id == cleanUserId,
    );
    if (!memberExists) {
      _statusMessage = '新的群管理必须是当前群成员。';
      notifyListeners();
      return;
    }
    await updateGroupChat(
      conversationId: conversationId,
      adminUserId: cleanUserId,
    );
    _statusMessage = '群管理已转让。';
    notifyListeners();
  }

  Future<void> leaveGroupChat(String conversationId) async {
    final conversation = _conversationById(conversationId);
    final currentUser = _user;
    if (conversation == null || !conversation.isGroup || currentUser == null) {
      return;
    }
    if (conversation.isDissolved) {
      _statusMessage = '群聊已解散，请使用删除会话来清理当前账号记录。';
      notifyListeners();
      return;
    }

    final remainingMembers = _uniqueFriends(conversation.members);
    final leavingAdmin = conversation.adminUserId == currentUser.id;
    final nextAdminUserId = leavingAdmin && remainingMembers.isNotEmpty
        ? remainingMembers.first.id
        : conversation.adminUserId;
    await _leaveGroupOnServer(
      conversationId: conversation.id,
      nextAdminUserId: leavingAdmin ? nextAdminUserId : null,
    );
    await _sendRealtimeGroupControl(
      conversation: conversation,
      recipients: remainingMembers,
      controlType: 'member-left',
      removedUserId: currentUser.id,
      memberIds: remainingMembers.map((member) => member.id).toList(),
      adminUserId: nextAdminUserId,
      groupAvatarPreset: conversation.avatarPreset,
    );
    _deleteGroupConversation(conversation.id);
    _statusMessage = '已退出群聊，当前账号的群消息记录已从缓存和归档中删除。';
    notifyListeners();
    await _persistChatSnapshot();
  }

  Future<void> dissolveGroupChat(String conversationId) async {
    final conversation = _conversationById(conversationId);
    final currentUser = _user;
    if (conversation == null || !conversation.isGroup || currentUser == null) {
      return;
    }
    if (conversation.isDissolved) {
      _statusMessage = '群聊已处于解散状态。';
      notifyListeners();
      return;
    }
    if (conversation.adminUserId != currentUser.id) {
      _statusMessage = '只有群管理可以解散群聊。';
      notifyListeners();
      return;
    }

    final recipients = _uniqueFriends(conversation.members);
    final response = await _apiClient.dissolveGroup(
      baseUrl: _baseUrl,
      token: _token!,
      groupId: conversation.id,
    );
    final remainingMemberIds =
        (response['memberIds'] as List<dynamic>? ?? const [])
            .map((entry) => entry.toString())
            .where((entry) => entry.isNotEmpty)
            .toList();
    await _sendRealtimeGroupControl(
      conversation: conversation,
      recipients: recipients,
      controlType: 'group-dissolved',
      removedUserId: '',
      memberIds: remainingMemberIds,
      adminUserId: conversation.adminUserId,
      groupAvatarPreset: conversation.avatarPreset,
      groupStatus: 'dissolved',
      isDissolved: true,
      dissolvedByUserId: currentUser.id,
    );
    _deleteGroupConversation(conversation.id);
    _statusMessage = '群聊已解散，当前账号的群会话与归档已删除，其他成员会看到已解散提示。';
    notifyListeners();
    await _persistChatSnapshot();
  }

  Future<void> deleteDissolvedGroupConversation(String conversationId) async {
    final conversation = _conversationById(conversationId);
    if (conversation == null || !conversation.isGroup) {
      return;
    }
    if (!conversation.isDissolved) {
      _statusMessage = '当前群聊未解散，不能直接删除群会话。';
      notifyListeners();
      return;
    }

    await _leaveGroupOnServer(conversationId: conversation.id);
    _deleteGroupConversation(conversation.id);
    _statusMessage = '已删除解散群的会话记录，当前账号不再保留该群数据。';
    notifyListeners();
    await _persistChatSnapshot();
  }

  Future<void> clearDirectChatHistory(PublicUser friend) async {
    final conversationId = friend.id.trim();
    if (conversationId.isEmpty) {
      _statusMessage = '好友信息不完整，无法清除聊天记录。';
      notifyListeners();
      return;
    }

    await _runBusy(() async {
      _chatConversations = _chatConversations
          .where(
            (conversation) =>
                conversation.id != conversationId || conversation.isGroup,
          )
          .toList();
      _loadedChatConversationIds.remove(conversationId);
      _loadingChatConversationIds.remove(conversationId);
      _chatConversationLoadTasks.remove(conversationId);
      _queueChatConversationDeletion(conversationId);
      await _deleteLocalChatDetailCache(conversationId);
      await _persistChatSnapshot();
      _sortChatConversations();
      _markChatChanged();
      _statusMessage = '已清除你与“${friend.displayName}”的聊天记录，对方记录不会受影响。';
      notifyListeners();
    });
  }

  Future<void> clearGroupChatHistory(String conversationId) async {
    final cleanConversationId = conversationId.trim();
    final conversation = _conversationById(cleanConversationId);
    if (cleanConversationId.isEmpty || conversation == null) {
      _statusMessage = '群聊不存在，无法清除聊天记录。';
      notifyListeners();
      return;
    }
    if (!conversation.isGroup) {
      _statusMessage = '当前会话不是群聊，无法使用群聊清空功能。';
      notifyListeners();
      return;
    }
    if (conversation.isDissolved) {
      _statusMessage = '群聊已解散，只能删除会话，不能再单独清空聊天记录。';
      notifyListeners();
      return;
    }

    await _runBusy(() async {
      final archiveVersion = _nextChatArchiveVersion();
      final conversations = [..._chatConversations];
      final index = conversations.indexWhere(
        (current) => current.id == cleanConversationId,
      );
      if (index < 0) {
        return;
      }
      conversations[index] = conversations[index].copyWith(
        messages: const [],
        archiveVersion: archiveVersion,
      );
      _chatConversations = conversations;
      _queueChatConversationSync(cleanConversationId, archiveVersion);
      await _deleteLocalChatDetailCache(cleanConversationId);
      await _persistChatSnapshot();
      _sortChatConversations();
      _markChatChanged();
      _statusMessage =
          '已清空你在“${conversation.displayTitle}”中的聊天记录，群成员和其他成员记录不会受影响。';
      notifyListeners();
    });
  }

  Future<String> saveChatAttachment(ChatMessage message) async {
    if (!message.hasAttachment) {
      throw StateError('message has no attachment');
    }
    final bytes = await loadChatAttachmentBytes(message);
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory('${directory.path}/secure-x-chat');
    await folder.create(recursive: true);
    final fileName = _safeChatAttachmentName(message.attachmentName);
    final output = File('${folder.path}/$fileName');
    await output.writeAsBytes(bytes, flush: true);
    _statusMessage = '附件已保存到：${output.path}';
    notifyListeners();
    return output.path;
  }

  Future<Uint8List> loadChatAttachmentBytes(ChatMessage message) {
    if (!message.hasAttachment) {
      return Future<Uint8List>.error(StateError('message has no attachment'));
    }
    final cacheKey = _chatAttachmentCacheKey(message);
    final cached = _chatAttachmentPlainBytesCache[cacheKey];
    if (cached != null) {
      return Future.value(cached);
    }
    return _chatAttachmentBytesCache.putIfAbsent(cacheKey, () async {
      if (message.attachmentDataBase64.isNotEmpty) {
        final bytes = Uint8List.fromList(
          base64Decode(message.attachmentDataBase64),
        );
        _chatAttachmentPlainBytesCache[cacheKey] = bytes;
        return bytes;
      }
      final token = _token;
      if (token == null) {
        throw StateError('not authenticated');
      }
      final cipherBytes = await _apiClient.downloadChatAttachment(
        baseUrl: _baseUrl,
        token: token,
        attachmentId: message.attachmentObjectId,
      );
      final bytes = await _cryptoService.decryptBinary(
        cipherBytes,
        Uint8List.fromList(base64Decode(message.attachmentKeyBase64)),
      );
      _chatAttachmentPlainBytesCache[cacheKey] = bytes;
      return bytes;
    });
  }

  Uint8List? cachedChatAttachmentBytes(ChatMessage message) {
    if (!message.hasAttachment) {
      return null;
    }
    return _chatAttachmentPlainBytesCache[_chatAttachmentCacheKey(message)];
  }

  String _chatAttachmentCacheKey(ChatMessage message) {
    return message.attachmentObjectId.isNotEmpty
        ? 'remote:${message.attachmentObjectId}:${message.attachmentKeyBase64}'
        : 'inline:${message.id}:${message.attachmentDataBase64.hashCode}';
  }

  Future<({String objectId, String keyBase64})?> _uploadChatAttachmentCipher({
    required Uint8List bytes,
    required List<String> allowedUserIds,
  }) async {
    final token = _token;
    if (token == null) {
      return null;
    }
    final key = _cryptoService.randomKey();
    final cipherBytes = await _cryptoService.encryptBinary(bytes, key);
    final attachment = await _apiClient.uploadChatAttachment(
      baseUrl: _baseUrl,
      token: token,
      cipherBytes: cipherBytes,
      allowedUserIds: _uniqueIds(allowedUserIds),
    );
    final objectId = attachment['id'] as String? ?? '';
    if (objectId.isEmpty) {
      return null;
    }
    return (objectId: objectId, keyBase64: base64Encode(key));
  }

  Future<void> sendLocalChatMessage({
    required PublicUser friend,
    required String text,
  }) async {
    final content = text.trim();
    if (content.isEmpty) {
      return;
    }
    await _ensureChatConversationLoaded(friend.id);

    final message = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      friendId: friend.id,
      text: content,
      sentByMe: true,
      createdAt: DateTime.now(),
      status: _realtimeConfig?.signalingEnabled == true
          ? 'pending'
          : 'localOnly',
    );
    _replaceConversationMessages(friend, (messages) => [...messages, message]);
    notifyListeners();
    await _persistChatSnapshot();

    final deliveredToChannel = await _sendRealtimeMessage(friend, message);
    _replaceMessage(
      friend,
      message.id,
      (current) => current.copyWith(
        status: deliveredToChannel ? 'sent' : current.status,
      ),
    );
    _statusMessage = deliveredToChannel
        ? '消息已通过端到端加密通道发送。'
        : '好友当前暂无可用设备，消息已加密缓存在本机，并等待同步到服务端归档。';
    notifyListeners();

    await _persistChatSnapshot();
    notifyListeners();
  }

  Future<void> sendLocalChatAttachment({
    required PublicUser friend,
    required Uint8List bytes,
    required String name,
    required String mimeType,
    required bool image,
    String attachmentType = '',
  }) async {
    if (bytes.isEmpty) {
      return;
    }
    final type = attachmentType.isEmpty
        ? (image ? 'image' : 'file')
        : attachmentType;
    final maxBytes = type == 'video'
        ? _chatVideoAttachmentMaxBytes
        : _chatAttachmentMaxBytes;
    if (bytes.length > maxBytes) {
      _statusMessage = type == 'video'
          ? '聊天视频不能超过 20MB；更大的视频请先使用文件模块加密上传。'
          : '聊天附件不能超过 2MB；大文件请先使用文件模块加密上传。';
      notifyListeners();
      return;
    }
    await _ensureChatConversationLoaded(friend.id);
    _statusMessage = '正在加密上传聊天附件...';
    notifyListeners();
    final uploaded = await _uploadChatAttachmentCipher(
      bytes: bytes,
      allowedUserIds: [friend.id],
    );
    if (uploaded == null) {
      _statusMessage = '聊天附件上传失败，请稍后重试。';
      notifyListeners();
      return;
    }

    final safeName = _safeChatAttachmentName(name, image: image);
    final label = _chatAttachmentLabel(type);
    final message = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      friendId: friend.id,
      text: '[$label] $safeName',
      sentByMe: true,
      createdAt: DateTime.now(),
      status: _realtimeConfig?.signalingEnabled == true
          ? 'pending'
          : 'localOnly',
      attachmentType: type,
      attachmentName: safeName,
      attachmentMimeType: _safeChatMimeType(mimeType, image: image),
      attachmentSize: bytes.length,
      attachmentObjectId: uploaded.objectId,
      attachmentKeyBase64: uploaded.keyBase64,
    );
    _replaceConversationMessages(friend, (messages) => [...messages, message]);
    notifyListeners();
    await _persistChatSnapshot();

    final deliveredToChannel = await _sendRealtimeMessage(friend, message);
    _replaceMessage(
      friend,
      message.id,
      (current) => current.copyWith(
        status: deliveredToChannel ? 'sent' : current.status,
      ),
    );
    _statusMessage = deliveredToChannel
        ? '附件已通过端到端加密通道发送。'
        : '好友当前暂无可用设备，附件已加密缓存在本机，并等待同步到服务端归档。';
    notifyListeners();

    await _persistChatSnapshot();
    notifyListeners();
  }

  Future<bool> sendChatCallSignal({
    required PublicUser friend,
    required String callId,
    required String action,
    required String media,
    Map<String, dynamic> payload = const {},
  }) async {
    await _ensureRealtimeChatConnected();
    if (_realtimeConfig?.signalingEnabled != true) {
      _statusMessage = '实时通道暂未建立，无法发起通话。';
      notifyListeners();
      return false;
    }
    final ok = await _realtimeChatService.sendCallSignal(
      friend: friend,
      callId: callId,
      action: action,
      media: media,
      payload: payload,
    );
    _statusMessage = ok
        ? (action == 'invite'
              ? '${media == 'video' ? '视频' : '语音'}通话邀请已发送。'
              : '通话状态已同步。')
        : '通话信令发送失败，请确认好友在线。';
    notifyListeners();
    return ok;
  }

  Future<LiveKitCallToken?> createLiveKitCallToken({
    required PublicUser friend,
    required String callId,
    required String media,
  }) async {
    final token = _token;
    if (token == null) {
      _statusMessage = '请先登录后再发起通话。';
      notifyListeners();
      return null;
    }
    try {
      final identity = await _ensureChatIdentity(registerOnServer: true);
      if (identity == null) {
        _statusMessage = '通话设备初始化失败，请重新登录后再试。';
        notifyListeners();
        return null;
      }
      final credential = await _apiClient.createLiveKitCallToken(
        baseUrl: _baseUrl,
        token: token,
        peerUserId: friend.id,
        callId: callId,
        media: media,
        deviceId: identity.deviceId,
      );
      if (credential.url.isEmpty || credential.token.isEmpty) {
        _statusMessage = '音视频通话服务暂未配置。';
        notifyListeners();
        return null;
      }
      return credential;
    } catch (error) {
      appLog('生成 LiveKit 通话凭证失败', error);
      _statusMessage = '生成通话凭证失败，请稍后重试。';
      notifyListeners();
      return null;
    }
  }

  void _handleRealtimeCallSignal(RealtimeCallSignal signal) {
    _lastCallSignal = signal;
    _markCallChanged();
    final friend = _friendById(signal.friendId);
    final name = friend?.displayName ?? '好友';
    final mediaLabel = signal.media == 'video' ? '视频' : '语音';
    final actionLabel = switch (signal.action) {
      'invite' => '发起了$mediaLabel通话邀请',
      'accept' => '已接听$mediaLabel通话',
      'reject' => '拒绝了$mediaLabel通话',
      'cancel' => '取消了$mediaLabel通话',
      'end' => '结束了$mediaLabel通话',
      'offer' => '正在建立$mediaLabel通话',
      'answer' => '正在接通$mediaLabel通话',
      _ => '发送了$mediaLabel通话状态',
    };
    _statusMessage = '$name $actionLabel';
    notifyListeners();
  }

  Future<void> sendGroupChatMessage({
    required ChatConversation conversation,
    required String text,
  }) async {
    final content = text.trim();
    if (content.isEmpty || !conversation.isGroup) {
      return;
    }
    await _ensureChatConversationLoaded(conversation.id);

    final latest = _conversationById(conversation.id) ?? conversation;
    if (latest.isDissolved) {
      _statusMessage = '群聊已解散，无法继续发送消息。';
      notifyListeners();
      return;
    }
    final message = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      friendId: latest.id,
      text: content,
      sentByMe: true,
      createdAt: DateTime.now(),
      status: _realtimeConfig?.signalingEnabled == true
          ? 'pending'
          : 'localOnly',
      senderId: _user?.id ?? '',
      senderName: _user?.displayName ?? '',
    );
    _replaceConversationMessagesById(
      latest.id,
      (messages) => [...messages, message],
    );
    notifyListeners();
    await _persistChatSnapshot();

    final sentPeerIds = await _sendRealtimeGroupMessage(latest, message);
    _replaceMessageByConversationId(latest.id, message.id, (current) {
      final updated = current.copyWith(
        sentPeerIds: _uniqueIds([...current.sentPeerIds, ...sentPeerIds]),
      );
      return updated.copyWith(status: _groupMessageStatus(latest, updated));
    });
    _statusMessage = sentPeerIds.isNotEmpty
        ? '群消息已通过端到端加密通道发送给 ${sentPeerIds.length} 个在线成员。'
        : '群成员当前暂无可用设备，消息已加密缓存在本机，并等待同步到服务端归档。';
    notifyListeners();

    await _persistChatSnapshot();
    notifyListeners();
  }

  Future<void> sendGroupChatAttachment({
    required ChatConversation conversation,
    required Uint8List bytes,
    required String name,
    required String mimeType,
    required bool image,
    String attachmentType = '',
  }) async {
    if (bytes.isEmpty || !conversation.isGroup) {
      return;
    }
    await _ensureChatConversationLoaded(conversation.id);

    final latest = _conversationById(conversation.id) ?? conversation;
    if (latest.isDissolved) {
      _statusMessage = '群聊已解散，无法继续发送附件。';
      notifyListeners();
      return;
    }
    final type = attachmentType.isEmpty
        ? (image ? 'image' : 'file')
        : attachmentType;
    final maxBytes = type == 'video'
        ? _chatVideoAttachmentMaxBytes
        : _chatAttachmentMaxBytes;
    if (bytes.length > maxBytes) {
      _statusMessage = type == 'video'
          ? '聊天视频不能超过 20MB；更大的视频请先使用文件模块加密上传。'
          : '聊天附件不能超过 2MB；大文件请先使用文件模块加密上传。';
      notifyListeners();
      return;
    }
    _statusMessage = '正在加密上传群聊附件...';
    notifyListeners();
    final uploaded = await _uploadChatAttachmentCipher(
      bytes: bytes,
      allowedUserIds: latest.members.map((member) => member.id).toList(),
    );
    if (uploaded == null) {
      _statusMessage = '群聊附件上传失败，请稍后重试。';
      notifyListeners();
      return;
    }
    final safeName = _safeChatAttachmentName(name, image: image);
    final label = _chatAttachmentLabel(type);
    final message = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      friendId: latest.id,
      text: '[$label] $safeName',
      sentByMe: true,
      createdAt: DateTime.now(),
      status: _realtimeConfig?.signalingEnabled == true
          ? 'pending'
          : 'localOnly',
      senderId: _user?.id ?? '',
      senderName: _user?.displayName ?? '',
      attachmentType: type,
      attachmentName: safeName,
      attachmentMimeType: _safeChatMimeType(mimeType, image: image),
      attachmentSize: bytes.length,
      attachmentObjectId: uploaded.objectId,
      attachmentKeyBase64: uploaded.keyBase64,
    );
    _replaceConversationMessagesById(
      latest.id,
      (messages) => [...messages, message],
    );
    notifyListeners();
    await _persistChatSnapshot();

    final sentPeerIds = await _sendRealtimeGroupMessage(latest, message);
    _replaceMessageByConversationId(latest.id, message.id, (current) {
      final updated = current.copyWith(
        sentPeerIds: _uniqueIds([...current.sentPeerIds, ...sentPeerIds]),
      );
      return updated.copyWith(status: _groupMessageStatus(latest, updated));
    });
    _statusMessage = sentPeerIds.isNotEmpty
        ? '群附件已通过端到端加密通道发送给 ${sentPeerIds.length} 个在线成员。'
        : '群成员当前暂无可用设备，附件已加密缓存在本机，并等待同步到服务端归档。';
    notifyListeners();

    await _persistChatSnapshot();
    notifyListeners();
  }

  Future<void> retryChatMessage({
    required PublicUser friend,
    required ChatMessage message,
  }) async {
    await _ensureChatConversationLoaded(friend.id);
    final retryStatus = _realtimeConfig?.signalingEnabled == true
        ? 'pending'
        : 'localOnly';
    _replaceConversationMessages(
      friend,
      (messages) => messages
          .map(
            (current) => current.id == message.id
                ? current.copyWith(
                    status: retryStatus,
                    createdAt: DateTime.now(),
                  )
                : current,
          )
          .toList(),
    );
    notifyListeners();
    await _persistChatSnapshot();

    final updated = _findMessage(friend.id, message.id) ?? message;
    final deliveredToChannel = await _sendRealtimeMessage(friend, updated);
    _replaceMessage(
      friend,
      message.id,
      (current) => current.copyWith(
        status: deliveredToChannel ? 'sent' : current.status,
      ),
    );
    _statusMessage = deliveredToChannel
        ? '消息已重新通过端到端加密通道发送。'
        : '实时通道仍未建立，消息继续保存在本机缓存，并等待后续同步。';
    notifyListeners();

    await _persistChatSnapshot();
    notifyListeners();
  }

  Future<void> retryGroupChatMessage({
    required ChatConversation conversation,
    required ChatMessage message,
  }) async {
    if (!conversation.isGroup) {
      return;
    }
    await _ensureChatConversationLoaded(conversation.id);
    final latest = _conversationById(conversation.id) ?? conversation;
    if (latest.isDissolved) {
      _statusMessage = '群聊已解散，无法重发消息。';
      notifyListeners();
      return;
    }
    final retryStatus = _realtimeConfig?.signalingEnabled == true
        ? 'pending'
        : 'localOnly';
    _replaceConversationMessagesById(
      conversation.id,
      (messages) => messages
          .map(
            (current) => current.id == message.id
                ? current.copyWith(
                    status: retryStatus,
                    createdAt: DateTime.now(),
                  )
                : current,
          )
          .toList(),
    );
    notifyListeners();
    await _persistChatSnapshot();

    final updated =
        _findMessageInConversation(conversation.id, message.id) ?? message;
    final sentPeerIds = await _sendRealtimeGroupMessage(latest, updated);
    _replaceMessageByConversationId(conversation.id, message.id, (current) {
      final next = current.copyWith(
        sentPeerIds: _uniqueIds([...current.sentPeerIds, ...sentPeerIds]),
      );
      return next.copyWith(status: _groupMessageStatus(latest, next));
    });
    _statusMessage = sentPeerIds.isNotEmpty
        ? '群消息已重新发送给 ${sentPeerIds.length} 个在线成员。'
        : '群实时通道仍未建立，消息继续保存在本机缓存，并等待后续同步。';
    notifyListeners();

    await _persistChatSnapshot();
    notifyListeners();
  }

  ChatConversation _ensureConversation(PublicUser friend) {
    for (final conversation in _chatConversations) {
      if (conversation.friend?.id == friend.id) {
        return conversation;
      }
    }

    final conversation = ChatConversation(friend: friend, messages: []);
    _chatConversations = [..._chatConversations, conversation];
    _sortChatConversations();
    _markChatChanged();
    return conversation;
  }

  void _replaceConversationMessages(
    PublicUser friend,
    List<ChatMessage> Function(List<ChatMessage> messages) update, {
    bool markDirty = true,
    int? archiveVersion,
  }) {
    final conversations = [..._chatConversations];
    final index = conversations.indexWhere(
      (conversation) => conversation.friend?.id == friend.id,
    );
    final nextArchiveVersion =
        archiveVersion ?? (markDirty ? _nextChatArchiveVersion() : 0);
    if (index < 0) {
      conversations.add(
        ChatConversation(
          friend: friend,
          messages: _sortMessages(update([])),
          archiveVersion: nextArchiveVersion,
        ),
      );
      if (markDirty) {
        _queueChatConversationSync(friend.id, nextArchiveVersion);
      }
    } else {
      final conversation = conversations[index];
      conversations[index] = conversation.copyWith(
        messages: _sortMessages(update([...conversation.messages])),
        archiveVersion: nextArchiveVersion > 0
            ? nextArchiveVersion
            : conversation.archiveVersion,
      );
      if (markDirty) {
        _queueChatConversationSync(conversations[index].id, nextArchiveVersion);
      }
    }
    _chatConversations = conversations;
    _loadedChatConversationIds.add(friend.id);
    _sortChatConversations();
    _markChatChanged();
  }

  void _replaceConversationMessagesById(
    String conversationId,
    List<ChatMessage> Function(List<ChatMessage> messages) update, {
    bool markDirty = true,
    int? archiveVersion,
  }) {
    final conversations = [..._chatConversations];
    final index = conversations.indexWhere(
      (conversation) => conversation.id == conversationId,
    );
    if (index < 0) {
      return;
    }
    final conversation = conversations[index];
    final nextArchiveVersion =
        archiveVersion ?? (markDirty ? _nextChatArchiveVersion() : 0);
    conversations[index] = conversation.copyWith(
      messages: _sortMessages(update([...conversation.messages])),
      archiveVersion: nextArchiveVersion > 0
          ? nextArchiveVersion
          : conversation.archiveVersion,
    );
    if (markDirty) {
      _queueChatConversationSync(conversationId, nextArchiveVersion);
    }
    _chatConversations = conversations;
    _loadedChatConversationIds.add(conversationId);
    _sortChatConversations();
    _markChatChanged();
  }

  List<ChatMessage> _sortMessages(List<ChatMessage> messages) {
    return messages..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> _ensureRealtimeChatConnected({bool forceReconnect = false}) {
    _realtimeConnectTask = _realtimeConnectTask.then((_) async {
      try {
        await _connectRealtimeChat(forceReconnect: forceReconnect);
      } catch (error) {
        appLog('预热聊天实时通道失败', error);
      }
    });
    return _realtimeConnectTask;
  }

  Future<void> _connectRealtimeChat({bool forceReconnect = false}) async {
    if (_token == null || _user == null) {
      return;
    }
    final identity = await _ensureChatIdentity(registerOnServer: true);
    if (identity == null) {
      return;
    }
    _realtimeConfig ??= await _apiClient.realtimeConfig(
      baseUrl: _baseUrl,
      token: _token!,
    );
    if (_realtimeConfig?.signalingEnabled != true ||
        _realtimeConfig!.signalingUrl.isEmpty) {
      return;
    }
    await _realtimeChatService.connect(
      signalingUrl: _realtimeConfig!.signalingUrl,
      token: _token!,
      userId: _user!.id,
      deviceId: identity.deviceId,
      iceServers: _realtimeConfig!.iceServers,
      forceReconnect: forceReconnect,
    );
    _ensurePendingChatPolling();
    unawaited(_pullPendingChatMessages(expectedDeviceId: identity.deviceId));
    unawaited(_flushAllPendingRealtimeMessages());
  }

  Future<bool> _sendRealtimeMessage(
    PublicUser friend,
    ChatMessage message,
  ) async {
    if (_realtimeConfig?.signalingEnabled != true) {
      return false;
    }
    try {
      return await _dispatchDirectMessage(
        friend: friend,
        message: message,
      ).timeout(_chatSendSoftTimeout);
    } on TimeoutException catch (error) {
      appLog('实时单聊发送超过 9 秒，转入后台重试', error);
      unawaited(_flushPendingRealtimeMessages(friend.id));
      return false;
    } catch (error) {
      appLog('实时单聊发送失败', error);
      return false;
    }
  }

  Future<List<String>> _sendRealtimeGroupMessage(
    ChatConversation conversation,
    ChatMessage message,
  ) async {
    if (_realtimeConfig?.signalingEnabled != true) {
      return const [];
    }
    final sentPeerIds = <String>[];
    try {
      sentPeerIds.addAll(
        await _dispatchGroupMessage(
          conversation: conversation,
          message: message,
        ).timeout(_chatSendSoftTimeout),
      );
    } on TimeoutException catch (error) {
      appLog('实时群聊发送超过 9 秒，转入后台重试', error);
      for (final member in conversation.members) {
        unawaited(_flushPendingRealtimeMessages(member.id));
      }
    } catch (error) {
      appLog('实时群聊发送失败', error);
    }
    return sentPeerIds;
  }

  Future<void> _sendRealtimeGroupControl({
    required ChatConversation conversation,
    required List<PublicUser> recipients,
    required String controlType,
    required String removedUserId,
    required List<String> memberIds,
    required String adminUserId,
    String groupAvatarPreset = '',
    String groupStatus = 'active',
    bool isDissolved = false,
    String dissolvedByUserId = '',
  }) async {
    if (_realtimeConfig?.signalingEnabled != true) {
      return;
    }
    try {
      await _dispatchGroupControl(
        conversation: conversation,
        recipients: recipients,
        controlType: controlType,
        removedUserId: removedUserId,
        memberIds: memberIds,
        adminUserId: adminUserId,
        groupAvatarPreset: groupAvatarPreset,
        groupStatus: groupStatus,
        isDissolved: isDissolved,
        dissolvedByUserId: dissolvedByUserId,
      );
    } catch (error) {
      appLog('实时群聊控制消息发送失败', error);
    }
  }

  Future<void> _notifyGroupConversationUpdated({
    required ChatConversation before,
    required ChatConversation after,
    required List<String> addedMemberIds,
    required List<String> removedMemberIds,
    required bool titleChanged,
    required bool avatarChanged,
    required bool adminChanged,
  }) async {
    final sharedChanged =
        titleChanged ||
        adminChanged ||
        addedMemberIds.isNotEmpty ||
        removedMemberIds.isNotEmpty;
    if (!sharedChanged) {
      return;
    }
    final recipientIds = _uniqueIds([
      ...before.members.map((member) => member.id),
      ...after.members.map((member) => member.id),
    ]);
    final knownRecipients = <PublicUser>[...before.members, ...after.members];
    final recipients = _uniqueFriends(
      knownRecipients
          .where((member) => recipientIds.contains(member.id))
          .toList(),
    );
    await _sendRealtimeGroupControl(
      conversation: after,
      recipients: recipients,
      controlType: 'group-updated',
      removedUserId: removedMemberIds.length == 1 ? removedMemberIds.first : '',
      memberIds: [_user?.id ?? '', ...after.members.map((member) => member.id)],
      adminUserId: after.adminUserId,
    );
  }

  Future<bool> _dispatchDirectMessage({
    required PublicUser friend,
    required ChatMessage message,
  }) async {
    final recipientMap = await _dispatchEncryptedPayloads(
      recipientUserIds: [friend.id],
      kind: 'direct-message',
      body: _chatMessagePayload(message),
    );
    return (recipientMap[friend.id] ?? 0) > 0;
  }

  Future<List<String>> _dispatchGroupMessage({
    required ChatConversation conversation,
    required ChatMessage message,
    List<String>? recipientUserIds,
  }) async {
    final memberIds =
        (recipientUserIds ??
                conversation.members.map((member) => member.id).toList())
            .where((id) => id.isNotEmpty && id != _user?.id)
            .toList();
    if (memberIds.isEmpty) {
      return const [];
    }
    final queuedByUser = await _dispatchEncryptedPayloads(
      recipientUserIds: memberIds,
      kind: 'group-message',
      body: {
        ..._chatMessagePayload(message),
        'groupId': conversation.id,
        'groupName': conversation.title,
        'groupAvatarPreset': conversation.avatarPreset,
        'memberIds': [_user?.id ?? '', ...memberIds],
        'adminUserId': conversation.adminUserId,
      },
    );
    return queuedByUser.entries
        .where((entry) => entry.value > 0)
        .map((entry) => entry.key)
        .toList();
  }

  Map<String, dynamic> _chatMessagePayload(ChatMessage message) {
    return {
      'messageId': message.id,
      'text': message.text,
      if (message.hasAttachment) ...{
        'attachmentType': message.attachmentType,
        'attachmentName': message.attachmentName,
        'attachmentMimeType': message.attachmentMimeType,
        'attachmentSize': message.attachmentSize,
        'attachmentDataBase64': message.attachmentDataBase64,
        'attachmentObjectId': message.attachmentObjectId,
        'attachmentKeyBase64': message.attachmentKeyBase64,
      },
    };
  }

  String _safeChatAttachmentName(String value, {bool image = false}) {
    final trimmed = value.trim();
    final fallback = image ? 'secure-x-image.jpg' : 'secure-x-file';
    final name = trimmed.isEmpty ? fallback : trimmed;
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '-');
    return safe.length > 120 ? safe.substring(safe.length - 120) : safe;
  }

  String _chatAttachmentLabel(String type) {
    if (type == 'image') {
      return '图片';
    }
    if (type == 'audio') {
      return '语音';
    }
    if (type == 'video') {
      return '视频';
    }
    return '文件';
  }

  String _safeChatMimeType(String value, {required bool image}) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isNotEmpty && !trimmed.contains('\n')) {
      return trimmed;
    }
    return image ? 'image/jpeg' : 'application/octet-stream';
  }

  Future<void> _dispatchGroupControl({
    required ChatConversation conversation,
    required List<PublicUser> recipients,
    required String controlType,
    required String removedUserId,
    required List<String> memberIds,
    required String adminUserId,
    String groupAvatarPreset = '',
    String groupStatus = 'active',
    bool isDissolved = false,
    String dissolvedByUserId = '',
  }) async {
    final targetIds = _uniqueFriends(recipients)
        .map((member) => member.id)
        .where((id) => id.isNotEmpty && id != _user?.id)
        .toList();
    if (targetIds.isEmpty) {
      return;
    }
    await _dispatchEncryptedPayloads(
      recipientUserIds: targetIds,
      kind: 'group-control',
      body: {
        'controlId': DateTime.now().microsecondsSinceEpoch.toString(),
        'controlType': controlType,
        'groupId': conversation.id,
        'groupName': conversation.title,
        'groupAvatarPreset': groupAvatarPreset,
        'memberIds': _uniqueIds(memberIds),
        'adminUserId': adminUserId,
        'removedUserId': removedUserId,
        'groupStatus': groupStatus,
        'isDissolved': isDissolved,
        'dissolvedByUserId': dissolvedByUserId,
      },
    );
  }

  Future<bool> _dispatchHistoryRequest(PublicUser friend) async {
    final queuedByUser = await _dispatchEncryptedPayloads(
      recipientUserIds: [friend.id],
      kind: 'history-request',
      body: {'requestId': DateTime.now().microsecondsSinceEpoch.toString()},
    );
    return (queuedByUser[friend.id] ?? 0) > 0;
  }

  Future<void> _dispatchHistoryResponse({
    required PublicUser friend,
    required String requestId,
    required List<Map<String, dynamic>> conversations,
  }) async {
    await _dispatchEncryptedPayloads(
      recipientUserIds: [friend.id],
      kind: 'history-response',
      body: {'requestId': requestId, 'conversations': conversations},
    );
  }

  Future<void> _dispatchDeliveryAck({
    required String recipientUserId,
    required String messageId,
    String groupId = '',
  }) async {
    await _dispatchEncryptedPayloads(
      recipientUserIds: [recipientUserId],
      kind: 'delivery-ack',
      body: {'messageId': messageId, 'groupId': groupId},
    );
  }

  void _sendDeliveryAckInBackground({
    required String recipientUserId,
    required String messageId,
    String groupId = '',
  }) {
    unawaited(
      _dispatchDeliveryAck(
        recipientUserId: recipientUserId,
        messageId: messageId,
        groupId: groupId,
      ).timeout(_chatSendSoftTimeout).catchError((Object error) {
        appLog('发送送达确认失败，后续待同步拉取会继续兜底', error);
      }),
    );
  }

  Future<Map<String, int>> _dispatchEncryptedPayloads({
    required List<String> recipientUserIds,
    required String kind,
    required Map<String, dynamic> body,
  }) async {
    final token = _token;
    final user = _user;
    final identity = await _ensureChatIdentity(registerOnServer: true);
    if (token == null || user == null || identity == null) {
      return const {};
    }

    final cleanUserIds = _uniqueIds(
      recipientUserIds,
    ).where((id) => id.isNotEmpty && id != user.id).toList();
    if (cleanUserIds.isEmpty) {
      return const {};
    }

    final deviceResults = await Future.wait(
      cleanUserIds.map((recipientUserId) async {
        try {
          final devices = await _apiClient.listUserChatDevices(
            baseUrl: _baseUrl,
            token: token,
            userId: recipientUserId,
          );
          return MapEntry(recipientUserId, devices);
        } catch (error) {
          appLog('加载聊天接收设备失败：recipientUserId=$recipientUserId', error);
          return MapEntry(recipientUserId, <ChatDeviceRecord>[]);
        }
      }),
    );

    final encryptionTasks = <Future<ChatOutgoingEnvelope>>[];
    for (final entry in deviceResults) {
      final supportedDevices = entry.value.where((device) {
        return device.id.isNotEmpty &&
            device.publicKey.isNotEmpty &&
            device.protocol == _chatProtocol.protocolId;
      }).toList();
      for (final device in supportedDevices) {
        encryptionTasks.add(
          _chatProtocol.encryptForDevice(
            senderIdentity: identity,
            senderUserId: user.id,
            recipientDevice: device,
            kind: kind,
            body: body,
          ),
        );
      }
    }

    if (encryptionTasks.isEmpty) {
      return const {};
    }

    final outgoing = await Future.wait(encryptionTasks);
    final outgoingByUser = <String, List<ChatOutgoingEnvelope>>{};
    for (final envelope in outgoing) {
      outgoingByUser
          .putIfAbsent(envelope.recipientUserId, () => <ChatOutgoingEnvelope>[])
          .add(envelope);
    }

    final queuedEntries = await Future.wait(
      outgoingByUser.entries.map((entry) async {
        var queuedCount = 0;
        for (
          var start = 0;
          start < entry.value.length;
          start += _chatDispatchChunkSize
        ) {
          final end = (start + _chatDispatchChunkSize).clamp(
            0,
            entry.value.length,
          );
          try {
            queuedCount += await _apiClient.dispatchChatMessages(
              baseUrl: _baseUrl,
              token: token,
              messages: entry.value.sublist(start, end),
            );
          } catch (error) {
            appLog('聊天消息入队失败：recipientUserId=${entry.key}', error);
          }
        }
        return MapEntry(entry.key, queuedCount);
      }),
    );

    final queuedByUser = <String, int>{};
    for (final entry in queuedEntries) {
      if (entry.value > 0) {
        queuedByUser[entry.key] = entry.value;
      }
    }
    return queuedByUser;
  }

  Future<void> _pullPendingChatMessages({
    String expectedDeviceId = '',
    String senderUserId = '',
  }) async {
    final token = _token;
    final identity = await _ensureChatIdentity(registerOnServer: true);
    if (token == null || identity == null) {
      return;
    }
    if (expectedDeviceId.isNotEmpty && expectedDeviceId != identity.deviceId) {
      return;
    }

    _pendingChatSyncTask = _pendingChatSyncTask.then((_) async {
      try {
        final pending = await _apiClient.listPendingChatMessages(
          baseUrl: _baseUrl,
          token: token,
          deviceId: identity.deviceId,
          senderUserId: senderUserId,
        );
        if (pending.isEmpty) {
          return;
        }
        final ackIds = await _processQueuedChatEnvelopes(
          identity: identity,
          envelopes: pending,
          senderUserId: senderUserId,
        );
        if (ackIds.isEmpty) {
          return;
        }
        await _apiClient.ackChatMessages(
          baseUrl: _baseUrl,
          token: token,
          deviceId: identity.deviceId,
          messageIds: ackIds,
        );
        if (pending.length >= 500) {
          unawaited(
            _pullPendingChatMessages(
              expectedDeviceId: identity.deviceId,
              senderUserId: senderUserId,
            ),
          );
        }
      } catch (error) {
        appLog('拉取待同步聊天消息失败', error);
      }
    });
    await _pendingChatSyncTask;
  }

  Future<void> _handleRealtimeQueuedEnvelope(
    RealtimeQueuedEnvelope envelope,
  ) async {
    final identity = await _ensureChatIdentity(registerOnServer: true);
    if (_token == null ||
        identity == null ||
        envelope.id.isEmpty ||
        envelope.payload.isEmpty) {
      return;
    }
    if (envelope.recipientDeviceId.isNotEmpty &&
        envelope.recipientDeviceId != identity.deviceId) {
      return;
    }
    appLog(
      '收到实时加密信封：messageId=${envelope.id}, senderUserId=${envelope.senderUserId}, deviceId=${identity.deviceId}',
    );

    final ackIds = await _processQueuedChatEnvelopes(
      identity: identity,
      envelopes: [
        QueuedChatEnvelopeRecord(
          id: envelope.id,
          senderUserId: envelope.senderUserId,
          senderDeviceId: envelope.senderDeviceId,
          protocol: envelope.protocol,
          payload: envelope.payload,
        ),
      ],
    );
    if (ackIds.isEmpty) {
      return;
    }
    try {
      await _apiClient.ackChatMessages(
        baseUrl: _baseUrl,
        token: _token!,
        deviceId: identity.deviceId,
        messageIds: ackIds,
      );
    } catch (error) {
      appLog('确认实时直推聊天消息失败', error);
    }
  }

  Future<List<String>> _processQueuedChatEnvelopes({
    required ChatIdentityBundle identity,
    required List<QueuedChatEnvelopeRecord> envelopes,
    String senderUserId = '',
  }) async {
    final ackIds = <String>[];
    for (final envelope in envelopes) {
      if (senderUserId.isNotEmpty &&
          envelope.senderUserId.isNotEmpty &&
          envelope.senderUserId != senderUserId) {
        continue;
      }
      try {
        final decrypted = await _chatProtocol.decryptEnvelope(
          recipientIdentity: identity,
          envelope: envelope,
        );
        appLog(
          '聊天密文已解封：messageId=${envelope.id}, kind=${decrypted.kind}, senderUserId=${decrypted.senderUserId}',
        );
        final handled = await _handleDecryptedChatEnvelope(envelope, decrypted);
        if (handled) {
          ackIds.add(envelope.id);
        } else {
          appLog('聊天消息暂不确认，等待下次继续处理：messageId=${envelope.id}');
        }
      } catch (error) {
        appLog('处理待同步聊天消息失败：messageId=${envelope.id}', error);
      }
    }
    return ackIds;
  }

  Future<bool> _handleDecryptedChatEnvelope(
    QueuedChatEnvelopeRecord envelope,
    ChatDecryptedEnvelope decrypted,
  ) async {
    switch (decrypted.kind) {
      case 'direct-message':
        final messageId = decrypted.body['messageId'] as String? ?? '';
        final text = decrypted.body['text'] as String? ?? '';
        if (messageId.isEmpty || text.isEmpty) {
          return false;
        }
        final handled = await _handleRealtimeIncomingMessage(
          RealtimeIncomingMessage(
            friendId: decrypted.senderUserId,
            messageId: messageId,
            text: text,
            attachmentType: decrypted.body['attachmentType'] as String? ?? '',
            attachmentName: decrypted.body['attachmentName'] as String? ?? '',
            attachmentMimeType:
                decrypted.body['attachmentMimeType'] as String? ?? '',
            attachmentSize:
                (decrypted.body['attachmentSize'] as num?)?.toInt() ?? 0,
            attachmentDataBase64:
                decrypted.body['attachmentDataBase64'] as String? ?? '',
            attachmentObjectId:
                decrypted.body['attachmentObjectId'] as String? ?? '',
            attachmentKeyBase64:
                decrypted.body['attachmentKeyBase64'] as String? ?? '',
          ),
        );
        if (!handled) {
          return false;
        }
        _sendDeliveryAckInBackground(
          recipientUserId: decrypted.senderUserId,
          messageId: messageId,
        );
        return true;
      case 'group-message':
        final messageId = decrypted.body['messageId'] as String? ?? '';
        final text = decrypted.body['text'] as String? ?? '';
        final groupId = decrypted.body['groupId'] as String? ?? '';
        if (messageId.isEmpty || text.isEmpty || groupId.isEmpty) {
          return false;
        }
        final handled = await _handleRealtimeIncomingMessage(
          RealtimeIncomingMessage(
            friendId: decrypted.senderUserId,
            messageId: messageId,
            text: text,
            groupId: groupId,
            groupName: decrypted.body['groupName'] as String? ?? '',
            groupAvatarPreset:
                decrypted.body['groupAvatarPreset'] as String? ?? '',
            memberIds:
                (decrypted.body['memberIds'] as List<dynamic>? ?? const [])
                    .map((entry) => entry.toString())
                    .where((entry) => entry.isNotEmpty)
                    .toList(),
            adminUserId: decrypted.body['adminUserId'] as String? ?? '',
            attachmentType: decrypted.body['attachmentType'] as String? ?? '',
            attachmentName: decrypted.body['attachmentName'] as String? ?? '',
            attachmentMimeType:
                decrypted.body['attachmentMimeType'] as String? ?? '',
            attachmentSize:
                (decrypted.body['attachmentSize'] as num?)?.toInt() ?? 0,
            attachmentDataBase64:
                decrypted.body['attachmentDataBase64'] as String? ?? '',
            attachmentObjectId:
                decrypted.body['attachmentObjectId'] as String? ?? '',
            attachmentKeyBase64:
                decrypted.body['attachmentKeyBase64'] as String? ?? '',
          ),
        );
        if (!handled) {
          return false;
        }
        _sendDeliveryAckInBackground(
          recipientUserId: decrypted.senderUserId,
          messageId: messageId,
          groupId: groupId,
        );
        return true;
      case 'group-control':
        return _handleRealtimeGroupControl(
          RealtimeGroupControl(
            friendId: decrypted.senderUserId,
            controlId: decrypted.body['controlId'] as String? ?? envelope.id,
            controlType: decrypted.body['controlType'] as String? ?? '',
            groupId: decrypted.body['groupId'] as String? ?? '',
            groupName: decrypted.body['groupName'] as String? ?? '',
            groupAvatarPreset:
                decrypted.body['groupAvatarPreset'] as String? ?? '',
            memberIds:
                (decrypted.body['memberIds'] as List<dynamic>? ?? const [])
                    .map((entry) => entry.toString())
                    .where((entry) => entry.isNotEmpty)
                    .toList(),
            adminUserId: decrypted.body['adminUserId'] as String? ?? '',
            removedUserId: decrypted.body['removedUserId'] as String? ?? '',
            groupStatus: decrypted.body['groupStatus'] as String? ?? 'active',
            isDissolved: decrypted.body['isDissolved'] as bool? ?? false,
            dissolvedByUserId:
                decrypted.body['dissolvedByUserId'] as String? ?? '',
          ),
        );
      case 'history-request':
        return _handleRealtimeHistoryRequest(
          RealtimeHistoryRequest(
            friendId: decrypted.senderUserId,
            requestId: decrypted.body['requestId'] as String? ?? '',
          ),
        );
      case 'history-response':
        return _handleRealtimeHistoryResponse(
          RealtimeHistoryResponse(
            friendId: decrypted.senderUserId,
            requestId: decrypted.body['requestId'] as String? ?? '',
            conversations:
                (decrypted.body['conversations'] as List<dynamic>? ?? const [])
                    .map((entry) => entry as Map<String, dynamic>)
                    .toList(),
          ),
        );
      case 'delivery-ack':
        final messageId = decrypted.body['messageId'] as String? ?? '';
        if (messageId.isEmpty) {
          return false;
        }
        await _markRealtimeMessageDelivered(decrypted.senderUserId, messageId);
        return true;
      default:
        appLog('收到未知聊天消息类型：${decrypted.kind}');
        return false;
    }
  }

  Future<bool> _handleRealtimeIncomingMessage(
    RealtimeIncomingMessage incoming,
  ) async {
    if (incoming.groupId.isNotEmpty) {
      return _handleRealtimeIncomingGroupMessage(incoming);
    }

    var friend = _knownChatPeerById(incoming.friendId);
    if (friend == null) {
      await _loadFriendsSnapshot();
      friend = _knownChatPeerById(incoming.friendId);
    }
    if (friend == null) {
      appLog('实时单聊消息暂缓确认：未找到好友信息，friendId=${incoming.friendId}');
      return false;
    }
    final messageFriend = friend;
    await _ensureChatConversationLoaded(messageFriend.id);
    if (_findMessage(messageFriend.id, incoming.messageId) != null) {
      appLog(
        '实时单聊消息已存在，跳过重复落库：friendId=${messageFriend.id}, messageId=${incoming.messageId}',
      );
      return true;
    }
    final beforeCount =
        _findDirectConversation(messageFriend.id)?.messages.length ?? 0;
    _replaceConversationMessages(
      messageFriend,
      (messages) => [
        ...messages,
        ChatMessage(
          id: incoming.messageId,
          friendId: messageFriend.id,
          text: incoming.text,
          sentByMe: false,
          createdAt: DateTime.now(),
          status: 'delivered',
          isRead: _activeConversationIds.contains(messageFriend.id),
          senderId: messageFriend.id,
          senderName: messageFriend.displayName,
          attachmentType: incoming.attachmentType,
          attachmentName: incoming.attachmentName,
          attachmentMimeType: incoming.attachmentMimeType,
          attachmentSize: incoming.attachmentSize,
          attachmentDataBase64: incoming.attachmentDataBase64,
          attachmentObjectId: incoming.attachmentObjectId,
          attachmentKeyBase64: incoming.attachmentKeyBase64,
        ),
      ],
    );
    final afterCount =
        _findDirectConversation(messageFriend.id)?.messages.length ?? 0;
    appLog(
      '实时单聊消息已写入会话：friendId=${messageFriend.id}, messageId=${incoming.messageId}, before=$beforeCount, after=$afterCount',
    );
    await _persistChatSnapshot();
    notifyListeners();
    return true;
  }

  Future<bool> _handleRealtimeIncomingGroupMessage(
    RealtimeIncomingMessage incoming,
  ) async {
    if (_user == null || incoming.groupId.isEmpty) {
      return false;
    }
    if (incoming.memberIds.isNotEmpty &&
        !incoming.memberIds.contains(_user!.id)) {
      appLog('实时群消息暂缓确认：当前用户不在群成员列表中，groupId=${incoming.groupId}');
      return false;
    }
    await _ensureChatConversationLoaded(incoming.groupId);
    final existingConversation = _conversationById(incoming.groupId);
    if (existingConversation?.isDissolved == true) {
      return true;
    }
    if (_findMessageInConversation(incoming.groupId, incoming.messageId) !=
        null) {
      appLog(
        '实时群消息已存在，跳过重复落库：groupId=${incoming.groupId}, messageId=${incoming.messageId}',
      );
      return true;
    }

    var sender = _knownChatPeerById(incoming.friendId);
    if (sender == null) {
      await _loadFriendsSnapshot();
      await _mergeServerGroupsIntoChatConversations();
      sender = _knownChatPeerById(incoming.friendId);
    }
    if (sender == null) {
      appLog('实时群消息暂缓确认：未找到发送者信息，friendId=${incoming.friendId}');
      return false;
    }
    final messageSender = sender;
    final memberById = <String, PublicUser>{
      for (final friend in _friends) friend.id: friend,
    };
    for (final conversation in _chatConversations) {
      for (final member in conversation.members) {
        memberById[member.id] = member;
      }
    }
    final members = <PublicUser>[];
    for (final memberId in incoming.memberIds) {
      final member = memberById[memberId];
      if (member != null) {
        members.add(member);
      }
    }
    if (!members.any((member) => member.id == messageSender.id)) {
      members.add(messageSender);
    }

    _ensureGroupConversation(
      id: incoming.groupId,
      title: incoming.groupName,
      members: members,
      adminUserId: incoming.adminUserId,
    );
    _replaceConversationMessagesById(
      incoming.groupId,
      (messages) => [
        ...messages,
        ChatMessage(
          id: incoming.messageId,
          friendId: incoming.groupId,
          text: incoming.text,
          sentByMe: false,
          createdAt: DateTime.now(),
          status: 'delivered',
          isRead: _activeConversationIds.contains(incoming.groupId),
          senderId: messageSender.id,
          senderName: messageSender.displayName,
          attachmentType: incoming.attachmentType,
          attachmentName: incoming.attachmentName,
          attachmentMimeType: incoming.attachmentMimeType,
          attachmentSize: incoming.attachmentSize,
          attachmentDataBase64: incoming.attachmentDataBase64,
          attachmentObjectId: incoming.attachmentObjectId,
          attachmentKeyBase64: incoming.attachmentKeyBase64,
        ),
      ],
    );
    final total = _conversationById(incoming.groupId)?.messages.length ?? 0;
    appLog(
      '实时群消息已写入会话：groupId=${incoming.groupId}, messageId=${incoming.messageId}, total=$total',
    );
    await _persistChatSnapshot();
    notifyListeners();
    return true;
  }

  Future<bool> _handleRealtimeGroupControl(RealtimeGroupControl control) async {
    if (_user == null || control.groupId.isEmpty) {
      return false;
    }
    if (control.controlType == 'group-dissolved') {
      await _ensureChatConversationLoaded(control.groupId);
      final members = await _resolveGroupControlMembers(control);
      _applyDissolvedGroupConversation(
        groupId: control.groupId,
        title: control.groupName,
        avatarPreset: '',
        members: members,
        adminUserId: control.adminUserId,
        dissolvedByUserId: control.dissolvedByUserId,
      );
      _statusMessage = '群聊已被群管理解散，你可以在群信息页删除该会话。';
      notifyListeners();
      await _persistChatSnapshot();
      return true;
    }
    if (control.removedUserId == _user!.id ||
        !control.memberIds.contains(_user!.id)) {
      _deleteGroupConversation(control.groupId);
      _statusMessage = '已退出群聊，当前账号的群消息记录已从缓存和归档中删除。';
      notifyListeners();
      await _persistChatSnapshot();
      return true;
    }

    await _ensureChatConversationLoaded(control.groupId);
    final members = await _resolveGroupControlMembers(control);
    final conversation = _ensureGroupConversation(
      id: control.groupId,
      title: control.groupName,
      members: members,
      adminUserId: control.adminUserId,
      groupStatus: control.groupStatus,
      isDissolved: control.isDissolved,
      dissolvedByUserId: control.dissolvedByUserId,
    );
    await updateGroupChat(
      conversationId: conversation.id,
      title: control.groupName,
      members: members,
      adminUserId: control.adminUserId,
      syncServer: false,
    );
    _statusMessage = '群聊成员已更新。';
    notifyListeners();
    return true;
  }

  Future<List<PublicUser>> _resolveGroupControlMembers(
    RealtimeGroupControl control,
  ) async {
    var memberById = <String, PublicUser>{
      for (final friend in _friends) friend.id: friend,
    };
    for (final existing in _chatConversations) {
      for (final member in existing.members) {
        memberById[member.id] = member;
      }
    }
    if (!control.memberIds.every(
      (memberId) => memberId == _user!.id || memberById.containsKey(memberId),
    )) {
      await _loadFriendsSnapshot();
      await _mergeServerGroupsIntoChatConversations();
      memberById = <String, PublicUser>{
        for (final friend in _friends) friend.id: friend,
      };
      for (final existing in _chatConversations) {
        for (final member in existing.members) {
          memberById[member.id] = member;
        }
      }
    }
    return control.memberIds
        .where((memberId) => memberId != _user!.id)
        .map((memberId) => memberById[memberId])
        .whereType<PublicUser>()
        .toList();
  }

  void _applyDissolvedGroupConversation({
    required String groupId,
    required String title,
    required String avatarPreset,
    required List<PublicUser> members,
    required String adminUserId,
    required String dissolvedByUserId,
  }) {
    final conversation = _ensureGroupConversation(
      id: groupId,
      title: title,
      avatarPreset: avatarPreset,
      members: members,
      adminUserId: adminUserId,
      groupStatus: 'dissolved',
      isDissolved: true,
      dissolvedByUserId: dissolvedByUserId,
      dissolvedAt: DateTime.now(),
    );
    _markConversationForArchiveSync(
      conversation.id,
      forceNewVersion: conversation.archiveVersion <= 0,
    );
  }

  Future<void> _markRealtimeMessageDelivered(
    String friendId,
    String messageId,
  ) async {
    final directConversation = _findDirectConversation(friendId);
    if (directConversation != null) {
      await _ensureChatConversationLoaded(directConversation.id);
    }
    final groupConversationIds = _chatConversations
        .where(
          (conversation) =>
              conversation.isGroup &&
              conversation.members.any((member) => member.id == friendId),
        )
        .map((conversation) => conversation.id)
        .toList();
    for (final conversationId in groupConversationIds) {
      await _ensureChatConversationLoaded(conversationId);
    }
    final friend = _knownChatPeerById(friendId);
    if (friend != null && _findMessage(friend.id, messageId) != null) {
      _replaceMessage(
        friend,
        messageId,
        (message) => message.copyWith(status: 'delivered'),
      );
    }
    _markGroupMessageDelivered(friendId, messageId);
    await _persistChatSnapshot();
    notifyListeners();
  }

  void _handleRealtimePeerStatus(String friendId, String status) {
    appLog('实时聊天好友状态变化：friendId=$friendId, status=$status');
    final normalizedStatus = status.toLowerCase();
    final online = normalizedStatus == 'presence-online';
    final offline = normalizedStatus == 'presence-offline';

    if (online || offline) {
      _chatFriendOnline[friendId] = online;
      _markChatChanged();
      notifyListeners();
    }

    if (online ||
        normalizedStatus == 'ready' ||
        normalizedStatus == 'relay-ready') {
      unawaited(_flushPendingRealtimeMessages(friendId));
      unawaited(_requestHistoryFromPeer(friendId));
    }
  }

  Future<void> _refreshRealtimePresenceSnapshot({
    List<String> userIds = const [],
  }) async {
    final token = _token;
    if (token == null) {
      return;
    }

    final peerIds = <String>{
      ...userIds.where((entry) => entry.trim().isNotEmpty),
      ..._friends.map((friend) => friend.id),
      for (final conversation in _chatConversations)
        ...conversation.members.map((member) => member.id),
    }.where((entry) => entry.isNotEmpty && entry != _user?.id).toList();
    if (peerIds.isEmpty) {
      return;
    }

    try {
      final statuses = await _apiClient.listRealtimePresence(
        baseUrl: _baseUrl,
        token: token,
        userIds: peerIds,
      );
      var changed = false;
      for (final status in statuses) {
        if (_chatFriendOnline[status.userId] != status.online) {
          _chatFriendOnline[status.userId] = status.online;
          changed = true;
        }
      }
      if (changed) {
        _markChatChanged();
        notifyListeners();
      }
    } catch (error) {
      appLog('刷新在线状态快照失败', error);
    }
  }

  Future<void> _requestHistoryFromPeer(String friendId) async {
    if (_historyRequestedPeerIds.contains(friendId)) {
      return;
    }
    final friend = _friendById(friendId);
    if (friend == null) {
      return;
    }
    try {
      final requested = await _dispatchHistoryRequest(friend);
      if (requested) {
        _historyRequestedPeerIds.add(friendId);
      }
    } catch (error) {
      appLog('实时聊天历史同步请求失败', error);
    }
  }

  Future<bool> _handleRealtimeHistoryRequest(
    RealtimeHistoryRequest request,
  ) async {
    final friend = _knownChatPeerById(request.friendId);
    if (friend == null || request.requestId.isEmpty) {
      if (friend == null) {
        appLog('实时历史请求暂缓确认：未找到好友信息，friendId=${request.friendId}');
      }
      return false;
    }
    final conversations = await _historyConversationsForPeer(friend.id);
    try {
      await _dispatchHistoryResponse(
        friend: friend,
        requestId: request.requestId,
        conversations: conversations,
      );
    } catch (error) {
      appLog('实时聊天历史同步响应失败', error);
      return false;
    }
    return true;
  }

  Future<bool> _handleRealtimeHistoryResponse(
    RealtimeHistoryResponse response,
  ) async {
    final friend = _knownChatPeerById(response.friendId);
    if (friend == null) {
      appLog('实时历史响应暂缓确认：未找到好友信息，friendId=${response.friendId}');
      return false;
    }
    var changed = false;
    for (final entry in response.conversations) {
      final isGroup = entry['isGroup'] as bool? ?? false;
      if (isGroup) {
        changed = await _mergeGroupHistory(friend, entry) || changed;
      } else {
        changed = await _mergeDirectHistory(friend, entry) || changed;
      }
    }
    if (!changed) {
      return true;
    }
    _statusMessage = '聊天历史已从在线好友同步。';
    await _persistChatSnapshot();
    await _syncKnownGroupSnapshotsSilently();
    notifyListeners();
    return true;
  }

  void _replaceMessage(
    PublicUser friend,
    String messageId,
    ChatMessage Function(ChatMessage message) update,
  ) {
    _replaceConversationMessages(
      friend,
      (messages) => messages
          .map((message) => message.id == messageId ? update(message) : message)
          .toList(),
    );
  }

  void _replaceMessageByConversationId(
    String conversationId,
    String messageId,
    ChatMessage Function(ChatMessage message) update,
  ) {
    _replaceConversationMessagesById(
      conversationId,
      (messages) => messages
          .map((message) => message.id == messageId ? update(message) : message)
          .toList(),
    );
  }

  void _markGroupMessageDelivered(String senderFriendId, String messageId) {
    for (final conversation in _chatConversations) {
      if (!conversation.isGroup) {
        continue;
      }
      final hasSender = conversation.members.any(
        (member) => member.id == senderFriendId,
      );
      final hasMessage = conversation.messages.any(
        (message) => message.id == messageId,
      );
      if (hasSender && hasMessage) {
        _replaceMessageByConversationId(conversation.id, messageId, (message) {
          final updated = message.copyWith(
            sentPeerIds: _uniqueIds([...message.sentPeerIds, senderFriendId]),
            deliveredPeerIds: _uniqueIds([
              ...message.deliveredPeerIds,
              senderFriendId,
            ]),
          );
          return updated.copyWith(
            status: _groupMessageStatus(conversation, updated),
          );
        });
        return;
      }
    }
  }

  ChatMessage? _findMessage(String friendId, String messageId) {
    for (final conversation in _chatConversations) {
      if (conversation.friend?.id != friendId) {
        continue;
      }
      for (final message in conversation.messages) {
        if (message.id == messageId) {
          return message;
        }
      }
    }
    return null;
  }

  ChatMessage? _findMessageInConversation(
    String conversationId,
    String messageId,
  ) {
    final conversation = _conversationById(conversationId);
    if (conversation == null) {
      return null;
    }
    for (final message in conversation.messages) {
      if (message.id == messageId) {
        return message;
      }
    }
    return null;
  }

  ChatConversation? _conversationById(String conversationId) {
    for (final conversation in _chatConversations) {
      if (conversation.id == conversationId) {
        return conversation;
      }
    }
    return null;
  }

  void _deleteGroupConversation(String conversationId) {
    _chatConversations = _chatConversations
        .where(
          (conversation) =>
              conversation.id != conversationId || !conversation.isGroup,
        )
        .toList();
    _loadedChatConversationIds.remove(conversationId);
    _loadingChatConversationIds.remove(conversationId);
    _chatConversationLoadTasks.remove(conversationId);
    _queueChatConversationDeletion(conversationId);
    unawaited(_deleteLocalChatDetailCache(conversationId));
    _sortChatConversations();
    _markChatChanged();
  }

  ChatConversation _ensureGroupConversation({
    required String id,
    required String title,
    String avatarPreset = '',
    required List<PublicUser> members,
    required String adminUserId,
    String groupStatus = 'active',
    bool isDissolved = false,
    String? dissolvedByUserId,
    DateTime? dissolvedAt,
    bool markDirty = true,
    int? archiveVersion,
  }) {
    final conversations = [..._chatConversations];
    final index = conversations.indexWhere(
      (conversation) => conversation.id == id,
    );
    final nextArchiveVersion =
        archiveVersion ?? (markDirty ? _nextChatArchiveVersion() : 0);
    if (index >= 0) {
      final existing = conversations[index];
      final nextIsDissolved = existing.isDissolved || isDissolved;
      conversations[index] = existing.copyWith(
        title: title.isEmpty ? existing.title : title,
        avatarPreset: avatarPreset.isEmpty
            ? existing.avatarPreset
            : avatarPreset,
        members: _uniqueFriends([...existing.members, ...members]),
        adminUserId: adminUserId.isEmpty ? existing.adminUserId : adminUserId,
        groupStatus: nextIsDissolved ? 'dissolved' : groupStatus,
        isDissolved: nextIsDissolved,
        dissolvedByUserId: dissolvedByUserId ?? existing.dissolvedByUserId,
        dissolvedAt: dissolvedAt ?? existing.dissolvedAt,
        archiveVersion: nextArchiveVersion > 0
            ? nextArchiveVersion
            : existing.archiveVersion,
      );
      if (markDirty) {
        _queueChatConversationSync(id, nextArchiveVersion);
      }
      _chatConversations = conversations;
      _sortChatConversations();
      _markChatChanged();
      return conversations[index];
    }

    final conversation = ChatConversation(
      id: id,
      title: title.isEmpty ? '未命名群聊' : title,
      avatarPreset: avatarPreset,
      members: _uniqueFriends(members),
      adminUserId: adminUserId,
      isGroup: true,
      groupStatus: groupStatus,
      isDissolved: isDissolved,
      dissolvedByUserId: dissolvedByUserId,
      dissolvedAt: dissolvedAt,
      messages: [],
      archiveVersion: nextArchiveVersion,
    );
    if (markDirty) {
      _queueChatConversationSync(id, nextArchiveVersion);
    }
    _chatConversations = [..._chatConversations, conversation];
    _sortChatConversations();
    _markChatChanged();
    return conversation;
  }

  List<PublicUser> _uniqueFriends(List<PublicUser> users) {
    final result = <PublicUser>[];
    final seen = <String>{};
    for (final user in users) {
      if (user.id.isEmpty || !seen.add(user.id)) {
        continue;
      }
      result.add(user);
    }
    return result;
  }

  List<String> _uniqueIds(List<String> ids) {
    final result = <String>[];
    final seen = <String>{};
    for (final id in ids) {
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      result.add(id);
    }
    return result;
  }

  int _nextChatArchiveVersion() => DateTime.now().millisecondsSinceEpoch;

  void _queueChatConversationSync(String conversationId, int archiveVersion) {
    if (conversationId.isEmpty || archiveVersion <= 0) {
      return;
    }
    _pendingDeletedChatConversationIds.remove(conversationId);
    final current = _pendingChatConversationVersions[conversationId] ?? 0;
    if (archiveVersion > current) {
      _pendingChatConversationVersions[conversationId] = archiveVersion;
    }
  }

  void _queueChatConversationDeletion(String conversationId) {
    if (conversationId.isEmpty) {
      return;
    }
    _pendingChatConversationVersions.remove(conversationId);
    _pendingDeletedChatConversationIds.add(conversationId);
  }

  void _markConversationForArchiveSync(
    String conversationId, {
    bool forceNewVersion = false,
  }) {
    if (conversationId.isEmpty) {
      return;
    }
    final conversations = [..._chatConversations];
    final index = conversations.indexWhere(
      (conversation) => conversation.id == conversationId,
    );
    if (index < 0) {
      return;
    }
    final conversation = conversations[index];
    final nextVersion = forceNewVersion || conversation.archiveVersion <= 0
        ? _nextChatArchiveVersion()
        : conversation.archiveVersion;
    conversations[index] = conversation.copyWith(archiveVersion: nextVersion);
    _chatConversations = conversations;
    _queueChatConversationSync(conversationId, nextVersion);
  }

  Future<String> _buildGroupSnapshotPayload(ChatConversation conversation) {
    return _cryptoService.encryptJson({
      'id': conversation.id,
      'title': conversation.title,
      'avatarPreset': conversation.avatarPreset,
      'memberIds': conversation.members.map((member) => member.id).toList(),
      'adminUserId': conversation.adminUserId,
    }, _vaultKey!);
  }

  int _nextGroupSnapshotVersion() => DateTime.now().millisecondsSinceEpoch;

  Future<void> _createGroupConversationOnServer(
    ChatConversation conversation,
  ) async {
    if (_token == null || !_canSyncGroupConversation(conversation)) {
      return;
    }
    final payload = await _buildGroupSnapshotPayload(conversation);
    final group = await _apiClient.createGroup(
      baseUrl: _baseUrl,
      token: _token!,
      groupId: conversation.id,
      payload: payload,
      version: _nextGroupSnapshotVersion(),
      memberIds: conversation.members.map((member) => member.id).toList(),
    );
    await _mergeServerGroupRecord(group);
  }

  Future<void> _updateGroupConversationOnServer(
    ChatConversation conversation,
  ) async {
    if (_token == null || !_canSyncGroupConversation(conversation)) {
      return;
    }
    final payload = await _buildGroupSnapshotPayload(conversation);
    final group = await _apiClient.updateGroup(
      baseUrl: _baseUrl,
      token: _token!,
      groupId: conversation.id,
      payload: payload,
      version: _nextGroupSnapshotVersion(),
      memberIds: conversation.members.map((member) => member.id).toList(),
      adminUserId: conversation.adminUserId,
    );
    await _mergeServerGroupRecord(group);
  }

  Future<void> _syncGroupSnapshotForConversation(
    ChatConversation conversation,
  ) async {
    if (_token == null || !_canSyncGroupConversation(conversation)) {
      return;
    }
    try {
      await _apiClient.upsertGroupSnapshot(
        baseUrl: _baseUrl,
        token: _token!,
        groupId: conversation.id,
        payload: await _buildGroupSnapshotPayload(conversation),
        version: _nextGroupSnapshotVersion(),
      );
    } catch (error) {
      appLog('群聊快照同步失败：groupId=${conversation.id}', error);
    }
  }

  Future<void> _leaveGroupOnServer({
    required String conversationId,
    String? nextAdminUserId,
  }) async {
    if (_token == null) {
      return;
    }
    await _apiClient.leaveGroup(
      baseUrl: _baseUrl,
      token: _token!,
      groupId: conversationId,
      nextAdminUserId: nextAdminUserId,
    );
  }

  Future<void> _mergeServerGroupRecord(GroupRecord group) async {
    if (_user == null || _vaultKey == null || group.id.isEmpty) {
      return;
    }
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
        appLog('群聊快照解密失败：groupId=${group.id}', error);
      }
    }
    _ensureGroupConversation(
      id: group.id,
      title: title,
      avatarPreset: avatarPreset,
      members: group.members.where((member) => member.id != _user!.id).toList(),
      adminUserId: group.adminUserId,
      groupStatus: group.status,
      isDissolved: group.isDissolved,
      dissolvedByUserId: group.dissolvedByUserId,
      dissolvedAt: group.dissolvedAt,
      markDirty: false,
    );
  }

  Future<void> _syncKnownGroupSnapshotsSilently() async {
    for (final conversation in _chatConversations) {
      if (!conversation.isGroup) {
        continue;
      }
      await _syncGroupSnapshotForConversation(conversation);
    }
  }

  bool _canSyncGroupConversation(ChatConversation conversation) {
    return conversation.isGroup &&
        !conversation.isDissolved &&
        _token != null &&
        _vaultKey != null;
  }

  String _groupMessageStatus(
    ChatConversation conversation,
    ChatMessage message,
  ) {
    final memberIds = conversation.members.map((member) => member.id).toSet();
    if (memberIds.isEmpty) {
      return 'delivered';
    }
    if (memberIds.every(message.deliveredPeerIds.contains)) {
      return 'delivered';
    }
    if (message.sentPeerIds.any(memberIds.contains)) {
      return 'sent';
    }
    return _realtimeConfig?.signalingEnabled == true ? 'pending' : 'localOnly';
  }

  Future<List<Map<String, dynamic>>> _historyConversationsForPeer(
    String peerId,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (final conversation in List<ChatConversation>.from(
      _chatConversations,
    )) {
      if (conversation.isGroup) {
        final peerInGroup = conversation.members.any(
          (member) => member.id == peerId,
        );
        if (!peerInGroup) {
          continue;
        }
        await _ensureChatConversationLoaded(conversation.id);
        final latest = _conversationById(conversation.id);
        if (latest == null) {
          continue;
        }
        result.add(_conversationToHistoryJson(latest));
        continue;
      }
      if (conversation.friend?.id == peerId) {
        await _ensureChatConversationLoaded(conversation.id);
        final latest = _conversationById(conversation.id);
        if (latest == null) {
          continue;
        }
        result.add(_conversationToHistoryJson(latest));
      }
    }
    return result;
  }

  Map<String, dynamic> _conversationToHistoryJson(
    ChatConversation conversation,
  ) {
    return {
      'id': conversation.id,
      'title': conversation.title,
      'avatarPreset': conversation.avatarPreset,
      'isGroup': conversation.isGroup,
      'friendId': conversation.friend?.id ?? '',
      'adminUserId': conversation.adminUserId,
      'groupStatus': conversation.groupStatus,
      'isDissolved': conversation.isDissolved,
      'dissolvedByUserId': conversation.dissolvedByUserId ?? '',
      'dissolvedAt': conversation.dissolvedAt?.toIso8601String() ?? '',
      'members': conversation.members.map((member) => member.toJson()).toList(),
      'messages': conversation.messages.map((message) {
        return _messageToHistoryJson(message);
      }).toList(),
    };
  }

  Map<String, dynamic> _messageToHistoryJson(ChatMessage message) {
    final data = message.toJson();
    if ((data['senderId'] as String? ?? '').isEmpty) {
      data['senderId'] = message.sentByMe ? _user?.id ?? '' : message.friendId;
    }
    if ((data['senderName'] as String? ?? '').isEmpty) {
      data['senderName'] = message.sentByMe ? _user?.displayName ?? '' : '';
    }
    return data;
  }

  Future<bool> _mergeDirectHistory(
    PublicUser peer,
    Map<String, dynamic> entry,
  ) async {
    final messages = _historyMessagesFromEntry(entry, peer.id);
    if (messages.isEmpty) {
      return false;
    }
    if (_findDirectConversation(peer.id) != null) {
      await _ensureChatConversationLoaded(peer.id);
    }
    final before = _findDirectConversation(peer.id)?.messages.length ?? 0;
    _replaceConversationMessages(peer, (current) {
      return _mergeMessages(current, messages);
    });
    final after = _findDirectConversation(peer.id)?.messages.length ?? 0;
    return after > before;
  }

  Future<bool> _mergeGroupHistory(
    PublicUser peer,
    Map<String, dynamic> entry,
  ) async {
    final groupId = entry['id'] as String? ?? '';
    if (groupId.isEmpty) {
      return false;
    }
    if (_conversationById(groupId) != null) {
      await _ensureChatConversationLoaded(groupId);
    }
    final rawMembers = (entry['members'] as List<dynamic>? ?? const [])
        .map((member) => PublicUser.fromJson(member as Map<String, dynamic>))
        .where((member) => member.id.isNotEmpty && member.id != _user?.id)
        .toList();
    if (!rawMembers.any((member) => member.id == peer.id)) {
      rawMembers.add(peer);
    }
    final existing = _conversationById(groupId);
    final conversation = _ensureGroupConversation(
      id: groupId,
      title: entry['title'] as String? ?? existing?.title ?? '未命名群聊',
      avatarPreset:
          entry['avatarPreset'] as String? ?? existing?.avatarPreset ?? '',
      members: _uniqueFriends([...?existing?.members, ...rawMembers]),
      adminUserId:
          entry['adminUserId'] as String? ?? existing?.adminUserId ?? '',
      groupStatus:
          entry['groupStatus'] as String? ?? existing?.groupStatus ?? 'active',
      isDissolved:
          entry['isDissolved'] as bool? ?? existing?.isDissolved ?? false,
      dissolvedByUserId:
          entry['dissolvedByUserId'] as String? ?? existing?.dissolvedByUserId,
      dissolvedAt:
          DateTime.tryParse(entry['dissolvedAt'] as String? ?? '') ??
          existing?.dissolvedAt,
    );
    final messages = _historyMessagesFromEntry(entry, groupId);
    final before = conversation.messages.length;
    _replaceConversationMessagesById(groupId, (current) {
      return _mergeMessages(current, messages);
    });
    final after = _conversationById(groupId)?.messages.length ?? before;
    return after > before;
  }

  List<ChatMessage> _historyMessagesFromEntry(
    Map<String, dynamic> entry,
    String fallbackFriendId,
  ) {
    return (entry['messages'] as List<dynamic>? ?? const [])
        .map((message) {
          final parsed = ChatMessage.fromJson(message as Map<String, dynamic>);
          final senderId = parsed.senderId.isNotEmpty
              ? parsed.senderId
              : (parsed.sentByMe ? fallbackFriendId : _user?.id ?? '');
          return parsed.copyWith(
            friendId: entry['isGroup'] == true
                ? entry['id'] as String? ?? parsed.friendId
                : fallbackFriendId,
            sentByMe: senderId == _user?.id,
            senderId: senderId,
          );
        })
        .where((message) => message.id.isNotEmpty)
        .toList();
  }

  List<ChatMessage> _mergeMessages(
    List<ChatMessage> current,
    List<ChatMessage> incoming,
  ) {
    final byId = {for (final message in current) message.id: message};
    for (final message in incoming) {
      byId.putIfAbsent(message.id, () => message);
    }
    return _sortMessages(byId.values.toList());
  }

  ChatConversation? _findDirectConversation(String friendId) {
    for (final conversation in _chatConversations) {
      if (!conversation.isGroup && conversation.friend?.id == friendId) {
        return conversation;
      }
    }
    return null;
  }

  PublicUser? _friendById(String friendId) {
    for (final friend in _friends) {
      if (friend.id == friendId) {
        return friend;
      }
    }
    return null;
  }

  PublicUser? _knownChatPeerById(String friendId) {
    final direct = _friendById(friendId);
    if (direct != null) {
      return direct;
    }
    for (final conversation in _chatConversations) {
      for (final member in conversation.members) {
        if (member.id == friendId) {
          return member;
        }
      }
    }
    return null;
  }

  Future<void> _flushAllPendingRealtimeMessages() async {
    final peerIds = <String>{};
    for (final conversation in _chatConversations) {
      if (conversation.isGroup) {
        for (final member in conversation.members) {
          if (member.id.isNotEmpty && member.id != _user?.id) {
            peerIds.add(member.id);
          }
        }
        continue;
      }
      final friendId = conversation.friend?.id ?? '';
      if (friendId.isNotEmpty) {
        peerIds.add(friendId);
      }
    }
    for (final peerId in peerIds) {
      await _flushPendingRealtimeMessages(peerId);
    }
  }

  Future<void> _flushPendingRealtimeMessages(String friendId) async {
    final friend = _knownChatPeerById(friendId);
    if (friend == null) {
      return;
    }
    final relatedConversationIds = _chatConversations
        .where(
          (conversation) =>
              conversation.friend?.id == friendId ||
              (conversation.isGroup &&
                  conversation.members.any((member) => member.id == friendId)),
        )
        .map((conversation) => conversation.id)
        .toList();
    for (final conversationId in relatedConversationIds) {
      await _ensureChatConversationLoaded(conversationId);
    }
    final pending = <ChatMessage>[];
    for (final conversation in _chatConversations) {
      if (conversation.friend?.id != friendId) {
        continue;
      }
      pending.addAll(
        conversation.messages.where(
          (message) =>
              message.sentByMe &&
              (message.status == 'pending' || message.status == 'localOnly'),
        ),
      );
    }
    for (final conversation in _chatConversations) {
      if (!conversation.isGroup ||
          !conversation.members.any((member) => member.id == friendId)) {
        continue;
      }
      pending.addAll(
        conversation.messages.where(
          (message) =>
              message.sentByMe &&
              !message.deliveredPeerIds.contains(friendId) &&
              !message.sentPeerIds.contains(friendId) &&
              (message.status == 'pending' ||
                  message.status == 'localOnly' ||
                  message.status == 'sent'),
        ),
      );
    }
    for (final message in pending) {
      final conversation = _conversationById(message.friendId);
      final deliveredToChannel = conversation?.isGroup == true
          ? (await _dispatchGroupMessage(
              conversation: conversation!,
              message: message,
              recipientUserIds: [friend.id],
            )).contains(friend.id)
          : await _sendRealtimeMessage(friend, message);
      if (!deliveredToChannel) {
        continue;
      }
      if (conversation?.isGroup == true) {
        final groupConversation = conversation!;
        _replaceMessageByConversationId(groupConversation.id, message.id, (
          current,
        ) {
          final updated = current.copyWith(
            sentPeerIds: _uniqueIds([...current.sentPeerIds, friend.id]),
          );
          return updated.copyWith(
            status: _groupMessageStatus(groupConversation, updated),
          );
        });
      } else {
        _replaceMessage(
          friend,
          message.id,
          (current) => current.copyWith(status: 'sent'),
        );
      }
    }
    if (pending.isNotEmpty) {
      await _persistChatSnapshot();
      notifyListeners();
    }
  }
}
