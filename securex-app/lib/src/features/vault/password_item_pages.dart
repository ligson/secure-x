part of '../../../main.dart';

class _PasswordEditorPage extends StatefulWidget {
  const _PasswordEditorPage({
    required this.controller,
    required this.item,
    required this.folders,
    required this.initialGeneratedPassword,
    required this.onGeneratePassword,
  });

  final AppController controller;
  final DecryptedLoginItem? item;
  final List<DecryptedFolder> folders;
  final String initialGeneratedPassword;
  final String Function() onGeneratePassword;

  @override
  State<_PasswordEditorPage> createState() => _PasswordEditorPageState();
}

class _PasswordEditorPageState extends State<_PasswordEditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _urlController;
  late final TextEditingController _noteController;
  late final TextEditingController _totpSecretController;
  late String _folderId;
  bool _showPassword = false;
  bool _showTotpSecret = false;
  TotpConfig _totpConfig = const TotpConfig(secret: '');

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item?.title ?? '');
    _usernameController = TextEditingController(
      text: widget.item?.username ?? '',
    );
    _passwordController = TextEditingController(
      text: widget.item?.password ?? '',
    );
    _urlController = TextEditingController(text: widget.item?.url ?? '');
    _noteController = TextEditingController(text: widget.item?.note ?? '');
    _totpConfig = widget.item?.totp ?? const TotpConfig(secret: '');
    _totpSecretController = TextEditingController(text: _totpConfig.secret);
    _folderId = widget.item?.folderId ?? '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _noteController.dispose();
    _totpSecretController.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<String>> _folderItems() {
    return [
      const DropdownMenuItem<String>(value: '', child: Text('未分类')),
      ...widget.controller.orderedPasswordFolders().map(
        (folder) => DropdownMenuItem<String>(
          value: folder.id,
          child: Text(widget.controller.passwordFolderLabel(folder)),
        ),
      ),
    ];
  }

  Future<void> _scanTotpQr() async {
    if (!_canScanTotpQr) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前平台暂不支持摄像头识别，请手动粘贴密钥')));
      return;
    }
    final rawValue = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const _TotpQrScannerPage()),
    );
    if (!mounted || rawValue == null || rawValue.trim().isEmpty) {
      return;
    }
    try {
      final config = _parseTotpInput(rawValue);
      setState(() {
        _totpConfig = config;
        _totpSecretController.text = config.secret;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('验证器密钥已识别')));
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('二维码内容无法识别为 TOTP')));
    }
  }

  bool get _canScanTotpQr =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  _LoginItemDraft? _buildDraft() {
    TotpConfig totp;
    try {
      final input = _totpSecretController.text.trim();
      final parsed = _parseTotpInput(input);
      totp = input.isEmpty
          ? const TotpConfig(secret: '')
          : TotpConfig(
              secret: parsed.secret,
              issuer: parsed.issuer.isNotEmpty
                  ? parsed.issuer
                  : _totpConfig.issuer,
              account: parsed.account.isNotEmpty
                  ? parsed.account
                  : _totpConfig.account,
              algorithm: parsed.algorithm,
              digits: parsed.digits,
              period: parsed.period,
            );
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return null;
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('验证器密钥格式不正确')));
      return null;
    }

    return _LoginItemDraft(
      title: _titleController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      url: _urlController.text.trim(),
      note: _noteController.text.trim(),
      totp: totp,
      folderId: _folderId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.item == null ? '创建密码' : '编辑密码')),
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
                    child: Column(
                      children: [
                        TextField(
                          controller: _titleController,
                          decoration: const InputDecoration(labelText: '标题'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(labelText: '用户名'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            labelText: '密码',
                            suffixIcon: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: _showPassword ? '隐藏密码' : '查看密码',
                                  onPressed: () {
                                    setState(() {
                                      _showPassword = !_showPassword;
                                    });
                                  },
                                  icon: Icon(
                                    _showPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '生成密码',
                                  onPressed: () {
                                    _passwordController.text =
                                        widget
                                            .initialGeneratedPassword
                                            .isNotEmpty
                                        ? widget.initialGeneratedPassword
                                        : widget.onGeneratePassword();
                                  },
                                  icon: const Icon(
                                    Icons.auto_fix_high_outlined,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _urlController,
                          decoration: const InputDecoration(labelText: '地址'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _noteController,
                          minLines: 3,
                          maxLines: 5,
                          decoration: const InputDecoration(labelText: '备注'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _totpSecretController,
                          obscureText: !_showTotpSecret,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: '验证器密钥',
                            suffixIcon: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: _showTotpSecret
                                      ? '隐藏验证器密钥'
                                      : '查看验证器密钥',
                                  onPressed: () {
                                    setState(() {
                                      _showTotpSecret = !_showTotpSecret;
                                    });
                                  },
                                  icon: Icon(
                                    _showTotpSecret
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '识别二维码',
                                  onPressed: () => unawaited(_scanTotpQr()),
                                  icon: const Icon(
                                    Icons.qr_code_scanner_outlined,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _folderId,
                          items: _folderItems(),
                          onChanged: (value) {
                            setState(() {
                              _folderId = value ?? '';
                            });
                          },
                          decoration: const InputDecoration(labelText: '保存到分类'),
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
                  onPressed: () {
                    final draft = _buildDraft();
                    if (draft == null) {
                      return;
                    }
                    Navigator.of(context).pop(draft);
                  },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordDetailPage extends StatefulWidget {
  const _PasswordDetailPage({required this.item, required this.folderName});

  final DecryptedLoginItem item;
  final String folderName;

  @override
  State<_PasswordDetailPage> createState() => _PasswordDetailPageState();
}

class _PasswordDetailPageState extends State<_PasswordDetailPage> {
  bool _showPassword = false;
  Timer? _totpTimer;

  @override
  void initState() {
    super.initState();
    if (widget.item.hasTotp) {
      _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyPassword() async {
    await Clipboard.setData(ClipboardData(text: widget.item.password));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('密码已复制')));
  }

  Future<void> _copyTotpCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('验证码已复制')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.title.isEmpty ? '(未命名)' : widget.item.title),
      ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DetailRow(label: '分类', value: widget.folderName),
                        const SizedBox(height: 12),
                        _DetailRow(label: '用户名', value: widget.item.username),
                        const SizedBox(height: 12),
                        Text(
                          '密码',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.sx.mutedText),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: context.sx.subtle,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: context.sx.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  _showPassword
                                      ? (widget.item.password.isEmpty
                                            ? '-'
                                            : widget.item.password)
                                      : (widget.item.password.isEmpty
                                            ? '-'
                                            : '••••••••••••'),
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                tooltip: '复制密码',
                                onPressed: widget.item.password.isEmpty
                                    ? null
                                    : _copyPassword,
                                icon: const Icon(Icons.copy_outlined),
                              ),
                              IconButton(
                                tooltip: _showPassword ? '隐藏密码' : '查看密码',
                                onPressed: widget.item.password.isEmpty
                                    ? null
                                    : () {
                                        setState(() {
                                          _showPassword = !_showPassword;
                                        });
                                      },
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DetailRow(label: '地址', value: widget.item.url),
                        const SizedBox(height: 12),
                        if (widget.item.hasTotp) ...[
                          _TotpDetailCard(
                            config: widget.item.totp,
                            onCopy: _copyTotpCode,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _DetailRow(label: '备注', value: widget.item.note),
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
                  onPressed: () =>
                      Navigator.of(context).pop(_PasswordDetailAction.delete),
                  child: const Text('删除'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_PasswordDetailAction.edit),
                  child: const Text('编辑'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotpQrScannerPage extends StatefulWidget {
  const _TotpQrScannerPage();

  @override
  State<_TotpQrScannerPage> createState() => _TotpQrScannerPageState();
}

class _TotpQrScannerPageState extends State<_TotpQrScannerPage> {
  late final MobileScannerController _scannerController;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    unawaited(_scannerController.dispose());
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    if (value.isEmpty) {
      return;
    }
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描二维码')),
      body: SafeArea(
        child: Stack(
          children: [
            MobileScanner(
              controller: _scannerController,
              onDetect: _handleDetect,
              errorBuilder: (context, error) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '摄像头无法使用',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                );
              },
            ),
            Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: context.sx.primary, width: 3),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: '切换闪光灯',
                    onPressed: () =>
                        unawaited(_scannerController.toggleTorch()),
                    icon: const Icon(Icons.flashlight_on_outlined),
                  ),
                  const SizedBox(width: 16),
                  IconButton.filledTonal(
                    tooltip: '切换摄像头',
                    onPressed: () =>
                        unawaited(_scannerController.switchCamera()),
                    icon: const Icon(Icons.cameraswitch_outlined),
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

class _TotpDetailCard extends StatelessWidget {
  const _TotpDetailCard({required this.config, required this.onCopy});

  final TotpConfig config;
  final Future<void> Function(String code) onCopy;

  @override
  Widget build(BuildContext context) {
    final value = _generateTotp(config);
    final progress = value.period <= 0
        ? 0.0
        : value.remainingSeconds / value.period;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '验证码 (TOTP)',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.sx.mutedText),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.sx.subtle,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.sx.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  _formatTotpCode(value.code),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 4,
                      color: value.remainingSeconds <= 5
                          ? context.sx.danger
                          : context.sx.primary,
                      backgroundColor: context.sx.border,
                    ),
                    Text(
                      value.remainingSeconds.toString(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '复制验证码',
                onPressed: value.code.isEmpty
                    ? null
                    : () => unawaited(onCopy(value.code)),
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.sx.mutedText),
        ),
        const SizedBox(height: 6),
        SelectableText(
          value.isEmpty ? '-' : value,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
