import 'package:flutter/material.dart';

/// ZVBible-aligned color palette tokens (from `theme-palettes.css` / `globals.css`).
///
/// Maps ZVBible CSS variables (`--pw-*`) onto Material 3 [ColorScheme] + [ThemeData]
/// so ZVComm and ZVBible share the same visual language.
final class ZvPalette {
  final String id;
  final String label;
  final String description;
  final Brightness brightness;

  final Color bgApp;
  final Color bgElevated;
  final Color bgSurface;
  final Color bgPanel;
  final Color bgInput;

  final Color text;
  final Color textSoft;
  final Color textMuted;
  final Color textSubtle;

  final Color border;
  final Color borderStrong;

  final Color accent;
  final Color accentHover;
  final Color accentGold;
  final Color accentGoldHover;
  final Color onGold;
  final Color bridge; // vav / secondary accent
  final Color link;

  final Color success;
  final Color warning;
  final Color danger; // jesus / error tone

  /// Swatch gradient for the picker (gold → bridge → accent).
  final Color swatchGold;
  final Color swatchBridge;
  final Color swatchAccent;

  const ZvPalette({
    required this.id,
    required this.label,
    required this.description,
    required this.brightness,
    required this.bgApp,
    required this.bgElevated,
    required this.bgSurface,
    required this.bgPanel,
    required this.bgInput,
    required this.text,
    required this.textSoft,
    required this.textMuted,
    required this.textSubtle,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.accentHover,
    required this.accentGold,
    required this.accentGoldHover,
    required this.onGold,
    required this.bridge,
    required this.link,
    required this.success,
    required this.warning,
    required this.danger,
    required this.swatchGold,
    required this.swatchBridge,
    required this.swatchAccent,
  });

  bool get isDark => brightness == Brightness.dark;

  ColorScheme toColorScheme() {
    return ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: _on(accent),
      primaryContainer: Color.lerp(accent, bgPanel, 0.72)!,
      onPrimaryContainer: text,
      secondary: accentGold,
      onSecondary: onGold,
      secondaryContainer: Color.lerp(accentGold, bgPanel, 0.7)!,
      onSecondaryContainer: text,
      tertiary: bridge,
      onTertiary: onGold,
      tertiaryContainer: Color.lerp(bridge, bgPanel, 0.7)!,
      onTertiaryContainer: text,
      error: danger,
      onError: isDark ? const Color(0xFF1A0505) : Colors.white,
      errorContainer: Color.lerp(danger, bgPanel, 0.75)!,
      onErrorContainer: text,
      surface: bgSurface,
      onSurface: text,
      onSurfaceVariant: textMuted,
      surfaceContainerHighest: bgPanel,
      surfaceContainerHigh: bgElevated,
      surfaceContainer: bgSurface,
      surfaceContainerLow: bgElevated,
      surfaceContainerLowest: bgApp,
      surfaceDim: bgApp,
      surfaceBright: bgElevated,
      outline: border,
      outlineVariant: borderStrong,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: text,
      onInverseSurface: bgApp,
      inversePrimary: accentHover,
    );
  }

  ThemeData toThemeData() {
    final scheme = toColorScheme();
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bgApp,
      canvasColor: bgSurface,
      dividerColor: border,
      cardColor: bgElevated,
    );
    return base.copyWith(
      dialogTheme: DialogThemeData(backgroundColor: bgElevated),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: bgElevated,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgElevated,
        indicatorColor: Color.lerp(accent, bgPanel, 0.55),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? accent : textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? accent : textMuted);
        }),
      ),
      cardTheme: CardThemeData(
        color: bgElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: _on(accent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bgPanel,
        selectedColor: Color.lerp(accent, bgPanel, 0.55),
        side: BorderSide(color: border),
        labelStyle: TextStyle(color: textSoft),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textMuted,
        textColor: text,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return accent;
          return textSubtle;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return accent.withValues(alpha: 0.45);
          }
          return border;
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgPanel,
        contentTextStyle: TextStyle(color: text),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: text,
        displayColor: text,
      ),
    );
  }

  /// Readable ink for [bg] (simple luminance pick).
  static Color _on(Color bg) {
    final l = bg.computeLuminance();
    return l > 0.45 ? const Color(0xFF0B1118) : const Color(0xFFF8FAFC);
  }
}

/// ZVComm themes — same set and colors as ZVBible.
abstract final class ZvcommTheme {
  /// Default matches ZVBible default (`dark`).
  static const String defaultId = 'dark';

  static final List<ZvPalette> all = List.unmodifiable(_palettes);

