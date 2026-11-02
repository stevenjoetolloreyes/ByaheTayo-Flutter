// AdMob configuration — EstudyanteGO.
//
// HOW THE REAL IDS GET IN (one web-edit session, never chat):
//   1. Replace the three PLACEHOLDER constants below with the real
//      AdMob IDs from the AdMob dashboard (rewarded + interstitial
//      ad unit IDs). The App ID is NOT configured from Dart code:
//   2. Replace the Google test App ID in
//      android/app/src/main/AndroidManifest.xml (the APPLICATION_ID
//      meta-data) and ios/Runner/Info.plist (GADApplicationIdentifier)
//      with the real App IDs, in the same web-edit session.
//   Until the placeholders are replaced, every ID resolves to
//   Google's OFFICIAL TEST IDs, so the ad flows are verifiable with
//   zero policy risk: test ads never grant credits, and live ads
//   must never be clicked during development.
//
// VERIFIED CREDITING (honest split, binding):
//   - A client-side "user earned reward" callback is NEVER treated
//     as verified crediting. The 0.50-credits-per-verified-ad rule
//     is applied server-side once the SSV (server-side verification)
//     endpoint exists; until then the rewarded flow shows an honest
//     "verified crediting awaits SSV" state and grants nothing.
//   - The SSV phase plugs in at AdService: it will call
//     setServerSideOptions on the loaded rewarded ad (with the user
//     ID + a unique reward reference) before show(), and the server
//     will write the ad_rewards row + credits ledger row via the
//     Admin SDK. The client never writes ad_rewards (rules deny
//     client create/update/delete on that collection by design).
import 'dart:io' show Platform;

/// Placeholder marker: any ID still containing this segment is
/// unset and resolves to the matching Google test ID.
const _kPlaceholderSegment = '0000000000';

// --- Real-ID placeholders: replace via ONE GitHub web edit. ---
const String kAdMobAppIdAndroidPlaceholder =
    'ca-app-pub-1876880154950897/6899090347';
const String kAdMobAppIdIosPlaceholder =
    'ca-app-pub-0000000000000000~0000000000';
const String kAdMobRewardedAndroidPlaceholder =
    'ca-app-pub-1876880154950897/3586531296';
const String kAdMobRewardedIosPlaceholder =
    'ca-app-pub-0000000000000000/0000000000';
const String kAdMobInterstitialAndroidPlaceholder =
    'ca-app-pub-0000000000000000/0000000000';
const String kAdMobInterstitialIosPlaceholder =
    'ca-app-pub-0000000000000000/0000000000';

// --- Google's OFFICIAL TEST IDs (public, safe for development). ---
const String kTestAppIdAndroid = 'ca-app-pub-3940256099942544~3347511713';
const String kTestAppIdIos = 'ca-app-pub-3940256099942544~1458002511';
const String kTestRewardedAndroid =
    'ca-app-pub-3940256099942544/5224354917';
const String kTestRewardedIos = 'ca-app-pub-3940256099942544/1712485313';
const String kTestInterstitialAndroid =
    'ca-app-pub-3940256099942544/1033173712';
const String kTestInterstitialIos =
    'ca-app-pub-3940256099942544/4411468910';

bool _isPlaceholder(String id) => id.contains(_kPlaceholderSegment);

/// Resolved AdMob IDs for the running app.
///
/// Each ID resolves independently: a placeholder value falls back to
/// the matching Google test ID; a real value is used as-is. On
/// non-mobile hosts (widget tests) the Android test IDs are used.
class AdConfig {
  const AdConfig({
    this.appIdAndroid = kAdMobAppIdAndroidPlaceholder,
    this.appIdIos = kAdMobAppIdIosPlaceholder,
    this.rewardedAdUnitIdAndroid = kAdMobRewardedAndroidPlaceholder,
    this.rewardedAdUnitIdIos = kAdMobRewardedIosPlaceholder,
    this.interstitialAdUnitIdAndroid =
        kAdMobInterstitialAndroidPlaceholder,
    this.interstitialAdUnitIdIos = kAdMobInterstitialIosPlaceholder,
  });

  /// Production default: placeholders until the web edit fills them.
  static const AdConfig defaults = AdConfig();

  final String appIdAndroid;
  final String appIdIos;
  final String rewardedAdUnitIdAndroid;
  final String rewardedAdUnitIdIos;
  final String interstitialAdUnitIdAndroid;
  final String interstitialAdUnitIdIos;

  /// The rewarded ad unit ID in effect on this platform.
  String get rewardedAdUnitId {
    if (Platform.isIOS) {
      return _isPlaceholder(rewardedAdUnitIdIos)
          ? kTestRewardedIos
          : rewardedAdUnitIdIos;
    }
    return _isPlaceholder(rewardedAdUnitIdAndroid)
        ? kTestRewardedAndroid
        : rewardedAdUnitIdAndroid;
  }

  /// The interstitial ad unit ID in effect on this platform.
  String get interstitialAdUnitId {
    if (Platform.isIOS) {
      return _isPlaceholder(interstitialAdUnitIdIos)
          ? kTestInterstitialIos
          : interstitialAdUnitIdIos;
    }
    return _isPlaceholder(interstitialAdUnitIdAndroid)
        ? kTestInterstitialAndroid
        : interstitialAdUnitIdAndroid;
  }

  /// True while the ad units in effect are Google test IDs (i.e.
  /// the real IDs have not been filled in yet). The UI says so
  /// plainly instead of implying live ads.
  bool get usesTestIds {
    if (Platform.isIOS) {
      return _isPlaceholder(rewardedAdUnitIdIos) &&
          _isPlaceholder(interstitialAdUnitIdIos);
    }
    return _isPlaceholder(rewardedAdUnitIdAndroid) &&
        _isPlaceholder(interstitialAdUnitIdAndroid);
  }
}
