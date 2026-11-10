// Tests for Feature 5: the game-style Student tab entrance after
// the Welcome Back overlay (Sign In path only).
//
// The entrance plays once when the gate lands on the Student tab
// right after Welcome Back finishes: every element staggers in
// top-to-bottom, the points count up to the LIVE wallet balance,
// the Walking Goal bar fills to the LIVE progress, and the real
// streak badge pops with a confetti burst while the real checked
// day cells tick in one by one. Other arrivals show the tab
// static. Reduced motion disables it. Starting the Watch demo tour
// completes the entrance cleanly so the tour takes over.
//
// Live data in these tests is never hardcoded into the tab: the
// wallet holds 3 consecutive sign-in claims (30 pts, 3-day
// streak) from an in-memory ledger, and the walking controller
// reports 4,320 of 8,000 steps (54%) from a fake sensor. The tab
// must animate TO those values — the tests assert the end states
// equal them, and the mid-flight states are below them.
import 'dart:convert';

import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/points_wallet_repository.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:estudyantego/features/student/student_entrance.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:estudyantego/features/student/walking_repository.dart';
import 'package:estudyantego/features/student/walking_sensor.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:estudyantego/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

const _uid = 'uid-1';
const _user = AuthUser(
  uid: _uid,
  email: 'steven@example.com',
  displayName: 'Steven Reyes',
  emailVerified: true,
);

/// In-memory [PointsWalletRepository] with the same semantics as
/// the Firestore implementation (claim dedupe by reference ID,
/// reward-table validation, ledger-sum repair). Same shape as the
/// fake in points_wallet_test.dart, local to this file.
class _FakeWalletRepository implements PointsWalletRepository {
  final Map<String, PointsTransaction> _txns = {};

  @override
  Future<PointsWallet> fetchWallet(String uid) async {
    final entries = await fetchTransactions(uid);
    var sum = 0;
    for (final e in entries) {
      sum += e.points;
    }
    return PointsWallet(balance: sum, totalEarned: sum);
  }

  @override
  Future<List<PointsTransaction>> fetchTransactions(String uid) async {
    final entries =
        _txns.values.where((e) => e.userId == uid).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  @override
  Future<bool> claimSignin({
    required String uid,
    required String manilaDate,
    required int dayIndex,
    required int points,
  }) async {
    if (dayIndex < 1 || dayIndex > 7 || points != pointsForDay(dayIndex)) {
      throw ArgumentError(
        'Invalid sign-in reward: day $dayIndex = $points points',
      );
    }
    final ref = signinReferenceId(uid, manilaDate);
    if (_txns.containsKey(ref)) return false;
    _txns[ref] = PointsTransaction(
      id: ref,
      userId: uid,
      type: 'signin',
      points: points,
      description: signinDescription(dayIndex),
      source: 'signin',
      referenceId: ref,
      date: manilaDate,
      dayIndex: dayIndex,
      status: 'completed',
    );
    return true;
  }

  @override
  Future<int> migrateSignin({
    required String uid,
    required List<CheckinRecord> records,
  }) async {
    return 0;
  }
}

/// Live data for the entrance: a wallet with 3 consecutive
/// sign-in days (30 pts, 3-day streak) and a walking controller
/// at 4,320 of 8,000 steps (54% progress). Both are real
/// controller state, not values typed into the tab.
class _LiveState {
  _LiveState({
    required this.wallet,
    required this.walking,
    required this.sensor,
  });

  final PointsWalletController wallet;
  final WalkingController walking;
  final FakeWalkingSensor sensor;
}

Future<_LiveState> _buildLiveState(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  // Wallet: claims on Manila Nov 8, 9 and 10, 2026 (10 pts each).
  // The clock ends on Nov 10, so the streak (3) and the checked
  // cells (3) both end today.
  final repo = _FakeWalletRepository();
  var clock = DateTime.utc(2026, 11, 8, 2); // Manila Nov 8, 10:00.
  final wallet = PointsWalletController(
    repository: repo,
    clock: () => clock,
  );
  await wallet.loadForUser(_uid);
  for (var i = 0; i < 3; i++) {
    final outcome = await wallet.claimToday();
    expect(outcome.status, ClaimStatus.credited);
    clock = clock.add(const Duration(days: 1));
  }
  clock = DateTime.utc(2026, 11, 10, 2); // Back to Manila Nov 10.
  expect(wallet.balance, 30);
  expect(checkinStreak(wallet.derivedRecords, wallet.manilaToday), 3);

  // Walking: baseline 1,000 then +4,320 steps of the 8,000 goal.
  final sensor = FakeWalkingSensor();
  final permission = FakeActivityPermission(
    current: ActivityPermissionStatus.granted,
  );
  final walking = WalkingController(sensor: sensor, permission: permission);
  await walking.init();
  sensor.emit(1000);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  sensor.emit(5320);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  expect(walking.todaySteps, 4320);
  expect(walking.todayProgress, closeTo(0.54, 0.001));
  return _LiveState(wallet: wallet, walking: walking, sensor: sensor);
}

/// Tall viewport so the full StudentTab list builds (every
/// entrance item laid out).
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpTab(
  WidgetTester tester,
  _LiveState live, {
  bool playEntrance = false,
  bool startWatchTour = false,
  VoidCallback? onEntranceConsumed,
  VoidCallback? onWatchTourConsumed,
  bool disableAnimations = false,
  bool settle = true,
}) async {
  _tallScreen(tester);
  final tab = StudentTab(
    user: _user,
    walletController: live.wallet,
    walkingController: live.walking,
    playEntrance: playEntrance,
    onEntranceConsumed: onEntranceConsumed,
    startWatchTour: startWatchTour,
    onWatchTourConsumed: onWatchTourConsumed,
  );
  final child = disableAnimations
      ? MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: tab,
        )
      : tab;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(),
      themeMode: ThemeMode.light,
      home: Scaffold(body: StudentHubTheme(child: child)),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await _pumpUntilLoaded(tester);
  }
}

