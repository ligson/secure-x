// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'app_controller.dart';

extension AppControllerChatActions on AppController {
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

    final archiveVersion = _nextChatArchiveVersion();
    conversations[index] = conversations[index].copyWith(
      title: title,
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
    await _persistChatSnapshot();
  }

  Future<void> leaveGroupChat(String conversationId) async {
    final conversation = _conversationById(conversationId);
    final currentUser = _user;
    if (conversation == null || !conversation.isGroup || currentUser == null) {
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
    );
    _deleteGroupConversation(conversation.id);
    _statusMessage = '已退出群聊，当前账号的群消息记录已从缓存和归档中删除。';
    notifyListeners();
    await _persistChatSnapshot();
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
      senderName: _user?.username ?? '',
    );
    _replaceConversationMessagesById(
      latest.id,
      (messages) => [...messages, message],
    );
    notifyListeners();

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

    final latest = _conversationById(conversation.id) ?? conversation;
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
      return _dispatchDirectMessage(friend: friend, message: message);
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
        ),
      );
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
      );
    } catch (error) {
      appLog('实时群聊控制消息发送失败', error);
    }
  }

  Future<bool> _dispatchDirectMessage({
    required PublicUser friend,
    required ChatMessage message,
  }) async {
    final recipientMap = await _dispatchEncryptedPayloads(
      recipientUserIds: [friend.id],
      kind: 'direct-message',
      body: {'messageId': message.id, 'text': message.text},
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
        'messageId': message.id,
        'text': message.text,
        'groupId': conversation.id,
        'groupName': conversation.title,
        'memberIds': [_user?.id ?? '', ...memberIds],
        'adminUserId': conversation.adminUserId,
      },
    );
    return queuedByUser.entries
        .where((entry) => entry.value > 0)
        .map((entry) => entry.key)
        .toList();
  }

  Future<void> _dispatchGroupControl({
    required ChatConversation conversation,
    required List<PublicUser> recipients,
    required String controlType,
    required String removedUserId,
    required List<String> memberIds,
    required String adminUserId,
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
        'memberIds': _uniqueIds(memberIds),
        'adminUserId': adminUserId,
        'removedUserId': removedUserId,
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

    final outgoing = <ChatOutgoingEnvelope>[];
    final queuedByUser = <String, int>{};
    for (final recipientUserId in cleanUserIds) {
      final devices = await _apiClient.listUserChatDevices(
        baseUrl: _baseUrl,
        token: token,
        userId: recipientUserId,
      );
      final supportedDevices = devices.where((device) {
        return device.id.isNotEmpty &&
            device.publicKey.isNotEmpty &&
            device.protocol == _chatProtocol.protocolId;
      }).toList();
      for (final device in supportedDevices) {
        outgoing.add(
          await _chatProtocol.encryptForDevice(
            senderIdentity: identity,
            senderUserId: user.id,
            recipientDevice: device,
            kind: kind,
            body: body,
          ),
        );
      }
      if (supportedDevices.isNotEmpty) {
        queuedByUser[recipientUserId] = supportedDevices.length;
      }
    }

    if (outgoing.isEmpty) {
      return queuedByUser;
    }

    await _apiClient.dispatchChatMessages(
      baseUrl: _baseUrl,
      token: token,
      messages: outgoing,
    );
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
        );
        if (pending.isEmpty) {
          return;
        }
        final ackIds = <String>[];
        for (final envelope in pending) {
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
            await _handleDecryptedChatEnvelope(envelope, decrypted);
            ackIds.add(envelope.id);
          } catch (error) {
            appLog('处理待同步聊天消息失败：messageId=${envelope.id}', error);
          }
        }
        if (ackIds.isEmpty) {
          return;
        }
        await _apiClient.ackChatMessages(
          baseUrl: _baseUrl,
          token: token,
          deviceId: identity.deviceId,
          messageIds: ackIds,
        );
      } catch (error) {
        appLog('拉取待同步聊天消息失败', error);
      }
    });
    await _pendingChatSyncTask;
  }

  Future<void> _handleDecryptedChatEnvelope(
    QueuedChatEnvelopeRecord envelope,
    ChatDecryptedEnvelope decrypted,
  ) async {
    switch (decrypted.kind) {
      case 'direct-message':
        final messageId = decrypted.body['messageId'] as String? ?? '';
        final text = decrypted.body['text'] as String? ?? '';
        if (messageId.isEmpty || text.isEmpty) {
          return;
        }
        await _handleRealtimeIncomingMessage(
          RealtimeIncomingMessage(
            friendId: decrypted.senderUserId,
            messageId: messageId,
            text: text,
          ),
        );
        await _dispatchDeliveryAck(
          recipientUserId: decrypted.senderUserId,
          messageId: messageId,
        );
        return;
      case 'group-message':
        final messageId = decrypted.body['messageId'] as String? ?? '';
        final text = decrypted.body['text'] as String? ?? '';
        final groupId = decrypted.body['groupId'] as String? ?? '';
        if (messageId.isEmpty || text.isEmpty || groupId.isEmpty) {
          return;
        }
        await _handleRealtimeIncomingMessage(
          RealtimeIncomingMessage(
            friendId: decrypted.senderUserId,
            messageId: messageId,
            text: text,
            groupId: groupId,
            groupName: decrypted.body['groupName'] as String? ?? '',
            memberIds:
                (decrypted.body['memberIds'] as List<dynamic>? ?? const [])
                    .map((entry) => entry.toString())
                    .where((entry) => entry.isNotEmpty)
                    .toList(),
            adminUserId: decrypted.body['adminUserId'] as String? ?? '',
          ),
        );
        await _dispatchDeliveryAck(
          recipientUserId: decrypted.senderUserId,
          messageId: messageId,
          groupId: groupId,
        );
        return;
      case 'group-control':
        await _handleRealtimeGroupControl(
          RealtimeGroupControl(
            friendId: decrypted.senderUserId,
            controlId: decrypted.body['controlId'] as String? ?? envelope.id,
            controlType: decrypted.body['controlType'] as String? ?? '',
            groupId: decrypted.body['groupId'] as String? ?? '',
            groupName: decrypted.body['groupName'] as String? ?? '',
            memberIds:
                (decrypted.body['memberIds'] as List<dynamic>? ?? const [])
                    .map((entry) => entry.toString())
                    .where((entry) => entry.isNotEmpty)
                    .toList(),
            adminUserId: decrypted.body['adminUserId'] as String? ?? '',
            removedUserId: decrypted.body['removedUserId'] as String? ?? '',
          ),
        );
        return;
      case 'history-request':
        await _handleRealtimeHistoryRequest(
          RealtimeHistoryRequest(
            friendId: decrypted.senderUserId,
            requestId: decrypted.body['requestId'] as String? ?? '',
          ),
        );
        return;
      case 'history-response':
        await _handleRealtimeHistoryResponse(
          RealtimeHistoryResponse(
            friendId: decrypted.senderUserId,
            requestId: decrypted.body['requestId'] as String? ?? '',
            conversations:
                (decrypted.body['conversations'] as List<dynamic>? ?? const [])
                    .map((entry) => entry as Map<String, dynamic>)
                    .toList(),
          ),
        );
        return;
      case 'delivery-ack':
        final messageId = decrypted.body['messageId'] as String? ?? '';
        if (messageId.isEmpty) {
          return;
        }
        await _markRealtimeMessageDelivered(decrypted.senderUserId, messageId);
        return;
      default:
        appLog('收到未知聊天消息类型：${decrypted.kind}');
        return;
    }
  }

  Future<void> _handleRealtimeIncomingMessage(
    RealtimeIncomingMessage incoming,
  ) async {
    if (incoming.groupId.isNotEmpty) {
      await _handleRealtimeIncomingGroupMessage(incoming);
      return;
    }

    var friend = _knownChatPeerById(incoming.friendId);
    if (friend == null) {
      await _loadFriendsSnapshot();
      friend = _knownChatPeerById(incoming.friendId);
    }
    if (friend == null) {
      return;
    }
    final messageFriend = friend;
    await _ensureChatConversationLoaded(messageFriend.id);
    if (_findMessage(messageFriend.id, incoming.messageId) != null) {
      return;
    }
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
          senderId: messageFriend.id,
          senderName: messageFriend.username,
        ),
      ],
    );
    await _persistChatSnapshot();
    notifyListeners();
  }

  Future<void> _handleRealtimeIncomingGroupMessage(
    RealtimeIncomingMessage incoming,
  ) async {
    if (_user == null || incoming.groupId.isEmpty) {
      return;
    }
    if (incoming.memberIds.isNotEmpty &&
        !incoming.memberIds.contains(_user!.id)) {
      return;
    }
    await _ensureChatConversationLoaded(incoming.groupId);
    if (_findMessageInConversation(incoming.groupId, incoming.messageId) !=
        null) {
      return;
    }

    var sender = _knownChatPeerById(incoming.friendId);
    if (sender == null) {
      await _loadFriendsSnapshot();
      await _mergeServerGroupsIntoChatConversations();
      sender = _knownChatPeerById(incoming.friendId);
    }
    if (sender == null) {
      return;
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
          senderId: messageSender.id,
          senderName: messageSender.username,
        ),
      ],
    );
    await _persistChatSnapshot();
    notifyListeners();
  }

  Future<void> _handleRealtimeGroupControl(RealtimeGroupControl control) async {
    if (_user == null || control.groupId.isEmpty) {
      return;
    }
    if (control.removedUserId == _user!.id ||
        !control.memberIds.contains(_user!.id)) {
      _deleteGroupConversation(control.groupId);
      _statusMessage = '已退出群聊，当前账号的群消息记录已从缓存和归档中删除。';
      notifyListeners();
      await _persistChatSnapshot();
      return;
    }

    await _ensureChatConversationLoaded(control.groupId);

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
    final members = control.memberIds
        .where((memberId) => memberId != _user!.id)
        .map((memberId) => memberById[memberId])
        .whereType<PublicUser>()
        .toList();
    final conversation = _ensureGroupConversation(
      id: control.groupId,
      title: control.groupName,
      members: members,
      adminUserId: control.adminUserId,
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

  Future<void> _handleRealtimeHistoryRequest(
    RealtimeHistoryRequest request,
  ) async {
    final friend = _knownChatPeerById(request.friendId);
    if (friend == null || request.requestId.isEmpty) {
      return;
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
    }
  }

  Future<void> _handleRealtimeHistoryResponse(
    RealtimeHistoryResponse response,
  ) async {
    final friend = _knownChatPeerById(response.friendId);
    if (friend == null) {
      return;
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
      return;
    }
    _statusMessage = '聊天历史已从在线好友同步。';
    await _persistChatSnapshot();
    await _syncKnownGroupSnapshotsSilently();
    notifyListeners();
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
    required List<PublicUser> members,
    required String adminUserId,
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
      conversations[index] = existing.copyWith(
        title: title.isEmpty ? existing.title : title,
        members: _uniqueFriends([...existing.members, ...members]),
        adminUserId: adminUserId.isEmpty ? existing.adminUserId : adminUserId,
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
      members: _uniqueFriends(members),
      adminUserId: adminUserId,
      isGroup: true,
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
        appLog('群聊快照解密失败：groupId=${group.id}', error);
      }
    }
    _ensureGroupConversation(
      id: group.id,
      title: title,
      members: group.members.where((member) => member.id != _user!.id).toList(),
      adminUserId: group.adminUserId,
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
    return conversation.isGroup && _token != null && _vaultKey != null;
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
      'isGroup': conversation.isGroup,
      'friendId': conversation.friend?.id ?? '',
      'adminUserId': conversation.adminUserId,
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
      data['senderName'] = message.sentByMe ? _user?.username ?? '' : '';
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
      members: _uniqueFriends([...?existing?.members, ...rawMembers]),
      adminUserId:
          entry['adminUserId'] as String? ?? existing?.adminUserId ?? '',
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
