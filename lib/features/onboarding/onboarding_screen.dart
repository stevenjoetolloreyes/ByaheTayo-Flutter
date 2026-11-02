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
// Layout system (refinement): every page shares ONE illustration
// frame sized from the available page height (55% of it, clamped to
// 240–400dp), and every illustration is drawn on the same 320x300
// logical canvas scaled into that frame — so all four pages render
// at exactly the same size and swiping never jumps. The page content
// spreads evenly (illustration upper-middle, title + description
// below, controls pinned at the bottom), so tall phones get balanced
// breathing room instead of one big empty band, and the whole page
// scrolls instead of overflowing on small phones.
//
// Navigation targets are preserved exactly: Get Started opens the
// existing registration flow, Sign In (and Skip, on every screen)
// opens the existing sign-in flow. The first-launch-only flag
// (byahetayo_onboarding_done) is owned by the gate, not this screen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_layout.dart';
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
                          // ONE illustration frame on every page,
                          // sized from the available page height: it
                          // grows on tall phones, shrinks on small
                          // ones, and never changes size between
                          // pages — so swiping never jumps. The page
                          // stays scrollable on small phones, never
                          // an overflow.
                          final frameHeight =
                              (constraints.maxHeight * 0.55)
                                  .clamp(240.0, 400.0)
                                  .toDouble();
                          return SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s24),
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
                                          // Evenly spread: the free
                                          // space splits above the
                                          // illustration, between
                                          // illustration and text,
                                          // and below the text — so
                                          // tall phones get balanced
                                          // breathing room instead of
                                          // one big empty band, and
                                          // small phones stay compact.
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceEvenly,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            // Shared frame: same size
                                            // on every page. The
                                            // 320x300 illustration
                                            // canvas scales into it
                                            // (contain), so motifs
                                            // render large without
                                            // ever overflowing.
                                            SizedBox(
                                              height: frameHeight,
                                              width: double.infinity,
                                              child: FittedBox(
                                                fit: BoxFit.contain,
                                                child: SizedBox(
                                                  width: 320,
                                                  height: 300,
                                                  child: _illustrationFor(
                                                    index,
                                                    colors,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            ConstrainedBox(
                                              constraints:
                                                  const BoxConstraints(
                                                maxWidth: 360,
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    page.title,
                                                    textAlign:
                                                        TextAlign.center,
                                                    style: AppText.titleLarge.copyWith(color: colors.primaryText),
                                                  ),
                                                  const SizedBox(height: AppSpacing.s12),
                                                  Text(
                                                    page.description,
                                                    textAlign:
                                                        TextAlign.center,
                                                    style: AppText.bodyRelaxed.copyWith(color: colors.secondaryText),
                                                  ),
                                                ],
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
                const SizedBox(height: AppSpacing.s20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s24),
                  child: _isLast
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton(
                              onPressed: widget.onGetStarted,
                              child: const Text('Get Started'),
                            ),
                            const SizedBox(height: AppSpacing.s12),
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

  /// One consistent illustration canvas for all four pages. The
  /// caller places this in a fixed 320x300 box and scales it into the
  /// shared responsive frame, so every page renders at exactly the
  /// same size — swiping never jumps. No card shell: the mockup's
  /// illustrations sit directly on the themed background. All four
  /// keep the same motifs as before, redrawn larger to fill the
  /// canvas. Built UI only — no image assets.
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

  /// 1. Explore the Map: folded-map motif, primary location marker,
  /// bus icon center, church landmark, mountain, terminal/hub.
  Widget _mapIllustration(EntryColors colors) {
    final faint = colors.primaryText.withValues(alpha: 0.1);
    return Stack(
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
          left: 24,
          right: 24,
          bottom: 78,
          height: 52,
          child: CustomPaint(painter: _DashedLinePainter(colors.primary)),
        ),
        Positioned(
          left: 30,
          top: 26,
          child: Icon(Icons.terrain, color: colors.primary, size: 38),
        ),
        Positioned(
          right: 30,
          top: 24,
          child: Icon(Icons.location_on, color: colors.primary, size: 48),
        ),
        Center(
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.directions_bus,
              color: colors.onPrimary,
              size: 46,
            ),
          ),
        ),
        Positioned(
          left: 34,
          bottom: 30,
          child: Icon(Icons.church, color: colors.secondaryText, size: 38),
        ),
        Positioned(
          right: 34,
          bottom: 30,
          child: Icon(Icons.store, color: colors.secondaryText, size: 38),
        ),
      ],
    );
  }

  /// 2. Plan Your Trip: bus, dashed route path, stop dots, destination
  /// marker, navigation graphic.
  Widget _tripIllustration(EntryColors colors) {
    return Stack(
      children: [
        Positioned(
          left: 24,
          right: 24,
          top: 150,
          height: 56,
          child: CustomPaint(painter: _DashedLinePainter(colors.primary)),
        ),
        Positioned(
          right: 30,
          top: 26,
          child: Icon(Icons.near_me, color: colors.primary, size: 34),
        ),
        Positioned(
          left: 30,
          top: 132,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.directions_bus,
              color: colors.onPrimary,
              size: 38,
            ),
          ),
        ),
        // Stops along the route.
        Positioned(
          left: 138,
          top: 176,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: colors.secondaryText,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          right: 138,
          top: 176,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: colors.secondaryText,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          right: 28,
          top: 126,
          child: Icon(Icons.location_on, color: colors.primary, size: 52),
        ),
        Positioned(
          left: 30,
          bottom: 28,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.secondarySurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.route, color: colors.primary, size: 28),
          ),
        ),
      ],
    );
  }

  /// 3. Know Your Fare: fare-estimate card motif, peso symbol, coins,
  /// calculator, primary verification indicators. HARD RULE: no
  /// specific peso amount anywhere — the estimate slot is a blank
  /// bar, and the coins carry the peso symbol only, never a figure.
  Widget _fareIllustration(EntryColors colors) {
    return Stack(
      children: [
        Center(
          child: Container(
            width: 200,
            height: 172,
            decoration: BoxDecoration(
              color: colors.secondarySurface,
              borderRadius: BorderRadius.circular(22),
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
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.verified, color: colors.primary, size: 24),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '₱',
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w800,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 14),
                // Estimate slot: blank bar, deliberately no digits.
                Container(
                  width: 96,
                  height: 9,
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
          left: 26,
          top: 26,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.secondarySurface,
              shape: BoxShape.circle,
              border: Border.all(color: colors.primary),
            ),
            child: Center(
              child: Text(
                '₱',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 26,
          bottom: 26,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.secondarySurface,
              shape: BoxShape.circle,
              border: Border.all(color: colors.primary),
            ),
            child: Center(
              child: Text(
                '₱',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 28,
          top: 26,
          child: Icon(Icons.check_circle, color: colors.primary, size: 32),
        ),
        Positioned(
          left: 28,
          bottom: 26,
          child: Icon(Icons.verified, color: colors.primary, size: 32),
        ),
      ],
    );
  }

  /// 4. Community Updates: smartphone with community posts, people
  /// icon, route update chip, fare-report notification.
  Widget _communityIllustration(EntryColors colors) {
    return Stack(
      children: [
        Center(
          child: Container(
            width: 142,
            height: 232,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.secondarySurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                _postRow(colors),
                const SizedBox(height: 16),
                _postRow(colors),
                const SizedBox(height: 16),
                _postRow(colors),
              ],
            ),
          ),
        ),
        Positioned(
          right: 26,
          top: 24,
          child: Icon(Icons.groups, color: colors.primary, size: 38),
        ),
        Positioned(
          left: 22,
          top: 112,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.secondarySurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.route, color: colors.primary, size: 26),
          ),
        ),
        Positioned(
          right: 22,
          bottom: 28,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.secondarySurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                ),
                child: Icon(Icons.flag, color: colors.primary, size: 22),
              ),
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 12,
                  height: 12,
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
          left: 24,
          bottom: 32,
          child: Icon(
            Icons.notifications,
            color: colors.secondaryText,
            size: 28,
          ),
        ),
      ],
    );
  }

  /// One community-post row inside the phone: avatar dot + two bars.
  Widget _postRow(EntryColors colors) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
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
                height: 9,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colors.secondaryText.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 9,
                width: 48,
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
