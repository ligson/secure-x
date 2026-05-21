part of '../../main.dart';

class SecureXPalette extends ThemeExtension<SecureXPalette> {
  const SecureXPalette({
    required this.scaffold,
    required this.card,
    required this.surface,
    required this.subtle,
    required this.border,
    required this.text,
    required this.mutedText,
    required this.primary,
    required this.onPrimary,
    required this.accentSoft,
    required this.button,
    required this.onButton,
    required this.success,
    required this.danger,
    required this.gradient,
    required this.glow,
  });

  final Color scaffold;
  final Color card;
  final Color surface;
  final Color subtle;
  final Color border;
  final Color text;
  final Color mutedText;
  final Color primary;
  final Color onPrimary;
  final Color accentSoft;
  final Color button;
  final Color onButton;
  final Color success;
  final Color danger;
  final List<Color> gradient;
  final List<Color> glow;

  @override
  SecureXPalette copyWith({
    Color? scaffold,
    Color? card,
    Color? surface,
    Color? subtle,
    Color? border,
    Color? text,
    Color? mutedText,
    Color? primary,
    Color? onPrimary,
    Color? accentSoft,
    Color? button,
    Color? onButton,
    Color? success,
    Color? danger,
    List<Color>? gradient,
    List<Color>? glow,
  }) {
    return SecureXPalette(
      scaffold: scaffold ?? this.scaffold,
      card: card ?? this.card,
      surface: surface ?? this.surface,
      subtle: subtle ?? this.subtle,
      border: border ?? this.border,
      text: text ?? this.text,
      mutedText: mutedText ?? this.mutedText,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      accentSoft: accentSoft ?? this.accentSoft,
      button: button ?? this.button,
      onButton: onButton ?? this.onButton,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      gradient: gradient ?? this.gradient,
      glow: glow ?? this.glow,
    );
  }

  @override
  SecureXPalette lerp(ThemeExtension<SecureXPalette>? other, double t) {
    if (other is! SecureXPalette) {
      return this;
    }
    return SecureXPalette(
      scaffold: Color.lerp(scaffold, other.scaffold, t)!,
      card: Color.lerp(card, other.card, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      button: Color.lerp(button, other.button, t)!,
      onButton: Color.lerp(onButton, other.onButton, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      gradient: List.generate(
        gradient.length,
        (index) => Color.lerp(gradient[index], other.gradient[index], t)!,
      ),
      glow: List.generate(
        glow.length,
        (index) => Color.lerp(glow[index], other.glow[index], t)!,
      ),
    );
  }
}

class SecureXThemeSpec {
  const SecureXThemeSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.brightness,
    required this.palette,
  });

  final String id;
  final String name;
  final String description;
  final Brightness brightness;
  final SecureXPalette palette;

  bool get isDark => brightness == Brightness.dark;