/// Pumps zero-duration frames until the tab has loaded (the Watch
/// demo button is up) — never a settle, so a playing entrance or
/// tour clock is not fast-forwarded.
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  for (var i = 0; i < 50; i++) {
    await tester.pump();
    if (find
        .byKey(const ValueKey('watch-demo-button'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
  }
  fail('Student tab did not load');
}

/// The at-a-glance Points value right now.
String _pointsText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('at-a-glance-points'))).data!;

/// The Walking Goal bar's fill right now (0..1).
double _walkingBarValue(WidgetTester tester) {
  final bar = find.descendant(
    of: find.byKey(const ValueKey('walking-hub-card')),
    matching: find.byType(LinearProgressIndicator),
  );
  return tester.widget<LinearProgressIndicator>(bar).value ?? -1;
}

/// How many sign-in day tiles are ticked in right now.
int _checkedTiles(WidgetTester tester) => find
    .descendant(
      of: find.byKey(const ValueKey('signin-hub-card')),
      matching: find.byIcon(Icons.check_circle_rounded),
    )
    .evaluate()
    .length;

/// The tour is up when its caption line is on screen.
bool _tourUp(WidgetTester tester) =>
    find.textContaining('· How to use').evaluate().isNotEmpty;

void main() {
  group('entrance helpers (pure)', () {
    test('stagger items start at 0, end at 1, in order', () {
      expect(entranceItemProgress(0, 0), 0);
      expect(entranceItemProgress(1, 14), 1);
      // The first item is already moving while the last has not
      // started yet.
      final early = entranceItemProgress(0.1, 0);
      final late = entranceItemProgress(0.1, 14);
      expect(early, greaterThan(0));
      expect(late, 0);
      // Monotonic in controller value for one item.
      var prev = 0.0;
      for (var v = 0.0; v <= 1.0; v += 0.1) {
        final p = entranceItemProgress(v, 4);
        expect(p, greaterThanOrEqualTo(prev));
        prev = p;
      }
    });

    test('points count-up runs 0 -> the live target, never over', () {
      expect(entranceCountUp(30, 0), 0);
      expect(entranceCountUp(30, 1), 30);
      expect(entranceCountUp(30, 0.5), inInclusiveRange(1, 29));
      expect(entranceCountUp(0, 1), 0);
    });

    test('checked cells tick in one by one, never over the real count',
        () {
      expect(entranceCheckedCells(3, 0), 0);
      expect(entranceCheckedCells(3, 1), 3);
      expect(entranceCheckedCells(3, 0.5), 1);
      expect(entranceCheckedCells(3, 0.99), 2);
      expect(entranceCheckedCells(0, 1), 0);
    });
  });

  group('StudentTab entrance', () {
    testWidgets(
      'plays once after Welcome Back: points count up to the live '
      'balance with a floating chip, then never replays',
      (tester) async {
        final live = await _buildLiveState(tester);
        var consumed = 0;
        await _pumpTab(
          tester,
          live,
          playEntrance: true,
          onEntranceConsumed: () => consumed++,
          settle: false,
        );
        // Early in the entrance the count has barely started.
        await tester.pump(const Duration(milliseconds: 100));
        expect(_pointsText(tester), '0');
        // Mid-entrance: counting, with the floating "+30 pts" chip.
        await tester.pump(const Duration(milliseconds: 300));
        final mid = int.parse(_pointsText(tester));
        expect(mid, inInclusiveRange(1, 29));
        expect(find.byKey(entrancePointsFloatKey), findsOneWidget);
        expect(find.text('+30 pts'), findsOneWidget);
        expect(consumed, 1);

        await tester.pumpAndSettle();
        // End state: the LIVE balance, chip gone, consumed once.
        expect(_pointsText(tester), '30');
        expect(find.byKey(entrancePointsFloatKey), findsNothing);
        expect(consumed, 1);

        // A rebuild with the flag still true must NOT replay: the
        // points stay at the live balance immediately, with no
        // zero phase and no chip.
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            themeMode: ThemeMode.light,
            home: Scaffold(
              body: StudentHubTheme(
                child: StudentTab(
                  user: _user,
                  walletController: live.wallet,
                  walkingController: live.walking,
                  playEntrance: true,
                  onEntranceConsumed: () => consumed++,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(_pointsText(tester), '30');
        expect(find.byKey(entrancePointsFloatKey), findsNothing);
        expect(consumed, 1);
        live.walking.dispose();
      },
    );

    testWidgets('does NOT play on other arrivals at the tab',
        (tester) async {
      final live = await _buildLiveState(tester);
      var consumed = 0;
      await _pumpTab(
        tester,
        live,
        playEntrance: false,
        onEntranceConsumed: () => consumed++,
      );
      // Static from the first frame: live values at once, no
      // entrance overlays, flag never consumed.
      expect(_pointsText(tester), '30');
      expect(_walkingBarValue(tester), closeTo(0.54, 0.01));
      expect(_checkedTiles(tester), 3);
      expect(find.byKey(entrancePointsFloatKey), findsNothing);
      expect(find.byKey(entranceConfettiKey), findsNothing);
      expect(consumed, 0);
      live.walking.dispose();
    });

    testWidgets('Walking Goal bar fills 0 -> the live progress',
        (tester) async {
      final live = await _buildLiveState(tester);
      await _pumpTab(tester, live, playEntrance: true, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_walkingBarValue(tester), 0.0);
      await tester.pump(const Duration(milliseconds: 500));
      final mid = _walkingBarValue(tester);
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(0.54));
      await tester.pumpAndSettle();
      expect(_walkingBarValue(tester), closeTo(0.54, 0.01));
      live.walking.dispose();
    });

    testWidgets(
      'streak badge ticks in the real checked days with a '
      'confetti burst',
      (tester) async {
        final live = await _buildLiveState(tester);
        await _pumpTab(tester, live, playEntrance: true, settle: false);
        await tester.pump(const Duration(milliseconds: 300));
        expect(_checkedTiles(tester), 0);
        expect(find.byKey(entranceConfettiKey), findsNothing);
        // The burst fires as the sign-in card lands; the cells
        // tick in one by one after it.
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byKey(entranceConfettiKey), findsOneWidget);
        expect(_checkedTiles(tester), 1);
        await tester.pumpAndSettle();
        expect(_checkedTiles(tester), 3);
        expect(find.byKey(entranceConfettiKey), findsNothing);
        expect(find.text('Day 3 of 7'), findsOneWidget);
        expect(find.text('3 days'), findsOneWidget);
        live.walking.dispose();
      },
    );

    testWidgets('reduced motion disables the entrance entirely',
        (tester) async {
      final live = await _buildLiveState(tester);
      var consumed = 0;
      await _pumpTab(
        tester,
        live,
        playEntrance: true,
        onEntranceConsumed: () => consumed++,
        disableAnimations: true,
      );
      // The finished tab, instantly: live values, no overlays —
      // but the flag is still consumed exactly once.
      expect(_pointsText(tester), '30');
      expect(_walkingBarValue(tester), closeTo(0.54, 0.01));
      expect(_checkedTiles(tester), 3);
      expect(find.byKey(entrancePointsFloatKey), findsNothing);
      expect(find.byKey(entranceConfettiKey), findsNothing);
      expect(consumed, 1);
      live.walking.dispose();
    });

    testWidgets('starting the tour cancels the entrance cleanly',
        (tester) async {
      final live = await _buildLiveState(tester);
      var consumed = 0;
      await _pumpTab(
        tester,
        live,
        playEntrance: true,
        onEntranceConsumed: () => consumed++,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(int.parse(_pointsText(tester)), lessThan(30));
      await tester.tap(find.byKey(const ValueKey('watch-demo-button')));
      // Wait for the tour caption (bounded — the tour's pulsing
      // ring means pumpAndSettle never settles here).
      for (var i = 0; i < 20 && !_tourUp(tester); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // The tour is up, and the entrance is finished at its live
      // end states — nothing half-animated underneath it.
      expect(_tourUp(tester), isTrue);
      expect(find.text('1 of 9 · How to use'), findsOneWidget);
      expect(_pointsText(tester), '30');
      expect(_walkingBarValue(tester), closeTo(0.54, 0.01));
      expect(_checkedTiles(tester), 3);
      expect(find.byKey(entrancePointsFloatKey), findsNothing);
      expect(find.byKey(entranceConfettiKey), findsNothing);
      expect(consumed, 1);
      live.walking.dispose();
    });

    testWidgets('an auto-started tour wins over the entrance',
        (tester) async {
      final live = await _buildLiveState(tester);
      var entranceConsumed = 0;
      var tourConsumed = 0;
      await _pumpTab(
        tester,
        live,
        playEntrance: true,
        startWatchTour: true,
        onEntranceConsumed: () => entranceConsumed++,
        onWatchTourConsumed: () => tourConsumed++,
        settle: false,
      );
      // Wait for the tour caption (bounded — the tour's pulsing
      // ring means pumpAndSettle never settles here).
      for (var i = 0; i < 40 && !_tourUp(tester); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(_tourUp(tester), isTrue);
      expect(tourConsumed, 1);
      // The entrance was skipped, not played: live values at
      // once, no entrance overlays — but still consumed once.
      expect(_pointsText(tester), '30');
      expect(_walkingBarValue(tester), closeTo(0.54, 0.01));
      expect(_checkedTiles(tester), 3);
      expect(find.byKey(entrancePointsFloatKey), findsNothing);
      expect(find.byKey(entranceConfettiKey), findsNothing);
      expect(entranceConsumed, 1);
      live.walking.dispose();
    });
  });

  group('Welcome Back gate flow (entrance trigger)', () {
    testWidgets(
      'Sign In -> Welcome Back -> Student tab entrance is armed '
      'once, consumed, and never replays on return',
      (tester) async {
        // Phone viewport: the shell renders the icon-only top
        // nav (keys top-nav-item-*) instead of the wide sidebar.
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = FakeAuthService();
        await auth.createAccount(
          email: 'steven@example.com',
          password: 'secret1',
          displayName: 'Steven Reyes',
        );
        auth.markCurrentUserVerified();
        await auth.signOut();
        final uid = 'uid-${'steven@example.com'.hashCode}';
        SharedPreferences.setMockInitialValues({
          'byahetayo_onboarding_done': true,
          'byahetayo_notification_prompt_shown': true,
          'byahetayo_profile_setup_done_$uid': true,
          'byahetayo_profile_$uid': jsonEncode(
            const UserProfile(
              displayName: 'Steven Reyes',
              email: 'steven@example.com',
            ).toJson(),
          ),
        });
        await tester.pumpWidget(EstudyanteGOApp(authService: auth));
        await tester.pumpAndSettle();
        expect(find.text('Welcome Back'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'Email'),
          'steven@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          'secret1',
        );
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign In'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
        await tester.pump();
        for (var i = 0; i < 40; i++) {
          if (find.text('Welcome back, Steven!').evaluate().isNotEmpty) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Welcome back, Steven!'), findsOneWidget);
        // The tour hook stays disarmed on the Sign In path.
        expect(
          find.text('You know how to use the app?'),
          findsNothing,
        );

        // Overlay auto-advances after ~2 s. The moment it ends,
        // _finishWelcomeBack arms the entrance: the freshly
        // mounted Student tab must carry playEntrance true at
        // least once before the tab consumes it on start. (The
        // animation itself is covered by the bare-tab tests with
        // live wallet + walking data; the shell wallet is
        // local-only here, so this test asserts the wiring.)
        var sawArmed = false;
        await tester.pump(const Duration(milliseconds: 2100));
        for (var i = 0; i < 20; i++) {
          final tab = find.byType(StudentTab).evaluate().isNotEmpty
              ? tester.widget<StudentTab>(find.byType(StudentTab))
              : null;
          if (tab != null && tab.playEntrance) {
            sawArmed = true;
            break;
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(sawArmed, isTrue);

        await tester.pumpAndSettle();
        expect(find.text('Welcome back, Steven!'), findsNothing);
        expect(find.text('Student Hub', skipOffstage: true), findsOneWidget);
        // Consumed: the flag is cleared, so the entrance can
        // never re-fire on a later visit.
        expect(
          tester.widget<StudentTab>(find.byType(StudentTab)).playEntrance,
          isFalse,
        );
        expect(find.byKey(entranceConfettiKey), findsNothing);
        expect(find.byKey(entrancePointsFloatKey), findsNothing);

        // Leave the tab and come back: still disarmed, no replay.
        await tester.tap(find.byKey(const Key('top-nav-item-Study')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('top-nav-item-Student')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.widget<StudentTab>(find.byType(StudentTab)).playEntrance,
          isFalse,
        );
        expect(find.byKey(entranceConfettiKey), findsNothing);
        expect(find.byKey(entrancePointsFloatKey), findsNothing);
      },
    );
  });
}
