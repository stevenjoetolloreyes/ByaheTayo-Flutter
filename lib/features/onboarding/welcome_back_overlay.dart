// Welcome Back overlay (Feature 4 of the startup preview -> real
// app build).
//
// Shown ONLY to a returning user right after a successful Sign In
// (email/password or Google, step 7) and before landing on the
// Student tab (step 9). It never shows for the Create Account /
// Finish setup path (Feature 2 has its own celebration there), and
// it never shows the "You know how to use the app?" prompt or arms
// the Watch demo tour hook — those belong only to the new-user
// Finish setup path.
//
// Sequence: [WelcomeBackOverlay] (~2 s, tap to skip) -> Student
// tab. The gate (lib/main.dart) shows it only when the sign-in
// originated on the Sign In page and the restored profile is
// complete enough to land on the dashboard.
//
// Style: Minecraft dark (grass #58CC02 / deep leaves #2F7A12 on dark bg #0c1410),
// ENGLISH labels, Material icons only, no emoji as UI icons.
// Android-first; same layout on Android and iOS.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'onboarding_state.dart';
import 'splash_sound.dart';

import '../minecraft_theme.dart';

/// Dark emerald background shared with the Feature 2 overlays.
const _overlayBackground = MinecraftColors.darkBackground;

/// Deep emerald (avatar ring / secondary surfaces).
const _deepEmerald = MinecraftColors.deepLeaves;

/// Primary emerald (E badge, rings).
const _emerald = MinecraftColors.grassGreen;

/// Light emerald (subtitle text).
const _lightEmeraldText = Color(0xFFBBF7D0);

/// How long the overlay plays before auto-advancing to the Student
/// tab. Tapping anywhere skips ahead immediately.
const welcomeBackDuration = Duration(seconds: 2);

/// The first name to greet, from the signed-in user's stored
/// profile first, then the Firebase display name. Returns null
/// when no name is available — the overlay then says plain
/// "Welcome back!" with no name. An email local-part is never a
/// name, so it is never used here.
String? welcomeBackFirstName({UserProfile? profile, AuthUser? user}) {
  final displayName = (profile?.displayName ?? user?.displayName ?? '')
      .trim();
  if (displayName.isEmpty) return null;
  return displayName.split(RegExp(r'\s+')).first;
}

/// Honest initials for the avatar fallback, from the full display
/// name (same rule as [UserProfile.initials]). Null when there is
/// no name at all — the overlay then shows a person icon instead.
String? _initialsOf(String? displayName) {
  final parts = (displayName ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts[1][0]).toUpperCase();
}

/// Full-screen welcome-back overlay for a returning user.
///
/// A springing avatar (the user's photo when one exists — resolved
/// by the caller with the same rule the Student Hub and Account tab
/// use: local file -> uploaded URL -> Google avatar — or honest
/// initials / a person icon when there is no photo) together with
/// the emerald "E" logo badge, radiating rings, and the text
/// "Welcome back, `<first name>`!" (or plain "Welcome back!" when
/// no name is available). Plays the welcome-back chime + soft pop
/// ([SplashSound.welcomeBack]) on entry. Auto-advances via
/// [onFinished] after [autoAdvanceAfter]; tapping anywhere
/// finishes immediately. [onFinished] fires exactly once,
/// whichever path wins.
class WelcomeBackOverlay extends StatefulWidget {
  const WelcomeBackOverlay({
    super.key,
    required this.firstName,
    this.displayName,
    this.photoImage,
    required this.onFinished,
    this.autoAdvanceAfter = welcomeBackDuration,
  });

  /// First name to greet, or null for the plain "Welcome back!".
  /// See [welcomeBackFirstName].
  final String? firstName;

  /// Full display name, used only to derive the initials fallback
  /// when there is no photo.
  final String? displayName;

  /// The user's photo, resolved by the caller with the shared
  /// profile-photo rule (see profile_avatar.dart). Null means no
  /// photo: initials (or a person icon) are shown instead.
  final ImageProvider<Object>? photoImage;

  /// Called once when the overlay ends (auto-advance or tap).
  final VoidCallback onFinished;

