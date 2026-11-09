// Student Hub's OWN design — Premium Dark + Emerald Green.
//
// This theme applies ONLY to the Student Hub (dashboard + its module
// screens + the sign-in page). Other tabs keep the app theme.
//
// Tokens follow the ChatGPT design system Steven adopted Nov 5 as a
// LOOSE UI base ("wag mo seryusuhin"): Premium Dark + Emerald Green
// with a matching Light Mode. Adapted, not forced — the Hub keeps
// its approved structure (single-column dashboard, greeting banner,
// sign-in card values) and the tokens below are the Hub's own.
// Primary stays Deep Emerald Green #14532D in both modes; the
// readable dark accent is #34D399 and the light accent is #059669.

import 'package:flutter/material.dart';
import '../onboarding/onboarding_state.dart';
import '../profile_avatar.dart';

const kStudentEmerald = Color(0xFF14532D);
const kStudentEmeraldDark = Color(0xFF0A2E1A);
// Brand accent (greeting/Bible gradients, dark-mode primary, the
// approved sign-in card's light-mode greens). The ChatGPT light
// accent (#059669) is kStudentLightAccent below — the sign-in
// card's exact approved values stay untouched.
const kStudentEmeraldAccent = Color(0xFF16A34A);
const kStudentLightAccent = Color(0xFF059669);
const kStudentBg = Color(0xFFF5F8F6);
const kStudentCard = Colors.white;
const kStudentText = Color(0xFF17231C);
const kStudentSubtext = Color(0xFF64748B);
const kStudentBorder = Color(0xFFE2E8F0);

// Semantic colors (ChatGPT system) — used only where the Hub
// already has such a state (expenses, errors, info dots).
const kStudentSuccess = Color(0xFF22C55E);
const kStudentWarning = Color(0xFFF59E0B);
const kStudentError = Color(0xFFEF4444);
const kStudentInfo = Color(0xFF3B82F6);

// Card corner radius (ChatGPT: 18–22px).
const kStudentCardRadius = 20.0;

// Dark Mode palette for the Student Hub (ChatGPT dark tokens,
// adapted: the elevated surface, secondary text and border keep
// the Nov 2 polished values, which the ChatGPT system does not
// specify). The page background is the preview's #0c1410 (Nov 7)
// so the Hub matches the rest of the dark app exactly.
const kStudentDarkBg = Color(0xFF0C1410);
const kStudentDarkSecondaryBg = Color(0xFF18221D);
const kStudentDarkCard = Color(0xFF202B25);
const kStudentDarkElevated = Color(0xFF252B2D);
const kStudentDarkText = Color(0xFFF8FAF9);
const kStudentDarkSubtext = Color(0xFFB0B8B5);
const kStudentDarkBorder = Color(0xFF343B3D);
const kStudentDarkAccent = Color(0xFF34D399);

// Student Hub typography (ChatGPT scale, Hub-local so the shared
// AppText scale — used by other tabs — stays untouched).
// Page title 26 Bold, section heading 20 Semibold, card heading
// 16 Semibold. Body text keeps the app's established sizes.
// Headings use Plus Jakarta Sans (preview typography, Nov 7).
const kStudentPageTitle = TextStyle(
  fontFamily: 'PlusJakartaSans',
  fontSize: 26,
  fontWeight: FontWeight.w800,
);
const kStudentSectionHeading = TextStyle(
  fontFamily: 'PlusJakartaSans',
  fontSize: 20,
  fontWeight: FontWeight.w600,
);
const kStudentCardHeading = TextStyle(
  fontFamily: 'PlusJakartaSans',
  fontSize: 16,
  fontWeight: FontWeight.w600,
);

ThemeData get studentTheme => ThemeData.light().copyWith(
      // Inter body (preview typography): copyWith has no fontFamily
      // parameter, so the family is applied through the text theme.
      textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Inter'),
      scaffoldBackgroundColor: kStudentBg,
      cardColor: kStudentCard,
      colorScheme: const ColorScheme.light(
        primary: kStudentEmerald,
        onPrimary: Colors.white,
        secondary: kStudentLightAccent,
        onSecondary: Colors.white,
        surface: kStudentCard,
        onSurface: kStudentText,
        surfaceContainerHighest: kStudentCard,
        outline: kStudentBorder,
        error: kStudentError,
      ),
      cardTheme: const CardThemeData(
        color: kStudentCard,
        elevation: 1,
        shadowColor: Color(0x1A0F172A),
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.all(Radius.circular(kStudentCardRadius)),
          side: BorderSide(color: kStudentBorder),
        ),
      ),
    );

/// Dark twin of [studentTheme]: same geometry, same Emerald Green
/// identity, but the ChatGPT dark surfaces — #0c1410 page (preview
/// bg, Nov 7), #202B25 cards, #252B2D elevated surfaces, #F8FAF9
/// primary text, #B0B8B5 secondary text, #343B3D borders. The
/// greeting banner gradient stays deep emerald → accent green in
/// both modes.
ThemeData get studentDarkTheme => ThemeData.dark().copyWith(
      // Inter body (preview typography): copyWith has no fontFamily
      // parameter, so the family is applied through the text theme.
      textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter'),
      scaffoldBackgroundColor: kStudentDarkBg,
      canvasColor: kStudentDarkCard,
      cardColor: kStudentDarkCard,
      colorScheme: const ColorScheme.dark(
        primary: kStudentEmeraldAccent,
        onPrimary: Colors.white,
        secondary: kStudentDarkAccent,
        onSecondary: Color(0xFF052E16),
        surface: kStudentDarkCard,
        onSurface: kStudentDarkText,
        surfaceContainerHighest: kStudentDarkElevated,
        onSurfaceVariant: kStudentDarkSubtext,
        outline: kStudentDarkBorder,
        error: kStudentError,
      ),
      cardTheme: const CardThemeData(
        color: kStudentDarkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.all(Radius.circular(kStudentCardRadius)),
          side: BorderSide(color: kStudentDarkBorder),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: kStudentDarkElevated,
      ),
    );

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

/// Dashboard header: emerald gradient banner with the greeting,
/// title, subtitle, profile photo, and a notification bell.
/// The bell shows a real unread badge ([unreadNotifications], the
/// count of unread admin-reply notifications — 0 hides the badge,
/// so there is never a fake unread dot) and opens the Notifications
/// sheet.
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
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [kStudentEmerald, kStudentEmeraldAccent],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.all(Radius.circular(20)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: Colors.white24,
          backgroundImage: photoImage,
          child: hasPhoto
              ? null
              : const Icon(Icons.person, color: Colors.white, size: 30),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greetingName, $firstName!',
                style: kStudentPageTitle.copyWith(color: Colors.white),
              ),
              Text(
                'Student Hub',
                style:
                    kStudentSectionHeading.copyWith(color: Colors.white),
              ),
              const Text(
                'Your school commute, in one place.',
                style: TextStyle(color: Colors.white70),
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
