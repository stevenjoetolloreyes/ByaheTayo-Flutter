// Student Hub's OWN design — Minecraft theme (Nov 12, 2026 audit).
//
// The Hub used to carry its own ChatGPT "Premium Dark + Emerald Green"
// tokens (deep emerald #14532D primary, Inter body, Plus Jakarta Sans
// headings, 20px / 1px cards). The Minecraft theme audit repointed the
// Hub theme at the shared Minecraft tokens in
// lib/features/minecraft_theme.dart (grass #58CC02 primary, Baloo 2
// headings, Nunito body, 14px cards with 3px ink borders) so the
// Student tab and every module screen opened from it render in the
// same theme as the rest of the app. The Hub keeps its approved
// structure (single-column dashboard, greeting banner, sign-in card
// values) and the dark surfaces are unchanged — the Minecraft dark
// tokens ARE the Hub's dark values (#0c1410 page, #202B25 cards,
// #252B2D elevated, #343B3D borders).
//
// The old emerald constants below are KEPT: the 7-Day Sign-in tiles
// and the approved sign-in card hardcode them (deliberate — do NOT
// recolor the tile state colors), so they stay defined here even
// though the theme no longer uses them as its primary.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../minecraft_theme.dart';
import '../onboarding/onboarding_state.dart';
import '../profile_avatar.dart';

/// Deep emerald — the 7-Day Sign-in tiles' current-day tile and the
/// approved sign-in card's light-mode greens hardcode this (deliberate
/// — do NOT recolor the tile state colors).
const kStudentEmerald = Color(0xFF14532D);
// Brand accent — the 7-Day Sign-in tiles' completed-day tile (light)
// and current-day tile (dark) hardcode this (deliberate).
const kStudentEmeraldAccent = Color(0xFF16A34A);
const kStudentCard = Colors.white;
const kStudentText = Color(0xFF17231C);
const kStudentSubtext = Color(0xFF64748B);
const kStudentBorder = Color(0xFFE2E8F0);

// Error red — used by the Hub where it already has such a state
// (expenses, error text). Success/warning/info states use the
// Minecraft palette (emerald / gold / sky) via the theme.
const kStudentError = Color(0xFFEF4444);

// Dark surfaces for the Student Hub — identical to the Minecraft
// dark tokens (see MinecraftColors): #0c1410 page, #202B25 cards,
// #252B2D elevated, #B0B8B5 secondary text, #343B3D borders.
const kStudentDarkBg = Color(0xFF0C1410);
const kStudentDarkCard = Color(0xFF202B25);
const kStudentDarkElevated = Color(0xFF252B2D);
const kStudentDarkSubtext = Color(0xFFB0B8B5);
const kStudentDarkBorder = Color(0xFF343B3D);
const kStudentDarkAccent = Color(0xFF34D399);

// Student Hub typography (Minecraft theme, Nov 12 audit): Baloo 2
// headings. Page title 26 Bold, section heading 20 Semibold, card
// heading 16 Semibold. Body text keeps the app's established sizes
// (Nunito, from the theme).
final kStudentPageTitle = GoogleFonts.baloo2(
  fontSize: 26,
  fontWeight: FontWeight.w800,
);
final kStudentSectionHeading = GoogleFonts.baloo2(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);
final kStudentCardHeading = GoogleFonts.baloo2(
  fontSize: 16,
  fontWeight: FontWeight.w600,
);

/// The Student Hub theme: the shared Minecraft theme (light).
///
/// Light: paper background, white blocky cards with 3px ink borders
/// and hard shadows, grass-green primary, Baloo 2 headings, Nunito
/// body. See [minecraftThemeData].
ThemeData get studentTheme => minecraftThemeData(Brightness.light);

/// Dark twin of [studentTheme]: the shared Minecraft theme (dark).
/// Same dark surfaces the Hub already used (#0c1410 page, #202B25
/// cards, #252B2D elevated, #F8FAF9 primary text, #B0B8B5 secondary
/// text, #343B3D borders), grass-green primary, gold XP, Baloo 2 /
/// Nunito typography. See [minecraftThemeData].
ThemeData get studentDarkTheme => minecraftThemeData(Brightness.dark);

