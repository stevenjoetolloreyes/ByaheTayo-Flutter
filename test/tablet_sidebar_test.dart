// Tests for the collapsible left sidebar (wide layout, width >= 600).
//
// Spec: expanded 220dp with logo + name + icon+label rows; collapsed 80dp
// with icons only, centered, labels hidden, selected indicator preserved,
// Tooltips on every icon; chevron toggle at the top; ~225ms animation;
// selection never resets on toggle; preference persisted under
// 'byahetayo_sidebar_collapsed'; phones keep the bottom FloatingGlassNav.
import 'package:estudyantego/features/floating_nav.dart';
import 'package:estudyantego/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

double _sidebarWidth(WidgetTester tester) {
  return tester.getSize(find.byKey(const Key('sidebar-container'))).width;
}

void main() {
  setUp(() {
    // The app boots through the first-time gate; these sidebar tests
    // cover the dashboard, so onboarding is already done here.
    SharedPreferences.setMockInitialValues({'byahetayo_onboarding_done': true});
  });

  testWidgets('sidebar is 220dp wide when expanded (tablet portrait)', (
    WidgetTester tester,
  ) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const EstudyanteGOApp());
    await tester.pumpAndSettle();

    expect(_sidebarWidth(tester), 220);
    expect(find.text('EstudyanteGO'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
  });

  testWidgets('toggle collapses to 80dp, hides labels, keeps tooltips', (
    WidgetTester tester,
  ) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const EstudyanteGOApp());
    await tester.pumpAndSettle();

    // 'Fares' is unselected, so it only exists as a sidebar label.
    expect(find.text('Fares'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-toggle')));
    await tester.pumpAndSettle();

    expect(_sidebarWidth(tester), 80);
    expect(find.text('Fares'), findsNothing);
    expect(find.byTooltip('Fares'), findsOneWidget);
    expect(find.byTooltip('Map'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    // Expand again.
    await tester.tap(find.byKey(const Key('sidebar-toggle')));
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), 220);
    expect(find.text('Fares'), findsOneWidget);
  });

  testWidgets('selection is preserved across collapse and expand', (
    WidgetTester tester,
  ) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const EstudyanteGOApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar-item-Fares')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'LTFRB fare calculator — same rates and formula as the web app.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('sidebar-toggle')));
    await tester.pumpAndSettle();
    // Still on Fares: no top AppBar anymore, and the sidebar
    // label is gone while collapsed, so 'Fares' appears nowhere.
    expect(find.text('Fares'), findsNothing);
    expect(
      find.text(
        'LTFRB fare calculator — same rates and formula as the web app.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('sidebar-toggle')));
    await tester.pumpAndSettle();
    // Expanded again: only the sidebar label now — no top AppBar.
    expect(find.text('Fares'), findsOneWidget);
    expect(
      find.text(
        'LTFRB fare calculator — same rates and formula as the web app.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('restored collapsed value renders the 80dp sidebar', (
    WidgetTester tester,
  ) async {
    await _setSurface(tester, const Size(800, 1280));

    // Widget honors the restored initial value (main() loads the pref and
    // passes it in).
    await tester.pumpWidget(
      const EstudyanteGOApp(initialSidebarCollapsed: true),
    );
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), 80);
  });

  testWidgets('toggling saves the collapsed preference', (
    WidgetTester tester,
  ) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const EstudyanteGOApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar-toggle')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('byahetayo_sidebar_collapsed'), isTrue);
  });

  testWidgets('no overflow at tablet portrait and landscape sizes', (
    WidgetTester tester,
  ) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const EstudyanteGOApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sidebar-toggle')));
    await tester.pumpAndSettle();

    await _setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(const EstudyanteGOApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sidebar-toggle')));
    await tester.pumpAndSettle();
  });

  testWidgets('phones keep the bottom FloatingGlassNav, no sidebar', (
    WidgetTester tester,
  ) async {
    await _setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(const EstudyanteGOApp());
    await tester.pumpAndSettle();

    expect(find.byType(FloatingGlassNav), findsOneWidget);
    expect(find.byKey(const Key('sidebar-container')), findsNothing);
  });
}
