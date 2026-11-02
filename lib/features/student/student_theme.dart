// Student Hub's OWN design — Premium Light Emerald.
//
// This theme applies ONLY to the Student Hub (dashboard + its module
// screens + the sign-in page). Other tabs keep the app theme. Per the
// Nov 1 redesign reference: primary Deep Emerald Green #14532D,
// accent Emerald Green #16A34A, background soft white #F8FAFC, white
// cards with subtle shadows and rounded corners.
//
// (An earlier Emerald Dark theme shipped Nov 1, 09:57; the redesign
// reference the user sent later that day specifies this light theme,
// so the Hub follows the reference now.)
import 'dart:io';

import 'package:flutter/material.dart';
import '../app_layout.dart';
import '../onboarding/onboarding_state.dart';

const kStudentEmerald = Color(0xFF14532D);
const kStudentEmeraldDark = Color(0xFF0A2E1A);
const kStudentEmeraldAccent = Color(0xFF16A34A);
const kStudentBg = Color(0xFFF8FAFC);
const kStudentCard = Colors.white;
const kStudentText = Color(0xFF0F172A);
const kStudentSubtext = Color(0xFF64748B);
const kStudentBorder = Color(0xFFE2E8F0);

// Dark Mode palette for the Student Hub (Nov 2 polish), from the
// user's Dark Mode color system. Deep emerald #14532D is kept for
// brand surfaces (the greeting banner gradient); it is never used
// as foreground text on dark cards, where it would be unreadable —
// [kStudentDarkAccent] is the readable emerald there (same value
// as the app dark theme's primary).
const kStudentDarkBg = Color(0xFF121212);
const kStudentDarkSecondaryBg = Color(0xFF1B1F20);
const kStudentDarkCard = Color(0xFF202729);
const kStudentDarkElevated = Color(0xFF252B2D);
const kStudentDarkText = Color(0xFFFFFFFF);
const kStudentDarkSubtext = Color(0xFFB0B8B5);
const kStudentDarkBorder = Color(0xFF343B3D);
const kStudentDarkAccent = Color(0xFF34D399);

ThemeData get studentTheme => ThemeData.light().copyWith(
      scaffoldBackgroundColor: kStudentBg,
      cardColor: kStudentCard,
      colorScheme: const ColorScheme.light(
        primary: kStudentEmerald,
        onPrimary: Colors.white,
        secondary: kStudentEmeraldAccent,
        onSecondary: Colors.white,
        surface: kStudentCard,
        onSurface: kStudentText,
        surfaceContainerHighest: kStudentCard,
        outline: kStudentBorder,
      ),
      cardTheme: const CardThemeData(
        color: kStudentCard,
        elevation: 1,
        shadowColor: Color(0x1A0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppLayout.cardRadius)),
          side: BorderSide(color: kStudentBorder),
        ),
      ),
    );

/// Dark twin of [studentTheme]: same geometry, same Emerald Green
/// identity, but the user's Dark Mode surfaces — #121212 page,
/// #202729 cards, #252B2D elevated surfaces, white primary text,
/// #B0B8B5 secondary text, #343B3D borders. The greeting banner
/// gradient stays deep emerald → accent green in both modes.
ThemeData get studentDarkTheme => ThemeData.dark().copyWith(
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
      ),
      cardTheme: const CardThemeData(
        color: kStudentDarkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppLayout.cardRadius)),
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
/// The bell shows a real empty state (this app has no notification
/// system, so there is never a fake unread dot).
///
/// The profile circle shows the EXACT SAME photo the Account Profile
/// shows: [profile]'s `photoPath` (the local file picked in profile
/// setup / Edit Profile), read fresh on every build from the same
/// [UserProfile] object the shell passes to the Account tab — so an
/// Account-side photo change reflects here automatically, with no
/// second copy of the image anywhere. When there is no stored photo
/// (or its file is gone), the default person icon shows instead.
Widget studentHeader({
  required String greetingName,
  required VoidCallback onBell,
  UserProfile? profile,
}) {
  final photoPath = profile?.photoPath;
  final hasPhoto = photoPath != null && File(photoPath).existsSync();
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
          backgroundImage: hasPhoto ? FileImage(File(photoPath)) : null,
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
                '$greetingName, Steven!',
                style: AppText.titleStrong.copyWith(color: Colors.white),
              ),
              Text(
                'Student Hub',
                style: AppText.sectionTitle.copyWith(color: Colors.white),
              ),
              const Text(
                'Your school commute, in one place.',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onBell,
          icon: const Icon(Icons.notifications_outlined,
              color: Colors.white),
        ),
      ],
    ),
  );
}
