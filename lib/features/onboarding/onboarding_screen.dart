// Welcome / onboarding: four swipeable Material 3 pages introducing
// the app, with Skip + Next controls. The last page offers Get Started
// (create an account) and Sign In. Skipping goes to Sign In — there is
// no guest path.
//
// Visual system (dark emerald): background #071714, primary green
// #00C987, accent #32D3A0, dark green #103B30, card #172923, primary
// text white, secondary text #A1A1AA. Branding uses the EstudyanteGO
// logo asset (the same transparent-corner E + boy artwork as the auth
// screens) — never the old "Byahe Tayo" name. Illustrations are built
// UI compositions (icons + shapes), never emoji. The fare illustration
// shows the peso SYMBOL only — never a specific amount, so no figure
// here can be mistaken for an official price.
//
// Navigation targets are preserved exactly: Get Started opens the
// existing registration flow, Sign In (and Skip, on every screen) opens
// the existing sign-in flow. The first-launch-only flag
// (byahetayo_onboarding_done) is owned by the gate, not this screen.
import 'package:flutter/material.dart';

const _bg = Color(0xFF071714);
const _green = Color(0xFF00C987);
const _accent = Color(0xFF32D3A0);
const _darkGreen = Color(0xFF103B30);
const _card = Color(0xFF172923);
const _secondary = Color(0xFFA1A1AA);

