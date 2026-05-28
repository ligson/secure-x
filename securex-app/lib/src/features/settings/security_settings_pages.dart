part of '../../../main.dart';

class _SecuritySettingsPage extends StatelessWidget {
  const _SecuritySettingsPage({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('安全设置')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SettingsDetailHeader(
                  icon: Icons.security_outlined,
                  title: '安全设置',
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      _SettingsMenuTile(
                        icon: Icons.password_outlined,
                        title: '登录密码',
                        subtitle: '用于登录服务端账号',
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (context) =>
                                  _ChangePasswordPage(controller: controller),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1, color: context.sx.border),
                      _SettingsMenuTile(
                        icon: Icons.lock_open_outlined,
                        title: '解锁密码',
                        subtitle: '用于本机解锁和解密保险库',
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (context) => _ChangeUnlockPasswordPage(
                                controller: controller,
                              ),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1, color: context.sx.border),
                      _SettingsMenuTile(
                        icon: Icons.devices_other_outlined,
                        title: '设备管理',
                        subtitle: '查看和移除旧聊天设备',
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (context) =>
                                  _DeviceManagementPage(controller: controller),
                            ),
                          );
                        },
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
  }
}

class _DeviceManagementPage extends StatefulWidget {
  const _DeviceManagementPage({required this.controller});

  final AppController controller;

  @override
  State<_DeviceManagementPage> createState() => _DeviceManagementPageState();
}

class _DeviceManagementPageState extends State<_DeviceManagementPage> {
  late Future<List<ChatDeviceRecord>> _devicesFuture;

  @override
  void initState() {
    super.initState();
    _devicesFuture = widget.controller.listOwnChatDevices();
  }

  void _reload() {
    setState(() {
      _devicesFuture = widget.controller.listOwnChatDevices();
    });
  }

