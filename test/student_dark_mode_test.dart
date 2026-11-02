// Dark Mode Final Polish tests (Nov 2 polish).
//
// Asserts the polish, not a redesign:
//  (a) the Student Hub follows Dark Mode — charcoal cards and dark
//      sign-in tiles under a dark ambient theme, via StudentHubTheme;
//  (b) Light Mode rendering is unchanged — white cards, the exact
//      approved light sign-in palette, deep-emerald prices, grey
//      secondary note;
//  (c) subscription price / secondary text is readable in Dark
//      Mode (light emerald prices, #B0B8B5 secondary text).
//
// Module screens opened from the Hub keep the light StudentTheme
// wrapper by design, so they are intentionally NOT asserted here.
import 'package:estudyantego/features/student/signin_components.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:estudyantego/features/subscription_membership.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tall viewport so a full StudentTab list builds.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The tile Container wrapping a day label inside SigninDayTiles.
Container _dayTile(WidgetTester tester, String label) {
  return tester.widget<Container>(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byType(Container),
        )
        .first,
  );
}

Color _tileColor(WidgetTester tester, String label) {
  return (_dayTile(tester, label).decoration! as BoxDecoration).color!;
}

/// The Card surface color of the Hub sign-in card, as rendered.
Color _hubCardColor(WidgetTester tester) {
  final card = find.byKey(const ValueKey('signin-hub-card'));
  expect(card, findsOneWidget);
  final material = tester.widget<Material>(
    find.descendant(of: card, matching: find.byType(Material)).first,
  );
  return material.color!;
}

void main() {
  testWidgets('Hub uses dark charcoal cards under a dark ambient theme',
      (WidgetTester tester) async {
    _tallScreen(tester);
    // StudentTab loads from SharedPreferences; without mock values
    // its load never completes and the spinner spins forever
    // (pumpAndSettle timeout) — same pattern as the sign-in tests.
    SharedPreferences.setMockInitialValues({});
    ThemeData? captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: StudentHubTheme(
            child: Builder(
              builder: (context) {
                captured = Theme.of(context);
                return const StudentTab();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The hub theme selection itself: dark ambient → dark student theme.
    expect(captured, isNotNull);
    expect(captured!.brightness, Brightness.dark);
    expect(captured!.cardColor, kStudentDarkCard);
    expect(captured!.scaffoldBackgroundColor, kStudentDarkBg);
    expect(_hubCardColor(tester), kStudentDarkCard);
    // Empty state: Day 1 is the current tile — brightened to accent
    // green in dark mode (deep emerald would vanish on charcoal).
    expect(_tileColor(tester, 'D1'), kStudentEmeraldAccent);
  });

  testWidgets('Hub keeps the exact light rendering under light theme',
      (WidgetTester tester) async {
    _tallScreen(tester);
    SharedPreferences.setMockInitialValues({});
    ThemeData? captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        themeMode: ThemeMode.light,
        home: Scaffold(
          body: StudentHubTheme(
            child: Builder(
              builder: (context) {
                captured = Theme.of(context);
                return const StudentTab();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(captured, isNotNull);
    expect(captured!.brightness, Brightness.light);
    expect(captured!.cardColor, kStudentCard);
    expect(_hubCardColor(tester), kStudentCard);
    // Light current tile is unchanged deep emerald.
    expect(_tileColor(tester, 'D1'), kStudentEmerald);
    // Light stat values are unchanged deep emerald.
    final card = find.byKey(const ValueKey('signin-hub-card'));
    final value = tester.widget<Text>(
      find.descendant(of: card, matching: find.text('50 Points')),
    );
    expect(value.style?.color, kStudentEmerald);
  });

  testWidgets('Day tiles use dark tints under a dark theme',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: SigninDayTiles(
            checkedCells: 2,
            currentDay: 3,
            checkedToday: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Completed Day 1: dark green tint.
    expect(
      _tileColor(tester, 'D1'),
      kStudentEmeraldAccent.withValues(alpha: 0.18),
    );
    // Current Day 3: accent green tile.
    expect(_tileColor(tester, 'D3'), kStudentEmeraldAccent);
    // Upcoming Day 4: elevated charcoal tile.
    expect(_tileColor(tester, 'D4'), kStudentDarkElevated);
    // Upcoming Day 7: dark gold tint.
    expect(
      _tileColor(tester, 'D7'),
      kSigninGold.withValues(alpha: 0.18),
    );
  });

  testWidgets('Subscription price is readable emerald in Dark Mode',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SubscriptionMembershipScreen(onBack: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Pro is pre-selected, monthly by default.
    final price = tester.widget<Text>(find.text('₱299 / month'));
    expect(price.style?.color, const Color(0xFF34D399));
  });

  testWidgets('Subscription price stays deep emerald in Light Mode',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: SubscriptionMembershipScreen(onBack: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final price = tester.widget<Text>(find.text('₱299 / month'));
    expect(price.style?.color, const Color(0xFF14532D));
  });

  testWidgets(
      'Subscription secondary note uses the token grey in Dark Mode',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SubscriptionPlanDetailsScreen(
            plan: subscriptionPlans[2],
            billing: SubscriptionBilling.monthly,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final note = tester.widget<Text>(
      find.text('Your transaction is safe and encrypted.'),
    );
    expect(note.style?.color, const Color(0xFFB0B8B5));
  });

  testWidgets('Subscription secondary note keeps grey in Light Mode',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: SubscriptionPlanDetailsScreen(
            plan: subscriptionPlans[2],
            billing: SubscriptionBilling.monthly,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final note = tester.widget<Text>(
      find.text('Your transaction is safe and encrypted.'),
    );
    expect(note.style?.color, Colors.grey);
  });
}
