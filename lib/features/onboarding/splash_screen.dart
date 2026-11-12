// EstudyanteGO splash screen — anime intro (Nov 7).
//
// A faithful port of the Claude HTML splash (EstudyanteGO__1__3_cn09.html),
// adapted to the real app's emerald palette and real brand assets:
// same sequence — white flash + speed-lines burst + opening
// jingle; logo zoom 3.4 -> 0.9 -> 1.08 -> 0.97 -> 1.0 with blur;
// impact shake (visual only since Feature 6); tagline
// "Kasama mo sa araw-araw na eskwela"; loading bar 2 s with a tick
// each 25%; "Handa na!" at 100%; fade out ~4.9 s — then
// the splash hands off on its own. NO tap-to-start (the HTML's start
// overlay existed only for web audio autoplay policy; native audio
// plays without it, so it is not ported). The HTML's 4-tab mini app
// shell is not ported either — this file is the splash only.
//
// Adaptations (per the brief, not improvisation):
// - Palette: emerald (#0c1410 / #16a34a / #34d399) instead of the
//   spec's navy / yellow / teal. Speed-lines and road dashes use the
//   accent #34d399 (brand #16a34a in light mode); the bar gradient is
//   accent -> brand.
// - Brand: the real E logo asset + the real "EstudyanteGO" wordmark
//   (Estudyante + green GO), NOT the spec's "Estudyante + GO badge".
//   The logo + wordmark zoom as one brand block.
// - Tagline "Kasama mo sa araw-araw na eskwela" replaces
//   "Your Student Companion".
// - No mascot (it was main-app-only in the HTML).
// - Sounds are synthesized in Dart (splash_sound.dart) — no audio
//   files. Best-effort: visuals never depend on audio. The
//   Minecraft theme (Feature 6) plays a blocky opening jingle on
//   app open, replacing the old whoosh + impact sting; the loading
//   ticks are unchanged.
// - The ROAD motif is included (bottom strip + animated dashed line,
//   1.1 s loop), adapted to emerald.
//
// Timing is driven by ONE master controller (4650 ms) so the whole
// intro is a single finite timeline: every phase is an interval of
// it, and the road's drive phase derives from it too. That keeps
// widget tests able to settle it (no infinite animation runs while
// the splash is up). The exit fade is a separate 250 ms controller
// started once the destination is resolved, so a slow resolve holds
// the splash on "Handa na!" instead of fading to a blank screen.
//
// Reduced motion (MediaQuery.disableAnimations): the flourishes
// (flash, speed-lines, zoom, shake, fades) render at their end state
// and the road stands still; the loading timing and handoff are
// unchanged, matching the reference's reduced-motion behavior.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diagnostics/diagnostics.dart';
import 'entry_theme.dart';
import 'onboarding_state.dart';
import 'splash_sound.dart';

