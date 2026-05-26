part of '../../../main.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _unlockPasswordController = TextEditingController();

  @override
  void dispose() {
    _unlockPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final user = widget.controller.user;
        return Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: context.sx.subtle,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.lock_person_outlined),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '欢迎回来，${user?.username ?? ''}',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '输入解锁密码后，secure-x 会在本机恢复保险库、好友与聊天归档。',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: context.sx.mutedText),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.controller.baseUrl,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.sx.mutedText),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _unlockPasswordController,
                          decoration: const InputDecoration(labelText: '解锁密码'),
                          obscureText: true,
                          enabled: !widget.controller.busy,
                          onSubmitted: widget.controller.busy
                              ? null
                              : (_) async {
                                  try {
                                    await widget.controller.unlock(
                                      _unlockPasswordController.text,
                                    );
                                  } catch (_) {}
                                },
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: widget.controller.busy
                                    ? null
                                    : () async {
                                        try {
                                          await widget.controller.unlock(
                                            _unlockPasswordController.text,
                                          );
                                        } catch (_) {}
                                      },
                                child: Text(
                                  widget.controller.busy ? '正在解锁...' : '解锁',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: widget.controller.busy
                                    ? null
                                    : widget.controller.logout,
                                child: const Text('退出登录'),
                              ),
                            ),
                          ],
                        ),
                        _StatusLine(
                          message: widget.controller.statusMessage,
                          busy: widget.controller.busy,
                        ),
                      ],
                    ),
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
