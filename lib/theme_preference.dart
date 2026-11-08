// Theme preference: the option the user picks in Settings → General →
// Appearance (Account tab → Theme Settings). Stored under the existing
// 'byahetayo_theme_mode' key in lib/main.dart — no second key is
// introduced, so the stored setting can never disagree with itself.
//
// 'timeBased' is the 4th option (Nov 8): Light 6:00 AM–6:00 PM, Dark
// 6:00 PM–6:00 AM, resolved against the clock in lib/main.dart (which
// re-evaluates on resume and on a periodic check, so it flips without
// a restart). The other three map straight onto Flutter's ThemeMode.
import 'package:flutter/material.dart';

/// The theme option the user picks in Theme Settings.
enum AppThemePreference { system, light, dark, timeBased }

/// Daytime window for [AppThemePreference.timeBased]: light from 6:00 AM
/// up to (but not including) 6:00 PM, dark otherwise.
bool isDaytimeForTheme(DateTime now) => now.hour >= 6 && now.hour < 18;

/// Resolves a stored theme preference to the ThemeMode the app applies.
/// [now] is a parameter (not DateTime.now() inside) so the 6 AM / 6 PM
/// boundaries are unit-testable.
ThemeMode resolveThemeMode(AppThemePreference preference, DateTime now) {
  switch (preference) {
    case AppThemePreference.light:
      return ThemeMode.light;
    case AppThemePreference.dark:
      return ThemeMode.dark;
    case AppThemePreference.system:
      return ThemeMode.system;
    case AppThemePreference.timeBased:
      return isDaytimeForTheme(now) ? ThemeMode.light : ThemeMode.dark;
  }
}

/// Parses the stored preference string. Unknown or missing values fall
/// back to dark — the app's existing default (no stored preference
/// means dark, not system).
AppThemePreference appThemePreferenceFromString(String? value) {
  switch (value) {
    case 'light':
      return AppThemePreference.light;
    case 'dark':
      return AppThemePreference.dark;
    case 'system':
      return AppThemePreference.system;
    case 'timeBased':
      return AppThemePreference.timeBased;
    default:
      return AppThemePreference.dark;
  }
}

/// Maps an explicit [ThemeMode] onto the matching preference. Used when
/// a caller only has a ThemeMode (the entry screens flip light <-> dark;
/// tests inject an initial ThemeMode).
AppThemePreference appThemePreferenceForThemeMode(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return AppThemePreference.light;
    case ThemeMode.dark:
      return AppThemePreference.dark;
    case ThemeMode.system:
      return AppThemePreference.system;
  }
}
