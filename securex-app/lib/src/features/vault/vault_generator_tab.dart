// ignore_for_file: invalid_use_of_protected_member

part of '../../../main.dart';

class _GeneratorPageResult {
  const _GeneratorPageResult({
    required this.length,
    required this.useUppercase,
    required this.useLowercase,
    required this.useDigits,
    required this.useSymbols,
    required this.password,
  });

  final int length;
  final bool useUppercase;
  final bool useLowercase;
  final bool useDigits;
  final bool useSymbols;
  final String password;
}

extension _VaultGeneratorTab on _VaultScreenState {
  Future<void> _showGeneratorPage() async {
    final result = await Navigator.of(context).push<_GeneratorPageResult>(
      MaterialPageRoute(
        builder: (context) => _GeneratorPage(
          controller: widget.controller,
          initialLength: _generatorLength,
          initialUseUppercase: _generatorUseUppercase,
          initialUseLowercase: _generatorUseLowercase,
          initialUseDigits: _generatorUseDigits,
          initialUseSymbols: _generatorUseSymbols,
          initialPassword: _generatedPassword,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _generatorLength = result.length;
      _generatorUseUppercase = result.useUppercase;
      _generatorUseLowercase = result.useLowercase;
      _generatorUseDigits = result.useDigits;
      _generatorUseSymbols = result.useSymbols;
      _generatedPassword = result.password;
    });
  }
}

class _GeneratorPage extends StatefulWidget {
  const _GeneratorPage({
    required this.controller,
    required this.initialLength,
    required this.initialUseUppercase,
    required this.initialUseLowercase,
    required this.initialUseDigits,
    required this.initialUseSymbols,
    required this.initialPassword,
  });

  final AppController controller;
  final int initialLength;
  final bool initialUseUppercase;
  final bool initialUseLowercase;
  final bool initialUseDigits;
  final bool initialUseSymbols;
  final String initialPassword;

  @override
  State<_GeneratorPage> createState() => _GeneratorPageState();
}

class _GeneratorPageState extends State<_GeneratorPage> {
  late int _length;
  late bool _useUppercase;
  late bool _useLowercase;
  late bool _useDigits;
  late bool _useSymbols;
  late String _password;

  bool get _canGenerate =>
      _useUppercase || _useLowercase || _useDigits || _useSymbols;

  @override
  void initState() {
    super.initState();
    _length = widget.initialLength;
    _useUppercase = widget.initialUseUppercase;
    _useLowercase = widget.initialUseLowercase;
    _useDigits = widget.initialUseDigits;
    _useSymbols = widget.initialUseSymbols;
    _password = widget.initialPassword;
    if (_password.isEmpty && _canGenerate) {
      _regeneratePassword();
    }
  }

  void _applyPreset(String preset) {
    setState(() {
      switch (preset) {
        case 'pin':
          _length = 6;
          _useUppercase = false;
          _useLowercase = false;
          _useDigits = true;
          _useSymbols = false;
          break;
        case 'memorable':
          _length = 16;
          _useUppercase = false;
          _useLowercase = true;
          _useDigits = true;
          _useSymbols = false;
          break;
        default:
          _length = 20;
          _useUppercase = true;
          _useLowercase = true;
          _useDigits = true;
          _useSymbols = true;
      }
      _password = _canGenerate
          ? widget.controller.generatePassword(
              length: _length,
              useUppercase: _useUppercase,
              useLowercase: _useLowercase,
              useDigits: _useDigits,
              useSymbols: _useSymbols,
            )
          : '';
    });
  }

  void _regeneratePassword() {
    setState(() {
      _password = _canGenerate
          ? widget.controller.generatePassword(
              length: _length,
              useUppercase: _useUppercase,
              useLowercase: _useLowercase,
              useDigits: _useDigits,
              useSymbols: _useSymbols,
            )
          : '';
    });
  }

  Future<void> _copyPassword() async {
    await Clipboard.setData(ClipboardData(text: _password));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('密码已复制')));
  }

  void _closePage() {
    Navigator.of(context).pop(
      _GeneratorPageResult(
        length: _length,
        useUppercase: _useUppercase,
        useLowercase: _useLowercase,
        useDigits: _useDigits,
        useSymbols: _useSymbols,
        password: _password,
      ),
    );
  }

  TextStyle? _chipLabelStyle(bool selected) {
    final palette = context.sx;
    return Theme.of(context).textTheme.labelLarge?.copyWith(
      color: selected ? palette.primary : palette.text,
      fontWeight: FontWeight.w700,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closePage();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _closePage,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('密码生成器'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _GeneratorHeader(canGenerate: _canGenerate),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '格式预设',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            OutlinedButton(
                              onPressed: () => _applyPreset('strong'),
                              child: const Text('高强度'),
                            ),
                            OutlinedButton(
                              onPressed: () => _applyPreset('memorable'),
                              child: const Text('易读口令'),
                            ),
                            OutlinedButton(
                              onPressed: () => _applyPreset('pin'),
                              child: const Text('数字 PIN'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '长度：$_length',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              _canGenerate ? '已启用字符集' : '至少选择一种字符集',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _canGenerate
                                        ? context.sx.success
                                        : context.sx.danger,
                                  ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _length.toDouble(),
                          min: 4,
                          max: 40,
                          divisions: 36,
                          label: '$_length',
                          onChanged: (value) {
                            setState(() {
                              _length = value.round();
                            });
                          },
                          onChangeEnd: (_) => _regeneratePassword(),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilterChip(
                              label: Text(
                                '大写字母',
                                style: _chipLabelStyle(_useUppercase),
                              ),
                              selected: _useUppercase,
                              checkmarkColor: context.sx.primary,
                              onSelected: (value) {
                                setState(() {
                                  _useUppercase = value;
                                });
                                _regeneratePassword();
                              },
                            ),
                            FilterChip(
                              label: Text(
                                '小写字母',
                                style: _chipLabelStyle(_useLowercase),
                              ),
                              selected: _useLowercase,
                              checkmarkColor: context.sx.primary,
                              onSelected: (value) {
                                setState(() {
                                  _useLowercase = value;
                                });
                                _regeneratePassword();
                              },
                            ),
                            FilterChip(
                              label: Text(
                                '数字',
                                style: _chipLabelStyle(_useDigits),
                              ),
                              selected: _useDigits,
                              checkmarkColor: context.sx.primary,
                              onSelected: (value) {
                                setState(() {
                                  _useDigits = value;
                                });
                                _regeneratePassword();
                              },
                            ),
                            FilterChip(
                              label: Text(
                                '符号',
                                style: _chipLabelStyle(_useSymbols),
                              ),
                              selected: _useSymbols,
                              checkmarkColor: context.sx.primary,
                              onSelected: (value) {
                                setState(() {
                                  _useSymbols = value;
                                });
                                _regeneratePassword();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: context.sx.subtle,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: context.sx.border),
                          ),
                          child: SelectableText(
                            _password.isEmpty ? '当前组合无法生成密码' : _password,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: _canGenerate
                                  ? _regeneratePassword
                                  : null,
                              icon: const Icon(Icons.refresh),
                              label: const Text('重新生成'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _password.isEmpty
                                  ? null
                                  : _copyPassword,
                              icon: const Icon(Icons.copy_outlined),
                              label: const Text('复制'),
                            ),
                          ],
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

class _GeneratorHeader extends StatelessWidget {
  const _GeneratorHeader({required this.canGenerate});

  final bool canGenerate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: context.sx.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.sx.border),
          ),
          child: const Icon(Icons.password_outlined, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '生成器',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.sx.accentSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            canGenerate ? '本地生成' : '待选择',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.sx.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
