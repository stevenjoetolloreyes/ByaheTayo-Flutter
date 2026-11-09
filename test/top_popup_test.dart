// Tests for the shared top popup (Nov 9, 2026) — the app-wide
// replacement for every bottom white-bar SnackBar, and the single
// visual used by the rating "Thank you!" popup and the admin-reply
// popup.
//
// Covers: TopPopup.show shows the exact message, auto-dismisses
// after 5 seconds, title + action + tap behavior, and one-at-a-time
// replacement. The overlay-based rating/reply popups are covered
// by app_rating_test.dart and app_reviews_admin_test.dart.
import 'package:estudyantego/features/top_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => TopPopup.show(
                context,
                message: 'Note saved!',
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the exact message with no invented title',
      (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.text('Show'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Note saved!'), findsOneWidget);
    // No title line: only the message itself is shown.
    expect(find.byType(TopPopup), findsOneWidget);
  });

  testWidgets('auto-dismisses after 5 seconds', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.text('Show'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Note saved!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    // The entry is removed when the drain completes; one more frame
    // lets the overlay rebuild without it.
    await tester.pump();
    expect(find.text('Note saved!'), findsNothing);
  });

  testWidgets('shows a title when one is given', (tester) async {
    await _pumpShell(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => TopPopup.show(
                  context,
                  title: 'Thank you!',
                  message: 'Your feedback was sent.',
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Thank you!'), findsOneWidget);
    expect(find.text('Your feedback was sent.'), findsOneWidget);
  });

  testWidgets('action button runs onAction and dismisses', (tester) async {
    var actionRan = false;
    await _pumpShell(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => TopPopup.show(
                  context,
                  message: 'Route hidden.',
                  actionLabel: 'View hidden',
                  onAction: () => actionRan = true,
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Route hidden.'), findsOneWidget);
    await tester.tap(find.text('View hidden'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(actionRan, isTrue);
    expect(find.text('Route hidden.'), findsNothing);
  });

  testWidgets('tap runs onTap and dismisses', (tester) async {
    var tapped = false;
    await _pumpShell(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => TopPopup.show(
                  context,
                  title: 'EstudyanteGO replied to your review.',
                  message: 'Thanks for the feedback!',
                  onTap: () => tapped = true,
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Thanks for the feedback!'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tapped, isTrue);
    expect(find.text('Thanks for the feedback!'), findsNothing);
  });

  testWidgets('a new popup replaces the current one', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.text('Show'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Note saved!'), findsOneWidget);
    // Show a second popup from the same button (same message, but
    // the point is only one popup is on screen at a time).
    await tester.tap(find.text('Show'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TopPopup), findsOneWidget);
    expect(find.text('Note saved!'), findsOneWidget);
  });

  testWidgets('TopPopup widget renders title, message and drain bar',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TopPopup(
              progress: const AlwaysStoppedAnimation<double>(0.5),
              title: 'Thank you!',
              message: 'Your feedback was sent.',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Thank you!'), findsOneWidget);
    expect(find.text('Your feedback was sent.'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
