import 'package:flutter/material.dart';

import 'app_palette.dart';

export 'app_palette.dart'; // so `context.p` is available wherever app_theme is imported

/// One selectable theme: a palette + metadata for the picker.
class SlkTheme {
  const SlkTheme({
    required this.id,
    required this.label,
    required this.description,
    required this.brightness,
    required this.palette,
  });

  final String id;
  final String label;
  final String description;
  final Brightness brightness;
  final AppPalette palette;

  List<Color> get swatch => [palette.appBar, palette.primary, palette.accent, palette.surface1];

  ThemeData toThemeData() {
    final p = palette;
    final scheme = ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: brightness,
      primary: p.primary,
      secondary: p.accent,
      surface: p.surface2,
      error: p.danger,
      onSurface: p.text,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Roboto');
    return base.copyWith(
      scaffoldBackgroundColor: p.surface1,
      extensions: [p],
      appBarTheme: AppBarTheme(
        backgroundColor: p.appBar,
        foregroundColor: p.onAppBar,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: p.surface2,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.border)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface2,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.primary, width: 2)),
        labelStyle: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(color: p.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        // Let helper/error text wrap instead of clipping with an ellipsis.
        helperMaxLines: 3,
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textTheme: base.textTheme
          .copyWith(
            titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.2),
            titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            bodyLarge: const TextStyle(fontSize: 15, height: 1.35),
            bodyMedium: const TextStyle(fontSize: 14, height: 1.35),
            bodySmall: TextStyle(fontSize: 12, color: p.textMuted, height: 1.3),
            labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          )
          .apply(bodyColor: p.text, displayColor: p.text),
      dividerColor: p.border,
      splashFactory: InkSparkle.splashFactory,
      iconTheme: IconThemeData(color: p.textSecondary),
    );
  }
}

/// The theme registry — Kalamkari (default) + Dark + a few curated alternates.
class SlkThemes {
  SlkThemes._();

  static const kalamkari = SlkTheme(
    id: 'kalamkari', label: 'Kalamkari', description: 'Warm terracotta · Default',
    brightness: Brightness.light,
    palette: AppPalette(
      primary: Color(0xFFB5533B), primaryDark: Color(0xFF8F3F2C), accent: Color(0xFFC9A24B),
      surface1: Color(0xFFFBF6EF), surface2: Color(0xFFFFFFFF), surface3: Color(0xFFF5EEE4),
      text: Color(0xFF2A211C), textSecondary: Color(0xFF6B5D53), textMuted: Color(0xFF8A7C70),
      border: Color(0xFFE7DDD0), success: Color(0xFF2E7D57), danger: Color(0xFFB3261E),
      appBar: Color(0xFFB5533B), onAppBar: Color(0xFFFFFFFF), onPrimary: Color(0xFFFFFFFF),
    ),
  );

  static const dark = SlkTheme(
    id: 'dark', label: 'Dark', description: 'Night · Battery saver',
    brightness: Brightness.dark,
    palette: AppPalette(
      primary: Color(0xFFD4674E), primaryDark: Color(0xFFB5533B), accent: Color(0xFFD9B665),
      surface1: Color(0xFF141110), surface2: Color(0xFF221C19), surface3: Color(0xFF2E2723),
      text: Color(0xFFF4ECE4), textSecondary: Color(0xFFC7B9AD), textMuted: Color(0xFF9A8C80),
      border: Color(0xFF382E28), success: Color(0xFF4CAF80), danger: Color(0xFFE5675E),
      appBar: Color(0xFF221C19), onAppBar: Color(0xFFF4ECE4), onPrimary: Color(0xFFFFFFFF),
    ),
  );

