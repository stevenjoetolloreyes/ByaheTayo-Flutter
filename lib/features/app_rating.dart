// "Rate this EstudyanteGO App" — floating feedback (Nov 9, 2026).
//
// Flow (approved HTML preview `rate-this-estudyantego-app-preview`):
// nothing shows on first open. After the student has done 3 real
// in-app actions, a floating emerald "Rate this app" pill appears
// over every tab and the "Satisfied?" card pops up once.
// "Yes, satisfied" reveals 5 stars; "Not yet" jumps straight to
// "What can we improve?" (topic chips + optional comment) and can
// send without a star. Send saves to Firestore collection
// `app_ratings` — the app is NOT on Google Play yet (Play
// distribution Jan 21, 2027), so there is no Play Store rating
// link; Steven reads the ratings in Firestore. After sending, the
// card closes immediately, a small "Thank you!" popup shows at the
// top for 5 seconds, and the Rate button disappears completely.
// The prompt is one-time only per app version: it returns only
// after the next app update, and then only after 3 real actions
// again.
//
// Only REAL user actions unlock the prompt — never auto-counted,
// never faked. The action set and the rated flag are both keyed by
// app version, so a new version starts fresh.
//
// NOTE: Firestore needs a rule for `app_ratings` (allow create for
// signed-in users) before writes succeed. Until that rule is
// published, submit() returns false and the card shows an honest
// error instead of pretending the feedback was sent — the student
// is never marked rated on a failed write.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diagnostics/error_log_entry.dart';

/// App version the rating prompt is keyed to. Mirrors `version:` in
/// pubspec.yaml via the diagnostics constants (the same single
/// source — bump together with pubspec.yaml; the test in
/// test/app_rating_test.dart fails if they drift).
String get appRatingVersion =>
    '$kDiagnosticsAppVersion+$kDiagnosticsAppBuildNumber';

/// How many DISTINCT real actions unlock the rating prompt.
const int appRatingActionsToUnlock = 3;

/// Real user actions that count toward unlocking the prompt. Only
/// genuine taps the student performs are recorded — never
/// auto-counted, never faked. Three DISTINCT actions unlock the
/// prompt (repeating one action does not unlock it).
enum AppRatingAction {
  /// Opened a fare breakdown sheet (Fares tab).
  checkedFare,

  /// Jumped to the Map with a route ("Show direction on Map").
  viewedRouteOnMap,

  /// Start Ride (Live Follow) from the fare breakdown sheet.
  startedRide,

  /// Opened a note to read it (Study tab).
  openedNotes,

  /// Opened a quiz / flashcard / AI-quiz review flow (Study tab).
  startedReview,

  /// Liked or disliked a Communities post.
  interactedWithPost,
}

/// One submitted rating, as stored in Firestore `app_ratings`.
class AppRatingSubmission {
  const AppRatingSubmission({
    required this.satisfied,
    this.stars,
    required this.topics,
    required this.comment,
    required this.userId,
    required this.appVersion,
  });

  /// True = "Yes, satisfied", false = "Not yet".
  final bool satisfied;

  /// 1–5 when the student picked stars; null when they sent from
  /// the "Not yet" path without rating.
  final int? stars;

  /// Improve topics the student picked (may be empty).
  final List<String> topics;

  /// Optional free-text comment (may be empty).
  final String comment;

  /// Firebase UID, or null when the student is not signed in.
  final String? userId;

  /// App version at submission time (e.g. "3.5.1+2").
  final String appVersion;
}

/// Writes ratings to Firestore. Swappable so widget tests can use a
/// fake instead of the real backend.
abstract class AppRatingRepository {
  Future<void> submit(AppRatingSubmission submission);
}