  Future<void> _deleteDevice(ChatDeviceRecord device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除设备'),
          content: Text(
            '确定删除设备 ${_shortDeviceId(device.id)} 吗？该设备未拉取的密文消息也会被清理。',
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
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await widget.controller.deleteOwnChatDevice(device.id);
    if (mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final currentDeviceId = widget.controller.currentChatDeviceId;
        return Scaffold(
          appBar: AppBar(title: const Text('设备管理')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const _SettingsDetailHeader(
                        icon: Icons.devices_other_outlined,
                        title: '设备管理',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '设备身份用于端到端加密聊天投递。删除旧设备只影响该设备后续收取消息，不会解密或删除你的保险库数据。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.sx.mutedText,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<List<ChatDeviceRecord>>(
                        future: _devicesFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Card(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            );
                          }
                          final devices = snapshot.data ?? const [];
                          if (devices.isEmpty) {
                            return const Card(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: Text('暂无设备记录')),
                              ),
                            );
                          }
                          return Card(
                            child: Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < devices.length;
                                  index++
                                ) ...[
                                  _DeviceListTile(
                                    device: devices[index],
                                    current:
                                        devices[index].id == currentDeviceId,
                                    onDelete:
                                        devices[index].id == currentDeviceId
                                        ? null
                                        : () => _deleteDevice(devices[index]),
                                  ),
                                  if (index != devices.length - 1)
                                    Divider(
                                      height: 1,
                                      color: context.sx.border,
                                    ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DeviceListTile extends StatelessWidget {
  const _DeviceListTile({
    required this.device,
    required this.current,
    required this.onDelete,
  });

  final ChatDeviceRecord device;
  final bool current;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: current ? context.sx.accentSoft : context.sx.subtle,
        child: Icon(
          current ? Icons.check_circle_outline : Icons.devices_other_outlined,
          color: current ? context.sx.primary : context.sx.mutedText,
        ),
      ),
      title: Text(current ? '当前设备' : '聊天设备 ${_shortDeviceId(device.id)}'),
      subtitle: Text(
        [
          '编号 ${_shortDeviceId(device.id)}',
          if (device.appInstance.isNotEmpty) '实例 ${device.appInstance}',
          '最近在线 ${_formatDeviceTime(device.lastSeenAt)}',
        ].join(' · '),
      ),
      trailing: current
          ? const Text('使用中')
          : IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除设备',
            ),
    );
  }
}

String _shortDeviceId(String value) {
  final normalized = value.trim();
  if (normalized.length <= 8) {
    return normalized;
  }
  return '${normalized.substring(0, 8)}...';
}

String _formatDeviceTime(DateTime? value) {
  if (value == null) {
    return '未知';
  }
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _ChangePasswordPage extends StatefulWidget {
  const _ChangePasswordPage({required this.controller});

  final AppController controller;

  @override
  State<_ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<_ChangePasswordPage> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;
  String? _localMessage;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('登录密码')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const _SettingsDetailHeader(
                      icon: Icons.password_outlined,
                      title: '登录密码',
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '这里只修改服务端登录密码，不会修改解锁密码，也不会重新加密保险库数据。',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: context.sx.mutedText),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _currentPasswordController,
                              obscureText: !_showCurrentPassword,
                              decoration: InputDecoration(
                                labelText: '当前登录密码',
                                suffixIcon: IconButton(
                                  tooltip: _showCurrentPassword
                                      ? '隐藏密码'
                                      : '查看密码',
                                  onPressed: () {
                                    setState(() {
                                      _showCurrentPassword =
                                          !_showCurrentPassword;
                                    });
                                  },
                                  icon: Icon(
                                    _showCurrentPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _newPasswordController,
                              obscureText: !_showNewPassword,
                              decoration: InputDecoration(
                                labelText: '新登录密码',
                                suffixIcon: IconButton(
                                  tooltip: _showNewPassword ? '隐藏密码' : '查看密码',
                                  onPressed: () {
                                    setState(() {
                                      _showNewPassword = !_showNewPassword;
                                    });
                                  },
                                  icon: Icon(
                                    _showNewPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _confirmPasswordController,
                              obscureText: !_showConfirmPassword,
                              decoration: InputDecoration(
                                labelText: '确认新登录密码',
                                suffixIcon: IconButton(
                                  tooltip: _showConfirmPassword
                                      ? '隐藏密码'
                                      : '查看密码',
                                  onPressed: () {
                                    setState(() {
                                      _showConfirmPassword =
                                          !_showConfirmPassword;
                                    });
                                  },
                                  icon: Icon(
                                    _showConfirmPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                            ),
                            if (_localMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _localMessage!,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: context.sx.danger),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton(
                                onPressed: widget.controller.busy
                                    ? null
                                    : _submit,
                                child: const Text('保存新密码'),
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

  Future<void> _submit() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    setState(() {
      _localMessage = null;
    });

    if (currentPassword.isEmpty) {
      setState(() {
        _localMessage = '请输入当前登录密码。';
      });
      return;
    }
    if (newPassword.length < 8) {
      setState(() {
        _localMessage = '新登录密码至少需要 8 位。';
      });
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() {
        _localMessage = '两次输入的新登录密码不一致。';
      });
      return;
    }
    if (currentPassword == newPassword) {
      setState(() {
        _localMessage = '新登录密码不能和当前登录密码相同。';
      });
      return;
    }

    try {
      await widget.controller.changeLoginPassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (!mounted) {
        return;
      }
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('登录密码已修改')));
    } catch (_) {}
  }
}

class _ChangeUnlockPasswordPage extends StatefulWidget {
  const _ChangeUnlockPasswordPage({required this.controller});

  final AppController controller;

  @override
  State<_ChangeUnlockPasswordPage> createState() =>
      _ChangeUnlockPasswordPageState();
}

class _ChangeUnlockPasswordPageState extends State<_ChangeUnlockPasswordPage> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;
  String? _localMessage;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('解锁密码')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const _SettingsDetailHeader(
                      icon: Icons.lock_open_outlined,
                      title: '解锁密码',
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '这里只修改客户端解锁保险库使用的密码。服务端只保存新的密文封装结果，不会知道你的解锁密码。',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: context.sx.mutedText),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _currentPasswordController,
                              obscureText: !_showCurrentPassword,
                              decoration: InputDecoration(
                                labelText: '当前解锁密码',
                                suffixIcon: IconButton(
                                  tooltip: _showCurrentPassword
                                      ? '隐藏密码'
                                      : '查看密码',
                                  onPressed: () {
                                    setState(() {
                                      _showCurrentPassword =
                                          !_showCurrentPassword;
                                    });
                                  },
                                  icon: Icon(
                                    _showCurrentPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _newPasswordController,
                              obscureText: !_showNewPassword,
                              decoration: InputDecoration(
                                labelText: '新解锁密码',
                                suffixIcon: IconButton(
                                  tooltip: _showNewPassword ? '隐藏密码' : '查看密码',
                                  onPressed: () {
                                    setState(() {
                                      _showNewPassword = !_showNewPassword;
                                    });
                                  },
                                  icon: Icon(
                                    _showNewPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _confirmPasswordController,
                              obscureText: !_showConfirmPassword,
                              decoration: InputDecoration(
                                labelText: '确认新解锁密码',
                                suffixIcon: IconButton(
                                  tooltip: _showConfirmPassword
                                      ? '隐藏密码'
                                      : '查看密码',
                                  onPressed: () {
                                    setState(() {
                                      _showConfirmPassword =
                                          !_showConfirmPassword;
                                    });
                                  },
                                  icon: Icon(
                                    _showConfirmPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                            ),
                            if (_localMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _localMessage!,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: context.sx.danger),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton(
                                onPressed: widget.controller.busy
                                    ? null
                                    : _submit,
                                child: const Text('保存解锁密码'),
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

  Future<void> _submit() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    setState(() {
      _localMessage = null;
    });

    if (currentPassword.isEmpty) {
      setState(() {
        _localMessage = '请输入当前解锁密码。';
      });
      return;
    }
    if (newPassword.length < 8) {
      setState(() {
        _localMessage = '新解锁密码至少需要 8 位。';
      });
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() {
        _localMessage = '两次输入的新解锁密码不一致。';
      });
      return;
    }
    if (currentPassword == newPassword) {
      setState(() {
        _localMessage = '新解锁密码不能和当前解锁密码相同。';
      });
      return;
    }

    try {
      await widget.controller.changeUnlockPassword(
        currentUnlockPassword: currentPassword,
        newUnlockPassword: newPassword,
      );
      if (!mounted) {
        return;
      }
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('解锁密码已修改')));
    } catch (_) {}
  }
}
