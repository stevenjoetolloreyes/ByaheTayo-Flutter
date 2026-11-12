// Post-setup celebration + "You know how to use the app?" prompt
// (Feature 2 of the startup preview -> real app build).
//
// These overlays are part of the onboarding flow, NOT new steps:
// the 9-step stepper (Feature 1) stays as-is. They run only for a
// NEW user completing Profile Setup (step 8), right after tapping
// "Finish setup" and before landing on the Student tab (step 9).
// The Sign In / Welcome Back flow is separate and never shows them.
//
// Sequence: [SetupCelebrationOverlay] (~2.2 s, tap to skip) ->
// [SetupGuidePromptOverlay] -> Student tab, with or without the
// Watch demo tour (see the TOUR HOOK note on [StudentTab] — the
// tour itself is Feature 3, not built here).
//
// Style: Minecraft dark (grass #58CC02 / deep leaves #2F7A12 on dark bg #0c1410),
// ENGLISH labels, Material icons only, no emoji as UI icons.
// Android-first; same layout on Android and iOS.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../minecraft_theme.dart';
import 'splash_sound.dart';

/// Dark emerald background shared by both overlays.
const _overlayBackground = MinecraftColors.darkBackground;

/// Deep emerald (circle ring / secondary surfaces).
const _deepEmerald = MinecraftColors.deepLeaves;

/// Primary emerald (circle, buttons).
const _emerald = MinecraftColors.grassGreen;

/// Light emerald (confetti + secondary text).
const _lightEmerald = MinecraftColors.emerald;

/// Gold confetti accent.
const _gold = MinecraftColors.gold;

/// How long the celebration plays before auto-advancing to the
/// prompt. Tapping anywhere skips ahead immediately.
const setupCelebrationDuration = Duration(milliseconds: 2200);

/// Full-screen success overlay shown right after "Finish setup".
///
/// A springing emerald circle, a white checkmark that draws in,
/// radiating rings, a small confetti burst (emerald / green /
/// gold), and the text "Handa ka na!" / "Welcome to EstudyanteGO!",
/// with a success chime ([SplashSound.celebration]) on entry.
/// Auto-advances via [onFinished] after [autoAdvanceAfter];
/// tapping anywhere finishes immediately. [onFinished] fires
/// exactly once, whichever path wins.
class SetupCelebrationOverlay extends StatefulWidget {
  const SetupCelebrationOverlay({
    super.key,
    required this.onFinished,
    this.autoAdvanceAfter = setupCelebrationDuration,
  });

  /// Called once when the celebration ends (auto-advance or tap).
  final VoidCallback onFinished;

  /// Delay before auto-advance. Defaults to [setupCelebrationDuration];
  /// tests may pass a shorter value.
  final Duration autoAdvanceAfter;

  @override
  State<SetupCelebrationOverlay> createState() =>
      _SetupCelebrationOverlayState();
}

