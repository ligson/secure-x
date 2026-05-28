part of '../../main.dart';

PageRoute<T> _slidePageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}

class _SecureXAvatarPreset {
  const _SecureXAvatarPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.colors,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<Color> colors;
}

const _secureXAvatarPresets = <_SecureXAvatarPreset>[
  _SecureXAvatarPreset(
    id: 'sunrise',
    label: '晨光',
    icon: Icons.wb_sunny_outlined,
    colors: [Color(0xFFF97316), Color(0xFFFACC15)],
  ),
  _SecureXAvatarPreset(
    id: 'forest',
    label: '森林',
    icon: Icons.park_outlined,
    colors: [Color(0xFF15803D), Color(0xFF4ADE80)],
  ),
  _SecureXAvatarPreset(
    id: 'ocean',
    label: '海湾',
    icon: Icons.waves_outlined,
    colors: [Color(0xFF0369A1), Color(0xFF38BDF8)],
  ),
  _SecureXAvatarPreset(
    id: 'ember',
    label: '余烬',
    icon: Icons.local_fire_department_outlined,
    colors: [Color(0xFFB91C1C), Color(0xFFFB7185)],
  ),
  _SecureXAvatarPreset(
    id: 'violet',
    label: '紫晶',
    icon: Icons.auto_awesome_outlined,
    colors: [Color(0xFF7C3AED), Color(0xFFC084FC)],
  ),
  _SecureXAvatarPreset(
    id: 'sky',
    label: '晴空',
    icon: Icons.cloud_queue_outlined,
    colors: [Color(0xFF2563EB), Color(0xFF93C5FD)],
  ),
  _SecureXAvatarPreset(
    id: 'stone',
    label: '岩层',
    icon: Icons.terrain_outlined,
    colors: [Color(0xFF475569), Color(0xFF94A3B8)],
  ),
  _SecureXAvatarPreset(
    id: 'mint',
    label: '薄荷',
    icon: Icons.spa_outlined,
    colors: [Color(0xFF0F766E), Color(0xFF5EEAD4)],
  ),
  _SecureXAvatarPreset(
    id: 'orbit',
    label: '星轨',
    icon: Icons.public_outlined,
    colors: [Color(0xFF1D4ED8), Color(0xFF818CF8)],
  ),
  _SecureXAvatarPreset(
    id: 'shield',
    label: '盾牌',
    icon: Icons.shield_outlined,
    colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
  ),
];

String _normalizeAvatarPreset(String? value, {bool group = false}) {
  return normalizeSecureXAvatarPreset(value, group: group);
}

_SecureXAvatarPreset _avatarPresetById(String? value, {bool group = false}) {
  final normalized = _normalizeAvatarPreset(value, group: group);
  for (final preset in _secureXAvatarPresets) {
    if (preset.id == normalized) {
      return preset;
    }
  }
  return _secureXAvatarPresets.first;
}

class _PresetAvatar extends StatelessWidget {
  const _PresetAvatar({
    required this.presetId,
    required this.size,
    this.group = false,
    this.borderColor,
    this.imageUrl = '',
  });

  final String presetId;
  final double size;
  final bool group;
  final Color? borderColor;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final preset = _avatarPresetById(presetId, group: group);
    final cleanImageUrl = imageUrl.trim();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: preset.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.34),
        border: Border.all(color: borderColor ?? context.sx.border),
        boxShadow: [
          BoxShadow(
            color: preset.colors.last.withAlpha(38),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: cleanImageUrl.isEmpty
          ? Icon(preset.icon, color: Colors.white, size: size * 0.5)
          : Image.network(
              cleanImageUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, _, _) =>
                  Icon(preset.icon, color: Colors.white, size: size * 0.5),
            ),
    );
  }
}

class _AvatarPresetPicker extends StatelessWidget {
  const _AvatarPresetPicker({
    required this.selectedPresetId,
    required this.onSelected,
    this.group = false,
  });

  final String selectedPresetId;
  final ValueChanged<String> onSelected;
  final bool group;

  @override
  Widget build(BuildContext context) {
    final selected = _normalizeAvatarPreset(selectedPresetId, group: group);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final preset in _secureXAvatarPresets)
          InkWell(
            onTap: () => onSelected(preset.id),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 92,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: selected == preset.id
                    ? context.sx.accentSoft
                    : context.sx.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected == preset.id
                      ? context.sx.primary
                      : context.sx.border,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PresetAvatar(
                    presetId: preset.id,
                    size: 46,
                    group: group,
                    borderColor: selected == preset.id
                        ? context.sx.primary
                        : context.sx.border,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preset.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: selected == preset.id
                          ? context.sx.primary
                          : context.sx.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

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
                message ?? '正在处理中，请稍候...',
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
