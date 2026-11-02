// Ads phase tests: config resolution, service contract (fake),
// and Rewards screen ad UI. No real network, no real ad objects:
// the fake stands in for the AdMob SDK, and the real service is
// only asserted to never throw under the test host (where platform
// channels are absent).
import 'package:estudyantego/features/ad_config.dart';
import 'package:estudyantego/features/ad_service.dart';
import 'package:estudyantego/features/rewards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake AdService: deterministic results, call counting, and the
/// same once-per-session login-popup rule as the real service.
class FakeAdService implements AdService {
  FakeAdService({this.rewardedResult = RewardedAdResult.completed});

  RewardedAdResult rewardedResult;
  int rewardedCalls = 0;
  int loginPopupCalls = 0;
  bool _loginPopupShown = false;

  @override
  bool get loginPopupShown => _loginPopupShown;

  @override
  Future<void> initialize() async {}

  @override
  Future<RewardedAdResult> showRewardedAd() async {
    rewardedCalls++;
    return rewardedResult;
  }

  @override
  Future<void> showLoginPopupAd() async {
    if (_loginPopupShown) return;
    _loginPopupShown = true;
    loginPopupCalls++;
  }
}

void main() {
  group('AdConfig', () {
    test('placeholder values resolve to Google test IDs on this host', () {
      // Explicit placeholders, NOT AdConfig.defaults: the defaults are
      // the committed constants, whose values become real once the
      // user fills them in via web edit — so a defaults-based test
      // breaks on any checkout with real IDs (CI). Testing the
      // fallback with literal placeholders keeps this checkout-safe.
      const config = AdConfig(
        rewardedAdUnitIdAndroid: 'ca-app-pub-0000000000000000/0000000000',
        interstitialAdUnitIdAndroid: 'ca-app-pub-0000000000000000/0000000000',
      );
      expect(config.rewardedAdUnitId, kTestRewardedAndroid);
      expect(config.interstitialAdUnitId, kTestInterstitialAndroid);
      expect(config.usesTestIds, isTrue);
    });

    test('real (non-placeholder) IDs are used as-is', () {
      const config = AdConfig(
        rewardedAdUnitIdAndroid: 'ca-app-pub-1234567890123456/1234567890',
        interstitialAdUnitIdAndroid: 'ca-app-pub-1234567890123456/1234567890',
      );
      expect(config.rewardedAdUnitId, 'ca-app-pub-1234567890123456/1234567890');
      expect(
        config.interstitialAdUnitId,
        'ca-app-pub-1234567890123456/1234567890',
      );
      expect(config.usesTestIds, isFalse);
    });

    test('a partially filled config still uses test IDs for the rest', () {
      const config = AdConfig(
        rewardedAdUnitIdAndroid: 'ca-app-pub-1234567890123456/1234567890',
        // Explicit placeholder: leaving this at its default would
        // pick up the committed constant, which is real on CI.
        interstitialAdUnitIdAndroid: 'ca-app-pub-0000000000000000/0000000000',
      );
      expect(config.rewardedAdUnitId, 'ca-app-pub-1234567890123456/1234567890');
      expect(config.interstitialAdUnitId, kTestInterstitialAndroid);
      expect(config.usesTestIds, isFalse);
    });
  });

  group('FakeAdService contract', () {
    test('rewarded returns the configured result', () async {
      final fake = FakeAdService(rewardedResult: RewardedAdResult.skipped);
      expect(await fake.showRewardedAd(), RewardedAdResult.skipped);
      expect(fake.rewardedCalls, 1);
    });

    test('login popup fires at most once per session', () async {
      final fake = FakeAdService();
      await fake.showLoginPopupAd();
      await fake.showLoginPopupAd();
      await fake.showLoginPopupAd();
      expect(fake.loginPopupCalls, 1);
      expect(fake.loginPopupShown, isTrue);
    });

    test('initialize never throws', () async {
      await FakeAdService().initialize();
    });
  });

  // testWidgets (not plain test) so a binding exists; the plugin
  // channels themselves are unmocked, which is exactly the point:
  // every call must degrade cleanly instead of throwing.
  group('GoogleMobileAdsService robustness (no platform channels)', () {
    // Short service timeouts so the timeout paths run fast, and
    // runAsync so real timers fire: under plain testWidgets the
    // fake async clock is frozen, so a Future.timeout never fires
    // and the test hangs instead of degrading (the original bug).
    GoogleMobileAdsService fastService() => GoogleMobileAdsService(
      initTimeout: const Duration(seconds: 1),
      consentTimeout: const Duration(seconds: 1),
      adLoadTimeout: const Duration(seconds: 1),
    );

    testWidgets('initialize completes without throwing', (tester) async {
      await tester.pumpWidget(const SizedBox());
      // The platform boundary is stubbed (see platformInit in
      // GoogleMobileAdsService): the real AdMob/UMP calls can't run
      // in tests, so this covers the service's own init path —
      // idempotent, never throws — and the real plugin path is
      // covered on-device.
      final service = GoogleMobileAdsService(platformInit: () async {});
      await tester.runAsync(() => service.initialize());
      await tester.runAsync(() => service.initialize());
    });

    testWidgets('showRewardedAd degrades to a result, never throws', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      final result = await tester.runAsync(
        () => fastService().showRewardedAd(),
      );
      expect(RewardedAdResult.values, contains(result));
    });

    testWidgets('showLoginPopupAd is silent and once-only', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final service = fastService();
      await tester.runAsync(() => service.showLoginPopupAd());
      expect(service.loginPopupShown, isTrue);
      await service.showLoginPopupAd();
      expect(service.loginPopupShown, isTrue);
    });
  });

  group('RewardsScreen Watch Ads UI', () {
    Future<void> pumpRewards(WidgetTester tester, AdService? service) {
      return tester.pumpWidget(
        MaterialApp(
          home: RewardsScreen(
            pointsBalance: 350,
            onOpenStudentHub: () {},
            adService: service,
          ),
        ),
      );
    }

    testWidgets('without a service keeps the honest no-ads notice', (
      tester,
    ) async {
      await pumpRewards(tester, null);
      expect(find.textContaining('Not available yet'), findsOneWidget);
      expect(find.text('Watch ad'), findsNothing);
    });

    testWidgets('completed ad reports honestly: no credits granted', (
      tester,
    ) async {
      final fake = FakeAdService(rewardedResult: RewardedAdResult.completed);
      await pumpRewards(tester, fake);
      await tester.ensureVisible(find.text('Watch ad'));
      await tester.tap(find.text('Watch ad'));
      await tester.pumpAndSettle();
      expect(fake.rewardedCalls, 1);
      expect(find.textContaining('not verified crediting'), findsOneWidget);
      expect(find.textContaining('no credits were granted'), findsOneWidget);
    });

    testWidgets('skipped ad reports no credits granted', (tester) async {
      final fake = FakeAdService(rewardedResult: RewardedAdResult.skipped);
      await pumpRewards(tester, fake);
      await tester.ensureVisible(find.text('Watch ad'));
      await tester.tap(find.text('Watch ad'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ad not completed — no credits granted.'),
        findsOneWidget,
      );
    });

    testWidgets('no-fill reports no ad available', (tester) async {
      final fake = FakeAdService(rewardedResult: RewardedAdResult.noFill);
      await pumpRewards(tester, fake);
      await tester.ensureVisible(find.text('Watch ad'));
      await tester.tap(find.text('Watch ad'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No ad available right now'), findsOneWidget);
    });
  });
}
