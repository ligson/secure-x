// ignore_for_file: invalid_use_of_protected_member

part of '../../../main.dart';

extension _FriendsTab on _VaultScreenState {
  Widget _buildFriendsTab(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller.friendsListenable,
      builder: (context, _) {
        final friends = _filteredFriends();
        final groupedFriends = _groupFriends(friends);
        final incomingCount = widget.controller.incomingFriendRequests.length;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildFriendsHeader(context, incomingCount),
              const SizedBox(height: 12),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: widget.controller.refreshFriendsSilently,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      ..._buildSliverPageStatusSections(),
                      SliverToBoxAdapter(
                        child: TextField(
                          controller: _friendSearchController,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: '搜索好友',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      SliverToBoxAdapter(
                        child: Card(
                          child: Column(
                            children: [
                              _FriendActionTile(
                                color: const Color(0xFFFFA13A),
                                icon: Icons.person_add_alt_1_outlined,
                                title: '新的朋友',
                                subtitle: incomingCount == 0
                                    ? '查看好友申请'
                                    : '$incomingCount 条待处理申请',
                                trailing: incomingCount == 0
                                    ? const Icon(Icons.chevron_right_rounded)
                                    : _RequestBadge(count: incomingCount),
                                onTap: _showFriendRequests,
                              ),
                              Divider(height: 1, color: context.sx.border),
                              _FriendActionTile(
                                color: const Color(0xFF12A594),
                                icon: Icons.groups_2_outlined,
                                title: '群聊',
                                subtitle: '查看我创建和加入的群聊',
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: _showFriendGroups,
                              ),
                              Divider(height: 1, color: context.sx.border),
                              _FriendActionTile(
                                color: context.sx.primary,
                                icon: Icons.group_add_outlined,
                                title: '添加好友',
                                subtitle: '通过用户名或邮箱发送申请',
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: _showAddFriendPage,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      if (friends.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              _friendSearchController.text.trim().isEmpty
                                  ? '还没有好友'
                                  : '没有匹配的好友',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: context.sx.mutedText),
                            ),
                          ),
                        )
                      else ...[
                        for (final entry in groupedFriends.entries) ...[
                          SliverToBoxAdapter(
                            child: _FriendSectionHeader(label: entry.key),
                          ),
                          SliverToBoxAdapter(
                            child: Card(
                              child: Column(
                                children: [
                                  for (
                                    var index = 0;
                                    index < entry.value.length;
                                    index++
                                  ) ...[
                                    _FriendListTile(
                                      friend: entry.value[index],
                                      onTap: () =>
                                          _showFriendDetail(entry.value[index]),
                                    ),
                                    if (index != entry.value.length - 1)
                                      Divider(
                                        height: 1,
                                        color: context.sx.border,
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        ],
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Center(
                              child: Text(
                                '${widget.controller.friends.length} 个好友',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: context.sx.mutedText,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
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
        );
      },
    );
  }

  List<Widget> _buildSliverPageStatusSections() {
    final sections = _buildPageStatusSections();
    if (sections.isEmpty) {
      return const [];
    }
    return [
      SliverToBoxAdapter(child: sections.first),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ];
  }

  Widget _buildFriendsHeader(BuildContext context, int incomingCount) {
    return _buildModuleHeader(
      icon: Icons.people_outline,
      title: '好友',
      tag: incomingCount == 0 ? '通讯录' : '$incomingCount 个申请',
    );
  }

  List<PublicUser> _filteredFriends() {
    final query = _friendSearchController.text.trim().toLowerCase();
    final friends = [...widget.controller.friends]
      ..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
    if (query.isEmpty) {
      return friends;
    }
    return friends.where((friend) {
      return friend.username.toLowerCase().contains(query) ||
          friend.email.toLowerCase().contains(query);
    }).toList();
  }

  Map<String, List<PublicUser>> _groupFriends(List<PublicUser> friends) {
    final result = <String, List<PublicUser>>{};
    for (final friend in friends) {
      final key = _friendSectionKey(friend);
      result.putIfAbsent(key, () => []).add(friend);
    }
    return result;
  }

  String _friendSectionKey(PublicUser friend) {
    final source = friend.username.trim().isNotEmpty
        ? friend.username.trim()
        : friend.email.trim();
    if (source.isEmpty) {
      return '#';
    }
    final first = source[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
  }

  Future<void> _showAddFriendPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _AddFriendPage(controller: widget.controller),
      ),
    );
  }

  Future<void> _showFriendRequests() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            _FriendRequestsPage(controller: widget.controller),
      ),
    );
  }

  Future<void> _showFriendGroups() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _FriendGroupsPage(controller: widget.controller),
      ),
    );
  }

  Future<void> _showFriendDetail(PublicUser friend) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            _FriendDetailPage(controller: widget.controller, friend: friend),
      ),
    );
  }
}

