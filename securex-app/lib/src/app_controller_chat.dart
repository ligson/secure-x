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
      await _connectRealtimeChat();
      _statusMessage = _realtimeConfig!.signalingEnabled
          ? '实时聊天配置已加载。'
          : '实时聊天信令暂未启用，消息会先加密保存在本机。';
    });
  }

  Future<void> openChatWith(PublicUser friend) async {
    _ensureConversation(friend);
    await _connectRealtimeChat();
    await _realtimeChatService.openPeer(friend);
    notifyListeners();
  }

  Future<ChatConversation> createGroupChat({
    required String title,
    required List<PublicUser> members,
  }) async {
    final cleanMembers = _uniqueFriends(members);
    final conversation = ChatConversation(
      id: 'group-${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? '未命名群聊' : title.trim(),
      members: cleanMembers,
      adminUserId: _user?.id ?? '',
      isGroup: true,
      messages: [],
    );
    _chatConversations = [..._chatConversations, conversation];
    _sortChatConversations();
    notifyListeners();
    await _persistChatSnapshot();
    await openGroupChat(conversation.id);
    return conversation;
  }

  Future<void> openGroupChat(String conversationId) async {
    final conversation = _conversationById(conversationId);
    if (conversation == null || !conversation.isGroup) {
      return;
    }
    await _connectRealtimeChat();
    for (final member in conversation.members) {
      await _realtimeChatService.openPeer(member);
    }
    notifyListeners();
  }

  Future<void> _openRealtimePeersForHistorySync() async {
    if (_token == null || _user == null || _vaultKey == null) {
      return;
    }
    await _connectRealtimeChat();
    for (final friend in _friends) {
      await _realtimeChatService.openPeer(friend);
    }
  }

  Future<void> updateGroupChat({
    required String conversationId,
    String? title,
    List<PublicUser>? members,
    String? adminUserId,
  }) async {
    final conversations = [..._chatConversations];
    final index = conversations.indexWhere(
      (conversation) => conversation.id == conversationId,
    );
    if (index < 0 || !conversations[index].isGroup) {
      return;
    }

    conversations[index] = conversations[index].copyWith(
      title: title,
      members: members == null ? null : _uniqueFriends(members),
      adminUserId: adminUserId,
    );
    _chatConversations = conversations;
    _sortChatConversations();
    notifyListeners();
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
    await _sendRealtimeGroupControl(
      conversation: conversation,
      recipients: remainingMembers,
      controlType: 'member-left',
      removedUserId: currentUser.id,
      memberIds: remainingMembers.map((member) => member.id).toList(),
      adminUserId: nextAdminUserId,
    );
    _deleteGroupConversation(conversation.id);
    _statusMessage = '已退出群聊，本机群消息记录已删除。';
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
        ? '消息已通过端到端加密通道发送，等待对方确认。'
        : '好友未在线或实时通道未建立，消息已加密保存在本机。';
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
        : '群成员暂未建立实时通道，消息已加密保存在本机。';
    notifyListeners();

    await _persistChatSnapshot();
    notifyListeners();
  }

  Future<void> retryChatMessage({
    required PublicUser friend,
    required ChatMessage message,
  }) async {
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
        ? '消息已重新通过端到端加密通道发送，等待对方确认。'
        : '实时通道仍未建立，消息继续加密保存在本机。';
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
        : '群实时通道仍未建立，消息继续加密保存在本机。';
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
    return conversation;
  }

  void _replaceConversationMessages(
    PublicUser friend,
    List<ChatMessage> Function(List<ChatMessage> messages) update,
  ) {
    final conversations = [..._chatConversations];
    final index = conversations.indexWhere(
      (conversation) => conversation.friend?.id == friend.id,
    );
    if (index < 0) {
      conversations.add(
        ChatConversation(friend: friend, messages: _sortMessages(update([]))),
      );
    } else {
      final conversation = conversations[index];
      conversations[index] = conversation.copyWith(
        messages: _sortMessages(update([...conversation.messages])),
      );
    }
    _chatConversations = conversations;
    _sortChatConversations();
  }

  void _replaceConversationMessagesById(
    String conversationId,
    List<ChatMessage> Function(List<ChatMessage> messages) update,
  ) {
    final conversations = [..._chatConversations];
    final index = conversations.indexWhere(
      (conversation) => conversation.id == conversationId,
    );
    if (index < 0) {
      return;
    }
    final conversation = conversations[index];
    conversations[index] = conversation.copyWith(
      messages: _sortMessages(update([...conversation.messages])),
    );
    _chatConversations = conversations;
    _sortChatConversations();
  }

  List<ChatMessage> _sortMessages(List<ChatMessage> messages) {
    return messages..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> _connectRealtimeChat() async {
    if (_token == null || _user == null) {
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
      iceServers: _realtimeConfig!.iceServers,
    );
  }

  Future<bool> _sendRealtimeMessage(
    PublicUser friend,
    ChatMessage message,
  ) async {
    if (_realtimeConfig?.signalingEnabled != true) {
      return false;
    }
    try {
      await _connectRealtimeChat();
      return _realtimeChatService.sendMessage(friend: friend, message: message);
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
      await _connectRealtimeChat();
      for (final member in conversation.members) {
        if (message.deliveredPeerIds.contains(member.id)) {
          continue;
        }
        final delivered = await _realtimeChatService.sendMessage(
          friend: member,
          message: message,
          conversation: conversation,
        );
        if (delivered) {
          sentPeerIds.add(member.id);
        }
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
  }) async {
    if (_realtimeConfig?.signalingEnabled != true) {
      return;
    }
    try {
      await _connectRealtimeChat();
      for (final member in _uniqueFriends(recipients)) {
        await _realtimeChatService.sendGroupControl(
          friend: member,
          conversation: conversation,
          controlType: controlType,
          removedUserId: removedUserId,
          memberIds: _uniqueIds(memberIds),
          adminUserId: adminUserId,
        );
      }
    } catch (error) {
      appLog('实时群聊控制消息发送失败', error);
    }
  }

  Future<void> _handleRealtimeIncomingMessage(
    RealtimeIncomingMessage incoming,
  ) async {
    if (incoming.groupId.isNotEmpty) {
      await _handleRealtimeIncomingGroupMessage(incoming);
      return;
    }

    var friend = _friendById(incoming.friendId);
    if (friend == null) {
      await _loadFriendsSnapshot();
      friend = _friendById(incoming.friendId);
    }
    if (friend == null) {
      return;
    }
    final messageFriend = friend;
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
    if (_findMessageInConversation(incoming.groupId, incoming.messageId) !=
        null) {
      return;
    }

    var sender = _friendById(incoming.friendId);
    if (sender == null) {
      await _loadFriendsSnapshot();
      sender = _friendById(incoming.friendId);
    }
    if (sender == null) {
      return;
    }
    final messageSender = sender;
    final memberById = {for (final friend in _friends) friend.id: friend};
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
      _statusMessage = '已退出群聊，本机群消息记录已删除。';
      notifyListeners();
      await _persistChatSnapshot();
      return;
    }

    var memberById = {for (final friend in _friends) friend.id: friend};
    if (!control.memberIds.every(
      (memberId) => memberId == _user!.id || memberById.containsKey(memberId),
    )) {
      await _loadFriendsSnapshot();
      memberById = {for (final friend in _friends) friend.id: friend};
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
    );
    _statusMessage = '群聊成员已更新。';
    notifyListeners();
  }

  Future<void> _markRealtimeMessageDelivered(
    String friendId,
    String messageId,
  ) async {
    final friend = _friendById(friendId);
    if (friend == null) {
      return;
    }
    if (_findMessage(friend.id, messageId) != null) {
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
    final online =
        normalizedStatus == 'presence-online' ||
        normalizedStatus == 'ready' ||
        normalizedStatus == 'relay-ready';
    final offline = normalizedStatus == 'presence-offline';

    if (online || offline) {
      _chatFriendOnline[friendId] = online;
      notifyListeners();
    }

    if (online) {
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
      final requested = await _realtimeChatService.requestHistory(
        friend: friend,
      );
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
    final friend = _friendById(request.friendId);
    if (friend == null || request.requestId.isEmpty) {
      return;
    }
    final conversations = _historyConversationsForPeer(friend.id);
    try {
      await _realtimeChatService.sendHistoryResponse(
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
    final friend = _friendById(response.friendId);
    if (friend == null) {
      return;
    }
    var changed = false;
    for (final entry in response.conversations) {
      final isGroup = entry['isGroup'] as bool? ?? false;
      if (isGroup) {
        changed = _mergeGroupHistory(friend, entry) || changed;
      } else {
        changed = _mergeDirectHistory(friend, entry) || changed;
      }
    }
    if (!changed) {
      return;
    }
    _statusMessage = '聊天历史已从在线好友同步。';
    await _persistChatSnapshot();
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
    _sortChatConversations();
  }

  ChatConversation _ensureGroupConversation({
    required String id,
    required String title,
    required List<PublicUser> members,
    required String adminUserId,
  }) {
    final conversations = [..._chatConversations];
    final index = conversations.indexWhere(
      (conversation) => conversation.id == id,
    );
    if (index >= 0) {
      final existing = conversations[index];
      conversations[index] = existing.copyWith(
        title: title.isEmpty ? existing.title : title,
        members: _uniqueFriends([...existing.members, ...members]),
        adminUserId: adminUserId.isEmpty ? existing.adminUserId : adminUserId,
      );
      _chatConversations = conversations;
      _sortChatConversations();
      return conversations[index];
    }

    final conversation = ChatConversation(
      id: id,
      title: title.isEmpty ? '未命名群聊' : title,
      members: _uniqueFriends(members),
      adminUserId: adminUserId,
      isGroup: true,
      messages: [],
    );
    _chatConversations = [..._chatConversations, conversation];
    _sortChatConversations();
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

  List<Map<String, dynamic>> _historyConversationsForPeer(String peerId) {
    final result = <Map<String, dynamic>>[];
    for (final conversation in _chatConversations) {
      if (conversation.isGroup) {
        final peerInGroup = conversation.members.any(
          (member) => member.id == peerId,
        );
        if (!peerInGroup) {
          continue;
        }
        result.add(_conversationToHistoryJson(conversation));
        continue;
      }
      if (conversation.friend?.id == peerId) {
        result.add(_conversationToHistoryJson(conversation));
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

  bool _mergeDirectHistory(PublicUser peer, Map<String, dynamic> entry) {
    final messages = _historyMessagesFromEntry(entry, peer.id);
    if (messages.isEmpty) {
      return false;
    }
    final before = _findDirectConversation(peer.id)?.messages.length ?? 0;
    _replaceConversationMessages(peer, (current) {
      return _mergeMessages(current, messages);
    });
    final after = _findDirectConversation(peer.id)?.messages.length ?? 0;
    return after > before;
  }

  bool _mergeGroupHistory(PublicUser peer, Map<String, dynamic> entry) {
    final groupId = entry['id'] as String? ?? '';
    if (groupId.isEmpty) {
      return false;
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

  Future<void> _flushPendingRealtimeMessages(String friendId) async {
    final friend = _friendById(friendId);
    if (friend == null) {
      return;
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
              (message.status == 'pending' ||
                  message.status == 'localOnly' ||
                  message.status == 'sent'),
        ),
      );
    }
    for (final message in pending) {
      final conversation = _conversationById(message.friendId);
      final deliveredToChannel = conversation?.isGroup == true
          ? await _realtimeChatService.sendMessage(
              friend: friend,
              message: message,
              conversation: conversation,
            )
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
