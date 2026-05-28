// ignore_for_file: invalid_use_of_protected_member

part of '../../../main.dart';

extension _VaultSettingsTab on _VaultScreenState {
  Widget _buildSettingsTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildModuleHeader(
            icon: Icons.settings_outlined,
            title: '设置',
            tag: '已加密',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final notice in _buildPageStatusSections()) ...[
                    notice,
                    const SizedBox(height: 12),
                  ],
                  Card(
                    child: Column(
                      children: [
                        _SettingsMenuTile(
                          icon: Icons.person_outline,
                          title: '个人信息',
                          subtitle:
                              widget.controller.user?.displayName ?? '当前账号',
                          onTap: _showProfileSettings,
                        ),
                        Divider(height: 1, color: context.sx.border),
                        _SettingsMenuTile(
                          icon: Icons.palette_outlined,
                          title: '主题外观',
                          subtitle: SecureXThemeSpec.byId(
                            widget.controller.themeId,
                          ).name,
                          onTap: _showThemeSettings,
                        ),
                        Divider(height: 1, color: context.sx.border),
                        _SettingsMenuTile(
                          icon: Icons.lan_outlined,
                          title: '连接设置',
                          subtitle: widget.controller.baseUrl,
                          onTap: _showConnectionSettings,
                        ),
                        Divider(height: 1, color: context.sx.border),
                        _SettingsMenuTile(
                          icon: Icons.security_outlined,
                          title: '安全设置',
                          subtitle: '登录密码、解锁密码',
                          onTap: _showSecuritySettings,
                        ),
                        Divider(height: 1, color: context.sx.border),
                        _SettingsMenuTile(
                          icon: Icons.power_settings_new_outlined,
                          title: '会话操作',
                          subtitle: '同步、锁定、退出登录',
                          onTap: _showSessionSettings,
                        ),
                        Divider(height: 1, color: context.sx.border),
                        _SettingsMenuTile(
                          icon: Icons.info_outline,
                          title: '关于',
                          subtitle: '版本介绍、版本更新',
                          onTap: _showAboutSettings,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showProfileSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            _ProfileSettingsPage(controller: widget.controller),
      ),
    );
  }

  Future<void> _showThemeSettings() async {
    await _openSettingsPage(
      title: '主题外观',
      icon: Icons.palette_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择适合白天或夜间使用的配色。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.sx.mutedText),
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 760 ? 2 : 1;
                  final itemWidth =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final theme in SecureXThemeSpec.all)
                        SizedBox(
                          width: itemWidth,
                          child: _ThemeOptionCard(
                            theme: theme,
                            selected: widget.controller.themeId == theme.id,
                            onTap: () =>
                                widget.controller.saveThemeId(theme.id),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showConnectionSettings() async {
    await _openSettingsPage(
      title: '连接设置',
      icon: Icons.lan_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _settingsBaseUrlController,
            decoration: const InputDecoration(labelText: '后端地址'),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: widget.controller.busy
                  ? null
                  : () async {
                      final validationMessage = _validateBaseUrl(
                        _settingsBaseUrlController.text,
                      );
                      if (validationMessage != null) {
                        if (!mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(validationMessage)),
                        );
                        return;
                      }
                      await widget.controller.saveBaseUrl(
                        _settingsBaseUrlController.text,
                      );
                      if (!mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('后端地址已保存')));
                    },
              child: const Text('保存设置'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSecuritySettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            _SecuritySettingsPage(controller: widget.controller),
      ),
    );
  }

  Future<void> _showSessionSettings() async {
    await _openSettingsPage(
      title: '会话操作',
      icon: Icons.power_settings_new_outlined,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: widget.controller.busy
                ? null
                : widget.controller.refreshVault,
            icon: const Icon(Icons.sync),
            label: const Text('立即同步'),
          ),
          OutlinedButton.icon(
            onPressed: widget.controller.busy ? null : _handleSessionLock,
            icon: const Icon(Icons.lock_outline),
            label: const Text('锁定'),
          ),
          OutlinedButton.icon(
            onPressed: widget.controller.busy ? null : _handleSessionLogout,
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAboutSettings() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (context) => const _AboutPage()));
  }

  Future<void> _openSettingsPage({
    required String title,
    required IconData icon,
    required Widget child,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            _SettingsDetailPage(title: title, icon: icon, child: child),
      ),
    );
  }

  Future<void> _handleSessionLock() async {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    await widget.controller.lock();
  }

  Future<void> _handleSessionLogout() async {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    await widget.controller.logout();
  }
}