  static const midnight = SlkTheme(
    id: 'midnight', label: 'Midnight', description: 'Indigo · Premium',
    brightness: Brightness.light,
    palette: AppPalette(
      primary: Color(0xFF4F46E5), primaryDark: Color(0xFF312E81), accent: Color(0xFFF59E0B),
      surface1: Color(0xFFEEF2FF), surface2: Color(0xFFFFFFFF), surface3: Color(0xFFE0E7FF),
      text: Color(0xFF1E1B4B), textSecondary: Color(0xFF3730A3), textMuted: Color(0xFF6D7AC7),
      border: Color(0xFFC7D2FE), success: Color(0xFF10B981), danger: Color(0xFFEF4444),
      appBar: Color(0xFF312E81), onAppBar: Color(0xFFFFFFFF), onPrimary: Color(0xFFFFFFFF),
    ),
  );

  static const forest = SlkTheme(
    id: 'forest', label: 'Forest', description: 'Green · Calm',
    brightness: Brightness.light,
    palette: AppPalette(
      primary: Color(0xFF0D7A4E), primaryDark: Color(0xFF0D4F3C), accent: Color(0xFF2563EB),
      surface1: Color(0xFFF0FDF4), surface2: Color(0xFFFFFFFF), surface3: Color(0xFFDCFCE7),
      text: Color(0xFF052E1A), textSecondary: Color(0xFF1E5C41), textMuted: Color(0xFF4D8C6F),
      border: Color(0xFFBBE8D4), success: Color(0xFF10A868), danger: Color(0xFFE01E35),
      appBar: Color(0xFF0D4F3C), onAppBar: Color(0xFFFFFFFF), onPrimary: Color(0xFFFFFFFF),
    ),
  );

  static const slate = SlkTheme(
    id: 'slate', label: 'Slate', description: 'Corporate · Minimal',
    brightness: Brightness.light,
    palette: AppPalette(
      primary: Color(0xFF2563EB), primaryDark: Color(0xFF1E293B), accent: Color(0xFFF59E0B),
      surface1: Color(0xFFF8FAFC), surface2: Color(0xFFFFFFFF), surface3: Color(0xFFF1F5F9),
      text: Color(0xFF0F172A), textSecondary: Color(0xFF475569), textMuted: Color(0xFF7A8DA3),
      border: Color(0xFFCBD5E1), success: Color(0xFF22C55E), danger: Color(0xFFEF4444),
      appBar: Color(0xFF1E293B), onAppBar: Color(0xFFFFFFFF), onPrimary: Color(0xFFFFFFFF),
    ),
  );

  static const terminal = SlkTheme(
    id: 'terminal', label: 'Terminal', description: 'Hazard yellow · Warehouse',
    brightness: Brightness.dark,
    palette: AppPalette(
      primary: Color(0xFFF4C000), primaryDark: Color(0xFFC99A00), accent: Color(0xFFF4C000),
      surface1: Color(0xFF101214), surface2: Color(0xFF17191B), surface3: Color(0xFF202224),
      text: Color(0xFFF2F1EA), textSecondary: Color(0xFFA9AD9F), textMuted: Color(0xFF6E7166),
      border: Color(0xFF2B2E2F), success: Color(0xFF3FAE5C), danger: Color(0xFFEF5350),
      appBar: Color(0xFF0A0B0C), onAppBar: Color(0xFFF2F1EA), onPrimary: Color(0xFF0A0B0C),
    ),
  );

  static const List<SlkTheme> all = [kalamkari, dark, midnight, forest, slate, terminal];
  static const fallback = kalamkari;
  static SlkTheme byId(String id) => all.firstWhere((t) => t.id == id, orElse: () => fallback);
}

/// Spacing tokens.
class Gaps {
  static const h4 = SizedBox(height: 4);
  static const h8 = SizedBox(height: 8);
  static const h12 = SizedBox(height: 12);
  static const h16 = SizedBox(height: 16);
  static const h24 = SizedBox(height: 24);
  static const w8 = SizedBox(width: 8);
  static const w12 = SizedBox(width: 12);
}

/// Corner-radius tokens.
class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
}