class _OnboardingPage {
  const _OnboardingPage({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
}

const _pages = <_OnboardingPage>[
  _OnboardingPage(
    title: 'Explore the map',
    description:
        'See hubs, routes, and places across Northern Luzon on a live map.',
  ),
  _OnboardingPage(
    title: 'Plan your trip',
    description:
        'Find jeepney and bus routes with directions, stops, and live tracking.',
  ),
  _OnboardingPage(
    title: 'Know your fare',
    description:
        'Compute LTFRB-based fares and check verified operator fares '
        'before you ride.',
  ),
  _OnboardingPage(
    title: 'Community updates',
    description:
        'Share local routes, report overpriced fares, and stay updated '
        'with fellow commuters.',
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onGetStarted,
    required this.onSignIn,
  });

  /// Get Started pressed: the gate marks onboarding done and opens
  /// account creation.
  final VoidCallback onGetStarted;

  /// Sign In pressed (or Skip, on any page): the gate marks onboarding
  /// done and opens sign-in.
  final VoidCallback onSignIn;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      widget.onGetStarted();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _green,
          secondary: _accent,
          surface: _card,
        ),
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _WavesPainter()),
              ),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header: brand left, Skip right, on every screen.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/images/estudyantego_logo.png',
                          width: 36,
                          height: 36,
                        ),
                        const SizedBox(width: 10),
                        const Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                                children: [
                                  TextSpan(text: 'Estudyante'),
                                  TextSpan(
                                    text: 'GO',
                                    style: TextStyle(color: _green),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: widget.onSignIn,
                          style: TextButton.styleFrom(
                            foregroundColor: _secondary,
                          ),
                          child: const Text('Skip'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _pages.length,
                      onPageChanged: (index) => setState(() => _index = index),
                      itemBuilder: (context, index) {
                        final page = _pages[index];
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            // Centered when the content fits, scrollable
                            // on small phones — never an overflow.
                            return SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                  ),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.0, end: 1.0),
                                    duration:
                                        const Duration(milliseconds: 400),
                                    curve: Curves.easeOut,
                                    builder: (context, value, _) {
                                      return Opacity(
                                        opacity: value,
                                        child: Transform.translate(
                                          offset: Offset(0, (1 - value) * 16),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Transform.scale(
                                                scale: 0.94 + 0.06 * value,
                                                child:
                                                    _illustrationFor(index),
                                              ),
                                              const SizedBox(height: 28),
                                              Text(
                                                page.title,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 24,
                                                  fontWeight:
                                                      FontWeight.w800,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                page.description,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  color: _secondary,
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
                          },
                        );
                      },
                    ),
                  ),
                  // Pagination: active = expanded green pill, inactive =
                  // small gray circles, smoothly animated.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _index ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? _green
                                : _secondary.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _isLast
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FilledButton(
                                onPressed: widget.onGetStarted,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: const StadiumBorder(),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                child: const Text('Get Started'),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: widget.onSignIn,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _green,
                                  side: const BorderSide(
                                    color: _green,
                                    width: 1.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: const StadiumBorder(),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                child: const Text('Sign In'),
                              ),
                            ],
                          )
                        : SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _next,
                              style: FilledButton.styleFrom(
                                backgroundColor: _green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text('Next'),
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _illustrationFor(int index) {
    switch (index) {
      case 0:
        return _mapIllustration();
      case 1:
        return _tripIllustration();
      case 2:
        return _fareIllustration();
      default:
        return _communityIllustration();
    }
  }

  /// Card shell shared by all four illustrations.
  Widget _illustrationCard({required Widget child}) {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: child,
      ),
    );
  }

  /// 1. Explore the map: folded-map motif, green location marker, bus
  /// icon center, church landmark, mountain, terminal/hub.
  Widget _mapIllustration() {
    return _illustrationCard(
      child: Stack(
        children: [
          // Fold lines.
          Positioned.fill(
            child: Row(
              children: [
                const Expanded(child: SizedBox()),
                Container(width: 1, color: Colors.white.withValues(alpha: 0.1)),
                const Expanded(child: SizedBox()),
                Container(width: 1, color: Colors.white.withValues(alpha: 0.1)),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
          // Dashed route across the lower half.
          const Positioned(
            left: 16,
            right: 16,
            bottom: 52,
            height: 40,
            child: CustomPaint(painter: _DashedLinePainter(_accent)),
          ),
          const Positioned(
            left: 20,
            top: 18,
            child: Icon(Icons.terrain, color: _accent, size: 30),
          ),
          const Positioned(
            right: 20,
            top: 16,
            child: Icon(Icons.location_on, color: _green, size: 38),
          ),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: _green,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          const Positioned(
            left: 24,
            bottom: 20,
            child: Icon(Icons.church, color: Colors.white70, size: 30),
          ),
          const Positioned(
            right: 24,
            bottom: 20,
            child: Icon(Icons.store, color: Colors.white70, size: 30),
          ),
        ],
      ),
    );
  }

  /// 2. Plan your trip: bus, dashed route path, stop dots, destination
  /// marker, navigation graphic.
  Widget _tripIllustration() {
    return _illustrationCard(
      child: Stack(
        children: [
          const Positioned(
            left: 16,
            right: 16,
            top: 88,
            height: 44,
            child: CustomPaint(painter: _DashedLinePainter(_accent)),
          ),
          const Positioned(
            right: 24,
            top: 20,
            child: Icon(Icons.near_me, color: _accent, size: 28),
          ),
          Positioned(
            left: 20,
            top: 84,
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: _green,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          // Stops along the route.
          Positioned(
            left: 96,
            top: 108,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.white54,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 96,
            top: 108,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.white54,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const Positioned(
            right: 20,
            top: 76,
            child: Icon(Icons.location_on, color: _green, size: 40),
          ),
          Positioned(
            left: 24,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _darkGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.route, color: _accent, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  /// 3. Know your fare: fare-estimate card motif, peso symbol, coins,
  /// calculator, green verification indicators. HARD RULE: no specific
  /// peso amount anywhere — the estimate slot is a blank bar, and the
  /// coins carry the peso symbol only, never a figure.
  Widget _fareIllustration() {
    return _illustrationCard(
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 170,
              height: 132,
              decoration: BoxDecoration(
                color: _darkGreen,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _accent.withValues(alpha: 0.25)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calculate, color: Colors.white70, size: 20),
                      SizedBox(width: 8),
                      Icon(Icons.verified, color: _green, size: 20),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '₱',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Estimate slot: blank bar, deliberately no digits.
                  Container(
                    width: 84,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Coins: peso symbol only, never an amount.
          Positioned(
            left: 22,
            top: 22,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _darkGreen,
                shape: BoxShape.circle,
                border: Border.all(color: _accent),
              ),
              child: const Center(
                child: Text(
                  '₱',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _accent,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 22,
            bottom: 22,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _darkGreen,
                shape: BoxShape.circle,
                border: Border.all(color: _accent),
              ),
              child: const Center(
                child: Text(
                  '₱',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _accent,
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            right: 24,
            top: 22,
            child: Icon(Icons.check_circle, color: _green, size: 26),
          ),
          const Positioned(
            left: 24,
            bottom: 22,
            child: Icon(Icons.verified, color: _accent, size: 26),
          ),
        ],
      ),
    );
  }

  /// 4. Community updates: smartphone with community posts, people
  /// icon, route update chip, fare-report notification.
  Widget _communityIllustration() {
    return _illustrationCard(
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 118,
              height: 184,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _darkGreen,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.24),
                ),
              ),
              child: Column(
                children: [
                  _postRow(),
                  const SizedBox(height: 14),
                  _postRow(),
                  const SizedBox(height: 14),
                  _postRow(),
                ],
              ),
            ),
          ),
          const Positioned(
            right: 22,
            top: 20,
            child: Icon(Icons.groups, color: _accent, size: 32),
          ),
          Positioned(
            left: 18,
            top: 84,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _darkGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.route, color: _green, size: 22),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 24,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _darkGreen,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: const Icon(Icons.flag, color: _accent, size: 18),
                ),
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: _bg, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Positioned(
            left: 20,
            bottom: 28,
            child: Icon(Icons.notifications, color: Colors.white70, size: 24),
          ),
        ],
      ),
    );
  }

  /// One community-post row inside the phone: avatar dot + two bars.
  Widget _postRow() {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 8,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 5),
              Container(
                height: 8,
                width: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Subtle emerald waves along the top and bottom edges.
class _WavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final top = Paint()
      ..color = _green.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final topPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.10)
      ..quadraticBezierTo(
        size.width * 0.6,
        size.height * 0.18,
        0,
        size.height * 0.08,
      )
      ..close();
    canvas.drawPath(topPath, top);

    final bottom = Paint()
      ..color = _green.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;
    final bottomPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, size.height * 0.92)
      ..quadraticBezierTo(
        size.width * 0.4,
        size.height * 0.84,
        0,
        size.height * 0.94,
      )
      ..close();
    canvas.drawPath(bottomPath, bottom);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A dashed curved line, used as the route path in the map and trip
/// illustrations.
class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.5)
      ..cubicTo(
        size.width * 0.3,
        size.height * 0.1,
        size.width * 0.6,
        size.height * 0.9,
        size.width,
        size.height * 0.5,
      );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 10), paint);
        distance += 18;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