  /// Delay before auto-advance. Defaults to [welcomeBackDuration];
  /// tests may pass a shorter value.
  final Duration autoAdvanceAfter;

  @override
  State<WelcomeBackOverlay> createState() => _WelcomeBackOverlayState();
}

class _WelcomeBackOverlayState extends State<WelcomeBackOverlay>
    with TickerProviderStateMixin {
  /// Entrance timeline (0.9 s): the avatar + E badge spring in
  /// (elastic, 0-0.7), the greeting fades up (0.5-1.0).
  late final AnimationController _enterController;

  /// Radiating rings, one shot over the overlay's lifetime (2 s):
  /// two rings staggered so the second starts as the first fades.
  /// Deliberately NOT repeating — a looping controller would keep
  /// scheduling frames forever and widget tests could never settle
  /// while the overlay is up.
  late final AnimationController _ringsController;

  Timer? _autoAdvanceTimer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _ringsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();
    // Success chime + soft pop (synthesized, same pattern as the
    // splash sounds — no audio asset, best-effort, silence on
    // failure).
    SplashSound.welcomeBack();
    _autoAdvanceTimer = Timer(widget.autoAdvanceAfter, _finish);
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _enterController.dispose();
    _ringsController.dispose();
    super.dispose();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _autoAdvanceTimer?.cancel();
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final greeting = widget.firstName == null
        ? 'Welcome back!'
        : 'Welcome back, ${widget.firstName}!';
    final initials = _initialsOf(widget.displayName);
    return Scaffold(
      key: const Key('welcome-back-overlay'),
      backgroundColor: _overlayBackground,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge(
                    [_enterController, _ringsController],
                  ),
                  builder: (context, _) {
                    final t = _enterController.value;
                    final avatarScale = Curves.elasticOut.transform(
                      const Interval(0.0, 0.7).transform(t),
                    );
                    final textOpacity =
                        const Interval(0.5, 1.0).transform(t);
                    // Two rings, staggered across the overlay's
                    // lifetime: the second starts as the first fades.
                    final ringProgresses = <double>[
                      const Interval(0.0, 0.75).transform(
                        _ringsController.value,
                      ),
                      const Interval(0.25, 1.0).transform(
                        _ringsController.value,
                      ),
                    ];
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 280,
                          height: 280,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                size: const Size(280, 280),
                                painter: _RingsPainter(
                                  progresses: ringProgresses,
                                ),
                              ),
                              Transform.scale(
                                scale: math.max(avatarScale, 0.0),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    CircleAvatar(
                                      radius: 56,
                                      backgroundColor: _deepEmerald,
                                      backgroundImage: widget.photoImage,
                                      child: widget.photoImage != null
                                          ? null
                                          : initials != null
                                              ? Text(
                                                  initials,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 40,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.person,
                                                  color: Colors.white,
                                                  size: 56,
                                                ),
                                    ),
                                    // The emerald "E" logo badge,
                                    // overlapping the avatar's
                                    // bottom-right — logo and photo
                                    // spring in together as one unit.
                                    Positioned(
                                      right: -4,
                                      bottom: -4,
                                      child: Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: _emerald,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                            color: _overlayBackground,
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: _emerald.withValues(
                                                alpha: 0.45,
                                              ),
                                              blurRadius: 16,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                        alignment: Alignment.center,
                                        child: const Text(
                                          'E',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 26,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Opacity(
                          opacity: textOpacity,
                          child: Transform.translate(
                            offset: Offset(0, (1 - textOpacity) * 12),
                            child: Column(
                              children: [
                                Text(
                                  greeting,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Good to see you again.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: _lightEmeraldText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: Text(
                  'Tap anywhere to continue',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expanding, fading rings around the avatar. One entry per ring,
/// each a 0 -> 1 loop progress. (Same pattern as the Feature 2
/// celebration rings.)
class _RingsPainter extends CustomPainter {
  const _RingsPainter({required this.progresses});

  final List<double> progresses;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (final progress in progresses) {
      final radius = 68 + progress * 68;
      final paint = Paint()
        ..color = _emerald.withValues(alpha: (1 - progress) * 0.5)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter oldDelegate) =>
      progresses != oldDelegate.progresses;
}