class _SetupCelebrationOverlayState extends State<SetupCelebrationOverlay>
    with TickerProviderStateMixin {
  /// Entrance timeline (1 s): circle spring 0-0.6, check draw
  /// 0.35-0.8, confetti burst 0.15-0.95, text fade 0.55-1.0.
  late final AnimationController _enterController;

  /// Radiating rings, one shot over the overlay's lifetime (2.2 s):
  /// two rings staggered so the second starts as the first fades.
  /// Deliberately NOT repeating — a looping controller would keep
  /// scheduling frames forever and widget tests could never settle
  /// while the overlay is up.
  late final AnimationController _ringsController;

  Timer? _autoAdvanceTimer;
  bool _finished = false;

  /// Confetti pieces, fixed at first build so the burst is stable
  /// across frames (seeded, deterministic).
  late final List<_ConfettiPiece> _pieces = _buildPieces();

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    _ringsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
    // Success chime (synthesized, same pattern as the splash
    // sounds — no audio asset, best-effort, silence on failure).
    SplashSound.celebration();
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

  static List<_ConfettiPiece> _buildPieces() {
    final random = math.Random(7);
    const colors = <Color>[_emerald, _lightEmerald, _gold, _deepEmerald];
    return List.generate(26, (_) {
      final angle = random.nextDouble() * 2 * math.pi;
      return _ConfettiPiece(
        angle: angle,
        distance: 78 + random.nextDouble() * 62,
        size: 5 + random.nextDouble() * 5,
        color: colors[random.nextInt(colors.length)],
        isCircle: random.nextBool(),
        spin: (random.nextDouble() - 0.5) * 4 * math.pi,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('setup-celebration-overlay'),
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
                    final circleScale = Curves.elasticOut.transform(
                      const Interval(0.0, 0.6).transform(t),
                    );
                    final checkProgress =
                        const Interval(0.35, 0.8).transform(t);
                    final confettiProgress = Curves.easeOut.transform(
                      const Interval(0.15, 0.95).transform(t),
                    );
                    final textOpacity =
                        const Interval(0.55, 1.0).transform(t);
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
                              CustomPaint(
                                size: const Size(280, 280),
                                painter: _ConfettiPainter(
                                  pieces: _pieces,
                                  progress: confettiProgress,
                                ),
                              ),
                              Transform.scale(
                                scale: math.max(circleScale, 0.0),
                                child: Container(
                                  width: 128,
                                  height: 128,
                                  decoration: BoxDecoration(
                                    color: _emerald,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: _emerald.withValues(
                                          alpha: 0.45,
                                        ),
                                        blurRadius: 32,
                                        spreadRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: CustomPaint(
                                    painter: _CheckmarkPainter(
                                      progress: checkProgress,
                                    ),
                                  ),
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
                            child: const Column(
                              children: [
                                Text(
                                  'Handa ka na!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Welcome to EstudyanteGO!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFBBF7D0),
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

/// Second overlay: asks whether the new user already knows the app.
///
/// "Yes, take me in" goes straight to the Student tab.
/// "No, show me how" goes to the Student tab and auto-starts the
/// Watch demo guided tour (Feature 3 — see the TOUR HOOK note on
/// [StudentTab]; this overlay only reports the choice, it never
/// builds the tour).
class SetupGuidePromptOverlay extends StatelessWidget {
  const SetupGuidePromptOverlay({
    super.key,
    required this.onTakeMeIn,
    required this.onShowMeHow,
  });

  /// "Yes, take me in" pressed: straight to the Student tab.
  final VoidCallback onTakeMeIn;

  /// "No, show me how" pressed: Student tab + auto-start the tour.
  final VoidCallback onShowMeHow;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('setup-guide-prompt-overlay'),
      backgroundColor: _overlayBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: _deepEmerald,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.explore,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'You know how to use the app?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Take the quick tour, or jump straight in.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFFBBF7D0),
                ),
              ),
              const SizedBox(height: 36),
              FilledButton(
                onPressed: onTakeMeIn,
                style: FilledButton.styleFrom(
                  backgroundColor: _emerald,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Yes, take me in',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onShowMeHow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: _emerald, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'No, show me how',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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

/// One confetti piece: bursts outward from the circle along [angle]
/// to [distance], spinning by [spin] radians, fading out.
class _ConfettiPiece {
  const _ConfettiPiece({
    required this.angle,
    required this.distance,
    required this.size,
    required this.color,
    required this.isCircle,
    required this.spin,
  });

  final double angle;
  final double distance;
  final double size;
  final Color color;
  final bool isCircle;
  final double spin;
}

/// White checkmark that draws in as [progress] goes 0 -> 1.
class _CheckmarkPainter extends CustomPainter {
  const _CheckmarkPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = Path()
      ..moveTo(size.width * 0.24, size.height * 0.54)
      ..lineTo(size.width * 0.44, size.height * 0.74)
      ..lineTo(size.width * 0.78, size.height * 0.30);
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 11
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final total = metrics.fold<double>(
      0,
      (sum, metric) => sum + metric.length,
    );
    var remaining = total * progress.clamp(0.0, 1.0);
    for (final metric in metrics) {
      if (remaining <= 0) break;
      final take = math.min(metric.length, remaining);
      canvas.drawPath(metric.extractPath(0, take), paint);
      remaining -= take;
    }
  }

  @override
  bool shouldRepaint(covariant _CheckmarkPainter oldDelegate) =>
      progress != oldDelegate.progress;
}

/// Expanding, fading rings around the circle. One entry per ring,
/// each a 0 -> 1 loop progress.
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

/// Confetti burst: pieces fly outward from the centre and fade.
class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.pieces, required this.progress});

  final List<_ConfettiPiece> pieces;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final opacity = (1 - progress).clamp(0.0, 1.0);
    for (final piece in pieces) {
      final distance = piece.distance * progress;
      final offset = center +
          Offset(
            math.cos(piece.angle) * distance,
            math.sin(piece.angle) * distance,
          );
      final paint = Paint()
        ..color = piece.color.withValues(alpha: opacity);
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.rotate(piece.spin * progress);
      if (piece.isCircle) {
        canvas.drawCircle(
          Offset.zero,
          piece.size / 2,
          paint,
        );
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: piece.size,
            height: piece.size * 0.6,
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      progress != oldDelegate.progress || pieces != oldDelegate.pieces;
}