  ThemeData toThemeData() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: palette.primary,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.scaffold,
      useMaterial3: true,
      extensions: [palette],
      appBarTheme: AppBarTheme(
        backgroundColor: palette.scaffold,
        foregroundColor: palette.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        hintStyle: TextStyle(color: palette.mutedText),
        labelStyle: TextStyle(color: palette.mutedText),
        prefixIconColor: palette.mutedText,
        suffixIconColor: palette.mutedText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.primary, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.button,
          foregroundColor: palette.onButton,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          side: BorderSide(color: palette.border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surface,
        selectedColor: palette.accentSoft,
        checkmarkColor: palette.primary,
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        labelStyle: TextStyle(color: palette.text, fontWeight: FontWeight.w700),
        secondaryLabelStyle: TextStyle(
          color: palette.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: palette.card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: palette.border),
        ),
      ),
      textTheme: ThemeData(
        brightness: brightness,
      ).textTheme.apply(bodyColor: palette.text, displayColor: palette.text),
      dividerColor: palette.border,
      popupMenuTheme: PopupMenuThemeData(
        color: palette.card,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: palette.text),
      ),
    );
  }

  static const all = [
    SecureXThemeSpec(
      id: 'dawn',
      name: '晨雾白',
      description: '干净、柔和，适合日间办公',
      brightness: Brightness.light,
      palette: SecureXPalette(
        scaffold: Color(0xFFF3F5F7),
        card: Color(0xFFFFFFFF),
        surface: Color(0xFFFFFFFF),
        subtle: Color(0xFFF7F8FA),
        border: Color(0xFFD8DEE6),
        text: Color(0xFF111827),
        mutedText: Color(0xFF667085),
        primary: Color(0xFF0F766E),
        onPrimary: Color(0xFFFFFFFF),
        accentSoft: Color(0xFFE7F5F2),
        button: Color(0xFF111827),
        onButton: Color(0xFFFFFFFF),
        success: Color(0xFF0F766E),
        danger: Color(0xFFC2543C),
        gradient: [Color(0xFFF6F7F9), Color(0xFFF3F5F7), Color(0xFFEEF2F6)],
        glow: [Color(0x110F766E), Color(0x11111827), Color(0x100F766E)],
      ),
    ),
    SecureXThemeSpec(
      id: 'linen',
      name: '亚麻暖白',
      description: '温暖低对比，长时间阅读更舒服',
      brightness: Brightness.light,
      palette: SecureXPalette(
        scaffold: Color(0xFFF8F4EC),
        card: Color(0xFFFFFCF7),
        surface: Color(0xFFFFFEFB),
        subtle: Color(0xFFF4EEE4),
        border: Color(0xFFE2D6C6),
        text: Color(0xFF211A14),
        mutedText: Color(0xFF75685A),
        primary: Color(0xFF9A5B1F),
        onPrimary: Color(0xFFFFFFFF),
        accentSoft: Color(0xFFF3E2C9),
        button: Color(0xFF2A1F18),
        onButton: Color(0xFFFFFFFF),
        success: Color(0xFF7A5A16),
        danger: Color(0xFFB14D38),
        gradient: [Color(0xFFFCF8F1), Color(0xFFF8F4EC), Color(0xFFF1E8D9)],
        glow: [Color(0x169A5B1F), Color(0x1430241B), Color(0x14C28A3D)],
      ),
    ),
    SecureXThemeSpec(
      id: 'forestNight',
      name: '松林夜',
      description: '深绿夜间主题，沉稳不刺眼',
      brightness: Brightness.dark,
      palette: SecureXPalette(
        scaffold: Color(0xFF091311),
        card: Color(0xFF101D1A),
        surface: Color(0xFF14231F),
        subtle: Color(0xFF182B26),
        border: Color(0xFF29443D),
        text: Color(0xFFEAF5F0),
        mutedText: Color(0xFFA5B8B1),
        primary: Color(0xFF5EEAD4),
        onPrimary: Color(0xFF06201C),
        accentSoft: Color(0xFF173B35),
        button: Color(0xFF5EEAD4),
        onButton: Color(0xFF06201C),
        success: Color(0xFF5EEAD4),
        danger: Color(0xFFFCA5A5),
        gradient: [Color(0xFF07100E), Color(0xFF091311), Color(0xFF10231F)],
        glow: [Color(0x225EEAD4), Color(0x1FEAF5F0), Color(0x185EEAD4)],
      ),
    ),
    SecureXThemeSpec(
      id: 'midnight',
      name: '星港夜',
      description: '蓝黑高质感，适合暗光环境',
      brightness: Brightness.dark,
      palette: SecureXPalette(
        scaffold: Color(0xFF080D18),
        card: Color(0xFF101827),
        surface: Color(0xFF131E2E),
        subtle: Color(0xFF192538),
        border: Color(0xFF2B3A52),
        text: Color(0xFFEAF0FF),
        mutedText: Color(0xFF9EABC2),
        primary: Color(0xFF93C5FD),
        onPrimary: Color(0xFF071426),
        accentSoft: Color(0xFF1D3554),
        button: Color(0xFF93C5FD),
        onButton: Color(0xFF071426),
        success: Color(0xFF86EFAC),
        danger: Color(0xFFFDA4AF),
        gradient: [Color(0xFF070B14), Color(0xFF080D18), Color(0xFF111B2B)],
        glow: [Color(0x2493C5FD), Color(0x1EEAF0FF), Color(0x167C3AED)],
      ),
    ),
  ];

  static SecureXThemeSpec byId(String id) {
    return all.firstWhere((theme) => theme.id == id, orElse: () => all.first);
  }
}

extension SecureXThemeContext on BuildContext {
  SecureXPalette get sx => Theme.of(this).extension<SecureXPalette>()!;
}
