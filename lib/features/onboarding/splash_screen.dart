// EstudyanteGO splash screen.
//
// Modern Minimalist entry theme: solid themed background (no
// gradient), the existing EstudyanteGO logo asset + wordmark, the
// "Your Student Companion" tagline, and a subtle one-shot loading
// bar. The screen resolves the next destination (onboarding, sign-in,
// or dashboard) while it shows, waits for a short minimum display
// time so the brand moment reads, then waits for the user's tap
// ("I-tap para magsimula" — preview tap-to-start, Nov 6) and hands
// off exactly once via [onDestination]. The progress animation is
// finite (one 1.2s run), so widget tests can settle it.
//
// The splash follows the app's selected theme ([themeMode]) so there
// is no flash of the wrong theme at startup; it has no theme
// switcher of its own (the switcher lives on Welcome and the auth
// screens).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'entry_theme.dart';
import 'onboarding_state.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.resolve,
    required this.onDestination,
    this.themeMode = ThemeMode.system,
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _handedOff = false;

  /// True once the next destination is resolved AND the minimum
  /// brand moment has elapsed: the splash then waits for the tap
  /// instead of handing off on its own (preview tap-to-start,
  /// Nov 6 — "I-tap para magsimula").
  bool _ready = false;
  AppStartDestination? _destination;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _go();
  }

  Future<void> _go() async {
    final results = await Future.wait([
      widget.resolve(),
      Future<void>.delayed(const Duration(milliseconds: 1200)),
    ]);
    if (!mounted || _handedOff) return;
    setState(() {
      _destination = results.first as AppStartDestination;
      _ready = true;
    });
  }

  /// The tap that starts the app. Exactly once, like the old
  /// automatic handoff.
  void _start() {
    final destination = _destination;
    if (_handedOff || destination == null) return;
    _handedOff = true;
    widget.onDestination(destination);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = entryEffectiveBrightness(widget.themeMode, context);
    final colors = entryColorsFor(brightness);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: entryOverlayStyle(brightness),
      child: Theme(
        data: entryThemeData(brightness),
        child: Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        // Reduced motion: no scale-in, the logo
                        // simply appears.
                        final reduceMotion = MediaQuery.of(context)
                            .disableAnimations;
                        final scale = reduceMotion
                            ? 1.0
                            : 0.92 +
                                0.08 *
                                    _controller.value.clamp(0.0, 1.0);
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: Image.asset(
                        'assets/images/estudyantego_logo.png',
                        width: 120,
                        height: 120,
                      ),
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
                          const TextSpan(text: 'Estudyante'),
                          TextSpan(
                            text: 'GO',
                            style: TextStyle(color: colors.primary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your Student Companion',
                      style: TextStyle(
                        color: colors.secondaryText,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 48),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        return LinearProgressIndicator(
                          value: _controller.value.clamp(0.0, 1.0),
                          backgroundColor: colors.border,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colors.primary,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        return Text(
                          _ready
                              ? 'Ready'
                              : 'Naglo-load… ${(_controller.value * 100).round()}%',
                          style: TextStyle(
                            color: colors.secondaryText,
                            fontSize: 13,
                          ),
                        );
                      },
                    ),
                    // Tap-to-start (preview parity, Nov 6): the app
                    // waits here until the user taps — it never
                    // jumps ahead on its own.
                    if (_ready) ...[
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('splash-start'),
                        onPressed: _start,
                        child: const Text('I-tap para magsimula'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Buksan ang EstudyanteGO',
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
