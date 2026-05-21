part of '../../../main.dart';

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final SecureXThemeSpec theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = theme.palette;
    return Material(
      color: selected ? palette.accentSoft : context.sx.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? palette.primary : context.sx.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: palette.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: palette.border),
                ),
                child: Center(
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: palette.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      theme.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: selected ? palette.primary : context.sx.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      theme.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: selected
                            ? palette.primary
                            : context.sx.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? palette.primary : context.sx.mutedText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
