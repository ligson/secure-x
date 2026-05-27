// ignore_for_file: invalid_use_of_protected_member

part of '../../../main.dart';

class _ChatRouteResult {
  static const leftGroup = 'left-group';
  static const dissolvedGroup = 'dissolved-group';
  static const deletedConversation = 'deleted-conversation';
}

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
                            tone: _statusNoticeTone(statusNotice),
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
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => _ChatRoomPage(
            controller: widget.controller,
            conversationId: conversation.id,
          ),
        ),
      );
      _handleChatRouteResult(result);
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
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => _ChatRoomPage(
          controller: widget.controller,
          conversationId: friend.id,
          friend: friend,
        ),
      ),
    );
    _handleChatRouteResult(result);
  }

  Future<void> _showStartGroupChatPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            _StartGroupChatPage(controller: widget.controller),
      ),
    );
  }

  void _handleChatRouteResult(String? result) {
    if (!mounted || result == null) {
      return;
    }
    final message = widget.controller.statusMessage;
    if (message == null || message.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
    setState(() {
      _dismissedPageStatusMessage = null;
    });
  }

  _PageNoticeTone _statusNoticeTone(String? message) {
    final text = (message ?? '').trim();
    if (text.isEmpty) {
      return _PageNoticeTone.neutral;
    }
    if (text.contains('失败') ||
        text.contains('无法') ||
        text.contains('错误') ||
        text.contains('断开')) {
      return _PageNoticeTone.warn;
    }
    if (text.contains('已删除') ||
        text.contains('已解散') ||
        text.contains('已退出') ||
        text.contains('已同步') ||
        text.contains('已刷新') ||
        text.contains('已创建') ||
        text.contains('已更新') ||
        text.contains('已保存') ||
        text.contains('已恢复')) {
      return _PageNoticeTone.success;
    }
    return _PageNoticeTone.neutral;
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
    final subtitle = _conversationSubtitle(conversation, lastMessage);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          conversation.isGroup
              ? _GroupAvatar(conversation: conversation)
              : _ChatAvatar(user: conversation.friend!),
          if (conversation.unreadCount > 0)
            Positioned(
              right: -5,
              top: -5,
              child: _RequestBadge(count: conversation.unreadCount),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (conversation.isGroup && conversation.isDissolved) ...[
            const SizedBox(width: 8),
            _ConversationStatePill(
              label: '已解散',
              icon: Icons.info_outline,
              tone: _PageNoticeTone.warn,
            ),
          ],
        ],
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
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

String _conversationSubtitle(
  ChatConversation conversation,
  ChatMessage? lastMessage,
) {
  if (conversation.isGroup && conversation.isDissolved) {
    if (lastMessage == null) {
      return '群聊已解散 · 当前仅保留历史记录';
    }
    return '已解散 · ${lastMessage.text}';
  }
  if (lastMessage != null) {
    return '${_conversationStatusPrefix(lastMessage)}${lastMessage.text}';
  }
  if (conversation.isGroup) {
    return '${conversation.members.length + 1} 人 · 端到端加密群聊';
  }
  return '端到端加密会话';
}

enum _PageNoticeTone { neutral, success, warn }

class _PageNotice extends StatelessWidget {
  const _PageNotice({
    required this.message,
    required this.tone,
    required this.onClose,
    this.dismissible = true,
  });

  final String message;
  final _PageNoticeTone tone;
  final VoidCallback onClose;
  final bool dismissible;

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
          if (dismissible) ...[
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
        ],
      ),
    );
  }
}

class _ConversationStatePill extends StatelessWidget {
  const _ConversationStatePill({
    required this.label,
    required this.icon,
    required this.tone,
  });

