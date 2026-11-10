// Widget tests for the School Calendar Edit feature (Nov 9–10,
// 2026): the green Edit button on the hub's School Calendar
// card, month prev/next, tappable days + day-detail line, the
// dynamic legend, the Coming up list, and the Edit School
// Calendar page itself (school field, Marked Days list with
// edit/remove, the bottom-left floating + with its Add Day sheet
// and duplicate guard, Save persisting through the store).
// Data is seeded through SharedPreferences exactly as the app
// stores it. Dates are November 2026 (today) unless stated.
import 'package:estudyantego/features/minecraft_theme.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tall viewport so the full StudentTab list builds.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpHub(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(),
      themeMode: ThemeMode.light,
      home: Scaffold(
        body: StudentHubTheme(child: const StudentTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Text inside the School Calendar card (scoped so a same-named
/// label in another Hub card cannot match).
Finder _inCalendarCard(String text) => find.descendant(
      of: find
          .ancestor(
            of: find.text('School Calendar'),
            matching: find.byType(MinecraftCard),
          )
          .first,
      matching: find.text(text),
    );

/// Opens the Edit page from the hub (school pre-seeded).
Future<void> _openEditPage(WidgetTester tester) async {
  _tallScreen(tester);
  SharedPreferences.setMockInitialValues({
    'byahetayo_profile_school': 'University of Northern Philippines',
  });
  await _pumpHub(tester);
  await tester.tap(find.byKey(const ValueKey('school-calendar-edit')));
  await tester.pumpAndSettle();
  expect(find.text('Edit School Calendar'), findsOneWidget);
}

/// The delete button on a Marked Days row, by the row's name.
Finder _removeButton(String name) => find.descendant(
      of: find.ancestor(
        of: find.text(name),
        matching: find.byType(ListTile),
      ),
      matching: find.byIcon(Icons.delete_outline),
    );

/// The edit (pencil) button on a Marked Days row, by the row's name.
Finder _editButton(String name) => find.descendant(
      of: find.ancestor(
        of: find.text(name),
        matching: find.byType(ListTile),
      ),
      matching: find.byIcon(Icons.edit_outlined),
    );

void main() {
  group('hub School Calendar card', () {
    testWidgets(
        'Edit button present, Add school gone, November shown, '
        'Coming up lists Bonifacio Day', (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({
        'byahetayo_profile_school': 'University of Northern Philippines',
      });
      await _pumpHub(tester);

      expect(find.text('School Calendar'), findsOneWidget);
      expect(find.byKey(const ValueKey('school-calendar-edit')),
          findsOneWidget);
      expect(find.text('Add school'), findsNothing);
      expect(_inCalendarCard('November 2026'), findsOneWidget);
      // Dynamic legend: Holiday is in the month, Today always is.
      expect(_inCalendarCard('Holiday'), findsOneWidget);
      expect(_inCalendarCard('Today'), findsOneWidget);
      // Coming up below the card: Bonifacio Day (Nov 30) is next.
      expect(find.text('Coming up — no-school days & events'),
          findsOneWidget);
      expect(find.text('Bonifacio Day'), findsWidgets);
    });

    testWidgets('tapping Nov 1 shows its day detail',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      await _pumpHub(tester);

      await tester.tap(find.byKey(const ValueKey('calendar-day-1')));
      await tester.pumpAndSettle();
      expect(_inCalendarCard("All Saints' Day · Holiday"), findsOneWidget);
    });

    testWidgets('month prev/next flips the month title',
        (WidgetTester tester) async {
      _tallScreen(tester);
      SharedPreferences.setMockInitialValues({});
      await _pumpHub(tester);

      await tester.tap(find.byKey(const ValueKey('calendar-next-month')));
      await tester.pumpAndSettle();
      expect(_inCalendarCard('December 2026'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('calendar-prev-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendar-prev-month')));
      await tester.pumpAndSettle();
      expect(_inCalendarCard('October 2026'), findsOneWidget);
    });
  });

  group('Edit School Calendar page', () {
    testWidgets('school field + the three November holidays listed',
        (WidgetTester tester) async {
      await _openEditPage(tester);

      expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('edit-calendar-school')))
            .controller
            ?.text,
        'University of Northern Philippines',
      );
      expect(find.text("All Saints' Day"), findsOneWidget);
      expect(find.text("All Souls' Day"), findsOneWidget);
      expect(find.text('Bonifacio Day'), findsOneWidget);
      // No dashed "+ Add a day" button in the list.
      expect(find.text('Add a day'), findsNothing);
      // The floating + sits at the bottom-left.
      expect(find.byKey(const ValueKey('calendar-edit-fab')), findsOneWidget);
    });

    testWidgets('Add Day adds a row with a New badge',
        (WidgetTester tester) async {
      await _openEditPage(tester);

      await tester.tap(find.byKey(const ValueKey('calendar-edit-fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendar-fab-add-day')));
      await tester.pumpAndSettle();
      expect(find.text('Add a day'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('day-sheet-name')), 'Foundation Day');
      await tester.tap(find.byKey(const ValueKey('day-sheet-date')));
      await tester.pumpAndSettle();
      // The date picker opens on the current month (November
      // 2026): pick the 20th, then confirm.
      await tester.tap(find.descendant(
        of: find.byType(Dialog),
        matching: find.text('20'),
      ));
      await tester.tap(find.descendant(
        of: find.byType(Dialog),
        matching: find.text('OK'),
      ));
      await tester.pumpAndSettle();
      // Pick the Event type (the sheet defaults to Holiday).
      await tester.tap(find.text('Event'));
      await tester.tap(find.byKey(const ValueKey('day-sheet-save')));
      await tester.pumpAndSettle();

      expect(find.text('Foundation Day'), findsOneWidget);
      expect(find.text('Nov 20, 2026 · Event'), findsOneWidget);
      // No "New" badge here: the green flash + badge belong to
      // the Files scan insert, not a manual Add Day.
    });

    testWidgets('Add Day on an already-marked date is refused',
        (WidgetTester tester) async {
      await _openEditPage(tester);

      await tester.tap(find.byKey(const ValueKey('calendar-edit-fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendar-fab-add-day')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('day-sheet-name')), 'Undas Party');
      await tester.tap(find.byKey(const ValueKey('day-sheet-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(Dialog),
        matching: find.text('1'),
      ));
      await tester.tap(find.descendant(
        of: find.byType(Dialog),
        matching: find.text('OK'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('day-sheet-save')));
      await tester.pumpAndSettle();

      expect(
        find.text('“All Saints\' Day” is already marked on that date.'),
        findsOneWidget,
      );
      // The sheet stays open — the row was not added.
      expect(find.text('Add a day'), findsOneWidget);
    });

    testWidgets('Add Day with no name is refused',
        (WidgetTester tester) async {
      await _openEditPage(tester);

      await tester.tap(find.byKey(const ValueKey('calendar-edit-fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendar-fab-add-day')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('day-sheet-save')));
      await tester.pumpAndSettle();

      expect(find.text('Give the day a name first.'), findsOneWidget);
    });

    testWidgets('remove drops the row with a toast',
        (WidgetTester tester) async {
      await _openEditPage(tester);

      await tester.tap(_removeButton('Bonifacio Day'));
      // One pump only: the top popup drains over 5s, so a full
      // pumpAndSettle would advance past it and it would be gone.
      await tester.pump();
      expect(find.text('Bonifacio Day'), findsNothing);
      expect(find.text('Removed “Bonifacio Day”'), findsOneWidget);
    });

    testWidgets('rename + save persists a name override',
        (WidgetTester tester) async {
      await _openEditPage(tester);

      await tester.tap(_editButton("All Saints' Day"));
      await tester.pumpAndSettle();
      expect(find.text('Edit day'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('day-sheet-name')), 'Undas');
      await tester.tap(find.byKey(const ValueKey('day-sheet-save')));
      await tester.pumpAndSettle();
      expect(find.text('Undas'), findsOneWidget);
      expect(find.text("All Saints' Day"), findsNothing);

      await tester.tap(find.byKey(const ValueKey('edit-calendar-save')));
      await tester.pumpAndSettle();
      expect(find.text('Edit School Calendar'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      final overrides =
          prefs.getString('byahetayo_holiday_overrides') ?? '';
      expect(overrides, contains('Undas'));
      expect(overrides, contains('2026-11-01'));
      // The hub card shows the renamed day right away: tap Nov 1
      // (a past date, so it is not in Coming up) and its detail
      // line carries the new name.
      await tester.tap(find.byKey(const ValueKey('calendar-day-1')));
      await tester.pumpAndSettle();
      expect(_inCalendarCard('Undas · Holiday'), findsOneWidget);
    });

    testWidgets('add + save persists a custom day',
        (WidgetTester tester) async {
      await _openEditPage(tester);

      await tester.tap(find.byKey(const ValueKey('calendar-edit-fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendar-fab-add-day')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('day-sheet-name')), 'Foundation Day');
      await tester.tap(find.byKey(const ValueKey('day-sheet-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(Dialog),
        matching: find.text('20'),
      ));
      await tester.tap(find.descendant(
        of: find.byType(Dialog),
        matching: find.text('OK'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('day-sheet-save')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('edit-calendar-save')));
      await tester.pumpAndSettle();
      expect(find.text('Edit School Calendar'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      final custom =
          prefs.getString('byahetayo_custom_school_days') ?? '';
      expect(custom, contains('Foundation Day'));
      // The hub calendar shows the new day (Coming up list).
      expect(find.text('Foundation Day'), findsWidgets);
    });

    testWidgets('back discards the draft',
        (WidgetTester tester) async {
      await _openEditPage(tester);

      await tester.tap(_removeButton('Bonifacio Day'));
      await tester.pumpAndSettle();
      expect(find.text('Bonifacio Day'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Edit School Calendar'), findsNothing);
      // Nothing persisted, and the hub still lists the day.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('byahetayo_holiday_overrides'), isNull);
      expect(find.text('Bonifacio Day'), findsWidgets);
    });
  });
}