class _FriendActionTile extends StatelessWidget {
  const _FriendActionTile({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: _FriendAvatar(color: color, icon: icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: trailing,
    );
  }
}

class _FriendListTile extends StatelessWidget {
  const _FriendListTile({required this.friend, required this.onTap});

  final PublicUser friend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: _UserAvatar(user: friend),
      title: Text(
        friend.username.isEmpty ? '(未命名用户)' : friend.username,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(friend.email),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _FriendGroupsPage extends StatelessWidget {
  const _FriendGroupsPage({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: ListenableBuilder(
        listenable: controller.chatListenable,
        builder: (context, _) {
          final groups = controller.chatConversations
              .where(
                (conversation) =>
                    conversation.isGroup && !conversation.isDissolved,
              )
              .toList();
          final userId = controller.user?.id ?? '';
          final createdGroups = groups
              .where((conversation) => conversation.adminUserId == userId)
              .toList();
          final joinedGroups = groups
              .where((conversation) => conversation.adminUserId != userId)
              .toList();

          return Scaffold(
            appBar: AppBar(
              title: const Text('群聊'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: '我创建的群聊'),
                  Tab(text: '我加入的群聊'),
                ],
              ),
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: TabBarView(
                    children: [
                      _FriendGroupList(
                        controller: controller,
                        groups: createdGroups,
                        emptyText: '还没有你创建的群聊',
                      ),
                      _FriendGroupList(
                        controller: controller,
                        groups: joinedGroups,
                        emptyText: '还没有你加入的群聊',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FriendGroupList extends StatelessWidget {
  const _FriendGroupList({
    required this.controller,
    required this.groups,
    required this.emptyText,
  });

  final AppController controller;
  final List<ChatConversation> groups;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: controller.refreshFriendsSilently,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: groups.isEmpty
            ? [
                SizedBox(
                  height: 320,
                  child: Center(
                    child: Text(
                      emptyText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.sx.mutedText,
                      ),
                    ),
                  ),
                ),
              ]
            : [
                Card(
                  child: Column(
                    children: [
                      for (var index = 0; index < groups.length; index++) ...[
                        _FriendGroupTile(
                          controller: controller,
                          conversation: groups[index],
                        ),
                        if (index != groups.length - 1)
                          Divider(height: 1, color: context.sx.border),
                      ],
                    ],
                  ),
                ),
              ],
      ),
    );
  }
}

class _FriendGroupTile extends StatelessWidget {
  const _FriendGroupTile({
    required this.controller,
    required this.conversation,
  });

  final AppController controller;
  final ChatConversation conversation;

  @override
  Widget build(BuildContext context) {
    final lastMessage = conversation.lastMessage;
    return ListTile(
      onTap: () async {
        unawaited(controller.openGroupChat(conversation.id));
        if (!context.mounted) {
          return;
        }
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (context) => _ChatRoomPage(
              controller: controller,
              conversationId: conversation.id,
            ),
          ),
        );
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: _GroupAvatar(conversation: conversation),
      title: Text(
        conversation.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        lastMessage == null
            ? '${conversation.members.length + 1} 人 · 端到端加密群聊'
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

class _FriendSectionHeader extends StatelessWidget {
  const _FriendSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: context.sx.mutedText,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RequestBadge extends StatelessWidget {
  const _RequestBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: context.sx.danger,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user});

  final PublicUser user;

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
        gradient: LinearGradient(colors: context.sx.gradient),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.sx.border),
      ),
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _AddFriendPage extends StatefulWidget {
  const _AddFriendPage({required this.controller});

  final AppController controller;

  @override
  State<_AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<_AddFriendPage> {
  final _identifierController = TextEditingController();
  final _messageController = TextEditingController();
  String? _localMessage;

  @override
  void dispose() {
    _identifierController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('添加好友')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const _SettingsDetailHeader(
                      icon: Icons.person_add_alt_1_outlined,
                      title: '发送好友申请',
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            TextField(
                              controller: _identifierController,
                              decoration: const InputDecoration(
                                labelText: '用户名或邮箱',
                                prefixIcon: Icon(Icons.search),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _messageController,
                              minLines: 2,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: '申请说明',
                                hintText: '你好，我想添加你为好友',
                              ),
                            ),
                            if (_localMessage != null) ...[
                              const SizedBox(height: 12),
                              _InlineNotice(message: _localMessage!),
                            ],
                            if (widget.controller.statusMessage != null) ...[
                              const SizedBox(height: 12),
                              _StatusLine(
                                message: widget.controller.statusMessage,
                                busy: widget.controller.busy,
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
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.controller.busy ? null : _submit,
                      child: const Text('发送申请'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    final identifier = _identifierController.text.trim();
    setState(() {
      _localMessage = null;
    });
    if (identifier.isEmpty) {
      setState(() {
        _localMessage = '请输入好友用户名或邮箱。';
      });
      return;
    }

    try {
      await widget.controller.sendFriendRequest(
        identifier: identifier,
        message: _messageController.text,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (_) {}
  }
}

class _FriendRequestsPage extends StatelessWidget {
  const _FriendRequestsPage({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: AnimatedBuilder(
        animation: controller.friendsListenable,
        builder: (context, _) {
          final incomingRequests = controller.incomingFriendRequests;
          final outgoingRequests = controller.outgoingFriendRequests;
          return Scaffold(
            appBar: AppBar(
              title: const Text('新的朋友'),
              bottom: TabBar(
                tabs: [
                  Tab(text: '收到的申请 (${incomingRequests.length})'),
                  Tab(text: '发出的申请 (${outgoingRequests.length})'),
                ],
              ),
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: TabBarView(
                    children: [
                      _FriendRequestList(
                        controller: controller,
                        title: '收到的申请',
                        emptyText: '暂无待处理申请',
                        requests: incomingRequests,
                        incoming: true,
                      ),
                      _FriendRequestList(
                        controller: controller,
                        title: '发出的申请',
                        emptyText: '暂无发出的申请',
                        requests: outgoingRequests,
                        incoming: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FriendRequestList extends StatelessWidget {
  const _FriendRequestList({
    required this.controller,
    required this.title,
    required this.emptyText,
    required this.requests,
    required this.incoming,
  });

  final AppController controller;
  final String title;
  final String emptyText;
  final List<FriendRequestRecord> requests;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: controller.refreshFriendsSilently,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsDetailHeader(
            icon: incoming
                ? Icons.mark_email_unread_outlined
                : Icons.send_outlined,
            title: title,
          ),
          const SizedBox(height: 12),
          _RequestSection(
            title: title,
            emptyText: emptyText,
            requests: requests,
            incoming: incoming,
            controller: controller,
          ),
        ],
      ),
    );
  }
}

class _RequestSection extends StatelessWidget {
  const _RequestSection({
    required this.title,
    required this.emptyText,
    required this.requests,
    required this.incoming,
    required this.controller,
  });

  final String title;
  final String emptyText;
  final List<FriendRequestRecord> requests;
  final bool incoming;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          _ListCardHeader(title: title),
          if (requests.isEmpty)
            Padding(
              padding: const EdgeInsets.all(22),
              child: Text(
                emptyText,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: context.sx.mutedText),
              ),
            )
          else
            for (var index = 0; index < requests.length; index++) ...[
              _RequestTile(
                request: requests[index],
                incoming: incoming,
                controller: controller,
              ),
              if (index != requests.length - 1)
                Divider(height: 1, color: context.sx.border),
            ],
        ],
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.incoming,
    required this.controller,
  });

  final FriendRequestRecord request;
  final bool incoming;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final user = incoming ? request.requester : request.addressee;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: _UserAvatar(user: user),
      title: Text(
        user.username,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(request.message.isEmpty ? user.email : request.message),
      trailing: incoming
          ? PopupMenuButton<String>(
              tooltip: '处理申请',
              onSelected: controller.busy
                  ? null
                  : (value) async {
                      if (value == 'accept') {
                        await controller.acceptFriendRequest(request);
                        return;
                      }
                      await controller.rejectFriendRequest(request);
                    },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'accept', child: Text('同意')),
                PopupMenuItem(value: 'reject', child: Text('拒绝')),
              ],
            )
          : Text(
              '等待验证',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.sx.mutedText,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

class _FriendDetailPage extends StatelessWidget {
  const _FriendDetailPage({required this.controller, required this.friend});

  final AppController controller;
  final PublicUser friend;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('好友信息')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            _UserAvatar(user: friend),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    friend.username,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    friend.email,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: context.sx.mutedText),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          '好友关系只用于通讯录和后续协作入口，不会让对方看到或解密你的密码库、文件和任何保险库明文。',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: context.sx.mutedText),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () async {
                        unawaited(controller.openChatWith(friend));
                        if (!context.mounted) {
                          return;
                        }
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (context) => _ChatRoomPage(
                              controller: controller,
                              conversationId: friend.id,
                              friend: friend,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('发消息'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: controller.busy
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('清除聊天记录'),
                                  content: Text(
                                    '确定清除你与“${friend.username.isEmpty ? friend.email : friend.username}”的聊天记录吗？清除后只有你自己看不到，对方聊天记录不会删除。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('清除'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) {
                                return;
                              }
                              await controller.clearDirectChatHistory(friend);
                              if (context.mounted &&
                                  controller.statusMessage != null &&
                                  controller.statusMessage!.isNotEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(controller.statusMessage!),
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('清除聊天记录'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.sx.danger,
                        side: BorderSide(color: context.sx.danger),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: controller.busy
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('删除好友'),
                                  content: Text('确定删除“${friend.username}”吗？'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('删除'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) {
                                return;
                              }
                              await controller.deleteFriend(friend);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                      icon: const Icon(Icons.person_remove_outlined),
                      label: const Text('删除好友'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.sx.danger,
                        side: BorderSide(color: context.sx.danger),
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
