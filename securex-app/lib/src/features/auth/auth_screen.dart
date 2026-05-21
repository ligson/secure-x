part of '../../../main.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  late final TabController _tabController;
  late final TextEditingController _baseUrlController;
  final _loginIdentifierController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _registerUsernameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerUnlockPasswordController = TextEditingController();
  bool _showLoginPassword = false;
  bool _showRegisterPassword = false;
  bool _showRegisterUnlockPassword = false;
  String? _localStatusMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _baseUrlController = TextEditingController(text: widget.controller.baseUrl);
    _tabController.addListener(_clearLocalStatusMessage);
  }

  @override
  void dispose() {
    _tabController.removeListener(_clearLocalStatusMessage);
    _tabController.dispose();
    _baseUrlController.dispose();
    _loginIdentifierController.dispose();
    _loginPasswordController.dispose();
    _registerUsernameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerUnlockPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _AuthBackdrop(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(26),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: context.sx.button,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.lock_outline_rounded,
                                  color: context.sx.onButton,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                'secure-x',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '客户端加密，服务端只存密文。',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: context.sx.mutedText),
                          ),
                          const SizedBox(height: 20),
                          _EndpointBanner(
                            controller: _baseUrlController,
                            busy: widget.controller.busy,
                            onSave: () async {
                              final validationMessage = _validateBaseUrl(
                                _baseUrlController.text,
                              );
                              if (validationMessage != null) {
                                _setLocalStatusMessage(validationMessage);
                                return;
                              }

                              _clearLocalStatusMessage();
                              await widget.controller.saveBaseUrl(
                                _baseUrlController.text,
                              );
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('后端地址已保存')),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              color: context.sx.subtle,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: context.sx.border),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: TabBar(
                              controller: _tabController,
                              dividerColor: Colors.transparent,
                              indicator: BoxDecoration(
                                color: context.sx.card,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              labelColor: context.sx.text,
                              unselectedLabelColor: context.sx.mutedText,
                              labelStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                              tabs: const [
                                Tab(text: '登录'),
                                Tab(text: '注册'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 400,
                            child: TabBarView(
                              controller: _tabController,
                              children: [_buildLogin(), _buildRegister()],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _StatusLine(
                            message:
                                _localStatusMessage ??
                                widget.controller.statusMessage,
                            busy: widget.controller.busy,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogin() {
    return ListView(
      children: [
        TextField(
          controller: _loginIdentifierController,
          decoration: const InputDecoration(
            hintText: '用户名 / 邮箱',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _loginPasswordController,
          decoration: InputDecoration(
            hintText: '登录密码',
            prefixIcon: const Icon(Icons.login_outlined),
            suffixIcon: IconButton(
              tooltip: _showLoginPassword ? '隐藏密码' : '查看密码',
              onPressed: () {
                setState(() {
                  _showLoginPassword = !_showLoginPassword;
                });
              },
              icon: Icon(
                _showLoginPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
          obscureText: !_showLoginPassword,
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: widget.controller.busy
              ? null
              : () async {
                  final validationMessage = _validateLoginInputs();
                  if (validationMessage != null) {
                    _setLocalStatusMessage(validationMessage);
                    return;
                  }

                  try {
                    _clearLocalStatusMessage();
                    await widget.controller.saveBaseUrl(
                      _baseUrlController.text,
                    );
                    await widget.controller.login(
                      identifier: _loginIdentifierController.text,
                      authPassword: _loginPasswordController.text,
                    );
                  } catch (_) {}
                },
          child: const Text('登录'),
        ),
      ],
    );
  }

  Widget _buildRegister() {
    return ListView(
      children: [
        TextField(
          controller: _registerUsernameController,
          decoration: const InputDecoration(
            hintText: '用户名',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _registerEmailController,
          decoration: const InputDecoration(
            hintText: '邮箱',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _registerPasswordController,
          decoration: InputDecoration(
            hintText: '登录密码',
            prefixIcon: const Icon(Icons.verified_user_outlined),
            suffixIcon: IconButton(
              tooltip: _showRegisterPassword ? '隐藏密码' : '查看密码',
              onPressed: () {
                setState(() {
                  _showRegisterPassword = !_showRegisterPassword;
                });
              },
              icon: Icon(
                _showRegisterPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
          obscureText: !_showRegisterPassword,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _registerUnlockPasswordController,
          decoration: InputDecoration(
            hintText: '解锁密码',
            prefixIcon: const Icon(Icons.enhanced_encryption_outlined),
            suffixIcon: IconButton(
              tooltip: _showRegisterUnlockPassword ? '隐藏密码' : '查看密码',
              onPressed: () {
                setState(() {
                  _showRegisterUnlockPassword = !_showRegisterUnlockPassword;
                });
              },
              icon: Icon(
                _showRegisterUnlockPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
          obscureText: !_showRegisterUnlockPassword,
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: widget.controller.busy
              ? null
              : () async {
                  final validationMessage = _validateRegisterInputs();
                  if (validationMessage != null) {
                    _setLocalStatusMessage(validationMessage);
                    return;
                  }

                  try {
                    _clearLocalStatusMessage();
                    await widget.controller.saveBaseUrl(
                      _baseUrlController.text,
                    );
                    await widget.controller.register(
                      username: _registerUsernameController.text,
                      email: _registerEmailController.text,
                      authPassword: _registerPasswordController.text,
                      unlockPassword: _registerUnlockPasswordController.text,
                    );
                  } catch (_) {}
                },
          child: const Text('创建账户'),
        ),
      ],
    );
  }

  void _setLocalStatusMessage(String message) {
    setState(() {
      _localStatusMessage = message;
    });
  }

  void _clearLocalStatusMessage() {
    if (_localStatusMessage == null) {
      return;
    }

    setState(() {
      _localStatusMessage = null;
    });
  }

  String? _validateBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return '请先填写后端地址。';
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        (uri.host.isEmpty && normalized != 'http://localhost')) {
      return '后端地址格式不正确，请使用 http://127.0.0.1:8080 这类完整地址。';
    }

    return null;
  }

  String? _validateLoginInputs() {
    final baseUrlMessage = _validateBaseUrl(_baseUrlController.text);
    if (baseUrlMessage != null) {
      return baseUrlMessage;
    }
    if (_loginIdentifierController.text.trim().isEmpty) {
      return '请输入用户名或邮箱。';
    }
    if (_loginPasswordController.text.isEmpty) {
      return '请输入登录密码。';
    }
    return null;
  }

  String? _validateRegisterInputs() {
    final baseUrlMessage = _validateBaseUrl(_baseUrlController.text);
    if (baseUrlMessage != null) {
      return baseUrlMessage;
    }
    if (_registerUsernameController.text.trim().isEmpty) {
      return '请输入用户名。';
    }
    if (!_emailPattern.hasMatch(_registerEmailController.text.trim())) {
      return '请输入有效的邮箱地址。';
    }
    if (_registerPasswordController.text.length < 8) {
      return '登录密码至少需要 8 位。';
    }
    if (_registerUnlockPasswordController.text.length < 8) {
      return '解锁密码至少需要 8 位。';
    }

    return null;
  }
}
