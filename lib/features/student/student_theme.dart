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
