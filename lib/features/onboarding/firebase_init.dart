// Guarded Firebase initialization.
//
// Returns true when Firebase initialized, false for ANY failure
// (missing google-services.json, missing plugin, no network at startup).
// The app never crashes over Firebase setup: a false result means the
// auth gate is skipped and auth screens show the not-configured state.
// The optional [initializer] exists so tests can inject a throwing or
// succeeding fake without touching the real Firebase SDK.
import 'package:firebase_core/firebase_core.dart';

Future<bool> initializeFirebase({
  Future<void> Function()? initializer,
}) async {
  try {
    await (initializer ?? () => Firebase.initializeApp())();
    return true;
  } catch (_) {
    return false;
  }
}