/// Applies the Student Hub theme to [child] (dashboard body or a
/// module screen opened from it). The shell (nav bar, app bar) sits
/// outside this wrapper and keeps the app theme.
class StudentTheme extends StatelessWidget {
  const StudentTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(data: studentTheme, child: child);
  }
}

/// Applies the Student Hub theme to the Hub tab page, following the
/// app's Dark Mode setting: the dark twin above when the ambient
/// theme is dark, the light theme otherwise. The Hub tab is the
/// only Student surface that follows Dark Mode — module screens
/// opened from it keep the light [StudentTheme] wrapper (their
/// approved light design), so their hardcoded light colors stay
/// correct and are never re-interpreted under a dark theme.
class StudentHubTheme extends StatelessWidget {
  const StudentHubTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Theme(
      data: isDark ? studentDarkTheme : studentTheme,
      child: child,
    );
  }
}

/// Greeting for the dashboard header, from the device clock.
String greetingFor(DateTime now) {
  if (now.hour >= 5 && now.hour < 12) return 'Good Morning';
  if (now.hour >= 12 && now.hour < 18) return 'Good Afternoon';
  return 'Good Evening';
}

/// Dashboard header (Minecraft restyle, Feature 2): grass gradient
/// banner with a 3px ink border and hard shadow, Baloo 2 greeting,
/// blocky white-bordered avatar, and the notification bell. The
/// bell's live unread badge ([unreadNotifications], the count of
/// unread admin-reply notifications — 0 hides the badge, so there
/// is never a fake unread dot) and the profile-photo rule below
/// are unchanged.
///
/// The profile circle shows the EXACT SAME photo the Account Profile
/// shows: one shared rule (see profile_avatar.dart) — local file →
/// uploaded remote URL → Google avatar → person icon — read fresh on
/// every build from the same [UserProfile] object the shell passes to
/// the Account tab, so an Account-side photo change reflects here
/// automatically, with no second copy of the image anywhere.
Widget studentHeader({
  required String greetingName,
  required VoidCallback onBell,
  UserProfile? profile,
  int unreadNotifications = 0,
}) {
  final photoImage = resolveProfilePhotoImage(profile);
  final hasPhoto = photoImage != null;
  // The greeting uses the profile's first name — the same display
  // name the Account tab shows — falling back to 'Steven' when
  // the profile has no display name (Fares × Map audit, Nov 7,
  // 2026: the old code hardcoded 'Steven' here, so a changed
  // display name would never show on the Student tab).
  final displayName = profile?.displayName.trim() ?? '';
  final firstName = displayName.isEmpty
      ? 'Steven'
      : displayName.split(RegExp(r'\s+')).first;
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [MinecraftColors.grassBright, MinecraftColors.grassMid],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius:
          BorderRadius.circular(MinecraftShapes.cardRadius),
      border: MinecraftShapes.blockBorder,
      boxShadow: const [MinecraftShapes.cardShadow],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white24,
            backgroundImage: photoImage,
            child: hasPhoto
                ? null
                : const Icon(Icons.person, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greetingName, $firstName!',
                style: MinecraftText.heading(
                  color: Colors.white,
                  fontSize: 26,
                ),
              ),
              Text(
                'Student Hub',
                style: MinecraftText.title(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
              Text(
                'Your school commute, in one place.',
                style: MinecraftText.body(color: Colors.white70),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: onBell,
              icon: const Icon(Icons.notifications_outlined,
                  color: Colors.white),
            ),
            if (unreadNotifications > 0)
              Positioned(
                right: 6,
                top: 6,
                // The badge must not swallow taps: it overlaps the
                // bell button's corner, so it is pointer-transparent
                // and taps pass through to the bell below.
                child: IgnorePointer(
                  child: Container(
                    key: const ValueKey('notification-badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      unreadNotifications > 9
                          ? '9+'
                          : '$unreadNotifications',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
