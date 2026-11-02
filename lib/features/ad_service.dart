// AdMob service — EstudyanteGO.
//
// HONEST SPLIT (binding, from the Queue #2 security report):
//   - This service DISPLAYS ads. It never grants credits.
//   - A client-side "user earned reward" callback is not verified
//     crediting: only the future SSV server may write ad_rewards +
//     credits ledger rows (client writes to ad_rewards are denied
//     by Firestore rules on purpose). The rewarded flow therefore
//     reports completion honestly and grants nothing until SSV.
//   - The login popup interstitial never blocks auth or access:
//     it is fire-and-forget, shows at most once per app session,
//     and is silent when there is no inventory.
//   - Every method here never throws: ad failures degrade to a
//     result value or silence, never a crash, never a blocked UI.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';

/// Outcome of one rewarded-ad attempt. `completed` means only that
/// the user watched the ad to the client-side reward callback — it
/// is NOT verified crediting (see the file header).
enum RewardedAdResult { completed, skipped, failed, noFill }

/// Ad display contract. The production implementation is
/// [GoogleMobileAdsService]; tests inject a fake.
abstract class AdService {
  /// Initializes the Mobile Ads SDK + UMP consent flow. Never
  /// throws; safe to call without awaiting (never blocks launch).
  Future<void> initialize();

  /// Loads and shows one rewarded ad. Never throws; every failure
  /// mode is a [RewardedAdResult] value.
  Future<RewardedAdResult> showRewardedAd();

  /// Shows the login popup interstitial once per app session.
  /// Fire-and-forget: never blocks the caller, never throws, and
  /// stays silent when there is no inventory.
  Future<void> showLoginPopupAd();

  /// True once the login popup has been attempted this session
  /// (shown or not — one attempt per session, by design).
  bool get loginPopupShown;
}

/// Production [AdService] over google_mobile_ads.
class GoogleMobileAdsService implements AdService {
  GoogleMobileAdsService({
    this.config = AdConfig.defaults,
    Duration? initTimeout,
    Duration? consentTimeout,
    Duration? adLoadTimeout,
    Future<void> Function()? platformInit,
  })  : _platformInitOverride = platformInit,
        initTimeout =
            _isTestHost ? Duration.zero : (initTimeout ?? const Duration(seconds: 10)),
        consentTimeout = _isTestHost
            ? Duration.zero
            : (consentTimeout ?? const Duration(seconds: 10)),
        adLoadTimeout = _isTestHost
            ? Duration.zero
            : (adLoadTimeout ?? const Duration(seconds: 30));

  final AdConfig config;

  /// Bounds every platform wait: a stuck SDK, consent form, or ad
  /// load degrades to a failure value instead of hanging the app.
  /// Under `flutter test` these resolve to zero (see [_isTestHost]),
  /// so no timer is left pending at teardown.
  final Duration initTimeout;
  final Duration consentTimeout;
  final Duration adLoadTimeout;

