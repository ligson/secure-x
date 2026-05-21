// ignore_for_file: invalid_use_of_protected_member

part of '../../../main.dart';

extension _VaultGeneratorTab on _VaultScreenState {
  Widget _buildGeneratorTab(BuildContext context) {
    final canGenerate =
        _generatorUseUppercase ||
        _generatorUseLowercase ||
        _generatorUseDigits ||
        _generatorUseSymbols;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildModuleHeader(
            icon: Icons.password_outlined,
            title: '生成器',
            tag: '本地生成',
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '格式预设',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton(
                        onPressed: () => _applyGeneratorPreset('strong'),
                        child: const Text('高强度'),
                      ),
                      OutlinedButton(
                        onPressed: () => _applyGeneratorPreset('memorable'),
                        child: const Text('易读口令'),
                      ),
                      OutlinedButton(
                        onPressed: () => _applyGeneratorPreset('pin'),
                        child: const Text('数字 PIN'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '长度：$_generatorLength',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        canGenerate ? '已启用字符集' : '至少选择一种字符集',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: canGenerate
                              ? context.sx.success
                              : context.sx.danger,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _generatorLength.toDouble(),
                    min: 4,
                    max: 40,
                    divisions: 36,
                    label: '$_generatorLength',
                    onChanged: (value) {
                      setState(() {
                        _generatorLength = value.round();
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
                          style: _chipLabelStyle(_generatorUseUppercase),
                        ),
                        selected: _generatorUseUppercase,
                        checkmarkColor: context.sx.primary,
                        onSelected: (value) {
                          setState(() {
                            _generatorUseUppercase = value;
                          });
                          _regeneratePassword();
                        },
                      ),
                      FilterChip(
                        label: Text(
                          '小写字母',
                          style: _chipLabelStyle(_generatorUseLowercase),
                        ),
                        selected: _generatorUseLowercase,
                        checkmarkColor: context.sx.primary,
                        onSelected: (value) {
                          setState(() {
                            _generatorUseLowercase = value;
                          });
                          _regeneratePassword();
                        },
                      ),
                      FilterChip(
                        label: Text(
                          '数字',
                          style: _chipLabelStyle(_generatorUseDigits),
                        ),
                        selected: _generatorUseDigits,
                        checkmarkColor: context.sx.primary,
                        onSelected: (value) {
                          setState(() {
                            _generatorUseDigits = value;
                          });
                          _regeneratePassword();
                        },
                      ),
                      FilterChip(
                        label: Text(
                          '符号',
                          style: _chipLabelStyle(_generatorUseSymbols),
                        ),
                        selected: _generatorUseSymbols,
                        checkmarkColor: context.sx.primary,
                        onSelected: (value) {
                          setState(() {
                            _generatorUseSymbols = value;
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
                      _generatedPassword.isEmpty
                          ? '当前组合无法生成密码'
                          : _generatedPassword,
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
                        onPressed: canGenerate ? _regeneratePassword : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新生成'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _generatedPassword.isEmpty
                            ? null
                            : () => _copyGeneratedPassword(context),
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
    );
  }
}