import '../minecraft_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.resolve,
    required this.onDestination,
    this.themeMode = ThemeMode.dark,
  });

  /// Decides where the app goes next (onboarding / sign-in /
  /// verification / profile setup / dashboard).
  final Future<AppStartDestination> Function() resolve;

  final ValueChanged<AppStartDestination> onDestination;

  /// Selected theme (from the app shell, already loaded from prefs
  /// before runApp, so the splash never flashes the wrong theme).
  final ThemeMode themeMode;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// The whole intro: loading completes at 4650 ms ("Handa na!").
  static const int _totalMs = 4650;

  /// Exit fade after the destination is resolved.
  static const int _fadeMs = 250;

  /// Master timeline for the intro.
  late final AnimationController _sequence;

  /// Exit fade, started once resolve + sequence are both done.
  late final AnimationController _fade;

  bool _handedOff = false;
  AppStartDestination? _destination;

  int _lastTickBucket = -1;

  @override
  void initState() {
    super.initState();
    _sequence = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _totalMs),
    )..addListener(_onSequenceTick);
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _fadeMs),
    );
    // Splash stage start (recorded, never blocking, never throwing).
    ErrorLogService.instance.record(
      category: ErrorCategory.startup,
      message: 'Splash init.',
      startupStage: StartupStage.splash.name,
      severity: ErrorSeverity.info,
    );
    SplashSound.openingJingle();
    _runSequence();
    _go();
  }

  Future<void> _runSequence() async {
    try {
      await _sequence.forward();
    } catch (_) {
      // Disposed mid-sequence: the splash is gone, nothing to do.
    }
  }

  /// Fires the timeline sounds: a tick at each 25% of the loading
  /// bar (700 / 760 / 820 / 880 Hz). The opening jingle already
  /// played in initState (Feature 6, replacing the old whoosh +
  /// impact sting at 1550 ms); the shake at 1550 ms is visual
  /// only now.
  void _onSequenceTick() {
    final elapsed = _sequence.value * _totalMs;
    final progress = ((elapsed - 2650) / 2000).clamp(0.0, 1.0);
    final bucket = (progress * 4).floor();
    if (bucket != _lastTickBucket && progress < 1.0) {
      _lastTickBucket = bucket;
      SplashSound.tick(700 + bucket * 60);
    }
  }

  Future<void> _go() async {
    // Previously unguarded: a resolve() throw left the splash frozen
    // forever (no handoff, no error shown). Now the failure is
    // recorded and the app falls back to onboarding — the safe
    // first-launch destination — instead of freezing. Onboarding
    // progress in prefs is never cleared by this fallback.
    AppStartDestination destination;
    try {
      final results = await Future.wait([
        widget.resolve(),
        Future<void>.delayed(const Duration(milliseconds: _totalMs)),
      ]);
      destination = results.first as AppStartDestination;
    } catch (error, stack) {
      try {
        await ErrorLogService.instance.record(
          category: ErrorCategory.startup,
          message: 'Splash resolve failed, falling back to onboarding: $error',
          stackTrace: stack.toString(),
          startupStage: StartupStage.splash.name,
          severity: ErrorSeverity.error,
        );
      } catch (_) {
        // Diagnostics failure must never block the fallback.
      }
      await Future<void>.delayed(const Duration(milliseconds: _totalMs));
      destination = AppStartDestination.onboarding;
    }
    if (!mounted || _handedOff) return;
    _destination = destination;
    try {
      await _fade.forward();
    } catch (_) {
      // Disposed mid-fade: the splash is gone, nothing to do.
    }
    if (!mounted || _handedOff) return;
    await _start();
  }

  /// Hands the app off to the resolved destination. Exactly once.
  Future<void> _start() async {
    final destination = _destination;
    if (_handedOff || destination == null) return;
    _handedOff = true;
    try {
      await ErrorLogService.instance.record(
        category: ErrorCategory.startup,
        message: 'Splash completed, destination: ${destination.name}.',
        startupStage: StartupStage.splash.name,
        severity: ErrorSeverity.info,
      );
    } catch (_) {
      // Diagnostics failure must never block the handoff.
    }
    widget.onDestination(destination);
  }

  @override
  void dispose() {
    _sequence.removeListener(_onSequenceTick);
    _sequence.dispose();
    _fade.dispose();
    super.dispose();
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Progress of [startMs]..[endMs] within the master timeline,
  /// warped by [curve], clamped to 0..1.
  double _phase(double elapsedMs, double startMs, double endMs,
      [Curve curve = Curves.linear]) {
    final p = ((elapsedMs - startMs) / (endMs - startMs)).clamp(0.0, 1.0);
    return curve.transform(p);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final brightness = entryEffectiveBrightness(widget.themeMode, context);
    final colors = entryColorsFor(brightness);
    final size = MediaQuery.sizeOf(context);
    final isDark = brightness == Brightness.dark;
    // Emerald adaptations of the spec's yellow / teal accents.
    final accent = isDark
        ? MinecraftColors.emerald
        : MinecraftColors.grassGreen;
    final roadBase =
        Color.lerp(colors.background, colors.primary, 0.08) ??
            colors.background;
    final glowCenter =
        Color.lerp(colors.background, colors.primary, 0.15) ??
            colors.background;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: entryOverlayStyle(brightness),
      child: Theme(
        data: entryThemeData(brightness),
        child: Scaffold(
          backgroundColor: colors.background,
          body: AnimatedBuilder(
            animation: Listenable.merge([_sequence, _fade]),
            builder: (context, _) {
              final elapsed = _sequence.value * _totalMs;

              // Flash: white 1 -> 0 over 0.35 s, ease-out.
              final flash = reduceMotion
                  ? 0.0
                  : 1.0 - _phase(elapsed, 0, 350, Curves.easeOut);

              // Speed-lines burst (0.05–1.05 s): scale .3 -> 2.4,
              // rotate 0 -> 10 deg, opacity 0 -> .85 (12%) -> .35
              // (55%) -> 0.
              final speedP = reduceMotion
                  ? 1.0
                  : _phase(elapsed, 50, 1050, Curves.easeOut);
              final speedScale = _lerp(0.3, 2.4, speedP);
              final speedRotate = speedP * 10 * math.pi / 180;
              final double speedOpacity;
              if (reduceMotion) {
                speedOpacity = 0.0;
              } else if (speedP < 0.12) {
                speedOpacity = 0.85 * speedP / 0.12;
              } else if (speedP < 0.55) {
                speedOpacity =
                    0.85 - 0.5 * (speedP - 0.12) / (0.55 - 0.12);
              } else {
                speedOpacity = 0.35 * (1 - (speedP - 0.55) / 0.45);
              }

              // Logo zoom (0.45–1.55 s): scale 3.4 -> .9 -> 1.08 ->
              // .97 -> 1.0, opacity 0 -> 1 by 55%, blur 16 -> 0 by
              // 55%. Timing: cubic-bezier(.17,.89,.32,1.28).
              const zoomCurve = Cubic(0.17, 0.89, 0.32, 1.28);
              final zoomP = reduceMotion
                  ? 1.0
                  : _phase(elapsed, 450, 1550, zoomCurve);
              final double zoomScale;
              final double zoomOpacity;
              final double zoomBlur;
              if (zoomP < 0.55) {
                final k = zoomP / 0.55;
                zoomScale = _lerp(3.4, 0.9, k);
                zoomOpacity = k;
                zoomBlur = 16 * (1 - k);
              } else if (zoomP < 0.72) {
                zoomScale = _lerp(0.9, 1.08, (zoomP - 0.55) / 0.17);
                zoomOpacity = 1.0;
                zoomBlur = 0.0;
              } else if (zoomP < 0.86) {
                zoomScale = _lerp(1.08, 0.97, (zoomP - 0.72) / 0.14);
                zoomOpacity = 1.0;
                zoomBlur = 0.0;
              } else {
                zoomScale = _lerp(0.97, 1.0, (zoomP - 0.86) / 0.14);
                zoomOpacity = 1.0;
                zoomBlur = 0.0;
              }

              // Impact shake (1.55–1.90 s) on the whole content.
              final shakeP = reduceMotion
                  ? 1.0
                  : _phase(elapsed, 1550, 1900, Curves.ease);
              const shakeStops = [
                Offset(0, 0),
                Offset(-7, 2),
                Offset(6, -3),
                Offset(-5, 0),
                Offset(3, 2),
                Offset(0, 0),
              ];
              final shakeIndex = (shakeP * 5).floor().clamp(0, 4);
              final shakeFrac = (shakeP * 5) - shakeIndex;
              final shakeOffset = Offset(
                _lerp(shakeStops[shakeIndex].dx, shakeStops[shakeIndex + 1].dx,
                    shakeFrac),
                _lerp(shakeStops[shakeIndex].dy, shakeStops[shakeIndex + 1].dy,
                    shakeFrac),
              );

              // Tagline fade-up (2.05–2.55 s).
              final tagP = reduceMotion
                  ? 1.0
                  : _phase(elapsed, 2050, 2550, Curves.ease);
              final taglineOpacity = tagP;
              final taglineDy = 10 * (1 - tagP);

              // Loading wrap fades in from 2.65 s; the bar fills
              // 0 -> 100% over 2 s (2.65–4.65 s).
              final loadOpacity = reduceMotion
                  ? 1.0
                  : _phase(elapsed, 2650, 3050, Curves.ease);
              final loadProgress =
                  ((elapsed - 2650) / 2000).clamp(0.0, 1.0);
              final loadDone = loadProgress >= 1.0;

              // Road drive phase: 1.1 s loop, derived from the master
              // timeline (no infinite controller, so tests can settle).
              final roadPhase = reduceMotion
                  ? 0.0
                  : (elapsed % 1100) / 1100;

              return Opacity(
                opacity: 1.0 - _fade.value,
                child: ClipRect(
                  child: Stack(
                    children: [
                      // Stage: subtle emerald radial glow, like the
                      // reference's navy radial.
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0, -0.7),
                              radius: 1.2,
                              colors: [glowCenter, colors.background],
                            ),
                          ),
                        ),
                      ),
                      // ROAD motif: bottom strip + animated dashed line.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: -size.height * 0.10,
                        height: size.height * 0.46,
                        child: Container(
                          decoration: BoxDecoration(
                            color: roadBase,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.35),
                              ],
                            ),
                            border: Border(
                              top: BorderSide(
                                color: Colors.white.withOpacity(0.06),
                                width: 2,
                              ),
                            ),
                          ),
                          child: CustomPaint(
                            painter: _RoadDashesPainter(
                              phase: roadPhase,
                              color: accent.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
                      // Speed-lines burst.
                      if (speedOpacity > 0)
                        Positioned.fill(
                          child: Opacity(
                            opacity: speedOpacity,
                            child: Transform.scale(
                              scale: speedScale,
                              child: Transform.rotate(
                                angle: speedRotate,
                                child: CustomPaint(
                                  painter: _SpeedlinesPainter(
                                    color: accent.withOpacity(0.35),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Content: brand block, tagline, loading bar.
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Transform.translate(
                            offset: shakeOffset,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Transform.scale(
                                  scale: zoomScale,
                                  child: Opacity(
                                    opacity: zoomOpacity,
                                    child: ImageFiltered(
                                      imageFilter: ui.ImageFilter.blur(
                                        sigmaX: zoomBlur,
                                        sigmaY: zoomBlur,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Image.asset(
                                            'assets/images/estudyantego_logo.png',
                                            width: 120,
                                            height: 120,
                                          ),
                                          const SizedBox(height: 20),
                                          Text.rich(
                                            TextSpan(
                                              style: TextStyle(
                                                fontSize: 30,
                                                fontWeight: FontWeight.w800,
                                                color: colors.primaryText,
                                              ),
                                              children: [
                                                const TextSpan(
                                                  text: 'Estudyante',
                                                ),
                                                TextSpan(
                                                  text: 'GO',
                                                  style: TextStyle(
                                                    color: colors.primary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Opacity(
                                  opacity: taglineOpacity,
                                  child: Transform.translate(
                                    offset: Offset(0, taglineDy),
                                    child: Text(
                                      'Kasama mo sa araw-araw na eskwela',
                                      style: TextStyle(
                                        color: colors.secondaryText,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 48),
                                Opacity(
                                  opacity: loadOpacity,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      LinearProgressIndicator(
                                        value: loadProgress,
                                        backgroundColor: colors.border,
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                          MinecraftColors.emerald,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            loadDone
                                                ? 'Handa na!'
                                                : 'Naglo-load…',
                                            style: TextStyle(
                                              color: colors.secondaryText,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            '${(loadProgress * 100).round()}%',
                                            style: TextStyle(
                                              color: colors.secondaryText,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // White flash at the very start.
                      if (flash > 0)
                        Positioned.fill(
                          child: Opacity(
                            opacity: flash,
                            child: Container(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Speed-lines burst: 26 wedges (2 deg every 14 deg) radiating from
/// the center — the reference's repeating conic gradient.
class _SpeedlinesPainter extends CustomPainter {
  const _SpeedlinesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.max(size.width, size.height) * 0.75;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (var i = 0; i < 26; i++) {
      final start = i * 14 * math.pi / 180;
      final sweep = 2 * math.pi / 180;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          start,
          sweep,
          false,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SpeedlinesPainter old) => old.color != color;
}

/// Road dashes: 28 px dash / 28 px gap, 4 px tall, 18 px from the
/// road's top edge, sliding left by [phase] of one 56 px period.
class _RoadDashesPainter extends CustomPainter {
  const _RoadDashesPainter({required this.phase, required this.color});

  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    var x = -56 * phase;
    while (x < size.width) {
      canvas.drawRect(Rect.fromLTWH(x, 18, 28, 4), paint);
      x += 56;
    }
  }

  @override
  bool shouldRepaint(_RoadDashesPainter old) =>
      old.phase != phase || old.color != color;
}
