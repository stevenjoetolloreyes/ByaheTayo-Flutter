// App Check activation is skipped by default (temporary sideload
// pause, Nov 4, 2026): the default initializeFirebase path must never
// call the App Check activator, so no failing Play Integrity token is
// sent with AI requests. Activation only happens when explicitly
// opted in with enableAppCheck: true (and skipAppCheck: false).
import 'package:estudyantego/features/onboarding/firebase_init.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default path does not call the App Check activator', () async {
    var activatorCalled = false;
    bool? reportedResult;
    final result = await initializeFirebase(
      initializer: () async {},
      appCheckActivator: () async {
        activatorCalled = true;
      },
      onAppCheckResult: (succeeded) => reportedResult = succeeded,
    );
    expect(result, isTrue);
    expect(activatorCalled, isFalse);
    expect(reportedResult, isFalse);
  });

  test('enableAppCheck opt-in calls the activator', () async {
    var activatorCalled = false;
    bool? reportedResult;
    final result = await initializeFirebase(
      initializer: () async {},
      appCheckActivator: () async {
        activatorCalled = true;
      },
      enableAppCheck: true,
      onAppCheckResult: (succeeded) => reportedResult = succeeded,
    );
    expect(result, isTrue);
    expect(activatorCalled, isTrue);
    expect(reportedResult, isTrue);
  });

  test('skipAppCheck still wins over the enableAppCheck opt-in', () async {
    var activatorCalled = false;
    final result = await initializeFirebase(
      initializer: () async {},
      appCheckActivator: () async {
        activatorCalled = true;
      },
      enableAppCheck: true,
      skipAppCheck: true,
    );
    expect(result, isTrue);
    expect(activatorCalled, isFalse);
  });

  test('a failing activator never breaks init', () async {
    bool? reportedResult;
    final result = await initializeFirebase(
      initializer: () async {},
      appCheckActivator: () async {
        throw StateError('activation failed');
      },
      enableAppCheck: true,
      onAppCheckResult: (succeeded) => reportedResult = succeeded,
    );
    expect(result, isTrue);
    expect(reportedResult, isFalse);
  });

  test('a failing initializer returns false', () async {
    final result = await initializeFirebase(
      initializer: () async {
        throw StateError('firebase failed');
      },
    );
    expect(result, isFalse);
  });
}
