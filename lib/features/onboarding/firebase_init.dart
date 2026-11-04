// Guarded Firebase initialization.
//
// Returns true when Firebase initialized, false for ANY failure
// (missing google-services.json, missing plugin, no network at startup).
// The app never crashes over Firebase setup: a false result means the
// auth gate is skipped and auth screens show the not-configured state.
// The optional [initializer] exists so tests can inject a throwing or
// succeeding fake without touching the real Firebase SDK.
//
// App Check is activated right after Firebase init (best-effort, never
// throws): debug builds use the debug provider (its token is printed
// to logcat on first attestation and must be registered in the
// Firebase Console under App Check > Manage debug tokens), release
// builds use Play Integrity. A failure here never changes the init
// result — enforcement errors surface when a protected call (e.g.
// an AI call) is made, where the UI reports them. The optional
// [appCheckActivator] exists so tests can inject a no-op.
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Added for the diagnostics system only (no logic change):
/// [skipAppCheck] lets Safe Mode skip App Check activation (it is
/// already best-effort), and [onAppCheckResult] reports whether
/// activation succeeded so the startup stage can be recorded
/// separately from Firebase core init. Both default to the old
/// behaviour when omitted.
Future<bool> initializeFirebase({
  Future<void> Function()? initializer,
  Future<void> Function()? appCheckActivator,
  bool skipAppCheck = false,
  void Function(bool succeeded)? onAppCheckResult,
}) async {
  try {
    await (initializer ?? () => Firebase.initializeApp())();
    if (skipAppCheck) {
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