class _ProfileSettingsPage extends StatelessWidget {
  const _ProfileSettingsPage({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final user = controller.user;
        if (user == null) {
          return const SizedBox.shrink();
        }
        return Scaffold(
          appBar: AppBar(title: const Text('个人信息')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const _SettingsDetailHeader(
                      icon: Icons.person_outline,
                      title: '个人信息',
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            _PresetAvatar(
                              presetId: user.avatarPreset,
                              imageUrl: user.avatarUrl,
                              size: 76,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              user.displayName,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              user.email,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: context.sx.mutedText),
                            ),
                            const SizedBox(height: 18),
                            _ProfileReadonlyRow(
                              label: '用户名',
                              value: user.username,
                            ),
                            _ProfileReadonlyRow(label: '邮箱', value: user.email),
                            _ProfileReadonlyRow(
                              label: '当前服务',
                              value: controller.baseUrl,
                              last: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          const _ListCardHeader(title: '可修改信息'),
                          ListTile(
                            leading: _PresetAvatar(
                              presetId: user.avatarPreset,
                              imageUrl: user.avatarUrl,
                              size: 44,
                            ),
                            title: const Text(
                              '头像',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              user.avatarUrl.trim().isEmpty
                                  ? '当前使用预设头像'
                                  : '当前使用本地上传头像',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                _slidePageRoute(
                                  _ProfileAvatarPage(controller: controller),
                                ),
                              );
                            },
                          ),
                          Divider(height: 1, color: context.sx.border),
                          ListTile(
                            leading: Icon(
                              Icons.badge_outlined,
                              color: context.sx.primary,
                            ),
                            title: const Text(
                              '昵称',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              user.nickname.trim().isEmpty
                                  ? '未设置'
                                  : user.nickname,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                _slidePageRoute(
                                  _ProfileNicknamePage(
                                    controller: controller,
                                    initialNickname: user.nickname,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.sx.subtle,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: context.sx.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.security_outlined,
                            color: context.sx.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '头像和昵称属于公开资料，好友可以看到；密码、文件和聊天内容仍只在客户端加解密。',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: context.sx.mutedText),
                            ),
                          ),
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

class _ProfileReadonlyRow extends StatelessWidget {
  const _ProfileReadonlyRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 82,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.sx.mutedText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value.isEmpty ? '-' : value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        if (!last) Divider(height: 1, color: context.sx.border),
      ],
    );
  }
}

class _ProfileNicknamePage extends StatefulWidget {
  const _ProfileNicknamePage({
    required this.controller,
    required this.initialNickname,
  });

  final AppController controller;
  final String initialNickname;

  @override
  State<_ProfileNicknamePage> createState() => _ProfileNicknamePageState();
}

class _ProfileNicknamePageState extends State<_ProfileNicknamePage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNickname);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('修改昵称')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SettingsDetailHeader(
                  icon: Icons.badge_outlined,
                  title: '修改昵称',
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        TextField(
                          controller: _controller,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: '昵称',
                            hintText: '输入展示昵称',
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: widget.controller.busy
                                ? null
                                : () async {
                                    final nickname = _controller.text.trim();
                                    if (nickname.isEmpty) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(content: Text('请输入昵称')),
                                      );
                                      return;
                                    }
                                    await widget.controller.updateProfile(
                                      nickname: nickname,
                                    );
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                            child: const Text('保存昵称'),
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
  }
}

class _ProfileAvatarPage extends StatefulWidget {
  const _ProfileAvatarPage({required this.controller});

  final AppController controller;

  @override
  State<_ProfileAvatarPage> createState() => _ProfileAvatarPageState();
}

class _ProfileAvatarPageState extends State<_ProfileAvatarPage> {
  late String _avatarPreset;
  Uint8List? _previewBytes;
  String _previewName = 'avatar.jpg';

  @override
  void initState() {
    super.initState();
    _avatarPreset = normalizeSecureXAvatarPreset(
      widget.controller.user?.avatarPreset,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.controller.user;
    return Scaffold(
      appBar: AppBar(title: const Text('修改头像')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SettingsDetailHeader(
                  icon: Icons.account_circle_outlined,
                  title: '修改头像',
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _AvatarPreview(
                          bytes: _previewBytes,
                          presetId: _avatarPreset,
                          imageUrl: _previewBytes == null
                              ? user?.avatarUrl ?? ''
                              : '',
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _previewBytes == null ? '当前头像' : '待上传头像',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '可以选择本地图像上传，也可以继续使用预设头像。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: context.sx.mutedText),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: widget.controller.busy
                                    ? null
                                    : _pickLocalAvatar,
                                icon: const Icon(Icons.image_outlined),
                                label: const Text('选择本地图像'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed:
                                    widget.controller.busy ||
                                        _previewBytes == null
                                    ? null
                                    : () async {
                                        await widget.controller
                                            .uploadProfileAvatar(
                                              bytes: _previewBytes!,
                                              filename: _previewName,
                                            );
                                        if (context.mounted) {
                                          Navigator.of(context).pop();
                                        }
                                      },
                                icon: const Icon(Icons.cloud_upload_outlined),
                                label: const Text('上传头像'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '预设头像',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 12),
                        _AvatarPresetPicker(
                          selectedPresetId: _avatarPreset,
                          onSelected: (value) {
                            setState(() {
                              _avatarPreset = value;
                              _previewBytes = null;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: widget.controller.busy
                                ? null
                                : () async {
                                    await widget.controller.updateProfile(
                                      avatarPreset: _avatarPreset,
                                    );
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                            child: const Text('使用这个预设头像'),
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
  }

  Future<void> _pickLocalAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || bytes.isEmpty) {
      return;
    }
    final compressed = _compressAvatar(bytes);
    if (compressed.length > 1024 * 1024) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('头像图片不能超过 1MB')));
      return;
    }
    setState(() {
      _previewBytes = compressed;
      _previewName = _avatarUploadName(file.name);
    });
  }

  Uint8List _compressAvatar(Uint8List source) {
    final decoded = img.decodeImage(source);
    if (decoded == null) {
      return source;
    }
    final resized = decoded.width > 512 || decoded.height > 512
        ? img.copyResize(
            decoded,
            width: 512,
            interpolation: img.Interpolation.average,
          )
        : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 84));
  }

  String _avatarUploadName(String originalName) {
    final lower = originalName.toLowerCase();
    if (lower.endsWith('.png') || lower.endsWith('.webp')) {
      return 'avatar.jpg';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'avatar.jpg';
    }
    return 'avatar.jpg';
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({
    required this.bytes,
    required this.presetId,
    required this.imageUrl,
  });

  final Uint8List? bytes;
  final String presetId;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final previewBytes = bytes;
    if (previewBytes == null) {
      return _PresetAvatar(presetId: presetId, imageUrl: imageUrl, size: 92);
    }
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: context.sx.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.memory(previewBytes, fit: BoxFit.cover),
    );
  }
}