  static ZvPalette byId(String id) {
    for (final p in _palettes) {
      if (p.id == id) return p;
    }
    return _palettes.first; // dark
  }

  static ThemeData of(String id) => byId(id).toThemeData();

  /// Light / dark fallbacks for MaterialApp.theme / darkTheme when using ThemeMode.
  static ThemeData light() => byId('light').toThemeData();
  static ThemeData dark() => byId('dark').toThemeData();

  static final List<ZvPalette> _palettes = [
    // —— dark (ZVBible default) ——
    const ZvPalette(
      id: 'dark',
      label: 'Dark',
      description: 'Default dark mode with blue and gold accents.',
      brightness: Brightness.dark,
      bgApp: Color(0xFF0B1118),
      bgElevated: Color(0xFF111A25),
      bgSurface: Color(0xFF16202D),
      bgPanel: Color(0xFF1A2533),
      bgInput: Color(0xFF0F1824),
      text: Color(0xFFE8EEF5),
      textSoft: Color(0xFFD4DCE6),
      textMuted: Color(0xFF9AA8BB),
      textSubtle: Color(0xFF7C8B9E),
      border: Color(0xFF243241),
      borderStrong: Color(0xFF314556),
      accent: Color(0xFF3B82F6),
      accentHover: Color(0xFF60A5FA),
      accentGold: Color(0xFFC5A46E),
      accentGoldHover: Color(0xFFD8B97F),
      onGold: Color(0xFF0B1118),
      bridge: Color(0xFF8FB8D9),
      link: Color(0xFF8AB4FF),
      success: Color(0xFF4ADE80),
      warning: Color(0xFFFACC15),
      danger: Color(0xFFFF6B6B),
      swatchGold: Color(0xFFC5A46E),
      swatchBridge: Color(0xFF8FB8D9),
      swatchAccent: Color(0xFF3B82F6),
    ),
    // —— light ——
    const ZvPalette(
      id: 'light',
      label: 'Light',
      description: 'Clean light backgrounds for bright environments.',
      brightness: Brightness.light,
      bgApp: Color(0xFFFFFFFF),
      bgElevated: Color(0xFFFFFFFF),
      bgSurface: Color(0xFFF4F6F8),
      bgPanel: Color(0xFFEEF1F5),
      bgInput: Color(0xFFFFFFFF),
      text: Color(0xFF111827),
      textSoft: Color(0xFF1F2937),
      textMuted: Color(0xFF4B5563),
      textSubtle: Color(0xFF6B7280),
      border: Color(0xFFD1D5DB),
      borderStrong: Color(0xFF9CA3AF),
      accent: Color(0xFF2563EB),
      accentHover: Color(0xFF3B82F6),
      accentGold: Color(0xFFA37D44),
      accentGoldHover: Color(0xFFB38D54),
      onGold: Color(0xFF1A2533),
      bridge: Color(0xFF4B7AB8),
      link: Color(0xFF2563EB),
      success: Color(0xFF16A34A),
      warning: Color(0xFFCA8A04),
      danger: Color(0xFFC41E1E),
      swatchGold: Color(0xFFA37D44),
      swatchBridge: Color(0xFF4B7AB8),
      swatchAccent: Color(0xFF2563EB),
    ),
    // —— sepia ——
    const ZvPalette(
      id: 'sepia',
      label: 'Sepia',
      description: 'Warm parchment tones — easy on the eyes for long sessions.',
      brightness: Brightness.light,
      bgApp: Color(0xFFF5F0E6),
      bgElevated: Color(0xFFFAF6EE),
      bgSurface: Color(0xFFEFE8DB),
      bgPanel: Color(0xFFE8DFD0),
      bgInput: Color(0xFFFAF6EE),
      text: Color(0xFF2E2618),
      textSoft: Color(0xFF3D3424),
      textMuted: Color(0xFF5C4F3A),
      textSubtle: Color(0xFF7A6B52),
      border: Color(0xFFD4C4A8),
      borderStrong: Color(0xFFB8A484),
      accent: Color(0xFFB45309),
      accentHover: Color(0xFFC2410C),
      accentGold: Color(0xFF9A7B4F),
      accentGoldHover: Color(0xFFB08D5C),
      onGold: Color(0xFF2E2618),
      bridge: Color(0xFF8B7355),
      link: Color(0xFF9A3412),
      success: Color(0xFF15803D),
      warning: Color(0xFFA16207),
      danger: Color(0xFFB91C1C),
      swatchGold: Color(0xFF9A7B4F),
      swatchBridge: Color(0xFF8B7355),
      swatchAccent: Color(0xFFB45309),
    ),
    // —— sky ——
    const ZvPalette(
      id: 'sky',
      label: 'Sky',
      description: 'Soft daylight blues with crisp contrast.',
      brightness: Brightness.light,
      bgApp: Color(0xFFF0F7FF),
      bgElevated: Color(0xFFF8FBFF),
      bgSurface: Color(0xFFE8F2FC),
      bgPanel: Color(0xFFDCEAF8),
      bgInput: Color(0xFFFFFFFF),
      text: Color(0xFF0F172A),
      textSoft: Color(0xFF1E293B),
      textMuted: Color(0xFF475569),
      textSubtle: Color(0xFF64748B),
      border: Color(0xFFBFDBFE),
      borderStrong: Color(0xFF93C5FD),
      accent: Color(0xFF0284C7),
      accentHover: Color(0xFF0369A1),
      accentGold: Color(0xFF5B8FD4),
      accentGoldHover: Color(0xFF4A7EC3),
      onGold: Color(0xFF0F172A),
      bridge: Color(0xFF7EB8E8),
      link: Color(0xFF0369A1),
      success: Color(0xFF059669),
      warning: Color(0xFFD97706),
      danger: Color(0xFFDC2626),
      swatchGold: Color(0xFF5B8FD4),
      swatchBridge: Color(0xFF7EB8E8),
      swatchAccent: Color(0xFF0284C7),
    ),
    // —— purple ——
    const ZvPalette(
      id: 'purple',
      label: 'Purple',
      description: 'Deep violet base with gold and purple accents.',
      brightness: Brightness.dark,
      bgApp: Color(0xFF0F0B18),
      bgElevated: Color(0xFF161024),
      bgSurface: Color(0xFF1E1630),
      bgPanel: Color(0xFF241C3A),
      bgInput: Color(0xFF120E1C),
      text: Color(0xFFECE8F5),
      textSoft: Color(0xFFDDD6EE),
      textMuted: Color(0xFFA89BC4),
      textSubtle: Color(0xFF8778A8),
      border: Color(0xFF3A2D52),
      borderStrong: Color(0xFF4C3A68),
      accent: Color(0xFF8B5CF6),
      accentHover: Color(0xFFA78BFA),
      accentGold: Color(0xFFE8C872),
      accentGoldHover: Color(0xFFF4D99A),
      onGold: Color(0xFF0F0B18),
      bridge: Color(0xFFA78BFA),
      link: Color(0xFFC4B5FD),
      success: Color(0xFFE8C872),
      warning: Color(0xFF8B5CF6),
      danger: Color(0xFFF0D060),
      swatchGold: Color(0xFFE8C872),
      swatchBridge: Color(0xFFA78BFA),
      swatchAccent: Color(0xFF8B5CF6),
    ),
    // —— midnight ——
    const ZvPalette(
      id: 'midnight',
      label: 'Midnight',
      description: 'Inky navy with cool silver-blue highlights.',
      brightness: Brightness.dark,
      bgApp: Color(0xFF060A12),
      bgElevated: Color(0xFF0C1220),
      bgSurface: Color(0xFF111A2C),
      bgPanel: Color(0xFF162238),
      bgInput: Color(0xFF080D16),
      text: Color(0xFFDCE4EF),
      textSoft: Color(0xFFC8D4E4),
      textMuted: Color(0xFF8FA0B8),
      textSubtle: Color(0xFF6B7F9A),
      border: Color(0xFF243044),
      borderStrong: Color(0xFF334560),
      accent: Color(0xFF5B9FD4),
      accentHover: Color(0xFF7EB3DE),
      accentGold: Color(0xFF8FA8C4),
      accentGoldHover: Color(0xFFA3BBD4),
      onGold: Color(0xFF060A12),
      bridge: Color(0xFF6B8CAF),
      link: Color(0xFF93C5FD),
      success: Color(0xFF4ADE80),
      warning: Color(0xFFFBBF24),
      danger: Color(0xFFF87171),
      swatchGold: Color(0xFF8FA8C4),
      swatchBridge: Color(0xFF6B8CAF),
      swatchAccent: Color(0xFF5B9FD4),
    ),
    // —— ocean ——
    const ZvPalette(
      id: 'ocean',
      label: 'Ocean',
      description: 'Dark teal depths with aqua bridge accents.',
      brightness: Brightness.dark,
      bgApp: Color(0xFF081418),
      bgElevated: Color(0xFF0C1E24),
      bgSurface: Color(0xFF102830),
      bgPanel: Color(0xFF14323C),
      bgInput: Color(0xFF060F12),
      text: Color(0xFFE0F2F1),
      textSoft: Color(0xFFCCE8E6),
      textMuted: Color(0xFF8EC8C4),
      textSubtle: Color(0xFF6AA8A4),
      border: Color(0xFF1E4A52),
      borderStrong: Color(0xFF2A626C),
      accent: Color(0xFF2DD4BF),
      accentHover: Color(0xFF5EEAD4),
      accentGold: Color(0xFF7EC8C8),
      accentGoldHover: Color(0xFF94D4D4),
      onGold: Color(0xFF081418),
      bridge: Color(0xFF5EEAD4),
      link: Color(0xFF99F6E4),
      success: Color(0xFF34D399),
      warning: Color(0xFFFBBF24),
      danger: Color(0xFFFB7185),
      swatchGold: Color(0xFF7EC8C8),
      swatchBridge: Color(0xFF5EEAD4),
      swatchAccent: Color(0xFF2DD4BF),
    ),
    // —— forest ——
    const ZvPalette(
      id: 'forest',
      label: 'Forest',
      description: 'Earthy dark greens with muted gold tones.',
      brightness: Brightness.dark,
      bgApp: Color(0xFF0A120C),
      bgElevated: Color(0xFF101A12),
      bgSurface: Color(0xFF162218),
      bgPanel: Color(0xFF1C2A1E),
      bgInput: Color(0xFF080E0A),
      text: Color(0xFFE6F0E8),
      textSoft: Color(0xFFD4E4D8),
      textMuted: Color(0xFF94B89C),
      textSubtle: Color(0xFF729878),
      border: Color(0xFF2A4030),
      borderStrong: Color(0xFF3A5440),
      accent: Color(0xFF4ADE80),
      accentHover: Color(0xFF6EE7A8),
      accentGold: Color(0xFFA3C9A8),
      accentGoldHover: Color(0xFFB8D8BC),
      onGold: Color(0xFF0A120C),
      bridge: Color(0xFF6EE7A8),
      link: Color(0xFF86EFAC),
      success: Color(0xFF4ADE80),
      warning: Color(0xFFFACC15),
      danger: Color(0xFFFCA5A5),
      swatchGold: Color(0xFFA3C9A8),
      swatchBridge: Color(0xFF6EE7A8),
      swatchAccent: Color(0xFF4ADE80),
    ),
    // —— amber ——
    const ZvPalette(
      id: 'amber',
      label: 'Amber',
      description: 'Warm charcoal with sunset gold and orange.',
      brightness: Brightness.dark,
      bgApp: Color(0xFF12100A),
      bgElevated: Color(0xFF1A1610),
      bgSurface: Color(0xFF221E16),
      bgPanel: Color(0xFF2A241C),
      bgInput: Color(0xFF0E0C08),
      text: Color(0xFFFAF5EB),
      textSoft: Color(0xFFEDE4D4),
      textMuted: Color(0xFFC4B49A),
      textSubtle: Color(0xFFA09078),
      border: Color(0xFF3D3428),
      borderStrong: Color(0xFF524438),
      accent: Color(0xFFF59E0B),
      accentHover: Color(0xFFFBBF24),
      accentGold: Color(0xFFD4A574),
      accentGoldHover: Color(0xFFE4B888),
      onGold: Color(0xFF12100A),
      bridge: Color(0xFFFBBF24),
      link: Color(0xFFFCD34D),
      success: Color(0xFF84CC16),
      warning: Color(0xFFF59E0B),
      danger: Color(0xFFF87171),
      swatchGold: Color(0xFFD4A574),
      swatchBridge: Color(0xFFFBBF24),
      swatchAccent: Color(0xFFF59E0B),
    ),
    // —— rose ——
    const ZvPalette(
      id: 'rose',
      label: 'Rose',
      description: 'Dark mauve with rose and soft gold accents.',
      brightness: Brightness.dark,
      bgApp: Color(0xFF140C10),
      bgElevated: Color(0xFF1C1218),
      bgSurface: Color(0xFF241820),
      bgPanel: Color(0xFF2C1E28),
      bgInput: Color(0xFF10080C),
      text: Color(0xFFFCE8F0),
      textSoft: Color(0xFFF0D4E0),
      textMuted: Color(0xFFC8A0B0),
      textSubtle: Color(0xFFA88090),
      border: Color(0xFF4A3040),
      borderStrong: Color(0xFF604050),
      accent: Color(0xFFF472B6),
      accentHover: Color(0xFFF9A8D4),
      accentGold: Color(0xFFE8B4B8),
      accentGoldHover: Color(0xFFF0C8CC),
      onGold: Color(0xFF140C10),
      bridge: Color(0xFFF9A8D4),
      link: Color(0xFFFBCFE8),
      success: Color(0xFFE8B4B8),
      warning: Color(0xFFF472B6),
      danger: Color(0xFFFCD34D),
      swatchGold: Color(0xFFE8B4B8),
      swatchBridge: Color(0xFFF9A8D4),
      swatchAccent: Color(0xFFF472B6),
    ),
    // —— slate ——
    const ZvPalette(
      id: 'slate',
      label: 'Slate',
      description: 'Cool neutral grays — minimal and calm.',
      brightness: Brightness.dark,
      bgApp: Color(0xFF0E1114),
      bgElevated: Color(0xFF151A1F),
      bgSurface: Color(0xFF1C2228),
      bgPanel: Color(0xFF232A32),
      bgInput: Color(0xFF0A0D10),
      text: Color(0xFFE2E8F0),
      textSoft: Color(0xFFCBD5E1),
      textMuted: Color(0xFF94A3B8),
      textSubtle: Color(0xFF64748B),
      border: Color(0xFF2D3744),
      borderStrong: Color(0xFF3D4A58),
      accent: Color(0xFF64748B),
      accentHover: Color(0xFF94A3B8),
      accentGold: Color(0xFFB8C4D0),
      accentGoldHover: Color(0xFFCBD5E1),
      onGold: Color(0xFF0E1114),
      bridge: Color(0xFF94A3B8),
      link: Color(0xFFCBD5E1),
      success: Color(0xFF94A3B8),
      warning: Color(0xFFCBD5E1),
      danger: Color(0xFFF87171),
      swatchGold: Color(0xFFB8C4D0),
      swatchBridge: Color(0xFF94A3B8),
      swatchAccent: Color(0xFF64748B),
    ),
    // —— crimson ——
    const ZvPalette(
      id: 'crimson',
      label: 'Crimson',
      description: 'Deep burgundy base with red and warm gold.',
      brightness: Brightness.dark,
      bgApp: Color(0xFF120808),
      bgElevated: Color(0xFF1A0C0C),
      bgSurface: Color(0xFF221010),
      bgPanel: Color(0xFF2A1414),
      bgInput: Color(0xFF0C0606),
      text: Color(0xFFFCE8E8),
      textSoft: Color(0xFFF0D4D4),
      textMuted: Color(0xFFC8A0A0),
      textSubtle: Color(0xFFA88080),
      border: Color(0xFF4A2828),
      borderStrong: Color(0xFF603838),
      accent: Color(0xFFEF4444),
      accentHover: Color(0xFFF87171),
      accentGold: Color(0xFFC9A0A0),
      accentGoldHover: Color(0xFFD8B4B4),
      onGold: Color(0xFF120808),
      bridge: Color(0xFFF87171),
      link: Color(0xFFFCA5A5),
      success: Color(0xFFC9A0A0),
      warning: Color(0xFFEF4444),
      danger: Color(0xFFFCD34D),
      swatchGold: Color(0xFFC9A0A0),
      swatchBridge: Color(0xFFF87171),
      swatchAccent: Color(0xFFEF4444),
    ),
    // —— contrast ——
    const ZvPalette(
      id: 'contrast',
      label: 'Contrast',
      description: 'High-contrast black and white for accessibility.',
      brightness: Brightness.dark,
      bgApp: Color(0xFF000000),
      bgElevated: Color(0xFF0A0A0A),
      bgSurface: Color(0xFF111111),
      bgPanel: Color(0xFF1A1A1A),
      bgInput: Color(0xFF000000),
      text: Color(0xFFFFFFFF),
      textSoft: Color(0xFFFFFFFF),
      textMuted: Color(0xFFE5E5E5),
      textSubtle: Color(0xFFCCCCCC),
      border: Color(0xFFFFFFFF),
      borderStrong: Color(0xFFFFFFFF),
      accent: Color(0xFFFFFF00),
      accentHover: Color(0xFFFFFF66),
      accentGold: Color(0xFFFFFF00),
      accentGoldHover: Color(0xFFFFFF66),
      onGold: Color(0xFF000000),
      bridge: Color(0xFFFFFFFF),
      link: Color(0xFFFFFF00),
      success: Color(0xFFFFFF00),
      warning: Color(0xFFFFFFFF),
      danger: Color(0xFFFF6666),
      swatchGold: Color(0xFFFFFF00),
      swatchBridge: Color(0xFFFFFFFF),
      swatchAccent: Color(0xFFFFFF00),
    ),
  ];
}
