import 'package:estudyantego/features/floating_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _destinations = <FloatingNavDestination>[
  FloatingNavDestination('Map', Icons.map_outlined, Icons.map),
  FloatingNavDestination('Fares', Icons.payments_outlined, Icons.payments),
  FloatingNavDestination('Student', Icons.school_outlined, Icons.school),
  FloatingNavDestination('Friends', Icons.people_outlined, Icons.people),
  FloatingNavDestination(
      'Communities', Icons.groups_outlined, Icons.groups),
  FloatingNavDestination('Account', Icons.person_outlined, Icons.person),
];

Widget _pumpNav({
  int selectedIndex = 0,
  ValueChanged<int>? onSelect,
  ThemeData? theme,
  EdgeInsets? viewPaddingOverride,
}) {
  final nav = FloatingGlassNav(
    selectedIndex: selectedIndex,
    onSelect: onSelect ?? (_) {},
    destinations: _destinations,
  );
  return MaterialApp(
    theme: theme ?? ThemeData.light(),
    home: Builder(
      builder: (context) {
        final child = Scaffold(bottomNavigationBar: nav);
        if (viewPaddingOverride == null) return child;
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(viewPadding: viewPaddingOverride),
          child: child,
        );
      },
    ),
  );
}

void main() {
  testWidgets('renders all six tabs with labels', (tester) async {
    await tester.pumpWidget(_pumpNav());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('floating-nav')), findsOneWidget);
    for (final label in ['Map', 'Fares', 'Student', 'Friends', 'Communities', 'Account']) {
      expect(find.byKey(Key('floating-nav-item-$label')), findsOneWidget);
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('active tab is a white bold pill, inactive tabs muted',
      (tester) async {
    await tester.pumpWidget(_pumpNav(selectedIndex: 2));
    await tester.pumpAndSettle();
    // Only the nav's own label styles: the Scaffold also wraps the
    // bar in its default (14sp bodyMedium) animated text style.
    final styles = tester
        .widgetList<AnimatedDefaultTextStyle>(find.descendant(
            of: find.byKey(const Key('floating-nav')),
            matching: find.byType(AnimatedDefaultTextStyle)))
        .map((w) => w.style)
        .where((s) => s.fontSize == 11)
        .toList();
    expect(styles, hasLength(6));
    expect(styles[2].color, Colors.white);
    expect(styles[2].fontWeight, FontWeight.w700);
    for (var i = 0; i < 6; i++) {
      if (i == 2) continue;
      expect(styles[i].color, Colors.white.withValues(alpha: 0.55));
      expect(styles[i].fontWeight, FontWeight.w500);
    }
  });

  testWidgets('tapping a tab reports its index', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(_pumpNav(onSelect: tapped.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(tapped, [3]);
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(tapped, [3, 5]);
  });

  testWidgets('renders in light and dark mode, capsule adapts',
      (tester) async {
    double capsuleAlpha() {
      final container = tester.widget<Container>(
          find.byKey(const Key('floating-nav-capsule')));
      final gradient =
          (container.decoration! as BoxDecoration).gradient! as LinearGradient;
      return gradient.colors.first.a;
    }

    await tester.pumpWidget(_pumpNav(theme: ThemeData.light()));
    await tester.pumpAndSettle();
    final lightAlpha = capsuleAlpha();
    await tester.pumpWidget(_pumpNav(theme: ThemeData.dark()));
    await tester.pumpAndSettle();
    final darkAlpha = capsuleAlpha();
    // Dark glass is more transparent on dark backgrounds.
    expect(darkAlpha, lessThan(lightAlpha));
  });

  testWidgets('bottom margin includes the system gesture inset',
      (tester) async {
    await tester.pumpWidget(_pumpNav(
        viewPaddingOverride: const EdgeInsets.only(bottom: 34)));
    await tester.pumpAndSettle();
    final container = tester
        .widget<Container>(find.byKey(const Key('floating-nav')));
    final margin = container.margin! as EdgeInsets;
    expect(margin.bottom, 12 + 34);
    expect(margin.left, 16);
    expect(margin.right, 16);
  });

  testWidgets('no overflow on a small 320dp phone, tabs still tappable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tapped = <int>[];
    await tester.pumpWidget(_pumpNav(onSelect: tapped.add));
    await tester.pumpAndSettle();
    // Pumping + settling with no overflow exception is the assertion;
    // "Communities" is wider than one tab slot and must scale down.
    expect(find.byKey(const Key('floating-nav')), findsOneWidget);
    await tester.tap(find.text('Communities'));
    await tester.pumpAndSettle();
    expect(tapped, [4]);
  });
}
