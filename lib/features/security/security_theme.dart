// Login Alerts + Session Manager — Minecraft theme tokens.
//
// Same palette as the app's Minecraft theme (Grass, Deep Leaves,
// Dirt, Gold, Emerald, Sky) with 3px borders and blocky buttons.
// Headings use the app's bundled Plus Jakarta Sans (the preview's
// Press Start 2P / Baloo 2 are not bundled as fonts in the app,
// so no new font files are added).
import 'package:flutter/material.dart';

const kSecurityGrass = Color(0xFF58CC02);
const kSecurityDeepLeaves = Color(0xFF2F7A12);
const kSecurityDirt = Color(0xFF9C6B30);
const kSecurityGold = Color(0xFFFFC800);
const kSecurityEmerald = Color(0xFF00D68F);
const kSecuritySky = Color(0xFF1CB0F6);
const kSecurityHeart = Color(0xFFFF4B4B);
const kSecurityCloud = Color(0xFF8ED6FF);

/// Blocky card: white/dark surface, 3px Deep Leaves border, 12px
/// corners (Minecraft block, softened to the app's radius).
BoxDecoration securityCardDecoration(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: dark ? const Color(0xFF202B25) : Colors.white,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: dark ? kSecurityGrass : kSecurityDeepLeaves,
      width: 3,
    ),
  );
}

/// Blocky filled button: Grass background, white bold label, 3px
/// Deep Leaves border, square-ish corners.
ButtonStyle securityBlockButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    backgroundColor: kSecurityGrass,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    textStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: kSecurityDeepLeaves, width: 3),
    ),
  );
}

/// Blocky danger button: white surface, Heart-red label + border.
ButtonStyle securityDangerButtonStyle(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return OutlinedButton.styleFrom(
    foregroundColor: kSecurityHeart,
    backgroundColor: dark ? const Color(0xFF3A1A1A) : Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    textStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: kSecurityHeart, width: 3),
    ),
  );
}

/// SUCCESS / FAILED pill, as in the preview: green for success,
/// red for failure.
Widget securityStatusPill(bool success) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: success
          ? kSecurityGrass.withValues(alpha: 0.16)
          : kSecurityHeart.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: success ? kSecurityDeepLeaves : kSecurityHeart,
        width: 2,
      ),
    ),
    child: Text(
      success ? 'SUCCESS' : 'FAILED',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
        color: success ? kSecurityDeepLeaves : kSecurityHeart,
      ),
    ),
  );
}

/// Green CURRENT badge for 'This device', as in the preview.
Widget securityCurrentBadge() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: kSecurityGrass,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: kSecurityDeepLeaves, width: 2),
    ),
    child: const Text(
      'CURRENT',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
        color: Colors.white,
      ),
    ),
  );
}
