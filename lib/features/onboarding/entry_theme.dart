// Shared Modern Minimalist theme for the entry experience ONLY
// (splash, onboarding, welcome, create account, sign in).
//
// This theme is deliberately LOCAL to the entry screens: the dashboard
// tabs keep the global MaterialApp theme in lib/main.dart untouched,
// so this redesign cannot restyle any other screen. The entry screens
// wrap themselves in Theme(data: entryThemeData(...)) and read their
// colors from [EntryColors].
//
// Theme MODE state (light / dark / system) is owned by the app shell
// in lib/main.dart and persisted under the existing
// 'byahetayo_theme_mode' key — the same key the Account tab's theme
// settings already use. No second key is introduced: two keys for one
// setting would let the entry toggle and the Account settings disagree.
// The entry screens only ever FLIP light <-> dark explicitly; the
// System Default option stays selectable in Account settings (the
// existing settings entry point).
//
// Tokens are the spec's exact values. Typography uses the Android
// system typeface (Roboto on Android) — no font dependency is added.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Exact spec tokens for one brightness.
class EntryColors {
  const EntryColors({
    required this.primary,
    required this.primaryDark,
    required this.background,
    required this.surface,
    required this.secondarySurface,
    required this.primaryText,
    required this.secondaryText,
    required this.border,
    required this.error,
    required this.onPrimary,
  });

  final Color primary;
  final Color primaryDark;
  final Color background;
  final Color surface;
  final Color secondarySurface;
  final Color primaryText;
  final Color secondaryText;
  final Color border;
  final Color error;

  /// Text/icon color on top of [primary].
  final Color onPrimary;

  static const light = EntryColors(
    primary: Color(0xFF079B61),
    primaryDark: Color(0xFF067A4D),
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    secondarySurface: Color(0xFFF1F5F3),
    primaryText: Color(0xFF17211D),
    secondaryText: Color(0xFF64748B),
    border: Color(0xFFE2E8F0),
    error: Color(0xFFDC2626),
    onPrimary: Colors.white,
  );

  static const dark = EntryColors(
    primary: Color(0xFF12C98A),
    primaryDark: Color(0xFF079B61),
    background: Color(0xFF101816),
    surface: Color(0xFF19231F),
    secondarySurface: Color(0xFF202D27),
    primaryText: Color(0xFFF5F7F6),
    secondaryText: Color(0xFFA0ADA6),
    border: Color(0xFF2D3B34),
    error: Color(0xFFFF8A80),
    onPrimary: Color(0xFF06281C),
  );
}

/// Colors for a brightness.
EntryColors entryColorsFor(Brightness brightness) =>
    brightness == Brightness.dark ? EntryColors.dark : EntryColors.light;

/// Effective brightness for a [ThemeMode]: explicit modes win, System
/// follows the device.
Brightness entryEffectiveBrightness(ThemeMode mode, BuildContext context) {
  switch (mode) {
    case ThemeMode.light:
      return Brightness.light;
    case ThemeMode.dark:
      return Brightness.dark;
    case ThemeMode.system:
      return MediaQuery.platformBrightnessOf(context);
  }
}

/// Full ThemeData for the entry screens at [brightness].
ThemeData entryThemeData(Brightness brightness) {
  final colors = entryColorsFor(brightness);
  final scheme = brightness == Brightness.dark
      ? ColorScheme.dark(
          primary: colors.primary,
          secondary: colors.primaryDark,
          surface: colors.surface,
          onSurface: colors.primaryText,
          outline: colors.border,
          error: colors.error,
        )
      : ColorScheme.light(
          primary: colors.primary,
          secondary: colors.primaryDark,
          surface: colors.surface,
          onSurface: colors.primaryText,
          outline: colors.border,
          error: colors.error,
        );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    // Rounded inputs, 14dp (spec range 12-16dp).
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      labelStyle: TextStyle(color: colors.secondaryText),
      hintStyle: TextStyle(color: colors.secondaryText),
      prefixIconColor: colors.secondaryText,
      suffixIconColor: colors.secondaryText,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.error, width: 1.5),
      ),
    ),
    // Primary buttons, 16dp (spec range 14-18dp), 52dp tall, 16sp
    // semibold.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        disabledBackgroundColor: colors.primary.withValues(alpha: 0.4),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.primary,
        side: BorderSide(color: colors.primary, width: 1.5),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.primary,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
    // Cards, 18dp (spec range 16-20dp), outline instead of shadow.
    cardTheme: CardThemeData(
      color: colors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background,
      foregroundColor: colors.primaryText,
      elevation: 0,
    ),
  );
}

/// Status-bar / navigation-bar appearance for the entry screens:
/// transparent status bar, icons contrasting with the background, and
/// a navigation bar painted the screen background.
SystemUiOverlayStyle entryOverlayStyle(Brightness brightness) {
  final colors = entryColorsFor(brightness);
  final lightIcons = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: lightIcons ? Brightness.light : Brightness.dark,
    statusBarBrightness: brightness,
    systemNavigationBarColor: colors.background,
    systemNavigationBarIconBrightness:
        lightIcons ? Brightness.light : Brightness.dark,
  );
}

/// Light/Dark toggle for the entry screens: a sun icon in dark mode
/// (tap for light) and a moon icon in light mode (tap for dark).
/// Tapping always sets an EXPLICIT mode; System Default remains
/// selectable in Account settings. Renders nothing but the button —
/// callers decide where it sits.
class ThemeModeToggle extends StatelessWidget {
  const ThemeModeToggle({
    super.key,
    required this.mode,
    required this.onModeChanged,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final isDark =
        entryEffectiveBrightness(mode, context) == Brightness.dark;
    return IconButton(
      key: const Key('theme-mode-toggle'),
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      onPressed: () =>
          onModeChanged(isDark ? ThemeMode.light : ThemeMode.dark),
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
    );
  }
}

/// Shared input decoration for the entry screens: label + icon (+
/// optional suffix). The rounded 14dp fill, border, and primary focus
/// ring come from the entry theme's inputDecorationTheme, so every
/// entry field stays consistent from one place.
InputDecoration entryInputDecoration({
  required String label,
  required IconData icon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    suffixIcon: suffixIcon,
  );
}
