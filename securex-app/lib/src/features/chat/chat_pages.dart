// ignore_for_file: invalid_use_of_protected_member

part of '../../../main.dart';

const _chatUiAttachmentMaxBytes = 2 * 1024 * 1024;
const _chatUiVideoAttachmentMaxBytes = 20 * 1024 * 1024;

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
  String _composerPanel = '';
  bool _hasComposerText = false;

  @override
  void initState() {
    super.initState();
    _inputController.clear();
    _inputController.addListener(_handleComposerTextChanged);
    unawaited(widget.controller.activateConversation(widget.conversationId));
  }

  @override
  void dispose() {
    widget.controller.deactivateConversation(widget.conversationId);
    _inputController.removeListener(_handleComposerTextChanged);
    _inputController.dispose();
    super.dispose();
  }

  void _handleComposerTextChanged() {
    final hasText = _inputController.text.trim().isNotEmpty;
    if (hasText == _hasComposerText) {
      return;
    }
    setState(() {
      _hasComposerText = hasText;
      if (hasText) {
        _composerPanel = '';
      }
    });
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
                    hasText: _hasComposerText,
                    showTools: _composerPanel == 'tools',
                    showEmoji: _composerPanel == 'emoji',
                    onToggleEmoji: () {
                      setState(() {
                        _composerPanel = _composerPanel == 'emoji'
                            ? ''
                            : 'emoji';
                      });
                    },
                    onToggleTools: () {
                      setState(() {
                        _composerPanel = _composerPanel == 'tools'
                            ? ''
                            : 'tools';
                      });
                    },
                    onClosePanel: () {
                      if (_composerPanel.isEmpty) {
                        return;
                      }
                      setState(() {
                        _composerPanel = '';
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
                  child: _ChatMessageContent(
                    controller: controller,
                    message: message,
                    foreground: foreground,
                    sentByMe: isMine,
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
                avatarUrl: controller.user?.avatarUrl ?? '',
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
      imageUrl: user.avatarUrl,
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
    required this.hasText,
    required this.showTools,
    required this.showEmoji,
    required this.onToggleEmoji,
    required this.onToggleTools,
    required this.onClosePanel,
  });

  final AppController controller;
  final ChatConversation? conversation;
  final PublicUser? friend;
  final TextEditingController textController;
  final bool hasText;
  final bool showTools;
  final bool showEmoji;
  final VoidCallback onToggleEmoji;
  final VoidCallback onToggleTools;
  final VoidCallback onClosePanel;

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
                    tooltip: showEmoji ? '收起表情' : '表情',
                    icon: showEmoji
                        ? Icons.keyboard_alt_outlined
                        : Icons.mood_outlined,
                    onPressed: composerDisabled ? null : onToggleEmoji,
                  ),
                  const SizedBox(width: 8),
                  _VoiceInputButton(
                    controller: controller,
                    conversation: conversation,
                    friend: friend,
                    disabled: composerDisabled,
                    onClosePanel: onClosePanel,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: textController,
                      readOnly: composerDisabled,
                      onTap: onClosePanel,
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
                  if (hasText)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: composerDisabled ? null : _sendTextMessage,
                      child: const Text('发送'),
                    )
                  else
                    _ComposerIconButton(
                      tooltip: showTools ? '收起更多' : '更多',
                      icon: showTools
                          ? Icons.keyboard_arrow_down
                          : Icons.add_circle_outline,
                      onPressed: composerDisabled ? null : onToggleTools,
                    ),
                ],
              ),
            ),
            if (showEmoji && !composerDisabled)
              _ChatEmojiPanel(
                onSelected: (emoji) {
                  final selection = textController.selection;
                  final text = textController.text;
                  final start = selection.start < 0
                      ? text.length
                      : selection.start;
                  final end = selection.end < 0 ? text.length : selection.end;
                  textController.value = TextEditingValue(
                    text: text.replaceRange(start, end, emoji),
                    selection: TextSelection.collapsed(
                      offset: start + emoji.length,
                    ),
                  );
                },
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
                  children: [
                    _ChatToolButton(
                      icon: Icons.image_outlined,
                      label: '相册',
                      onTap: () => _pickAndSendMedia(context),
                    ),
                    _ChatToolButton(
                      icon: Icons.insert_drive_file_outlined,
                      label: '文件',
                      onTap: () =>
                          _pickAndSendAttachment(context, image: false),
                    ),
                    _ChatToolButton(
                      icon: Icons.videocam_outlined,
                      label: '视频通话',
                      onTap: () => _showCallOptions(context),
                    ),
                    const _ChatToolButton(
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

  Future<void> _sendTextMessage() async {
    final text = textController.text;
    if (text.trim().isEmpty) {
      return;
    }
    textController.clear();
    onClosePanel();
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
    await controller.sendLocalChatMessage(friend: directFriend, text: text);
  }

  Future<void> _pickAndSendAttachment(
    BuildContext context, {
    required bool image,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: image ? FileType.image : FileType.any,
      allowMultiple: false,
      withData: true,
    );
    final picked = result?.files.single;
    if (picked == null) {
      return;
    }
    Uint8List? bytes = picked.bytes;
    if (bytes == null && picked.path != null) {
      bytes = await File(picked.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件读取失败')));
      }
      return;
    }
    final sendBytes = image ? _prepareChatImage(bytes) : bytes;
    if (sendBytes.length > _chatUiAttachmentMaxBytes) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('聊天附件不能超过 2MB，大文件请使用文件模块。')),
        );
      }
      return;
    }
    final name = image ? _imageAttachmentName(picked.name) : picked.name;
    final mimeType = image ? 'image/jpeg' : _guessMimeType(picked.name);
    if (conversation?.isGroup == true) {
      await controller.sendGroupChatAttachment(
        conversation: conversation!,
        bytes: sendBytes,
        name: name,
        mimeType: mimeType,
        image: image,
      );
      return;
    }
    final directFriend = friend;
    if (directFriend == null) {
      return;
    }
    await controller.sendLocalChatAttachment(
      friend: directFriend,
      bytes: sendBytes,
      name: name,
      mimeType: mimeType,
      image: image,
    );
  }

  Future<void> _pickAndSendMedia(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: false,
      withData: true,
    );
    final picked = result?.files.single;
    if (picked == null) {
      return;
    }
    Uint8List? bytes = picked.bytes;
    if (bytes == null && picked.path != null) {
      bytes = await File(picked.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('媒体文件读取失败')));
      }
      return;
    }
    final video = _isVideoFile(picked.name);
    final sendBytes = video ? bytes : _prepareChatImage(bytes);
    final maxBytes = video
        ? _chatUiVideoAttachmentMaxBytes
        : _chatUiAttachmentMaxBytes;
    if (sendBytes.length > maxBytes) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              video ? '聊天视频不能超过 20MB，大视频请使用文件模块。' : '聊天图片不能超过 2MB。',
            ),
          ),
        );
      }
      return;
    }
    final name = video ? picked.name : _imageAttachmentName(picked.name);
    final mimeType = video ? _guessMimeType(picked.name) : 'image/jpeg';
    final attachmentType = video ? 'video' : 'image';
    if (conversation?.isGroup == true) {
      await controller.sendGroupChatAttachment(
        conversation: conversation!,
        bytes: sendBytes,
        name: name,
        mimeType: mimeType,
        image: !video,
        attachmentType: attachmentType,
      );
      return;
    }
    final directFriend = friend;
    if (directFriend == null) {
      return;
    }
    await controller.sendLocalChatAttachment(
      friend: directFriend,
      bytes: sendBytes,
      name: name,
      mimeType: mimeType,
      image: !video,
      attachmentType: attachmentType,
    );
  }

  Future<void> _showCallOptions(BuildContext context) async {
    final directFriend = friend;
    if (directFriend == null || conversation?.isGroup == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前仅支持单聊发起通话。')));
      return;
    }
    final media = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _ChatCallOptionSheet(friend: directFriend),
    );
    if (!context.mounted || media == null || media.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ChatCallPage(
          controller: controller,
          friend: directFriend,
          initialVideo: media == 'video',
        ),
      ),
    );
  }

  Uint8List _prepareChatImage(Uint8List source) {
    final decoded = img.decodeImage(source);
    if (decoded == null) {
      return source;
    }
    final resized = decoded.width > 1280 || decoded.height > 1280
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 1280 : null,
            height: decoded.height > decoded.width ? 1280 : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
  }

  String _imageAttachmentName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'secure-x-image.jpg';
    }
    final base = trimmed.replaceAll(RegExp(r'\.[^.]+$'), '');
    return '${base.isEmpty ? 'secure-x-image' : base}.jpg';
  }

  String _guessMimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lower.endsWith('.txt')) {
      return 'text/plain';
    }
    if (lower.endsWith('.mp4')) {
      return 'video/mp4';
    }
    if (lower.endsWith('.mov')) {
      return 'video/quicktime';
    }
    if (lower.endsWith('.m4v')) {
      return 'video/x-m4v';
    }
    if (lower.endsWith('.webm')) {
      return 'video/webm';
    }
    return 'application/octet-stream';
  }

  bool _isVideoFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv');
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;

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
            color: active
                ? context.sx.primary
                : enabled
                ? context.sx.accentSoft
                : context.sx.subtle,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.sx.border),
          ),
          child: Icon(
            icon,
            color: active
                ? Colors.white
                : enabled
                ? context.sx.primary
                : context.sx.mutedText,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _ChatCallOptionSheet extends StatelessWidget {
  const _ChatCallOptionSheet({required this.friend});

  final PublicUser friend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.sx.card,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(60),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              _CallSheetAction(
                icon: Icons.videocam_rounded,
                label: '视频通话',
                onTap: () => Navigator.of(context).pop('video'),
              ),
              Divider(height: 1, color: context.sx.border),
              _CallSheetAction(
                icon: Icons.call_rounded,
                label: '语音通话',
                onTap: () => Navigator.of(context).pop('audio'),
              ),
              Divider(height: 8, thickness: 8, color: context.sx.subtle),
              _CallSheetAction(
                label: '取消',
                center: true,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallSheetAction extends StatelessWidget {
  const _CallSheetAction({
    required this.label,
    required this.onTap,
    this.icon,
    this.center = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
        child: Row(
          mainAxisAlignment: center
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, color: context.sx.text, size: 28),
              const SizedBox(width: 20),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.sx.text,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatCallPage extends StatefulWidget {
  const _ChatCallPage({
    required this.controller,
    required this.friend,
    required this.initialVideo,
    this.incomingCallId,
  });

  final AppController controller;
  final PublicUser friend;
  final bool initialVideo;
  final String? incomingCallId;

  @override
  State<_ChatCallPage> createState() => _ChatCallPageState();
}

class _ChatCallPageState extends State<_ChatCallPage> {
  final rtc.RTCVideoRenderer _localRenderer = rtc.RTCVideoRenderer();
  final rtc.RTCVideoRenderer _remoteRenderer = rtc.RTCVideoRenderer();
  final List<rtc.RTCIceCandidate> _pendingCandidates = [];
  rtc.MediaStream? _localStream;
  rtc.RTCPeerConnection? _peerConnection;
  late final String _callId;
  bool _microphoneOn = true;
  bool _speakerOn = true;
  bool _cameraOn = false;
  bool _accepted = false;
  bool _incomingWaiting = false;
  bool _remoteVideoReady = false;
  bool _remoteDescriptionSet = false;
  bool _ended = false;
  String _notice = '正在准备通话...';

  bool get _isIncoming => widget.incomingCallId != null;
  String get _media => widget.initialVideo ? 'video' : 'audio';

  @override
  void initState() {
    super.initState();
    _callId =
        widget.incomingCallId ??
        DateTime.now().microsecondsSinceEpoch.toString();
    _cameraOn = widget.initialVideo;
    _incomingWaiting = _isIncoming;
    widget.controller.callListenable.addListener(_handleCallSignal);
    unawaited(_startCall());
  }

  @override
  void dispose() {
    widget.controller.callListenable.removeListener(_handleCallSignal);
    unawaited(_endCall(sendAction: _accepted ? 'end' : 'cancel'));
    super.dispose();
  }

  Future<void> _startCall() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      if (_isIncoming) {
        if (!mounted) {
          return;
        }
        setState(() {
          _notice = '邀请你进行${widget.initialVideo ? '视频' : '语音'}通话';
        });
        return;
      }
      await _openLocalMedia(video: widget.initialVideo);
      await _ensurePeerConnection();
      await widget.controller.sendChatCallSignal(
        friend: widget.friend,
        callId: _callId,
        action: 'invite',
        media: _media,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _notice = '等待对方接受邀请.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _notice = '通话启动失败，请检查麦克风或摄像头权限。';
      });
    }
  }

  void _handleCallSignal() {
    final signal = widget.controller.lastCallSignal;
    if (signal == null ||
        signal.callId != _callId ||
        signal.friendId != widget.friend.id) {
      return;
    }
    unawaited(_handleCallSignalAsync(signal));
  }

  Future<void> _handleCallSignalAsync(RealtimeCallSignal signal) async {
    switch (signal.action) {
      case 'accept':
        if (_isIncoming) {
          return;
        }
        _accepted = true;
        _setNotice('对方已接听，正在建立安全通话...');
        await _ensurePeerConnection();
        await _sendOffer();
        break;
      case 'reject':
        _setNotice('对方已拒绝通话。');
        await _closeAfterDelay();
        break;
      case 'cancel':
      case 'end':
        _setNotice(signal.action == 'cancel' ? '对方已取消通话。' : '通话已结束。');
        await _closeAfterDelay();
        break;
      case 'offer':
        _accepted = true;
        await _ensurePeerConnection();
        await _setRemoteDescription(signal.payload, fallbackType: 'offer');
        await _drainPendingCandidates();
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        await _sendCallSignal('answer', {
          'sdp': answer.sdp,
          'sdpType': answer.type,
        });
        _setNotice('正在接通...');
        break;
      case 'answer':
        await _setRemoteDescription(signal.payload, fallbackType: 'answer');
        await _drainPendingCandidates();
        _setNotice('正在接通...');
        break;
      case 'candidate':
        await _handleRemoteCandidate(signal.payload);
        break;
    }
  }

  Future<void> _openLocalMedia({required bool video}) async {
    if (_localStream != null) {
      return;
    }
    final stream = await rtc.navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 960},
            }
          : false,
    });
    _localStream = stream;
    _localRenderer.srcObject = stream;
    _setAudioEnabled(_microphoneOn);
    _setVideoEnabled(video && _cameraOn);
  }

  Future<void> _ensurePeerConnection() async {
    if (_peerConnection != null) {
      return;
    }
    await _openLocalMedia(video: widget.initialVideo);
    final iceServers = widget.controller.realtimeConfig?.iceServers ?? const [];
    final connection = await rtc.createPeerConnection({
      'iceServers': [
        if (iceServers.isNotEmpty) {'urls': iceServers},
      ],
    });
    _peerConnection = connection;
    connection.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (value == null || value.isEmpty || _ended) {
        return;
      }
      unawaited(
        _sendCallSignal('candidate', {
          'candidate': value,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }),
      );
    };
    connection.onTrack = (event) {
      final streams = event.streams;
      if (streams.isEmpty) {
        return;
      }
      _remoteRenderer.srcObject = streams.first;
      if (mounted) {
        setState(() {
          _remoteVideoReady = event.track.kind == 'video';
          _notice = '通话中';
        });
      }
    };
    connection.onConnectionState = (state) {
      if (!mounted) {
        return;
      }
      if (state == rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _notice = '通话中');
      }
      if (state == rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state ==
              rtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        setState(() => _notice = '通话连接不稳定，正在等待恢复...');
      }
    };
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await connection.addTrack(track, stream);
      }
    }
  }

  Future<void> _sendOffer() async {
    final connection = _peerConnection;
    if (connection == null) {
      return;
    }
    final offer = await connection.createOffer();
    await connection.setLocalDescription(offer);
    await _sendCallSignal('offer', {'sdp': offer.sdp, 'sdpType': offer.type});
  }

  Future<void> _setRemoteDescription(
    Map<String, dynamic> payload, {
    required String fallbackType,
  }) async {
    final connection = _peerConnection;
    if (connection == null) {
      return;
    }
    await connection.setRemoteDescription(
      rtc.RTCSessionDescription(
        payload['sdp'] as String? ?? '',
        payload['sdpType'] as String? ?? fallbackType,
      ),
    );
    _remoteDescriptionSet = true;
  }

  Future<void> _handleRemoteCandidate(Map<String, dynamic> payload) async {
    final candidate = payload['candidate'] as String? ?? '';
    if (candidate.isEmpty) {
      return;
    }
    final iceCandidate = rtc.RTCIceCandidate(
      candidate,
      payload['sdpMid'] as String?,
      (payload['sdpMLineIndex'] as num?)?.toInt(),
    );
    if (!_remoteDescriptionSet || _peerConnection == null) {
      _pendingCandidates.add(iceCandidate);
      return;
    }
    await _peerConnection!.addCandidate(iceCandidate);
  }

  Future<void> _drainPendingCandidates() async {
    final connection = _peerConnection;
    if (connection == null || _pendingCandidates.isEmpty) {
      return;
    }
    final candidates = [..._pendingCandidates];
    _pendingCandidates.clear();
    for (final candidate in candidates) {
      await connection.addCandidate(candidate);
    }
  }

  Future<void> _sendCallSignal(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) {
    return widget.controller.sendChatCallSignal(
      friend: widget.friend,
      callId: _callId,
      action: action,
      media: _media,
      payload: payload,
    );
  }

  Future<void> _acceptIncomingCall() async {
    _incomingWaiting = false;
    _accepted = true;
    _setNotice('正在接听...');
    try {
      await _openLocalMedia(video: widget.initialVideo);
      await _ensurePeerConnection();
      await _sendCallSignal('accept');
      _setNotice('等待对方建立安全通话...');
    } catch (_) {
      _setNotice('接听失败，请检查麦克风或摄像头权限。');
    }
  }

  Future<void> _rejectIncomingCall() async {
    await _sendCallSignal('reject');
    await _endCall(sendAction: null);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _closeAfterDelay() async {
    await _endCall(sendAction: null);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _setNotice(String value) {
    if (!mounted) {
      return;
    }
    setState(() => _notice = value);
  }

  Future<void> _endCall({required String? sendAction}) async {
    if (_ended) {
      return;
    }
    _ended = true;
    if (sendAction != null) {
      await _sendCallSignal(sendAction);
    }
    await _peerConnection?.close();
    await _peerConnection?.dispose();
    _peerConnection = null;
    final stream = _localStream;
    _localStream = null;
    for (final track in stream?.getTracks() ?? const <rtc.MediaStreamTrack>[]) {
      await track.stop();
    }
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
  }

  void _setAudioEnabled(bool enabled) {
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      track.enabled = enabled;
    }
  }

  void _setVideoEnabled(bool enabled) {
    for (final track in _localStream?.getVideoTracks() ?? const []) {
      track.enabled = enabled;
    }
  }

  Future<void> _toggleCamera() async {
    if (!widget.initialVideo) {
      return;
    }
    setState(() => _cameraOn = !_cameraOn);
    _setVideoEnabled(_cameraOn);
  }

  void _toggleMicrophone() {
    setState(() => _microphoneOn = !_microphoneOn);
    _setAudioEnabled(_microphoneOn);
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    // 桌面和移动端的扬声器路由能力差异较大，先保留 UI 状态和后续接入点。
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.friend.displayName.isEmpty
        ? widget.friend.username
        : widget.friend.displayName;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildCallBackground()),
            Positioned(
              top: 30,
              left: 28,
              child: IconButton(
                icon: const Icon(Icons.picture_in_picture_alt_outlined),
                color: Colors.white,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Align(
              alignment: const Alignment(0, -0.45),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CallAvatar(friend: widget.friend),
                  const SizedBox(height: 18),
                  Text(
                    name,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: const Alignment(0, 0.42),
              child: Text(
                _notice,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white.withAlpha(175),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 0, 26, 34),
                child: _buildControls(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallBackground() {
    if (widget.initialVideo && _remoteVideoReady) {
      return rtc.RTCVideoView(
        _remoteRenderer,
        mirror: false,
        objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    if (widget.initialVideo && _cameraOn && _localStream != null) {
      return rtc.RTCVideoView(
        _localRenderer,
        mirror: true,
        objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 1.1,
          colors: [Colors.blueGrey.shade900.withAlpha(190), Colors.black],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    if (_incomingWaiting) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallControlButton(
            icon: Icons.call_end_rounded,
            label: '拒绝',
            danger: true,
            onTap: () => unawaited(_rejectIncomingCall()),
          ),
          _CallControlButton(
            icon: Icons.call_rounded,
            label: '接听',
            success: true,
            onTap: () => unawaited(_acceptIncomingCall()),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CallControlButton(
              icon: _microphoneOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              label: _microphoneOn ? '麦克风已开' : '麦克风已关',
              onTap: _toggleMicrophone,
            ),
            _CallControlButton(
              icon: _speakerOn
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              label: _speakerOn ? '扬声器已开' : '扬声器已关',
              onTap: _toggleSpeaker,
            ),
            if (widget.initialVideo)
              _CallControlButton(
                icon: _cameraOn
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                label: _cameraOn ? '摄像头已开' : '摄像头已关',
                onTap: _toggleCamera,
              ),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 96),
            _HangupButton(
              onTap: () async {
                await _endCall(sendAction: _accepted ? 'end' : 'cancel');
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
            if (widget.initialVideo)
              _CallControlButton(
                icon: Icons.cameraswitch_rounded,
                label: '切换摄像头',
                compact: true,
                onTap: () async {
                  final tracks = _localStream?.getVideoTracks() ?? const [];
                  final videoTrack = tracks.isEmpty ? null : tracks.first;
                  if (videoTrack != null) {
                    await rtc.Helper.switchCamera(videoTrack);
                  }
                },
              )
            else
              const SizedBox(width: 96),
          ],
        ),
      ],
    );
  }
}

class _CallAvatar extends StatelessWidget {
  const _CallAvatar({required this.friend});

  final PublicUser friend;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 122,
      height: 122,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withAlpha(30),
      ),
      child: Center(
        child: Text(
          (friend.displayName.isNotEmpty ? friend.displayName : friend.username)
              .characters
              .take(1)
              .toString()
              .toUpperCase(),
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
    this.danger = false,
    this.success = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;
  final bool danger;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 58.0 : 88.0;
    final background = danger
        ? context.sx.danger
        : success
        ? context.sx.success
        : Colors.white;
    final foreground = (danger || success) ? Colors.white : Colors.black;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: foreground, size: compact ? 28 : 38),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withAlpha(215),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HangupButton extends StatelessWidget {
  const _HangupButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: context.sx.danger,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.call_end_rounded,
          color: Colors.white,
          size: 42,
        ),
      ),
    );
  }
}

class _VoiceInputButton extends StatefulWidget {
  const _VoiceInputButton({
    required this.controller,
    required this.conversation,
    required this.friend,
    required this.disabled,
    required this.onClosePanel,
  });

  final AppController controller;
  final ChatConversation? conversation;
  final PublicUser? friend;
  final bool disabled;
  final VoidCallback onClosePanel;

  @override
  State<_VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<_VoiceInputButton> {
  final record.AudioRecorder _recorder = record.AudioRecorder();
  bool _recording = false;
  DateTime? _startedAt;
  Timer? _maxDurationTimer;
  String? _recordingPath;

  @override
  void dispose() {
    _maxDurationTimer?.cancel();
    if (_recording) {
      unawaited(_recorder.cancel());
    }
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (widget.disabled) {
      return;
    }
    widget.onClosePanel();
    if (_recording) {
      await _stopAndSend();
      return;
    }
    await _startRecording();
  }

  Future<void> _startRecording() async {
    final allowed = await _recorder.hasPermission();
    if (!allowed) {
      _showSnack('麦克风权限未开启，请到系统设置中允许 secure-x 使用。');
      return;
    }
    final supported = await _recorder.isEncoderSupported(
      record.AudioEncoder.aacLc,
    );
    if (!supported) {
      _showSnack('当前设备暂不支持语音消息录制。');
      return;
    }
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/secure-x-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(
        const record.RecordConfig(
          encoder: record.AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      _recordingPath = path;
      _startedAt = DateTime.now();
      _maxDurationTimer?.cancel();
      _maxDurationTimer = Timer(const Duration(seconds: 60), () {
        if (mounted && _recording) {
          unawaited(_stopAndSend(autoStopped: true));
        }
      });
      if (!mounted) {
        return;
      }
      setState(() => _recording = true);
      _showSnack('正在录音，再点一次麦克风发送语音。');
    } catch (_) {
      _showSnack('语音录制启动失败，请检查麦克风是否被占用。');
    }
  }

  Future<void> _stopAndSend({bool autoStopped = false}) async {
    _maxDurationTimer?.cancel();
    final startedAt = _startedAt;
    final path = await _recorder.stop();
    if (mounted) {
      setState(() => _recording = false);
    }
    final outputPath = path ?? _recordingPath;
    _recordingPath = null;
    _startedAt = null;
    if (outputPath == null) {
      _showSnack('语音录制失败，请重试。');
      return;
    }
    final file = File(outputPath);
    if (!await file.exists()) {
      _showSnack('语音文件生成失败，请重试。');
      return;
    }
    final duration = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);
    if (duration < const Duration(milliseconds: 700)) {
      await _deleteTempVoiceFile(file);
      _showSnack('录音时间太短，未发送。');
      return;
    }
    final bytes = await file.readAsBytes();
    await _deleteTempVoiceFile(file);
    if (bytes.length > _chatUiAttachmentMaxBytes) {
      _showSnack('语音消息不能超过 2MB，请缩短录音时间。');
      return;
    }
    final seconds = duration.inSeconds.clamp(1, 60);
    final name =
        'secure-x-voice-${DateTime.now().millisecondsSinceEpoch}-${seconds}s.m4a';
    if (widget.conversation?.isGroup == true) {
      await widget.controller.sendGroupChatAttachment(
        conversation: widget.conversation!,
        bytes: bytes,
        name: name,
        mimeType: 'audio/mp4',
        image: false,
        attachmentType: 'audio',
      );
    } else {
      final directFriend = widget.friend;
      if (directFriend == null) {
        _showSnack('当前会话不可发送语音。');
        return;
      }
      await widget.controller.sendLocalChatAttachment(
        friend: directFriend,
        bytes: bytes,
        name: name,
        mimeType: 'audio/mp4',
        image: false,
        attachmentType: 'audio',
      );
    }
    if (autoStopped) {
      _showSnack('已达到最长录音时间，语音已发送。');
    }
  }

  Future<void> _deleteTempVoiceFile(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // 临时录音删除失败不影响消息发送，系统临时目录后续会自行清理。
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ComposerIconButton(
      tooltip: _recording ? '停止并发送语音' : '语音消息',
      icon: _recording ? Icons.stop_rounded : Icons.mic_none_outlined,
      onPressed: widget.disabled ? null : _toggleRecording,
      active: _recording,
    );
  }
}

class _ChatEmojiPanel extends StatelessWidget {
  const _ChatEmojiPanel({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _emojis = [
    '😀',
    '😄',
    '😂',
    '😊',
    '😍',
    '😘',
    '😎',
    '😢',
    '😭',
    '😡',
    '👍',
    '🙏',
    '👏',
    '💪',
    '🎉',
    '❤️',
    '🔥',
    '✨',
    '🌹',
    '☕',
    '🍻',
    '✅',
    '❌',
    '❓',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 230,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      decoration: BoxDecoration(
        color: context.sx.card,
        border: Border(top: BorderSide(color: context.sx.border)),
      ),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _emojis.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: MediaQuery.sizeOf(context).width < 520 ? 6 : 10,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemBuilder: (context, index) {
          final emoji = _emojis[index];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onSelected(emoji),
            child: Container(
              decoration: BoxDecoration(
                color: context.sx.subtle,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.sx.border),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
          );
        },
      ),
    );
  }
}

class _ChatToolButton extends StatelessWidget {
  const _ChatToolButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: enabled ? context.sx.accentSoft : context.sx.subtle,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.sx.border),
            ),
            child: Icon(
              icon,
              color: enabled ? context.sx.primary : context.sx.mutedText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: enabled ? context.sx.primary : context.sx.mutedText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
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

class _ChatMessageContent extends StatelessWidget {
  const _ChatMessageContent({
    required this.controller,
    required this.message,
    required this.foreground,
    required this.sentByMe,
  });

  final AppController controller;
  final ChatMessage message;
  final Color foreground;
  final bool sentByMe;

  @override
  Widget build(BuildContext context) {
    if (!message.hasAttachment) {
      return _messageText(context);
    }
    if (message.isImageAttachment) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChatImageAttachment(message: message),
          if (_cleanCaption.isNotEmpty) ...[
            const SizedBox(height: 10),
            _messageText(context),
          ],
        ],
      );
    }
    if (message.isAudioAttachment) {
      return _ChatAudioAttachment(message: message, sentByMe: sentByMe);
    }
    if (message.isVideoAttachment) {
      return _ChatVideoAttachment(
        controller: controller,
        message: message,
        foreground: foreground,
        sentByMe: sentByMe,
      );
    }
    return _ChatFileAttachment(
      controller: controller,
      message: message,
      foreground: foreground,
      sentByMe: sentByMe,
    );
  }

  String get _cleanCaption {
    final label = message.attachmentName.trim();
    final text = message.text.trim();
    if (text == '[图片] $label' || text == '[文件] $label') {
      return '';
    }
    if (text == '[语音] $label') {
      return '';
    }
    if (text == '[视频] $label') {
      return '';
    }
    return text;
  }

  Widget _messageText(BuildContext context) {
    return Text(
      _cleanCaption.isEmpty ? message.text : _cleanCaption,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: foreground,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ChatImageAttachment extends StatelessWidget {
  const _ChatImageAttachment({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    try {
      final bytes = base64Decode(message.attachmentDataBase64);
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          bytes,
          width: 220,
          fit: BoxFit.cover,
          errorBuilder: (context, _, _) => _broken(context),
        ),
      );
    } catch (_) {
      return _broken(context);
    }
  }

  Widget _broken(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, color: context.sx.mutedText),
        const SizedBox(width: 8),
        Text(
          message.attachmentName.isEmpty ? '图片无法显示' : message.attachmentName,
          style: TextStyle(
            color: context.sx.mutedText,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ChatAudioAttachment extends StatefulWidget {
  const _ChatAudioAttachment({required this.message, required this.sentByMe});

  final ChatMessage message;
  final bool sentByMe;

  @override
  State<_ChatAudioAttachment> createState() => _ChatAudioAttachmentState();
}

class _ChatAudioAttachmentState extends State<_ChatAudioAttachment> {
  final audio.AudioPlayer _player = audio.AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _playing = false);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.stop();
      if (mounted) {
        setState(() => _playing = false);
      }
      return;
    }
    try {
      final bytes = base64Decode(widget.message.attachmentDataBase64);
      await _player.play(
        audio.BytesSource(
          Uint8List.fromList(bytes),
          mimeType: widget.message.attachmentMimeType.isEmpty
              ? 'audio/mp4'
              : widget.message.attachmentMimeType,
        ),
      );
      if (mounted) {
        setState(() => _playing = true);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('语音播放失败')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.sentByMe ? Colors.white : context.sx.text;
    final background = widget.sentByMe
        ? Colors.white.withAlpha(24)
        : context.sx.subtle;
    final border = widget.sentByMe
        ? Colors.white.withAlpha(50)
        : context.sx.border;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _togglePlay,
      child: Container(
        constraints: const BoxConstraints(minWidth: 168),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
              color: foreground,
              size: 30,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _voiceDurationLabel(widget.message.attachmentName),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _playing
                      ? '正在播放'
                      : '${_formatAttachmentSize(widget.message.attachmentSize)} · 点击播放',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground.withAlpha(190),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _voiceDurationLabel(String name) {
    final match = RegExp(r'-(\d+)s\.m4a$').firstMatch(name);
    final seconds = match?.group(1);
    if (seconds == null) {
      return '语音消息';
    }
    return '语音消息 $seconds"';
  }
}

class _ChatFileAttachment extends StatelessWidget {
  const _ChatFileAttachment({
    required this.controller,
    required this.message,
    required this.foreground,
    required this.sentByMe,
  });

  final AppController controller;
  final ChatMessage message;
  final Color foreground;
  final bool sentByMe;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          final path = await controller.saveChatAttachment(message);
          messenger.showSnackBar(SnackBar(content: Text('附件已保存：$path')));
        } catch (_) {
          messenger.showSnackBar(const SnackBar(content: Text('附件保存失败')));
        }
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 210),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sentByMe ? Colors.white.withAlpha(24) : context.sx.subtle,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: sentByMe ? Colors.white.withAlpha(50) : context.sx.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, color: foreground, size: 30),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.attachmentName.isEmpty
                        ? '未命名文件'
                        : message.attachmentName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatAttachmentSize(message.attachmentSize)} · 点击保存',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground.withAlpha(190),
                      fontWeight: FontWeight.w700,
                    ),
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

class _ChatVideoAttachment extends StatelessWidget {
  const _ChatVideoAttachment({
    required this.controller,
    required this.message,
    required this.foreground,
    required this.sentByMe,
  });

  final AppController controller;
  final ChatMessage message;
  final Color foreground;
  final bool sentByMe;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          final path = await controller.saveChatAttachment(message);
          messenger.showSnackBar(SnackBar(content: Text('视频已保存：$path')));
        } catch (_) {
          messenger.showSnackBar(const SnackBar(content: Text('视频保存失败')));
        }
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 220),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sentByMe ? Colors.white.withAlpha(24) : context.sx.subtle,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: sentByMe ? Colors.white.withAlpha(50) : context.sx.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: foreground.withAlpha(30),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: foreground,
                size: 34,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.attachmentName.isEmpty
                        ? '视频'
                        : message.attachmentName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatAttachmentSize(message.attachmentSize)} · 点击保存',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground.withAlpha(190),
                      fontWeight: FontWeight.w700,
                    ),
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

String _formatAttachmentSize(int size) {
  if (size < 1024) {
    return '${size}B';
  }
  if (size < 1024 * 1024) {
    return '${(size / 1024).toStringAsFixed(1)}KB';
  }
  return '${(size / 1024 / 1024).toStringAsFixed(1)}MB';
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
