// Walking Goal sensor + permission abstractions.
//
// The production sensor is a thin platform channel over Android's
// TYPE_STEP_COUNTER sensor (see MainActivity.kt): the sensor reports
// a CUMULATIVE step count since the last device boot, not a daily
// total. The daily-delta conversion lives in walking_repository.dart
// (WalkingController), never here, so it stays unit-testable.
//
// Production permission uses permission_handler (the same pattern as
// PermissionService in onboarding/permission_service.dart). Tests use
// the fakes below; no platform channel is ever touched by a test.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// A step-counter sensor: cumulative steps since boot, or nothing.
///
/// `isAvailable` is false on devices without a step-counter sensor
/// and on platforms without the channel (tests, iOS) — callers must
/// treat that as an honest "not available" state, never as zero.
abstract class WalkingSensor {
  Future<bool> get isAvailable;

  /// Broadcast stream of cumulative sensor values. Each value is the
  /// sensor's running total since boot; deltas are the caller's job.
  Stream<int> get cumulativeSteps;
}

class PlatformWalkingSensor implements WalkingSensor {
  static const _method =
      MethodChannel('byahetayo/walking_steps');
  static const _events =
      EventChannel('byahetayo/walking_steps');

  @override
  Future<bool> get isAvailable async {
    // Widget tests run under FakeAsync: a platform channel with no
    // responder never completes there, and a timeout timer never
    // fires either — so a bare StudentTab test would hang forever
    // on this call (and pumpAndSettle with it). Under flutter test
    // there is no sensor by definition, so report that directly.
    if (Platform.environment['FLUTTER_TEST'] == 'true') return false;
    try {
      // On platforms without the handler (iOS, or a build missing
      // the MainActivity registration) the call would otherwise hang
      // forever — a short timeout turns that into "not available".
      return await _method
              .invokeMethod<bool>('isAvailable')
              .timeout(const Duration(seconds: 2), onTimeout: () => false) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<int> get cumulativeSteps =>
      _events.receiveBroadcastStream().map((event) => (event as num).toInt());
}

/// Test sensor: the test drives cumulative values by hand.
class FakeWalkingSensor implements WalkingSensor {
  FakeWalkingSensor({this.available = true});

  bool available;
  final _controller = StreamController<int>.broadcast();

  @override
  Future<bool> get isAvailable async => available;

  @override
  Stream<int> get cumulativeSteps => _controller.stream;

  void emit(int cumulative) => _controller.add(cumulative);

  Future<void> close() => _controller.close();
}

/// Activity-recognition permission state, as the UI shows it.
enum ActivityPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  unknown,
}

abstract class ActivityPermission {
  Future<ActivityPermissionStatus> status();
  Future<ActivityPermissionStatus> request();
  Future<void> openSettings();
}

class AppActivityPermission implements ActivityPermission {
  @override
  Future<ActivityPermissionStatus> status() async {
    try {
      return _map(await ph.Permission.activityRecognition.status);
    } catch (_) {
      return ActivityPermissionStatus.unknown;
    }
  }

  @override
  Future<ActivityPermissionStatus> request() async {
    try {
      return _map(await ph.Permission.activityRecognition.request());
    } catch (_) {
      return ActivityPermissionStatus.unknown;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await ph.openAppSettings();
    } catch (_) {
      // Nothing to do: the user stays in the app.
    }
  }

  static ActivityPermissionStatus _map(ph.PermissionStatus status) {
    if (status.isGranted) return ActivityPermissionStatus.granted;
    if (status.isPermanentlyDenied) {
      return ActivityPermissionStatus.permanentlyDenied;
    }
    if (status.isDenied) return ActivityPermissionStatus.denied;
    return ActivityPermissionStatus.unknown;
  }
}

/// Test permission: the test sets the status it wants to simulate.
class FakeActivityPermission implements ActivityPermission {
  FakeActivityPermission({
    this.current = ActivityPermissionStatus.denied,
    this.requestResult = ActivityPermissionStatus.granted,
  });

  ActivityPermissionStatus current;
  ActivityPermissionStatus requestResult;
  bool settingsOpened = false;

  @override
  Future<ActivityPermissionStatus> status() async => current;

  @override
  Future<ActivityPermissionStatus> request() async {
    current = requestResult;
    return current;
  }

  @override
  Future<void> openSettings() async {
    settingsOpened = true;
  }
}
