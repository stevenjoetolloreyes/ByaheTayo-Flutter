// "Rate this EstudyanteGO App" tests (Nov 9, 2026).
//
// Covers the tracker (3 distinct real actions unlock, repeat does
// not count, one-time only per app version, submit success/failure,
// version change re-enables, persistence) and the overlay widget
// (Satisfied? gate, stars, "Not yet" -> improve chips, send ->
// Firestore write mocked, 5-second "Thank you!" popup, pill
// disappears after sending).
import 'dart:io';

import 'package:estudyantego/features/app_rating.dart';
import 'package:estudyantego/features/app_rating_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAppRatingRepository implements AppRatingRepository {
  final List<AppRatingSubmission> submissions = <AppRatingSubmission>[];
  bool failNext = false;

  @override
  Future<void> submit(AppRatingSubmission submission) async {
    if (failNext) {
      failNext = false;
      throw Exception('fake Firestore failure');
    }
    submissions.add(submission);
  }
}

void main() {
  group('AppRatingTracker', () {
    late FakeAppRatingRepository repo;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      repo = FakeAppRatingRepository();
    });

    Future<AppRatingTracker> newTracker({String? appVersion}) async {
      final tracker = AppRatingTracker(
        prefs: await SharedPreferences.getInstance(),
        repository: repo,
        appVersion: appVersion,
      );
      await tracker.ensureInitialized();
      return tracker;
    }

    test('appRatingVersion matches pubspec.yaml version', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match =
          RegExp(r'^version:\s*(.+)\s*$', multiLine: true).firstMatch(pubspec);
      expect(match, isNotNull);
      expect(appRatingVersion, match!.group(1)!.trim());
    });

    test('locked until 3 DISTINCT actions; repeats do not count',
        () async {
      final tracker = await newTracker();
      expect(tracker.showPrompt, isFalse);
      tracker.recordAction(AppRatingAction.checkedFare);
      expect(tracker.showPrompt, isFalse);
      // Repeating the same action does not move the count.
      tracker.recordAction(AppRatingAction.checkedFare);
      tracker.recordAction(AppRatingAction.checkedFare);
      expect(tracker.actionsDone.length, 1);
      expect(tracker.showPrompt, isFalse);
      tracker.recordAction(AppRatingAction.viewedRouteOnMap);
      expect(tracker.showPrompt, isFalse);
      tracker.recordAction(AppRatingAction.openedNotes);
      expect(tracker.isUnlocked, isTrue);
      expect(tracker.showPrompt, isTrue);
    });

    test('actions + rated flag persist across tracker instances',
        () async {
      final first = await newTracker();
      first.recordAction(AppRatingAction.checkedFare);
      first.recordAction(AppRatingAction.viewedRouteOnMap);
      first.recordAction(AppRatingAction.startedRide);
      expect(first.showPrompt, isTrue);
      // A fresh tracker on the same prefs sees the same state.
      final second = await newTracker();
      expect(second.showPrompt, isTrue);
      expect(second.actionsDone.length, 3);
    });

    test('submit success marks this version rated and hides prompt',
        () async {
      final tracker = await newTracker();
      tracker.recordAction(AppRatingAction.checkedFare);
      tracker.recordAction(AppRatingAction.viewedRouteOnMap);
      tracker.recordAction(AppRatingAction.openedNotes);
      final ok = await tracker.submit(
        const AppRatingSubmission(
          satisfied: true,
          stars: 5,
          topics: <String>['Live Follow'],
          comment: 'Love it!',
          userId: 'uid-1',
          appVersion: '1.0.0+1',
        ),
      );
      expect(ok, isTrue);
      expect(repo.submissions, hasLength(1));
      expect(repo.submissions.single.satisfied, isTrue);
      expect(repo.submissions.single.stars, 5);
      expect(repo.submissions.single.topics, <String>['Live Follow']);
      expect(repo.submissions.single.comment, 'Love it!');
      expect(repo.submissions.single.userId, 'uid-1');
      expect(repo.submissions.single.appVersion, '1.0.0+1');
      expect(tracker.hasRatedForVersion, isTrue);
      expect(tracker.showPrompt, isFalse);
      // Further actions no longer unlock anything.
      tracker.recordAction(AppRatingAction.startedReview);
      expect(tracker.showPrompt, isFalse);
    });

    test('submit failure does NOT mark rated; prompt stays', () async {
      final tracker = await newTracker();
      tracker.recordAction(AppRatingAction.checkedFare);
      tracker.recordAction(AppRatingAction.viewedRouteOnMap);
      tracker.recordAction(AppRatingAction.openedNotes);
      repo.failNext = true;
      final ok = await tracker.submit(
        const AppRatingSubmission(
          satisfied: false,
          topics: <String>['Bugs & Crashes'],
          comment: '',
          userId: null,
          appVersion: '1.0.0+1',
        ),
      );
      expect(ok, isFalse);
      expect(repo.submissions, isEmpty);
      expect(tracker.hasRatedForVersion, isFalse);
      expect(tracker.showPrompt, isTrue);
    });

    test('a new app version starts fresh: rated + actions reset',
        () async {
      final oldVersion = await newTracker(appVersion: '1.0.0+1');
      oldVersion.recordAction(AppRatingAction.checkedFare);
      oldVersion.recordAction(AppRatingAction.viewedRouteOnMap);
      oldVersion.recordAction(AppRatingAction.openedNotes);
      expect(
        await oldVersion.submit(
          const AppRatingSubmission(
            satisfied: true,
            stars: 4,
            topics: <String>[],
            comment: '',
            userId: null,
            appVersion: '1.0.0+1',
          ),
        ),
        isTrue,
      );
      expect(oldVersion.showPrompt, isFalse);
      // Same prefs, new version: nothing carries over.
      final newVersion = await newTracker(appVersion: '1.0.1+1');
      expect(newVersion.hasRatedForVersion, isFalse);
      expect(newVersion.actionsDone, isEmpty);
      expect(newVersion.showPrompt, isFalse);
    });
  });

  group('AppRatingOverlay', () {
    late FakeAppRatingRepository repo;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      repo = FakeAppRatingRepository();
    });

    Future<AppRatingTracker> newTracker() async {
      final tracker = AppRatingTracker(
        prefs: await SharedPreferences.getInstance(),
        repository: repo,
      );
      await tracker.ensureInitialized();
      return tracker;
    }

    Future<void> pumpOverlay(
      WidgetTester tester,
      AppRatingTracker tracker,
    ) async {
      // Phone-like viewport (Steven's phone is a tall portrait
      // screen): the card scrolls, so the test taps the Send button
      // via ensureVisible, like a real user scrolling the card.
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppRatingOverlay(
              tracker: tracker,
              currentUserId: 'uid-1',
              child: const Center(child: Text('Student tab content')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Records the 3 actions that unlock the prompt; the card
    /// auto-opens.
    Future<void> unlock(
      WidgetTester tester,
      AppRatingTracker tracker,
    ) async {
      tracker.recordAction(AppRatingAction.checkedFare);
      tracker.recordAction(AppRatingAction.viewedRouteOnMap);
      tracker.recordAction(AppRatingAction.openedNotes);
      await tester.pumpAndSettle();
      expect(find.text('Satisfied?'), findsOneWidget);
    }

    /// Taps a widget that may sit below the fold in the scrolling
    /// card: scrolls it into view first, like a real user.
    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
    }

    /// Pumps past the card-close animation while the pill is
    /// visible. pumpAndSettle cannot be used here: the pill's bob
    /// animation repeats forever, so frames are always scheduled
    /// and pumpAndSettle would time out.
    Future<void> pumpAfterClose(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('no pill before unlock; pill appears after closing card',
        (tester) async {
      final tracker = await newTracker();
      await pumpOverlay(tester, tracker);
      expect(find.text('Rate this app'), findsNothing);
      expect(find.text('Satisfied?'), findsNothing);
      // Two actions are not enough.
      tracker.recordAction(AppRatingAction.checkedFare);
      tracker.recordAction(AppRatingAction.viewedRouteOnMap);
      await tester.pumpAndSettle();
      expect(find.text('Rate this app'), findsNothing);
      // Third distinct action unlocks + auto-opens the card.
      tracker.recordAction(AppRatingAction.openedNotes);
      await tester.pumpAndSettle();
      expect(find.text('Satisfied?'), findsOneWidget);
      // The pill stays hidden while the card is open; closing the
      // card reveals it, and the same tab is still underneath.
      await tester.tap(find.byTooltip('Close'));
      await pumpAfterClose(tester);
      expect(find.text('Satisfied?'), findsNothing);
      expect(find.text('Rate this app'), findsOneWidget);
      expect(find.text('Student tab content'), findsOneWidget);
      // Tapping the pill reopens the card.
      await tester.tap(find.text('Rate this app'));
      await tester.pumpAndSettle();
      expect(find.text('Satisfied?'), findsOneWidget);
    });

    testWidgets('Yes satisfied + 5 stars sends and shows 5s thanks',
        (tester) async {
      final tracker = await newTracker();
      await pumpOverlay(tester, tracker);
      await unlock(tester, tracker);
      await tester.tap(find.text('Yes, satisfied'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Rate 5 stars'), findsOneWidget);
      // Send is disabled until stars are picked.
      expect(
        tester
            .widget<FilledButton>(find.byType(FilledButton))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Rate 5 stars'));
      await tester.pumpAndSettle();
      // Preview star row: prompt, word, hint, and the high-band
      // intro (the heading stays fixed).
      expect(find.text('Great! How would you rate it?'), findsOneWidget);
      expect(find.text('Excellent'), findsOneWidget);
      expect(
        find.text('Salamat! Glad EstudyanteGO helps your commute.'),
        findsOneWidget,
      );
      expect(find.text('What can we improve?'), findsOneWidget);
      expect(
        find.text(
          "Even good trips can get better. Pick anything you'd still like improved — or skip and just send your rating.",
        ),
        findsOneWidget,
      );
      expect(find.text('Map & Routes'), findsOneWidget);
      await tapVisible(tester, find.text('Map & Routes'));
      await tester.enterText(find.byType(TextField), 'Love the live map!');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Send Feedback'));
      // A short pump only: pumpAndSettle would fast-forward past
      // the 5-second "Thank you!" popup before we can assert it.
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.submissions, hasLength(1));
      final submission = repo.submissions.single;
      expect(submission.satisfied, isTrue);
      expect(submission.stars, 5);
      expect(submission.topics, <String>['Map & Routes']);
      expect(submission.comment, 'Love the live map!');
      expect(submission.userId, 'uid-1');
      // Card closed immediately; thanks popup at the top; the pill
      // is gone completely (one-time only per version).
      expect(find.text('Satisfied?'), findsNothing);
      expect(find.text('Thank you!'), findsOneWidget);
      expect(find.text('Your 5-star feedback was sent.'), findsOneWidget);
      expect(find.text('Rate this app'), findsNothing);
      // The popup dismisses itself after 5 seconds. (The drain
      // animation starts on the frame after the send, so pump a
      // little past 5s to let it finish.)
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(find.text('Thank you!'), findsNothing);
      expect(find.text('Student tab content'), findsOneWidget);
    });

    testWidgets('star bands change prompt, word, hint and intro',
        (tester) async {
      final tracker = await newTracker();
      await pumpOverlay(tester, tracker);
      await unlock(tester, tracker);
      await tester.tap(find.text('Yes, satisfied'));
      await tester.pumpAndSettle();
      // Prompt line follows the answer; word + hint are empty
      // until a star is picked.
      expect(find.text('Great! How would you rate it?'), findsOneWidget);
      expect(find.text('No rating yet — tap a star'), findsOneWidget);
      await tester.tap(find.byTooltip('Rate 2 stars'));
      await tester.pumpAndSettle();
      expect(find.text('Fair'), findsOneWidget);
      expect(
        find.text('Thanks for the honesty — help us do better below.'),
        findsOneWidget,
      );
      expect(
        find.text(
          "Sorry your trip with the app wasn't great. Pick what went wrong and we'll work on it first.",
        ),
        findsOneWidget,
      );
      expect(find.text('What can we improve?'), findsOneWidget);
      await tester.tap(find.byTooltip('Rate 3 stars'));
      await tester.pumpAndSettle();
      expect(find.text('Good'), findsOneWidget);
      expect(
        find.text('Thanks! Tell us what would make it a 5 below.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Pick the parts of the app you want us to make better. You can choose more than one.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Rate 4 stars'));
      await tester.pumpAndSettle();
      expect(find.text('Very Good'), findsOneWidget);
      expect(find.text("Glad it's working well for you!"), findsOneWidget);
      expect(
        find.text(
          "Even good trips can get better. Pick anything you'd still like improved — or skip and just send your rating.",
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'Not yet jumps to improve chips and can send without a star',
        (tester) async {
      final tracker = await newTracker();
      await pumpOverlay(tester, tracker);
      await unlock(tester, tracker);
      await tester.tap(find.text('Not yet'));
      await tester.pumpAndSettle();
      expect(find.text('What can we improve?'), findsOneWidget);
      // The star row shows on this path too (preview): the prompt
      // line is the "Not yet" variant, and the low-band intro.
      expect(
        find.text('Sorry to hear that — what should we fix?'),
        findsOneWidget,
      );
      expect(find.byTooltip('Rate 5 stars'), findsOneWidget);
      expect(
        find.text(
          "Sorry your trip with the app wasn't great. Pick what went wrong and we'll work on it first.",
        ),
        findsOneWidget,
      );
      // Send is disabled with nothing picked.
      expect(
        tester
            .widget<FilledButton>(find.byType(FilledButton))
            .onPressed,
        isNull,
      );
      await tapVisible(tester, find.text('Bugs & Crashes'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Send Feedback'));
      // A short pump only: pumpAndSettle would fast-forward past
      // the 5-second "Thank you!" popup before we can assert it.
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.submissions, hasLength(1));
      final submission = repo.submissions.single;
      expect(submission.satisfied, isFalse);
      expect(submission.stars, isNull);
      expect(submission.topics, <String>['Bugs & Crashes']);
      expect(find.text('Thank you!'), findsOneWidget);
      // No star was given, so the subtitle has no star count.
      expect(find.text('Your feedback was sent.'), findsOneWidget);
      expect(find.text('Rate this app'), findsNothing);
    });

    testWidgets('Not yet can send on a comment alone', (tester) async {
      final tracker = await newTracker();
      await pumpOverlay(tester, tracker);
      await unlock(tester, tracker);
      await tester.tap(find.text('Not yet'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'The map loads slowly on my phone.',
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Send Feedback'));
      await tester.pumpAndSettle();
      expect(repo.submissions, hasLength(1));
      expect(repo.submissions.single.satisfied, isFalse);
      expect(repo.submissions.single.stars, isNull);
      expect(repo.submissions.single.topics, isEmpty);
      expect(
        repo.submissions.single.comment,
        'The map loads slowly on my phone.',
      );
    });

    testWidgets('failed send shows an error and keeps the card open',
        (tester) async {
      final tracker = await newTracker();
      await pumpOverlay(tester, tracker);
      await unlock(tester, tracker);
      repo.failNext = true;
      await tester.tap(find.text('Yes, satisfied'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rate 4 stars'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Send Feedback'));
      await tester.pumpAndSettle();
      expect(repo.submissions, isEmpty);
      expect(find.textContaining("Couldn't send"), findsOneWidget);
      expect(find.text('Satisfied?'), findsOneWidget);
      expect(tracker.hasRatedForVersion, isFalse);
      // Closing the card brings the pill back — not rated yet.
      // (The card was scrolled down to reach Send, so the Close
      // button is off-screen above: scroll it into view first.)
      await tapVisible(tester, find.byTooltip('Close'));
      await pumpAfterClose(tester);
      expect(find.text('Rate this app'), findsOneWidget);
    });

    testWidgets('pill sits right-aligned with gradient and star badge',
        (tester) async {
      final tracker = await newTracker();
      await pumpOverlay(tester, tracker);
      await unlock(tester, tracker);
      // Close the card so the pill shows.
      await tester.tap(find.byTooltip('Close'));
      await pumpAfterClose(tester);
      final pill = find.text('Rate this app');
      expect(pill, findsOneWidget);
      final positioned = tester.widget<Positioned>(
        find.ancestor(of: pill, matching: find.byType(Positioned)),
      );
      expect(positioned.right, 16);
      expect(positioned.bottom, 88);
      final ink = tester.widget<Ink>(
        find.ancestor(of: pill, matching: find.byType(Ink)),
      );
      final gradient =
          (ink.decoration as BoxDecoration).gradient as LinearGradient;
      expect(
        gradient.colors,
        <Color>[const Color(0xFF34D399), const Color(0xFF16A34A)],
      );
    });

    testWidgets('card is a bottom sheet with handle, logo header, footer',
        (tester) async {
      final tracker = await newTracker();
      await pumpOverlay(tester, tracker);
      await unlock(tester, tracker);
      final sheet = tester.widget<Positioned>(
        find.ancestor(
          of: find.text('Satisfied?'),
          matching: find.byType(Positioned),
        ),
      );
      expect(sheet.left, 12);
      expect(sheet.right, 12);
      expect(sheet.bottom, 12);
      expect(find.byKey(const Key('rating-drag-handle')), findsOneWidget);
      expect(find.text('Rate EstudyanteGO'), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
      expect(
        find.textContaining('Floating over the Student screen'),
        findsOneWidget,
      );
      expect(find.text('Send Feedback'), findsOneWidget);
      expect(find.textContaining('close it with the X'), findsOneWidget);
    });

    testWidgets('improve chips use the preview labels', (tester) async {
      final tracker = await newTracker();
      await pumpOverlay(tester, tracker);
      await unlock(tester, tracker);
      await tester.tap(find.text('Yes, satisfied'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rate 4 stars'));
      await tester.pumpAndSettle();
      expect(find.text('What can we improve?'), findsOneWidget);
      // Preview labels.
      for (final label in <String>[
        'Map & Routes',
        'Fares',
        'Live Follow',
        'App Speed',
        'Bugs & Crashes',
        'Design',
        'Notifications',
        'Student Features',
        'Something Else',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      // Old labels are gone.
      for (final label in <String>[
        'Classes & Timetable',
        'Notes & Study',
        'Communities',
        'Account & Settings',
      ]) {
        expect(find.text(label), findsNothing);
      }
      // Green wrench icon in the heading.
      expect(find.byIcon(Icons.build), findsOneWidget);
    });

    testWidgets('comment field has label, live counter, band placeholder',
        (tester) async {
      final tracker = await newTracker();
      await pumpOverlay(tester, tracker);
      await unlock(tester, tracker);
      await tester.tap(find.text('Yes, satisfied'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rate 2 stars'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tell us more (optional)'), findsOneWidget);
      expect(find.text('0 / 500'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .decoration
            ?.hintText,
        'What went wrong? Tell us so we can fix it.',
      );
      await tester.enterText(find.byType(TextField), 'Slow map');
      await tester.pumpAndSettle();
      expect(find.text('8 / 500'), findsOneWidget);
      // Mid band changes the placeholder. (The card scrolled to
      // show the TextField after typing, so scroll the stars back
      // into view first.)
      await tapVisible(tester, find.byTooltip('Rate 3 stars'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .decoration
            ?.hintText,
        'What would make this a 5-star app for you?',
      );
      // High band changes it again.
      await tapVisible(tester, find.byTooltip('Rate 5 stars'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .decoration
            ?.hintText,
        'What did you love — and what could still be better?',
      );
    });

    testWidgets('closing without sending keeps the draft',
        (tester) async {
      final tracker = await newTracker();
      await pumpOverlay(tester, tracker);
      await unlock(tester, tracker);
      await tester.tap(find.text('Yes, satisfied'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rate 4 stars'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Design'));
      await tester.enterText(find.byType(TextField), 'Nice app');
      await tester.pumpAndSettle();
      // Close without sending, then reopen from the pill.
      await tapVisible(tester, find.byTooltip('Close'));
      await pumpAfterClose(tester);
      expect(find.text('Rate this app'), findsOneWidget);
      await tester.tap(find.text('Rate this app'));
      await tester.pumpAndSettle();
      expect(find.text('Very Good'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Nice app',
      );
      // Send is still enabled, and the picked chip survived too.
      expect(
        tester
            .widget<FilledButton>(find.byType(FilledButton))
            .onPressed,
        isNotNull,
      );
      await tapVisible(tester, find.text('Send Feedback'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.submissions, hasLength(1));
      expect(repo.submissions.single.stars, 4);
      expect(repo.submissions.single.topics, <String>['Design']);
      expect(repo.submissions.single.comment, 'Nice app');
    });

    testWidgets('auto-open waits 900ms after the 3rd action',
        (tester) async {
      final tracker = await newTracker();
      await pumpOverlay(tester, tracker);
      tracker.recordAction(AppRatingAction.checkedFare);
      tracker.recordAction(AppRatingAction.viewedRouteOnMap);
      tracker.recordAction(AppRatingAction.openedNotes);
      // Just after the 3rd action the pill is already there, but
      // the card has not popped up yet (preview: 900ms delay).
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Rate this app'), findsOneWidget);
      expect(find.text('Satisfied?'), findsNothing);
      // After the delay the card pops up on its own.
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(find.text('Satisfied?'), findsOneWidget);
    });
  });
}