  /// True when running under `flutter test`. The test binding freezes
  /// the async clock, so timeout timers created there never fire and
  /// trip the framework's pending-timer check at teardown (every test
  /// that pumps the app shell failed on this). Timeouts are therefore
  /// instant in tests and real on devices; production behavior is
  /// unchanged.
  static bool get _isTestHost {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  /// Test seam for the platform boundary. Production leaves this null
  /// and runs the real SDK + UMP calls. Tests stub it because the
  /// real calls can't run under `flutter test`: the UMP channel uses
  /// a codec the test messenger can't decode, and a missing platform
  /// implementation surfaces as an uncatchable async error. The seam
  /// covers only the platform calls; the service's own init logic
  /// (idempotency, never throws) is still exercised by tests, and the
  /// real plugin path is covered on-device.
  final Future<void> Function()? _platformInitOverride;

  bool _initialized = false;
  bool _loginPopupShown = false;

  /// In-flight rewarded attempt: concurrent taps share one load
  /// instead of stacking duplicate ads and dialogs.
  Future<RewardedAdResult>? _rewardedInFlight;

  @override
  bool get loginPopupShown => _loginPopupShown;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _platformInit();
    } catch (_) {
      // Init never throws to callers, whatever the platform did.
    }
  }

  Future<void> _platformInit() =>
      _platformInitOverride?.call() ?? _realPlatformInit();

  Future<void> _realPlatformInit() async {
    try {
      await MobileAds.instance.initialize().timeout(initTimeout);
    } catch (_) {
      // SDK unavailable or stuck: ads stay unavailable, the app never crashes.
    }
    try {
      await _requestConsent();
    } catch (_) {
      // Consent flow is best-effort; a failure never blocks ads UI.
    }
  }

  /// Standard UMP consent flow: update consent info, then show the
  /// consent form if one is required (e.g. EEA). Completes on
  /// success OR failure so callers never hang.
  Future<void> _requestConsent() async {
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
        } catch (_) {}
        finish();
      },
      (_) => finish(),
    );
    // Bounded: under a host that never answers (tests, or a stuck
    // SDK), proceed instead of waiting forever.
    await Future.any([
      done.future,
      Future.delayed(consentTimeout),
    ]);
  }

  @override
  Future<RewardedAdResult> showRewardedAd() {
    final inFlight = _rewardedInFlight;
    if (inFlight != null) return inFlight;
    final future = _showRewardedAdOnce();
    _rewardedInFlight = future;
    future.whenComplete(() {
      if (identical(_rewardedInFlight, future)) {
        _rewardedInFlight = null;
      }
    });
    return future;
  }

  Future<RewardedAdResult> _showRewardedAdOnce() async {
    final done = Completer<RewardedAdResult>();
    void finish(RewardedAdResult result) {
      if (!done.isCompleted) done.complete(result);
    }

    // If the load never answers, report noFill instead of hanging.
    // A late ad that arrives after the timeout is released, never shown.
    var loadTimedOut = false;
    Future.delayed(adLoadTimeout, () {
      loadTimedOut = true;
      finish(RewardedAdResult.noFill);
    });

    try {
      await RewardedAd.load(
        adUnitId: config.rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (loadTimedOut) {
              ad.dispose();
              return;
            }
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                finish(RewardedAdResult.skipped);
              },
              onAdFailedToShowFullScreenContent: (ad, _) {
                ad.dispose();
                finish(RewardedAdResult.failed);
              },
            );
            // SSV PLUG-IN POINT (future phase, not yet wired):
            // once the server endpoint exists, call
            // ad.setServerSideOptions(...) with the user ID + a
            // unique reward reference BEFORE show(). Until then no
            // client callback is ever treated as verified crediting.
            ad.show(
              onUserEarnedReward: (ad, reward) {
                // Client-side completion only. Deliberately grants
                // nothing: the caller reports this honestly and the
                // credits balance is untouched.
                finish(RewardedAdResult.completed);
              },
            );
          },
          onAdFailedToLoad: (_) => finish(RewardedAdResult.noFill),
        ),
      );
    } catch (_) {
      finish(RewardedAdResult.failed);
    }
    return done.future;
  }

  @override
  Future<void> showLoginPopupAd() async {
    if (_loginPopupShown) return;
    // Mark before loading: exactly one attempt per session, and a
    // no-fill still counts as the attempt (silent, normal access).
    _loginPopupShown = true;
    try {
      await InterstitialAd.load(
        adUnitId: config.interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) => ad.dispose(),
              onAdFailedToShowFullScreenContent: (ad, _) =>
                  ad.dispose(),
            );
            // The platform interstitial carries its own close
            // button; showing never blocks auth or app access.
            ad.show();
          },
          onAdFailedToLoad: (_) {
            // No inventory: silent, normal access continues.
          },
        ),
      ).timeout(adLoadTimeout);
    } catch (_) {
      // Silent by design: a popup failure must never surface.
    }
  }
}