  final String label;
  final IconData icon;
  final _PageNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _PageNoticeTone.success => context.sx.success,
      _PageNoticeTone.warn => context.sx.danger,
      _PageNoticeTone.neutral => context.sx.mutedText,
    };
    final background = switch (tone) {
      _PageNoticeTone.success => context.sx.success.withAlpha(24),
      _PageNoticeTone.warn => context.sx.danger.withAlpha(24),
      _PageNoticeTone.neutral => context.sx.subtle,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(64)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
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
    unawaited(widget.controller.activateConversation(widget.conversationId));
  }

  @override
  void dispose() {
    widget.controller.deactivateConversation(widget.conversationId);
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller.chatListenable,
      builder: (context, _) {
        final conversation = _conversation();
        final messages = widget.controller.chatMessagesForConversation(
          widget.conversationId,
        );
        final loadingDetails = widget.controller.isChatConversationLoading(
          widget.conversationId,
        );
        final isGroup = conversation?.isGroup == true;
        final friend = conversation?.friend ?? widget.friend;
        final friendOnline =
            friend != null && widget.controller.isChatFriendOnline(friend.id);
        final groupOnlineCount =
            conversation?.members
                .where(
                  (member) => widget.controller.isChatFriendOnline(member.id),
                )
                .length ??
            0;
        final groupDissolved =
            conversation?.isGroup == true && conversation?.isDissolved == true;
        final title =
            conversation?.displayTitle ??
            (friend == null ? '聊天' : friend.displayName);
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
                    if (groupDissolved)
                      const _OnlineStatusDot.custom(
                        colorKey: _OnlineStateColor.warn,
                        tooltip: '群已解散',
                      )
                    else
                      _OnlineStatusDot(
                        online: isGroup ? groupOnlineCount > 0 : friendOnline,
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  groupDissolved
                      ? '已解散 · 仅支持查看历史记录和删除会话'
                      : isGroup
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
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final result = await navigator.push<String>(
                      MaterialPageRoute(
                        builder: (context) => _GroupChatDetailPage(
                          controller: widget.controller,
                          conversationId: conversation.id,
                        ),
                      ),
                    );
                    if (!mounted || result == null) {
                      return;
                    }
                    navigator.pop(result);
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
                  if (groupDissolved)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: _PageNotice(
                        message: '该群已被群管理解散。你仍可查看历史记录，但不能再发送消息或修改群信息。',
                        tone: _PageNoticeTone.warn,
                        onClose: () {},
                        dismissible: false,
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refreshConversation,
                      triggerMode: RefreshIndicatorTriggerMode.anywhere,
                      child: ListView.builder(
                        reverse: true,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                        itemCount: messageCount == 0
                            ? (loadingDetails ? 2 : 1)
                            : messageCount,
                        itemBuilder: (context, index) {
                          if (messageCount == 0) {
                            if (loadingDetails && index == 0) {
                              return const _ChatLoadingState();
                            }
                            return _ChatEmptyState(
                              message: groupDissolved
                                  ? '该群已经解散。当前账号仍可查看此前同步下来的历史记录；如不再需要，可在群信息页删除会话。'
                                  : '好友在线后会自动建立端到端加密通道。',
                              icon: groupDissolved
                                  ? Icons.info_outline
                                  : Icons.lock_outline,
                              tone: groupDissolved
                                  ? _PageNoticeTone.warn
                                  : _PageNoticeTone.success,
                            );
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

  Future<void> _refreshConversation() async {
    await widget.controller.refreshChatOverview();
    unawaited(
      widget.controller.ensureChatConversationDetails(widget.conversationId),
    );
    unawaited(widget.controller.markConversationRead(widget.conversationId));
  }
}

class _OnlineStatusDot extends StatelessWidget {
  const _OnlineStatusDot({required this.online})
    : customColorKey = null,
      customTooltip = null;

  const _OnlineStatusDot.custom({
    required _OnlineStateColor colorKey,
    required String tooltip,
  }) : online = false,
       customColorKey = colorKey,
       customTooltip = tooltip;

  final bool online;
  final _OnlineStateColor? customColorKey;
  final String? customTooltip;

  @override
  Widget build(BuildContext context) {
    final color = switch (customColorKey) {
      _OnlineStateColor.success => context.sx.success,
      _OnlineStateColor.warn => context.sx.danger,
      _OnlineStateColor.neutral => context.sx.mutedText,
      null => online ? context.sx.success : context.sx.danger,
    };
    final tooltip = customTooltip ?? (online ? '好友在线' : '好友离线');
    return Tooltip(
      message: tooltip,
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

enum _OnlineStateColor { success, warn, neutral }

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState({
    required this.message,
    required this.icon,
    required this.tone,
  });

  final String message;
  final IconData icon;
  final _PageNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final accentColor = switch (tone) {
      _PageNoticeTone.success => context.sx.primary,
      _PageNoticeTone.warn => context.sx.danger,
      _PageNoticeTone.neutral => context.sx.mutedText,
    };
    final softBackground = switch (tone) {
      _PageNoticeTone.success => context.sx.accentSoft,
      _PageNoticeTone.warn => context.sx.danger.withAlpha(18),
      _PageNoticeTone.neutral => context.sx.subtle,
    };
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
                  color: softBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  message,
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

class _ChatLoadingState extends StatelessWidget {
  const _ChatLoadingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 120, bottom: 18),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: context.sx.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.sx.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: context.sx.primary,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '正在按需加载聊天记录...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.sx.mutedText,
                    fontWeight: FontWeight.w700,
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
                nickname: '我',
                avatarPreset: controller.user?.avatarPreset ?? '',
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
        nickname: message.senderName,
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
    return _PresetAvatar(
      presetId: user.avatarPreset,
      size: 46,
      borderColor: isMine ? context.sx.primary : context.sx.border,
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.conversation});

  final ChatConversation conversation;

  @override
  Widget build(BuildContext context) {
    return _PresetAvatar(
      presetId: conversation.avatarPreset,
      size: 46,
      group: true,
      borderColor: context.sx.border,
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
                                      friends[index].displayName.isEmpty
                                          ? '(未命名用户)'
                                          : friends[index].displayName,
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
  void initState() {
    super.initState();
    unawaited(widget.controller.refreshFriendsSilently());
  }

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
        final isDissolved = conversation.isDissolved;
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
                        Row(
                          children: [
                            _GroupAvatar(conversation: conversation),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _SettingsDetailHeader(
                                icon: Icons.groups_2_outlined,
                                title: conversation.displayTitle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ConversationStatePill(
                              label: isDissolved ? '已解散' : '正常群聊',
                              icon: isDissolved
                                  ? Icons.info_outline
                                  : Icons.verified_user_outlined,
                              tone: isDissolved
                                  ? _PageNoticeTone.warn
                                  : _PageNoticeTone.success,
                            ),
                            if (!isDissolved)
                              _ConversationStatePill(
                                label: isAdmin ? '你是群管理' : '成员身份',
                                icon: isAdmin
                                    ? Icons.shield_outlined
                                    : Icons.person_outline,
                                tone: _PageNoticeTone.neutral,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isDissolved
                              ? '群聊已解散，当前只保留只读历史记录，后续可删除当前账号自己的会话数据。'
                              : '${conversation.members.length + 1} 人 · 服务端只保存不可解密的群聊密文归档',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: context.sx.mutedText),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (isDissolved) ...[
                      _InlineNotice(
                        message: '已解散群不能继续邀请成员、发送消息、清空历史或退出群聊。当前账号只允许删除自己的群会话。',
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!isDissolved && isAdmin) ...[
                      Card(
                        child: Column(
                          children: [
                            const _ListCardHeader(title: '群设置'),
                            ListTile(
                              leading: const Icon(Icons.edit_outlined),
                              title: const Text(
                                '修改群名称',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(conversation.displayTitle),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _showRenameGroupPage(conversation),
                            ),
                            Divider(height: 1, color: context.sx.border),
                            ListTile(
                              leading: const Icon(Icons.image_outlined),
                              title: const Text(
                                '修改群头像',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: const Text('仅群管理可修改'),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () =>
                                  _showChangeGroupAvatarPage(conversation),
                            ),
                            Divider(height: 1, color: context.sx.border),
                            ListTile(
                              leading: const Icon(
                                Icons.admin_panel_settings_outlined,
                              ),
                              title: const Text(
                                '转让群管理',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(_adminDisplayName(conversation)),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _showTransferAdminPage(conversation),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Card(
                      child: Column(
                        children: [
                          const _ListCardHeader(title: '群成员'),
                          _GroupMemberTile(
                            user: PublicUser(
                              id: widget.controller.user?.id ?? '',
                              username: widget.controller.user?.username ?? '我',
                              nickname:
                                  '${widget.controller.user?.displayName ?? '我'}（我）',
                              avatarPreset:
                                  widget.controller.user?.avatarPreset ?? '',
                              email: widget.controller.user?.email ?? '',
                            ),
                            admin: isAdmin,
                          ),
                          Divider(height: 1, color: context.sx.border),
                          for (
                            var index = 0;
                            index < conversation.members.length;
                            index++
                          ) ...[
                            _GroupMemberTile(
                              user: conversation.members[index],
                              admin:
                                  conversation.members[index].id ==
                                  conversation.adminUserId,
                              trailing: isAdmin && !isDissolved
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
                    if (!isDissolved) ...[
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
                                    inviteCandidates[index].displayName.isEmpty
                                        ? '(未命名用户)'
                                        : inviteCandidates[index].displayName,
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
                    ],
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
                              isDissolved
                                  ? '解散后的群只允许删除当前账号自己的会话，删除后你将无法再看到这个群的历史消息。'
                                  : '清空聊天记录只会删除当前账号自己的本地缓存和加密归档，不会退出群聊，也不会影响其他成员查看自己的记录。',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: context.sx.mutedText),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: widget.controller.busy
                                    ? null
                                    : (isDissolved
                                          ? () =>
                                                _confirmDeleteDissolvedConversation(
                                                  conversation,
                                                )
                                          : () => _confirmClearHistory(
                                              conversation,
                                            )),
                                icon: Icon(
                                  isDissolved
                                      ? Icons.delete_outline
                                      : Icons.delete_sweep_outlined,
                                ),
                                label: Text(isDissolved ? '删除会话' : '清空聊天记录'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: context.sx.danger,
                                  side: BorderSide(color: context.sx.danger),
                                ),
                              ),
                            ),
                            if (!isDissolved && isAdmin) ...[
                              const SizedBox(height: 12),
                              Text(
                                '解散后，所有成员的聊天列表里仍会保留“已解散”提示，成员只能删除自己的会话，群元数据会逐步清理。',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: context.sx.mutedText),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _confirmDissolve(conversation),
                                  icon: const Icon(Icons.block_outlined),
                                  label: const Text('解散群聊'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: context.sx.danger,
                                    side: BorderSide(color: context.sx.danger),
                                  ),
                                ),
                              ),
                            ],
                            if (!isDissolved) ...[
                              const SizedBox(height: 12),
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
    if (conversation.isDissolved) {
      return;
    }
    final members = conversation.members
        .where((current) => current.id != member.id)
        .toList();
    await widget.controller.updateGroupChat(
      conversationId: conversation.id,
      members: members,
    );
  }

  Future<void> _showRenameGroupPage(ChatConversation conversation) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _RenameGroupPage(
          controller: widget.controller,
          conversationId: conversation.id,
          initialTitle: conversation.displayTitle,
        ),
      ),
    );
  }

  Future<void> _showTransferAdminPage(ChatConversation conversation) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _TransferGroupAdminPage(
          controller: widget.controller,
          conversationId: conversation.id,
        ),
      ),
    );
  }

  Future<void> _showChangeGroupAvatarPage(ChatConversation conversation) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _ChangeGroupAvatarPage(
          controller: widget.controller,
          conversationId: conversation.id,
          initialAvatarPreset: conversation.avatarPreset,
        ),
      ),
    );
  }

  String _adminDisplayName(ChatConversation conversation) {
    if (widget.controller.user?.id == conversation.adminUserId) {
      return '${widget.controller.user?.displayName ?? '我'}（我）';
    }
    for (final member in conversation.members) {
      if (member.id == conversation.adminUserId) {
        return member.displayName;
      }
    }
    return '未命名成员';
  }

  Future<void> _invite(ChatConversation conversation) async {
    if (conversation.isDissolved) {
      return;
    }
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
    Navigator.of(context).pop(_ChatRouteResult.leftGroup);
  }

  Future<void> _confirmClearHistory(ChatConversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: Text(
          '确定清空你在“${conversation.displayTitle}”中的聊天记录吗？清空后只有你自己看不到，其他成员的聊天记录不会删除，你也不会退出该群。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.controller.clearGroupChatHistory(conversation.id);
    if (!mounted) {
      return;
    }
    final message = widget.controller.statusMessage;
    if (message != null && message.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _confirmDissolve(ChatConversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解散群聊'),
        content: Text(
          '确定解散“${conversation.displayTitle}”吗？解散后成员仍会暂时看到该群，但只能删除自己的会话，且不能再继续聊天。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('解散'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.controller.dissolveGroupChat(conversation.id);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    Navigator.of(context).pop(_ChatRouteResult.dissolvedGroup);
  }

  Future<void> _confirmDeleteDissolvedConversation(
    ChatConversation conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: Text(
          '确定删除“${conversation.displayTitle}”的当前账号会话吗？删除后你将无法再看到该群的历史记录，其他成员不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.controller.deleteDissolvedGroupConversation(conversation.id);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    Navigator.of(context).pop(_ChatRouteResult.deletedConversation);
  }
}

class _RenameGroupPage extends StatefulWidget {
  const _RenameGroupPage({
    required this.controller,
    required this.conversationId,
    required this.initialTitle,
  });

  final AppController controller;
  final String conversationId;
  final String initialTitle;

  @override
  State<_RenameGroupPage> createState() => _RenameGroupPageState();
}

class _RenameGroupPageState extends State<_RenameGroupPage> {
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('修改群名称')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const _SettingsDetailHeader(
                      icon: Icons.edit_outlined,
                      title: '修改群名称',
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '群名称修改后，会通过端到端加密控制消息同步给群成员。',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: context.sx.mutedText),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _titleController,
                              decoration: const InputDecoration(
                                labelText: '群名称',
                                hintText: '请输入新的群名称',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: widget.controller.busy
                            ? null
                            : () async {
                                await widget.controller.renameGroupChat(
                                  conversationId: widget.conversationId,
                                  title: _titleController.text,
                                );
                                if (context.mounted &&
                                    widget.controller.statusMessage ==
                                        '群名称已更新。') {
                                  Navigator.of(context).pop();
                                }
                              },
                        child: const Text('保存'),
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
}

class _ChangeGroupAvatarPage extends StatefulWidget {
  const _ChangeGroupAvatarPage({
    required this.controller,
    required this.conversationId,
    required this.initialAvatarPreset,
  });

  final AppController controller;
  final String conversationId;
  final String initialAvatarPreset;

  @override
  State<_ChangeGroupAvatarPage> createState() => _ChangeGroupAvatarPageState();
}

class _ChangeGroupAvatarPageState extends State<_ChangeGroupAvatarPage> {
  late String _avatarPreset;

  @override
  void initState() {
    super.initState();
    _avatarPreset = normalizeSecureXAvatarPreset(
      widget.initialAvatarPreset,
      group: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('修改群头像')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const _SettingsDetailHeader(
                      icon: Icons.image_outlined,
                      title: '修改群头像',
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _PresetAvatar(
                                  presetId: _avatarPreset,
                                  size: 68,
                                  group: true,
                                  borderColor: context.sx.border,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    '群头像会随群资料一起加密同步到群成员本地和个人归档，只有群管理可以修改。',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: context.sx.mutedText),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            _AvatarPresetPicker(
                              selectedPresetId: _avatarPreset,
                              group: true,
                              onSelected: (value) {
                                setState(() {
                                  _avatarPreset = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: widget.controller.busy
                            ? null
                            : () async {
                                await widget.controller.changeGroupAvatar(
                                  conversationId: widget.conversationId,
                                  avatarPreset: _avatarPreset,
                                );
                                if (context.mounted &&
                                    widget.controller.statusMessage ==
                                        '群头像已更新。') {
                                  Navigator.of(context).pop();
                                }
                              },
                        child: const Text('保存'),
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
}

class _TransferGroupAdminPage extends StatelessWidget {
  const _TransferGroupAdminPage({
    required this.controller,
    required this.conversationId,
  });

  final AppController controller;
  final String conversationId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final conversation = controller.chatConversations
            .where((entry) => entry.id == conversationId)
            .cast<ChatConversation?>()
            .firstWhere((entry) => entry != null, orElse: () => null);
        if (conversation == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('转让群管理')),
            body: const Center(child: Text('群聊不存在')),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('转让群管理')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const _SettingsDetailHeader(
                      icon: Icons.admin_panel_settings_outlined,
                      title: '选择新的群管理',
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          '转让后，新的群管理将拥有修改群名称、移除成员、转让群管理和解散群聊的权限。',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: context.sx.mutedText),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          const _ListCardHeader(title: '群成员'),
                          for (
                            var index = 0;
                            index < conversation.members.length;
                            index++
                          ) ...[
                            ListTile(
                              leading: _ChatAvatar(
                                user: conversation.members[index],
                              ),
                              title: Text(
                                conversation.members[index].displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(conversation.members[index].email),
                              trailing: FilledButton.tonal(
                                onPressed: controller.busy
                                    ? null
                                    : () async {
                                        await controller.transferGroupAdmin(
                                          conversationId: conversation.id,
                                          nextAdminUserId:
                                              conversation.members[index].id,
                                        );
                                        if (context.mounted &&
                                            controller.statusMessage ==
                                                '群管理已转让。') {
                                          Navigator.of(context).pop();
                                        }
                                      },
                                child: const Text('设为群管理'),
                              ),
                            ),
                            if (index != conversation.members.length - 1)
                              Divider(height: 1, color: context.sx.border),
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
}

class _GroupMemberTile extends StatelessWidget {
  const _GroupMemberTile({
    required this.user,
    this.admin = false,
    this.trailing,
  });

  final PublicUser user;
  final bool admin;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final title = user.displayName.isEmpty ? '(未命名用户)' : user.displayName;
    return ListTile(
      leading: _ChatAvatar(user: user),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(user.email.isEmpty ? (admin ? '群管理' : '群成员') : user.email),
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
    final composerDisabled = conversation?.isDissolved == true;
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
            if (composerDisabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: context.sx.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '该群已解散，当前页面只支持查看历史记录；如不再需要，可到群信息页删除会话。',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: context.sx.danger,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
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
                      readOnly: composerDisabled,
                      minLines: 1,
                      maxLines: 4,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: context.sx.text,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: composerDisabled ? '群聊已解散' : '输入加密消息',
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
                    onPressed: composerDisabled ? null : onToggleTools,
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
                    onPressed: composerDisabled
                        ? null
                        : () async {
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
            if (showTools && !composerDisabled)
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
    return '$time · 待发送，等待同步到服务端归档';
  }
  if (message.status == 'pending') {
    return '$time · 待发送，等待目标设备拉取';
  }
  if (message.status == 'sent') {
    return '$time · 已发送';
  }
  return '$time · 已送达';
}

String _conversationStatusPrefix(ChatMessage message) {
  if (!message.sentByMe) {
    return '';
  }
  if (message.status == 'localOnly') {
    return '[待发送] ';
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
