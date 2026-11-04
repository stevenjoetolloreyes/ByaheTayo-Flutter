// Guarded Firebase initialization.
//
// Returns true when Firebase initialized, false for ANY failure
// (missing google-services.json, missing plugin, no network at startup).
// The app never crashes over Firebase setup: a false result means the
// auth gate is skipped and auth screens show the not-configured state.
// The optional [initializer] exists so tests can inject a throwing or
// succeeding fake without touching the real Firebase SDK.
//
// TEMPORARY APP CHECK PAUSE (Nov 4, 2026 — sideload builds only):
// App Check activation is SKIPPED by default (see [enableAppCheck]).
// Reason, confirmed on device: the cloud APK is a release build that
// is debug-signed and sideloaded (not from Play), so Play Integrity
// attestation fails, and Firebase AI Logic rejects the call with
// 403 "App attestation failed" — even after the Console was set to
// Basic - Unenforced + Replay - Unenforced, because the app still
// sent the failing Play Integrity token with every request. Sending
// NO token lets the unenforced backend accept the request as
// unverified. Firestore and Auth are Monitoring/unenforced, so they
// work without a token. This is NOT a permanent security solution:
// before the app is Play-distributed and Play-signed, App Check
// must be re-enabled (pass enableAppCheck: true), and it must be
// enforced before the Console's Jan 21, 2027 enforcement date, or
// AI calls will break again. Do not ship a Play release with this
// pause still in place.
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Added for the diagnostics system only (no logic change):
/// [skipAppCheck] lets Safe Mode skip App Check activation (it is
/// already best-effort), and [onAppCheckResult] reports whether
/// activation succeeded so the startup stage can be recorded
/// separately from Firebase core init.
///
/// [enableAppCheck] is the opt-in gate for App Check activation.
/// It defaults to false (see the temporary pause note above): with
/// the default, the [appCheckActivator] is never called, no Play
/// Integrity or Debug provider is activated, and [onAppCheckResult]
/// is reported as false — exactly like the [skipAppCheck] path.
/// Passing enableAppCheck: true (with skipAppCheck: false) restores
/// the old behaviour: the injected [appCheckActivator] runs, or the
/// built-in provider activates (debug builds use the debug provider,
/// whose token is printed to logcat on first attestation and must be
/// registered in the Firebase Console under App Check > Manage debug
/// tokens; release builds use Play Integrity). A failure there never
/// changes the init result — enforcement errors surface when a
/// protected call (e.g. an AI call) is made, where the UI reports
/// them. The optional [appCheckActivator] exists so tests can inject
/// a no-op.
Future<bool> initializeFirebase({
  Future<void> Function()? initializer,
  Future<void> Function()? appCheckActivator,
  bool skipAppCheck = false,
  bool enableAppCheck = false,
  void Function(bool succeeded)? onAppCheckResult,
}) async {
  try {
    await (initializer ?? () => Firebase.initializeApp())();
    if (!enableAppCheck || skipAppCheck) {
      onAppCheckResult?.call(false);
    } else {
      try {
        await (appCheckActivator ??
            () => FirebaseAppCheck.instance.activate(
                  providerAndroid: kDebugMode
                      ? const AndroidDebugProvider()
                      : const AndroidPlayIntegrityProvider(),
                ))();
        onAppCheckResult?.call(true);
      } catch (_) {
        // Best-effort: App Check must never break app launch.
        onAppCheckResult?.call(false);
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}
