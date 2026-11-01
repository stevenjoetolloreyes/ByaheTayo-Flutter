// Welcome / onboarding: four swipeable Material 3 pages introducing
// the app, with Skip + Next controls. The last page offers Get Started
// (create an account) and Sign In. Skipping goes to Sign In — there is
// no guest path.
import 'package:flutter/material.dart';

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

const _pages = <_OnboardingPage>[
  _OnboardingPage(
    icon: Icons.map,
    title: 'Explore the map',
    description:
        'See hubs, routes, and places across Northern Luzon on a live map.',
  ),
  _OnboardingPage(
    icon: Icons.route,
    title: 'Plan your trip',
    description:
        'Find jeepney and bus routes with directions, stops, and live tracking.',
  ),
  _OnboardingPage(
    icon: Icons.payments,
    title: 'Know your fare',
    description:
        'Compute LTFRB-based fares and check verified operator fares '
        'before you ride.',
  ),
  _OnboardingPage(
    icon: Icons.groups,
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

  /// Sign In pressed (or Skip): the gate marks onboarding done and
  /// opens sign-in.
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: _isLast
                  ? const SizedBox(height: 48)
                  : TextButton(
                      onPressed: widget.onSignIn,
                      child: const Text('Skip'),
                    ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: Icon(
                            page.icon,
                            size: 64,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          page.description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? scheme.primary
                          : scheme.outline.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
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
    );
  }
}
