// ignore_for_file: invalid_use_of_protected_member

part of '../../../main.dart';

extension _ChatTab on _VaultScreenState {
  Widget _buildChatTab(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller.chatListenable,
      builder: (context, _) {
        final conversations = widget.controller.chatConversations;
        final realtimeConfig = widget.controller.realtimeConfig;
        final realtimeReady = realtimeConfig?.signalingEnabled == true;
        final realtimeNotice = realtimeReady
            ? '实时信令已就绪，消息会通过端到端加密通道发送，并同步到当前账号的加密归档。'
            : '实时通道暂未建立，消息会先加密缓存在当前设备，并在联网后同步到服务端密文归档。';
        final statusNotice = widget.controller.busy
            ? '处理中...'
            : widget.controller.statusMessage;
        final showStatusNotice =
            statusNotice != null &&
            statusNotice.isNotEmpty &&
            _dismissedPageStatusMessage != statusNotice;
        final showRealtimeNotice =
            _dismissedChatRealtimeNotice != realtimeNotice;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildChatHeader(context, realtimeReady),
              const SizedBox(height: 12),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: widget.controller.refreshChatOverview,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (showStatusNotice) ...[
                        SliverToBoxAdapter(
                          child: _PageNotice(
                            message: statusNotice,
                            tone: _PageNoticeTone.neutral,
                            onClose: () {
                              setState(() {
                                _dismissedPageStatusMessage = statusNotice;
                              });
                            },
                          ),
                        ),
                      ],
                      if (showRealtimeNotice) ...[
                        if (showStatusNotice)
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        SliverToBoxAdapter(
                          child: _PageNotice(
                            message: realtimeNotice,
                            tone: realtimeReady
                                ? _PageNoticeTone.success
                                : _PageNoticeTone.warn,
                            onClose: () {
                              setState(() {
                                _dismissedChatRealtimeNotice = realtimeNotice;
                              });
                            },
                          ),
                        ),
                      ],
                      if (showStatusNotice || showRealtimeNotice)
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      if (conversations.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              '还没有会话，可以从好友详情发起聊天',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: context.sx.mutedText),
                            ),
                          ),
                        )
                      else
                        SliverToBoxAdapter(
                          child: Card(
                            child: Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < conversations.length;
                                  index++
                                ) ...[
                                  _ConversationTile(
                                    conversation: conversations[index],
                                    onTap: () =>
                                        _showConversation(conversations[index]),
                                  ),
                                  if (index != conversations.length - 1)
                                    Divider(
                                      height: 1,
                                      color: context.sx.border,
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChatHeader(BuildContext context, bool realtimeReady) {
    return Row(
      children: [
        Expanded(
          child: _buildModuleHeader(
            icon: Icons.chat_bubble_outline,
            title: '聊天',
            tag: realtimeReady ? '实时加密' : '归档同步',
          ),
        ),
        const SizedBox(width: 12),
        Text(
          realtimeReady ? '自动同步' : '等待联网',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: realtimeReady ? context.sx.success : context.sx.mutedText,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: '更多',
          icon: const Icon(Icons.add_circle_outline),
          onSelected: (value) {
            if (value == 'group') {
              _showStartGroupChatPage();
              return;
            }
            if (value == 'friend') {
              _showAddFriendPage();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'group',
              child: ListTile(
                leading: Icon(Icons.group_add_outlined),
                title: Text('发起群聊'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'friend',
              child: ListTile(
                leading: Icon(Icons.person_add_alt_1_outlined),
                title: Text('添加好友'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showConversation(ChatConversation conversation) async {
    if (conversation.isGroup) {
      unawaited(widget.controller.openGroupChat(conversation.id));
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => _ChatRoomPage(
            controller: widget.controller,
            conversationId: conversation.id,
          ),
        ),
      );
      return;
    }

    final friend = conversation.friend;
    if (friend == null) {
      return;
    }
    await _showChatRoom(friend);
  }

  Future<void> _showChatRoom(PublicUser friend) async {
    unawaited(widget.controller.openChatWith(friend));
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _ChatRoomPage(
          controller: widget.controller,
          conversationId: friend.id,
          friend: friend,
        ),
      ),
    );
  }

  Future<void> _showStartGroupChatPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            _StartGroupChatPage(controller: widget.controller),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final ChatConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lastMessage = conversation.lastMessage;
    final title = conversation.displayTitle;
    final subtitle = conversation.isGroup
        ? '${conversation.members.length + 1} 人 · 端到端加密群聊'
        : '端到端加密会话';
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          conversation.isGroup
              ? _GroupAvatar(conversation: conversation)
              : _ChatAvatar(user: conversation.friend!),
          if (conversation.pendingCount > 0)
            Positioned(
              right: -5,
              top: -5,
              child: _RequestBadge(count: conversation.pendingCount),
            ),
        ],
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        lastMessage == null
            ? subtitle
            : '${_conversationStatusPrefix(lastMessage)}${lastMessage.text}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: lastMessage == null
          ? const Icon(Icons.chevron_right_rounded)
          : Text(
              _formatChatTime(lastMessage.createdAt),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.sx.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

enum _PageNoticeTone { neutral, success, warn }

class _PageNotice extends StatelessWidget {
  const _PageNotice({
    required this.message,
    required this.tone,
    required this.onClose,
  });

  final String message;
  final _PageNoticeTone tone;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final toneColor = switch (tone) {
      _PageNoticeTone.success => context.sx.success,
      _PageNoticeTone.warn => context.sx.danger,
      _PageNoticeTone.neutral => context.sx.mutedText,
    };
    final icon = switch (tone) {
      _PageNoticeTone.success => Icons.lock_outline,
      _PageNoticeTone.warn => Icons.info_outline,
      _PageNoticeTone.neutral => Icons.notifications_none_outlined,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.sx.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.sx.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: toneColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: toneColor,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onClose,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close, size: 18, color: context.sx.mutedText),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatRoomPage extends StatefulWidget {
  const _ChatRoomPage({
    required this.controller,
    required this.conversationId,
    this.friend,
  });

  final AppController controller;
  final String conversationId;
  final PublicUser? friend;

  @override
  State<_ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<_ChatRoomPage> {
  final _inputController = TextEditingController();
  bool _showTools = false;

  @override
  void initState() {
    super.initState();
    _inputController.clear();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller.chatListenable,
      builder: (context, _) {
        final conversation = _conversation();
        final messages = conversation?.messages ?? [];
        final isGroup = conversation?.isGroup == true;
        final friend = widget.friend ?? conversation?.friend;
        final friendOnline =
            friend != null && widget.controller.isChatFriendOnline(friend.id);
        final groupOnlineCount =
            conversation?.members
                .where(
                  (member) => widget.controller.isChatFriendOnline(member.id),
                )
                .length ??
            0;
        final title =
            conversation?.displayTitle ??
            (friend == null
                ? '聊天'
                : (friend.username.isEmpty ? friend.email : friend.username));
        final messageCount = messages.length;
        return Scaffold(
          backgroundColor: context.sx.scaffold,
          appBar: AppBar(
            centerTitle: true,
            toolbarHeight: 74,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _OnlineStatusDot(
                      online: isGroup ? groupOnlineCount > 0 : friendOnline,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isGroup
                      ? '$groupOnlineCount 个成员在线 · 群消息端到端加密并同步归档'
                      : (friendOnline
                            ? '在线 · 端到端加密发送'
                            : '离线 · 消息会先进入加密归档并等待同步'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: context.sx.mutedText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            actions: [
              if (isGroup && conversation != null)
                IconButton(
                  tooltip: '群聊信息',
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (context) => _GroupChatDetailPage(
                          controller: widget.controller,
                          conversationId: conversation.id,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.more_horiz),
                )
              else if (friend != null)
                IconButton(
                  tooltip: '好友信息',
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (context) => _FriendDetailPage(
                          controller: widget.controller,
                          friend: friend,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.more_horiz),
                ),
            ],
          ),
          body: SafeArea(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    context.sx.scaffold,
                    context.sx.subtle,
                    context.sx.scaffold,
                  ],
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                      itemCount: messageCount == 0 ? 1 : messageCount,
                      itemBuilder: (context, index) {
                        if (messageCount == 0) {
                          return const _ChatEmptyState();
                        }
                        final message = messages[messageCount - 1 - index];
                        return _ChatMessageBubble(
                          controller: widget.controller,
                          conversation: conversation,
                          friend: friend,
                          message: message,
                        );
                      },
                    ),
                  ),
                  _ChatComposer(
                    controller: widget.controller,
                    conversation: conversation,
                    friend: friend,
                    textController: _inputController,
                    showTools: _showTools,
                    onToggleTools: () {
                      setState(() {
                        _showTools = !_showTools;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  ChatConversation? _conversation() {
    for (final conversation in widget.controller.chatConversations) {
      if (conversation.id == widget.conversationId) {
        return conversation;
      }
    }
    return null;
  }
}

class _OnlineStatusDot extends StatelessWidget {
  const _OnlineStatusDot({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final color = online ? context.sx.success : context.sx.danger;
    return Tooltip(
      message: online ? '好友在线' : '好友离线',
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: context.sx.card, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(90),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 140),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          decoration: BoxDecoration(
            color: context.sx.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.sx.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.sx.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.lock_outline,
                  color: context.sx.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '好友在线后会自动建立端到端加密通道。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.sx.mutedText,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({
    required this.controller,
    required this.conversation,
    required this.friend,
    required this.message,
  });

  final AppController controller;
  final ChatConversation? conversation;
  final PublicUser? friend;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isMine = message.sentByMe;
    final bubbleColor = isMine ? context.sx.primary : context.sx.card;
    final foreground = isMine ? context.sx.onPrimary : context.sx.text;
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.68;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            _ChatAvatar(
              user:
                  _messageSender() ??
                  friend ??
                  PublicUser(id: 'unknown', username: '?', email: ''),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(22),
                      topRight: const Radius.circular(22),
                      bottomLeft: Radius.circular(isMine ? 22 : 8),
                      bottomRight: Radius.circular(isMine ? 8 : 22),
                    ),
                    border: Border.all(
                      color: isMine ? Colors.transparent : context.sx.border,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.black.withAlpha(70)
                            : context.sx.border.withAlpha(90),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Text(
                    message.text,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: foreground,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                _ChatMessageStatusBar(
                  controller: controller,
                  conversation: conversation,
                  friend: friend,
                  message: message,
                ),
              ],
            ),
          ),
          if (isMine) ...[
            const SizedBox(width: 10),
            _ChatAvatar(
              isMine: true,
              user: PublicUser(
                id: 'me',
                username: '我',
                email: 'secure-x.local',
              ),
            ),
          ],
        ],
      ),
    );
  }

  PublicUser? _messageSender() {
    if (message.sentByMe || conversation == null || !conversation!.isGroup) {
      return null;
    }
    for (final member in conversation!.members) {
      if (member.id == message.senderId) {
        return member;
      }
    }
    if (message.senderName.isNotEmpty) {
      return PublicUser(
        id: message.senderId,
        username: message.senderName,
        email: '',
      );
    }
    return null;
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({required this.user, this.isMine = false});

  final PublicUser user;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final source = user.username.trim().isNotEmpty
        ? user.username.trim()
        : user.email.trim();
    final label = source.isNotEmpty ? source[0].toUpperCase() : '?';
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: isMine ? context.sx.primary : context.sx.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMine ? context.sx.primary : context.sx.border,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: isMine ? context.sx.onPrimary : context.sx.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.conversation});

  final ChatConversation conversation;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: context.sx.gradient),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.sx.border),
      ),
      child: const Icon(Icons.groups_2_outlined, color: Colors.white, size: 24),
    );
  }
}

class _StartGroupChatPage extends StatefulWidget {
  const _StartGroupChatPage({required this.controller});

  final AppController controller;

  @override
  State<_StartGroupChatPage> createState() => _StartGroupChatPageState();
}

class _StartGroupChatPageState extends State<_StartGroupChatPage> {
  final _groupNameController = TextEditingController();
  final Set<String> _selectedFriendIds = {};
  String? _localMessage;

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final friends = widget.controller.friends;
        final selectedFriends = _selectedFriends(friends);
        return Scaffold(
          appBar: AppBar(
            title: Text('发起群聊 (${selectedFriends.length})'),
            actions: [
              TextButton(
                onPressed: widget.controller.busy ? null : _complete,
                child: const Text('完成'),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const _SettingsDetailHeader(
                      icon: Icons.group_add_outlined,
                      title: '选择好友',
                    ),
                    const SizedBox(height: 12),
                    if (selectedFriends.length > 1) ...[
                      TextField(
                        controller: _groupNameController,
                        decoration: const InputDecoration(
                          labelText: '群聊名称',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_localMessage != null) ...[
                      _InlineNotice(message: _localMessage!),
                      const SizedBox(height: 12),
                    ],
                    Card(
                      child: friends.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(22),
                              child: Text(
                                '还没有好友，可以先从聊天页右上角添加好友。',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: context.sx.mutedText),
                              ),
                            )
                          : Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < friends.length;
                                  index++
                                ) ...[
                                  CheckboxListTile(
                                    value: _selectedFriendIds.contains(
                                      friends[index].id,
                                    ),
                                    onChanged: (checked) {
                                      setState(() {
                                        if (checked == true) {
                                          _selectedFriendIds.add(
                                            friends[index].id,
                                          );
                                        } else {
                                          _selectedFriendIds.remove(
                                            friends[index].id,
                                          );
                                        }
                                        _localMessage = null;
                                      });
                                    },
                                    secondary: _ChatAvatar(
                                      user: friends[index],
                                    ),
                                    title: Text(
                                      friends[index].username.isEmpty
                                          ? '(未命名用户)'
                                          : friends[index].username,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(friends[index].email),
                                  ),
                                  if (index != friends.length - 1)
                                    Divider(
                                      height: 1,
                                      color: context.sx.border,
                                    ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<PublicUser> _selectedFriends(List<PublicUser> friends) {
    return friends
        .where((friend) => _selectedFriendIds.contains(friend.id))
        .toList();
  }

  Future<void> _complete() async {
    final selectedFriends = _selectedFriends(widget.controller.friends);
    setState(() {
      _localMessage = null;
    });
    if (selectedFriends.isEmpty) {
      setState(() {
        _localMessage = '请选择至少一个好友。';
      });
      return;
    }

    if (selectedFriends.length == 1) {
      final friend = selectedFriends.first;
      unawaited(widget.controller.openChatWith(friend));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (context) => _ChatRoomPage(
            controller: widget.controller,
            conversationId: friend.id,
            friend: friend,
          ),
        ),
      );
      return;
    }

    final title = _groupNameController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _localMessage = '多人群聊需要填写群聊名称。';
      });
      return;
    }
    final conversation = await widget.controller.createGroupChat(
      title: title,
      members: selectedFriends,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (context) => _ChatRoomPage(
          controller: widget.controller,
          conversationId: conversation.id,
        ),
      ),
    );
  }
}

class _GroupChatDetailPage extends StatefulWidget {
  const _GroupChatDetailPage({
    required this.controller,
    required this.conversationId,
  });

  final AppController controller;
  final String conversationId;

  @override
  State<_GroupChatDetailPage> createState() => _GroupChatDetailPageState();
}

class _GroupChatDetailPageState extends State<_GroupChatDetailPage> {
  final Set<String> _inviteFriendIds = {};

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final conversation = _conversation();
        if (conversation == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('群聊信息')),
            body: const Center(child: Text('群聊不存在')),
          );
        }
        final isAdmin =
            conversation.adminUserId == (widget.controller.user?.id ?? '');
        final inviteCandidates = widget.controller.friends
            .where(
              (friend) =>
                  !conversation.members.any((member) => member.id == friend.id),
            )
            .toList();
        return Scaffold(
          appBar: AppBar(title: const Text('群聊信息')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SettingsDetailHeader(
                          icon: Icons.groups_2_outlined,
                          title: conversation.displayTitle,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${conversation.members.length + 1} 人 · 服务端只保存不可解密的群聊密文归档',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: context.sx.mutedText),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          const _ListCardHeader(title: '群成员'),
                          _GroupMemberTile(
                            name:
                                '${widget.controller.user?.username ?? '我'}（我）',
                            email: widget.controller.user?.email ?? '',
                            admin: isAdmin,
                          ),
                          Divider(height: 1, color: context.sx.border),
                          for (
                            var index = 0;
                            index < conversation.members.length;
                            index++
                          ) ...[
                            _GroupMemberTile(
                              name: conversation.members[index].username.isEmpty
                                  ? '(未命名用户)'
                                  : conversation.members[index].username,
                              email: conversation.members[index].email,
                              admin:
                                  conversation.members[index].id ==
                                  conversation.adminUserId,
                              trailing: isAdmin
                                  ? TextButton(
                                      onPressed: () => _removeMember(
                                        conversation,
                                        conversation.members[index],
                                      ),
                                      child: const Text('移除'),
                                    )
                                  : null,
                            ),
                            if (index != conversation.members.length - 1)
                              Divider(height: 1, color: context.sx.border),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          const _ListCardHeader(title: '邀请好友'),
                          if (inviteCandidates.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(22),
                              child: Text(
                                '暂无可邀请的好友。',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: context.sx.mutedText),
                              ),
                            )
                          else ...[
                            for (
                              var index = 0;
                              index < inviteCandidates.length;
                              index++
                            ) ...[
                              CheckboxListTile(
                                value: _inviteFriendIds.contains(
                                  inviteCandidates[index].id,
                                ),
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _inviteFriendIds.add(
                                        inviteCandidates[index].id,
                                      );
                                    } else {
                                      _inviteFriendIds.remove(
                                        inviteCandidates[index].id,
                                      );
                                    }
                                  });
                                },
                                secondary: _ChatAvatar(
                                  user: inviteCandidates[index],
                                ),
                                title: Text(
                                  inviteCandidates[index].username.isEmpty
                                      ? '(未命名用户)'
                                      : inviteCandidates[index].username,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(inviteCandidates[index].email),
                              ),
                              if (index != inviteCandidates.length - 1)
                                Divider(height: 1, color: context.sx.border),
                            ],
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _inviteFriendIds.isEmpty
                                      ? null
                                      : () => _invite(conversation),
                                  icon: const Icon(Icons.person_add_outlined),
                                  label: const Text('邀请进群'),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '群操作',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '退出后会删除当前账号在本机缓存和加密归档中的该群成员信息与聊天记录，后续将无法再恢复。',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: context.sx.mutedText),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _confirmLeave(conversation),
                                icon: const Icon(Icons.logout_rounded),
                                label: const Text('退出群聊'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: context.sx.danger,
                                  side: BorderSide(color: context.sx.danger),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  ChatConversation? _conversation() {
    for (final conversation in widget.controller.chatConversations) {
      if (conversation.id == widget.conversationId) {
        return conversation;
      }
    }
    return null;
  }

  Future<void> _removeMember(
    ChatConversation conversation,
    PublicUser member,
  ) async {
    final members = conversation.members
        .where((current) => current.id != member.id)
        .toList();
    await widget.controller.updateGroupChat(
      conversationId: conversation.id,
      members: members,
    );
  }

  Future<void> _invite(ChatConversation conversation) async {
    final invitees = widget.controller.friends
        .where((friend) => _inviteFriendIds.contains(friend.id))
        .toList();
    await widget.controller.updateGroupChat(
      conversationId: conversation.id,
      members: [...conversation.members, ...invitees],
    );
    setState(_inviteFriendIds.clear);
  }

  Future<void> _confirmLeave(ChatConversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出群聊'),
        content: Text(
          '确定退出“${conversation.displayTitle}”吗？退出后当前账号的该群聊记录会从本机缓存和加密归档中删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.controller.leaveGroupChat(conversation.id);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    Navigator.of(context).maybePop();
  }
}

class _GroupMemberTile extends StatelessWidget {
  const _GroupMemberTile({
    required this.name,
    required this.email,
    this.admin = false,
    this.trailing,
  });

  final String name;
  final String email;
  final bool admin;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _ChatAvatar(
        user: PublicUser(id: '', username: name, email: ''),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(email.isEmpty ? (admin ? '群管理' : '群成员') : email),
      trailing:
          trailing ??
          (admin
              ? Chip(
                  label: const Text('群管理'),
                  backgroundColor: context.sx.accentSoft,
                  labelStyle: TextStyle(
                    color: context.sx.primary,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : null),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.conversation,
    required this.friend,
    required this.textController,
    required this.showTools,
    required this.onToggleTools,
  });

  final AppController controller;
  final ChatConversation? conversation;
  final PublicUser? friend;
  final TextEditingController textController;
  final bool showTools;
  final VoidCallback onToggleTools;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.sx.card,
        border: Border(top: BorderSide(color: context.sx.border)),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withAlpha(110)
                : context.sx.border.withAlpha(120),
            blurRadius: 26,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Row(
                children: [
                  _ComposerIconButton(
                    tooltip: '语音输入',
                    icon: Icons.keyboard_voice_outlined,
                    onPressed: null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: textController,
                      minLines: 1,
                      maxLines: 4,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: context.sx.text,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: '输入加密消息',
                        hintStyle: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(
                              color: context.sx.mutedText,
                              fontWeight: FontWeight.w700,
                            ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ComposerIconButton(
                    tooltip: '更多',
                    icon: showTools
                        ? Icons.keyboard_arrow_down
                        : Icons.add_circle_outline,
                    onPressed: onToggleTools,
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () async {
                      final text = textController.text;
                      textController.clear();
                      if (conversation?.isGroup == true) {
                        await controller.sendGroupChatMessage(
                          conversation: conversation!,
                          text: text,
                        );
                        return;
                      }
                      final directFriend = friend;
                      if (directFriend == null) {
                        return;
                      }
                      await controller.sendLocalChatMessage(
                        friend: directFriend,
                        text: text,
                      );
                    },
                    child: const Text('发送'),
                  ),
                ],
              ),
            ),
            if (showTools)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                child: GridView.count(
                  crossAxisCount: MediaQuery.sizeOf(context).width < 520
                      ? 4
                      : 6,
                  shrinkWrap: true,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  physics: const NeverScrollableScrollPhysics(),
                  children: const [
                    _ChatToolButton(icon: Icons.image_outlined, label: '图片'),
                    _ChatToolButton(
                      icon: Icons.insert_drive_file_outlined,
                      label: '文件',
                    ),
                    _ChatToolButton(icon: Icons.videocam_outlined, label: '视频'),
                    _ChatToolButton(
                      icon: Icons.location_on_outlined,
                      label: '位置',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: enabled ? context.sx.accentSoft : context.sx.subtle,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.sx.border),
          ),
          child: Icon(
            icon,
            color: enabled ? context.sx.primary : context.sx.mutedText,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _ChatToolButton extends StatelessWidget {
  const _ChatToolButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: context.sx.subtle,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.sx.border),
          ),
          child: Icon(icon, color: context.sx.mutedText),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: context.sx.mutedText),
        ),
      ],
    );
  }
}

String _messageStatusText(ChatMessage message) {
  final time = _formatChatTime(message.createdAt);
  if (message.status == 'localOnly') {
    return '$time · 未送达，等待同步到服务端归档';
  }
  if (message.status == 'pending') {
    return '$time · 待发送，等待目标设备拉取';
  }
  if (message.status == 'sent') {
    return '$time · 已发送，等待确认';
  }
  return '$time · 已送达';
}

String _conversationStatusPrefix(ChatMessage message) {
  if (!message.sentByMe) {
    return '';
  }
  if (message.status == 'localOnly') {
    return '[未送达] ';
  }
  if (message.status == 'pending') {
    return '[待发送] ';
  }
  if (message.status == 'sent') {
    return '[已发送] ';
  }
  return '';
}

class _ChatMessageStatusBar extends StatelessWidget {
  const _ChatMessageStatusBar({
    required this.controller,
    required this.conversation,
    required this.friend,
    required this.message,
  });

  final AppController controller;
  final ChatConversation? conversation;
  final PublicUser? friend;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final icon = _statusIcon(message.status);
    final color = _statusColor(context, message.status);
    final canRetry =
        message.sentByMe &&
        (message.status == 'localOnly' || message.status == 'pending');

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: context.sx.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.sx.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                _messageStatusText(message),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.sx.mutedText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        if (canRetry) ...[
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              if (conversation?.isGroup == true) {
                controller.retryGroupChatMessage(
                  conversation: conversation!,
                  message: message,
                );
                return;
              }
              final directFriend = friend;
              if (directFriend == null) {
                return;
              }
              controller.retryChatMessage(
                friend: directFriend,
                message: message,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: context.sx.accentSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 13, color: context.sx.primary),
                  const SizedBox(width: 2),
                  Text(
                    '重发',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.sx.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  IconData _statusIcon(String status) {
    if (status == 'localOnly') {
      return Icons.cloud_off_outlined;
    }
    if (status == 'pending') {
      return Icons.schedule_outlined;
    }
    if (status == 'sent') {
      return Icons.done;
    }
    return Icons.done_all;
  }

  Color _statusColor(BuildContext context, String status) {
    if (status == 'localOnly') {
      return context.sx.danger;
    }
    if (status == 'pending') {
      return context.sx.mutedText;
    }
    if (status == 'sent') {
      return context.sx.primary;
    }
    return context.sx.success;
  }
}

String _formatChatTime(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final messageDay = DateTime(time.year, time.month, time.day);
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  if (messageDay == today) {
    return '$hour:$minute';
  }
  return '${time.month}月${time.day}日';
}
