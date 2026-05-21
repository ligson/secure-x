part of '../../main.dart';

class _AuthBackdrop extends StatelessWidget {
  const _AuthBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: context.sx.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -120,
            top: -100,
            child: _GlowOrb(size: 260, color: context.sx.glow[0]),
          ),
          Positioned(
            right: -80,
            top: 90,
            child: _GlowOrb(size: 220, color: context.sx.glow[1]),
          ),
          Positioned(
            left: 280,
            bottom: -140,
            child: _GlowOrb(size: 280, color: context.sx.glow[2]),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 120, spreadRadius: 24),
          ],
        ),
      ),
    );
  }
}

class _EndpointBanner extends StatelessWidget {
  const _EndpointBanner({
    required this.controller,
    required this.busy,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool busy;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.sx.subtle,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.sx.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '服务端',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton(
                onPressed: busy ? null : onSave,
                child: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'http://127.0.0.1:8080',
              prefixIcon: Icon(Icons.lan_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListCardHeader extends StatelessWidget {
  const _ListCardHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.sx.border)),
      ),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _UploadProgressTile extends StatelessWidget {
  const _UploadProgressTile({required this.task, required this.onDismiss});

  final FileUploadTask task;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final percent = (task.progress * 100).round();
    final color = task.failed
        ? context.sx.danger
        : task.done
        ? context.sx.success
        : context.sx.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                task.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              task.done ? '完成' : '$percent%',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (onDismiss != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: task.done ? '关闭上传记录' : '关闭失败记录',
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: task.done ? 1 : task.progress,
          color: color,
          backgroundColor: context.sx.subtle,
          minHeight: 7,
          borderRadius: BorderRadius.circular(999),
        ),
        const SizedBox(height: 6),
        Text(
          task.status,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.sx.mutedText),
        ),
      ],
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.sx.subtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.sx.border),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.sx.danger),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.message, required this.busy});

  final String? message;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (!busy && (message == null || message!.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.sx.subtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.sx.border),
        ),
        child: Row(
          children: [
            if (busy) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                message ?? '处理中...',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: context.sx.mutedText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