/// Firestore `app_ratings` implementation. The document gets a
/// server timestamp; the client never invents one.
class FirestoreAppRatingRepository implements AppRatingRepository {
  FirestoreAppRatingRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<void> submit(AppRatingSubmission submission) async {
    await _firestore.collection('app_ratings').add(<String, dynamic>{
      'satisfied': submission.satisfied,
      'stars': submission.stars,
      'topics': submission.topics,
      'comment': submission.comment,
      'userId': submission.userId,
      'appVersion': submission.appVersion,
      'submittedAt': FieldValue.serverTimestamp(),
    });
  }
}

/// Owns the rating-prompt state: which real actions the student has
/// done (persisted, keyed by app version), whether they already
/// rated for this version, and the Firestore submit. A
/// [ChangeNotifier] so the shell overlay rebuilds when the prompt
/// unlocks or the button disappears.
///
/// Production code uses [instance]; tests construct their own
/// tracker with a fake repository (and optional fake prefs).
class AppRatingTracker extends ChangeNotifier {
  AppRatingTracker({
    SharedPreferences? prefs,
    AppRatingRepository? repository,
    String? appVersion,
  }) : _appVersion = appVersion ?? appRatingVersion {
    // Assigned here (not as initializing formals) so the public
    // parameter names stay `prefs` / `repository` while the fields
    // stay private.
    _prefs = prefs;
    _repository = repository;
  }

  AppRatingTracker._() : this();

  /// Production singleton. Tabs call `instance.recordAction(...)`;
  /// the shell overlay listens to it.
  static final AppRatingTracker instance = AppRatingTracker._();

  SharedPreferences? _prefs;
  AppRatingRepository? _repository;
  final String _appVersion;
  final Set<AppRatingAction> _actionsDone = {};
  bool _ratedForVersion = false;
  bool _initialized = false;

  String get _actionsKey => 'app_rating_actions_$_appVersion';
  String get _ratedKey => 'app_rating_rated_$_appVersion';

  String get appVersion => _appVersion;

  Set<AppRatingAction> get actionsDone => Set.unmodifiable(_actionsDone);

  bool get isUnlocked => _actionsDone.length >= appRatingActionsToUnlock;

  bool get hasRatedForVersion => _ratedForVersion;

  /// The pill + auto popup are shown only when the prompt unlocked
  /// and the student has not rated for this version.
  bool get showPrompt => isUnlocked && !_ratedForVersion;

  /// Loads the persisted action set + rated flag for this version.
  /// Never throws: a prefs failure falls back to in-memory state
  /// (the prompt still works this session).
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final stored = _prefs!.getStringList(_actionsKey) ?? const <String>[];
      for (final name in stored) {
        for (final action in AppRatingAction.values) {
          if (action.name == name) _actionsDone.add(action);
        }
      }
      _ratedForVersion = _prefs!.getBool(_ratedKey) ?? false;
      notifyListeners();
    } catch (_) {
      // In-memory only; the prompt still works this session.
    }
  }

  /// Records one real user action. Only distinct actions count
  /// toward the unlock (repeating one action does not unlock it).
  /// No-ops once the student already rated for this version.
  void recordAction(AppRatingAction action) {
    if (_ratedForVersion || _actionsDone.contains(action)) return;
    _actionsDone.add(action);
    unawaited(_prefs?.setStringList(
      _actionsKey,
      _actionsDone.map((a) => a.name).toList(),
    ));
    notifyListeners();
  }

  /// Sends the rating to Firestore. Returns true on success (and
  /// marks this version rated, which hides the button completely);
  /// returns false when the write failed — the caller keeps the
  /// card open with an honest error so the student can retry, and
  /// the student is NOT marked rated.
  Future<bool> submit(AppRatingSubmission submission) async {
    try {
      final repository = _repository ??= FirestoreAppRatingRepository();
      await repository.submit(submission);
    } catch (_) {
      return false;
    }
    _ratedForVersion = true;
    unawaited(_prefs?.setBool(_ratedKey, true));
    notifyListeners();
    return true;
  }

  /// Test-only: resets the tracker to a fresh state.
  @visibleForTesting
  void debugReset() {
    _actionsDone.clear();
    _ratedForVersion = false;
    _initialized = false;
    notifyListeners();
  }
}
