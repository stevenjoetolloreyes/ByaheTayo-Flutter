// ByaheTayo splash screen.
//
// Deep emerald gradient, logo mark + wordmark, and a one-shot loading
// bar. The screen resolves the next destination (onboarding, sign-in,
// or dashboard) while it shows, waits for a short minimum display
// time so the brand moment reads, then hands off exactly once via
// [onDestination]. The progress animation is finite (one 1.2s run),
// so widget tests can settle it.
import 'package:flutter/material.dart';

import 'onboarding_state.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.resolve,
    required this.onDestination,
  });

  /// Decides where the app goes next (onboarding / sign-in /
  /// verification / profile setup / dashboard).
  final Future<AppStartDestination> Function() resolve;

  final ValueChanged<AppStartDestination> onDestination;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _handedOff = false;

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
    _handedOff = true;
    widget.onDestination(results.first as AppStartDestination);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF14532D), Color(0xFF16A34A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final scale =
                          0.92 + 0.08 * _controller.value.clamp(0.0, 1.0);
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.directions_bus,
                        color: Color(0xFF14532D),
                        size: 56,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'EstudyanteGO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Northern PH commute companion',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 48),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      return LinearProgressIndicator(
                        value: _controller.value.clamp(0.0, 1.0),
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Loading…',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
