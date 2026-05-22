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
                          subtitle: widget.controller.user?.username ?? '当前账号',
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
    await _openSettingsPage(
      title: '个人信息',
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsRow(
            label: '用户名',
            value: widget.controller.user?.username ?? '-',
          ),
          const SizedBox(height: 10),
          _SettingsRow(
            label: '邮箱',
            value: widget.controller.user?.email ?? '-',
          ),
          const SizedBox(height: 10),
          _SettingsRow(label: '当前服务', value: widget.controller.baseUrl),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: context.sx.subtle,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '密码、备注、文件都只在客户端加解密。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.sx.mutedText),
            ),
          ),
        ],
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
