// Welcome / onboarding: four swipeable Modern Minimalist pages
// introducing the app, with Skip + Next controls. The last page IS
// the welcome state: it offers Get Started (create an account) and
// Sign In, plus the Light/Dark theme toggle (the spec's welcome
// screen is not a separate route — onboarding-4 already is it, and a
// duplicate welcome route would break the gate's first-launch flow).
// Skipping goes to Sign In — there is no guest path.
//
// Visual system: the shared entry theme (light #F8FAFC / dark
// #101816 backgrounds, emerald primaries), solid colors, no gradients
// or oversized decorative shapes. Branding uses the EstudyanteGO logo
// asset — never the old "Byahe Tayo" name. Illustrations are built UI
// compositions (icons + shapes), never emoji. The fare illustration
// shows the peso SYMBOL only — never a specific amount, so no figure
// here can be mistaken for an official price.
//
// Navigation targets are preserved exactly: Get Started opens the
// existing registration flow, Sign In (and Skip, on every screen)
// opens the existing sign-in flow. The first-launch-only flag
// (byahetayo_onboarding_done) is owned by the gate, not this screen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'entry_theme.dart';

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
    title: 'Explore the Map',
    description:
        'See hubs, routes, and places across Northern Luzon on a live map.',
  ),
  _OnboardingPage(
    title: 'Plan Your Trip',
    description:
        'Find jeepney and bus routes with directions, stops, and live tracking.',
  ),
  _OnboardingPage(
    title: 'Know Your Fare',
    description:
        'Compute LTFRB-based fares and check verified operator fares '
        'before you ride.',
  ),
  _OnboardingPage(
    title: 'Community Updates',
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
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.initialPage = 0,
  });

  /// Get Started pressed: the gate marks onboarding done and opens
  /// account creation.
  final VoidCallback onGetStarted;

  /// Sign In pressed (or Skip, on any page): the gate marks onboarding
  /// done and opens sign-in.
  final VoidCallback onSignIn;

  /// Selected theme, from the app shell.
  final ThemeMode themeMode;

  /// When non-null, the welcome state (last page) shows the
  /// Light/Dark toggle. Null hides it (e.g. screens constructed
  /// without a theme callback).
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  /// Page to start on. The gate passes the last page when the user
  /// comes back from auth via the back button, so Back lands on the
  /// welcome state instead of restarting the tour.
  final int initialPage;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _controller;
  late int _index;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void initState() {
    super.initState();
    _index = widget.initialPage.clamp(0, _pages.length - 1);
    _controller = PageController(initialPage: _index);
  }

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
    final brightness = entryEffectiveBrightness(widget.themeMode, context);
    final colors = entryColorsFor(brightness);
    final onThemeModeChanged = widget.onThemeModeChanged;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: entryOverlayStyle(brightness),
      child: Theme(
        data: entryThemeData(brightness),
        child: Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header: brand left, theme toggle (welcome state
                // only) + Skip right, on every screen.
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
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text.rich(
                            TextSpan(
                              style: TextStyle(
                                fontSize: 17,
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
                        ),
                      ),
                      const Spacer(),
                      if (_isLast && onThemeModeChanged != null)
                        ThemeModeToggle(
                          mode: widget.themeMode,
                          onModeChanged: onThemeModeChanged,
                        ),
                      TextButton(
                        onPressed: widget.onSignIn,
                        style: TextButton.styleFrom(
                          foregroundColor: colors.secondaryText,
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
                                              child: _illustrationFor(
                                                index,
                                                colors,
                                              ),
                                            ),
                                            const SizedBox(height: 28),
                                            Text(
                                              page.title,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 26,
                                                fontWeight:
                                                    FontWeight.w800,
                                                color: colors.primaryText,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              page.description,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 15,
                                                color: colors.secondaryText,
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
                // Pagination: active = expanded primary pill, inactive =
                // small muted circles, smoothly animated.
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
                              ? colors.primary
                              : colors.secondaryText
                                  .withValues(alpha: 0.5),
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
                              child: const Text('Get Started'),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: widget.onSignIn,
                              child: const Text('Sign In'),
                            ),
                          ],
                        )
                      : SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _next,
                            child: const Text('Next'),
                          ),
                        ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _illustrationFor(int index, EntryColors colors) {
    switch (index) {
      case 0:
        return _mapIllustration(colors);
      case 1:
        return _tripIllustration(colors);
      case 2:
        return _fareIllustration(colors);
      default:
        return _communityIllustration(colors);
    }
  }

  /// Card shell shared by all four illustrations: surface + border,
  /// 20dp corners, no shadow.
  Widget _illustrationCard(EntryColors colors, {required Widget child}) {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: child,
      ),
    );
  }

  /// 1. Explore the Map: folded-map motif, primary location marker,
  /// bus icon center, church landmark, mountain, terminal/hub.
  Widget _mapIllustration(EntryColors colors) {
    final faint = colors.primaryText.withValues(alpha: 0.1);
    return _illustrationCard(
      colors,
      child: Stack(
        children: [
          // Fold lines.
          Positioned.fill(
            child: Row(
              children: [
                const Expanded(child: SizedBox()),
                Container(width: 1, color: faint),
                const Expanded(child: SizedBox()),
                Container(width: 1, color: faint),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
          // Dashed route across the lower half.
          Positioned(
            left: 16,
            right: 16,
            bottom: 52,
            height: 40,
            child: CustomPaint(painter: _DashedLinePainter(colors.primary)),
          ),
          Positioned(
            left: 20,
            top: 18,
            child: Icon(Icons.terrain, color: colors.primary, size: 30),
          ),
          Positioned(
            right: 20,
            top: 16,
            child: Icon(Icons.location_on, color: colors.primary, size: 38),
          ),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.directions_bus,
                color: colors.onPrimary,
                size: 36,
              ),
            ),
          ),
          Positioned(
            left: 24,
            bottom: 20,
            child: Icon(Icons.church, color: colors.secondaryText, size: 30),
          ),
          Positioned(
            right: 24,
            bottom: 20,
            child: Icon(Icons.store, color: colors.secondaryText, size: 30),
          ),
        ],
      ),
    );
  }

  /// 2. Plan Your Trip: bus, dashed route path, stop dots, destination
  /// marker, navigation graphic.
  Widget _tripIllustration(EntryColors colors) {
    return _illustrationCard(
      colors,
      child: Stack(
        children: [
          Positioned(
            left: 16,
            right: 16,
            top: 88,
            height: 44,
            child: CustomPaint(painter: _DashedLinePainter(colors.primary)),
          ),
          Positioned(
            right: 24,
            top: 20,
            child: Icon(Icons.near_me, color: colors.primary, size: 28),
          ),
          Positioned(
            left: 20,
            top: 84,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.directions_bus,
                color: colors.onPrimary,
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
              decoration: BoxDecoration(
                color: colors.secondaryText,
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
              decoration: BoxDecoration(
                color: colors.secondaryText,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 20,
            top: 76,
            child: Icon(Icons.location_on, color: colors.primary, size: 40),
          ),
          Positioned(
            left: 24,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.secondarySurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.route, color: colors.primary, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  /// 3. Know Your Fare: fare-estimate card motif, peso symbol, coins,
  /// calculator, primary verification indicators. HARD RULE: no
  /// specific peso amount anywhere — the estimate slot is a blank
  /// bar, and the coins carry the peso symbol only, never a figure.
  Widget _fareIllustration(EntryColors colors) {
    return _illustrationCard(
      colors,
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 170,
              height: 132,
              decoration: BoxDecoration(
                color: colors.secondarySurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calculate,
                        color: colors.secondaryText,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.verified, color: colors.primary, size: 20),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '₱',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Estimate slot: blank bar, deliberately no digits.
                  Container(
                    width: 84,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.secondaryText.withValues(alpha: 0.4),
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
                color: colors.secondarySurface,
                shape: BoxShape.circle,
                border: Border.all(color: colors.primary),
              ),
              child: Center(
                child: Text(
                  '₱',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.primary,
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
                color: colors.secondarySurface,
                shape: BoxShape.circle,
                border: Border.all(color: colors.primary),
              ),
              child: Center(
                child: Text(
                  '₱',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 24,
            top: 22,
            child: Icon(Icons.check_circle, color: colors.primary, size: 26),
          ),
          Positioned(
            left: 24,
            bottom: 22,
            child: Icon(Icons.verified, color: colors.primary, size: 26),
          ),
        ],
      ),
    );
  }

  /// 4. Community Updates: smartphone with community posts, people
  /// icon, route update chip, fare-report notification.
  Widget _communityIllustration(EntryColors colors) {
    return _illustrationCard(
      colors,
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 118,
              height: 184,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.secondarySurface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                  _postRow(colors),
                  const SizedBox(height: 14),
                  _postRow(colors),
                  const SizedBox(height: 14),
                  _postRow(colors),
                ],
              ),
            ),
          ),
          Positioned(
            right: 22,
            top: 20,
            child: Icon(Icons.groups, color: colors.primary, size: 32),
          ),
          Positioned(
            left: 18,
            top: 84,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.secondarySurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.route, color: colors.primary, size: 22),
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
                    color: colors.secondarySurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(Icons.flag, color: colors.primary, size: 18),
                ),
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            bottom: 28,
            child: Icon(
              Icons.notifications,
              color: colors.secondaryText,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  /// One community-post row inside the phone: avatar dot + two bars.
  Widget _postRow(EntryColors colors) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.35),
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
                  color: colors.secondaryText.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 5),
              Container(
                height: 8,
                width: 44,
                decoration: BoxDecoration(
                  color: colors.secondaryText.withValues(alpha: 0.25),
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
