// Health Connect fallback for the Walking Goal.
//
// Used ONLY when the phone has no TYPE_STEP_COUNTER sensor (see
// walking_repository.dart): the sensor path always wins when the
// sensor exists. Health Connect is a snapshot source, not a live
// stream — the controller reads today's aggregate on demand (hub
// load + manual Refresh), never continuously.
//
// The production implementation is a thin platform channel over
// androidx.health:health-connect-client (see MainActivity.kt).
// Tests use the fake below; no platform channel is ever touched
// by a test.
//
// Honest limits, stated here so no caller can mistake them:
//   * Health Connect only has steps if another app (e.g. Google
//     Fit) records them there. Strava does NOT write all-day steps
//     to Health Connect, so Strava workouts do not count here.
//   * The Steps permission is granted in the Health Connect app,
//     never via the runtime permission dialog.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Health Connect availability on this device.
enum HealthConnectSdkStatus {
  /// Health Connect is installed and usable.
  available,

  /// No Health Connect service/app on this device.
  unavailable,

  /// Health Connect is present but needs an install/update first
  /// (Android 13 and below: the Health Connect app from Play).
  updateRequired,
}

/// Today's step window in Manila time, as epoch millis.
///
/// The app's day key is Manila-based (see manilaDateKey), so the
/// window starts at Manila midnight, not device-local midnight.
/// Pure function of [now], so it is unit-testable.
({int startMillis, int endMillis}) healthConnectTodayRange(DateTime now) {
  final manila = now.toUtc().add(const Duration(hours: 8));
  final start = DateTime.utc(manila.year, manila.month, manila.day)
      .subtract(const Duration(hours: 8));
  return (
    startMillis: start.millisecondsSinceEpoch,
    endMillis: now.millisecondsSinceEpoch,
  );
}

/// Health Connect steps source: availability, Steps permission,
/// and today's aggregate step count.
abstract class HealthConnectSteps {
  /// Health Connect availability. Never throws: failures read as
  /// [HealthConnectSdkStatus.unavailable].
  Future<HealthConnectSdkStatus> get sdkStatus;

  /// Whether the Steps read permission is currently granted.
  /// Never throws: failures read as not granted.
  Future<bool> get hasStepsPermission;

  /// Opens the Health Connect permission flow and reports whether
  /// Steps was granted when the user finished it. The call
  /// suspends while the user is in the Health Connect UI, so it
  /// has no timeout; backing out of the flow reports false.
  Future<bool> requestStepsPermission();

  /// Aggregate steps for today (Manila midnight -> now). A zero
  /// is real data — no steps recorded in the window. Throws on
  /// failure so callers show an error state, never a fake zero.
  Future<int> readTodaySteps();
}

class PlatformHealthConnectSteps implements HealthConnectSteps {
  static const _channel =
      MethodChannel('byahetayo/health_connect_steps');

  @override
  Future<HealthConnectSdkStatus> get sdkStatus async {
    // Same FakeAsync guard as PlatformWalkingSensor: under
    // flutter test there is no Health Connect by definition.
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return HealthConnectSdkStatus.unavailable;
    }
    try {
      final value = await _channel
          .invokeMethod<String>('getSdkStatus')
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      return switch (value) {
        'available' => HealthConnectSdkStatus.available,
        'updateRequired' => HealthConnectSdkStatus.updateRequired,
        _ => HealthConnectSdkStatus.unavailable,
      };
    } catch (_) {
      return HealthConnectSdkStatus.unavailable;
    }
  }

  @override
  Future<bool> get hasStepsPermission async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return false;
    try {
      return await _channel
              .invokeMethod<bool>('hasStepsPermission')
              .timeout(const Duration(seconds: 2), onTimeout: () => false) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestStepsPermission() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return false;
    try {
      // No timeout: the call completes when the user finishes the
      // Health Connect permission flow (grant, deny, or back out).
      return await _channel
              .invokeMethod<bool>('requestStepsPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int> readTodaySteps() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      throw StateError('No Health Connect under flutter test');
    }
    final range = healthConnectTodayRange(DateTime.now());
    final steps = await _channel.invokeMethod<int>('readTodaySteps', {
      'startMillis': range.startMillis,
      'endMillis': range.endMillis,
    }).timeout(const Duration(seconds: 10));
    if (steps == null) {
      throw StateError('Health Connect returned no step count');
    }
    return steps;
  }
}

/// Test source: the test drives availability, permission, and the
/// aggregate count by hand.
class FakeHealthConnectSteps implements HealthConnectSteps {
  FakeHealthConnectSteps({
    this.sdkStatusValue = HealthConnectSdkStatus.available,
    this.hasPermission = false,
    this.requestResult = true,
    this.todaySteps = 0,
  });

  HealthConnectSdkStatus sdkStatusValue;
  bool hasPermission;
  bool requestResult;
  int todaySteps;

  /// How many times the test's aggregate was read.
  int readCount = 0;

  /// How many times the permission flow was opened.
  int requestCount = 0;

  @override
  Future<HealthConnectSdkStatus> get sdkStatus async => sdkStatusValue;

  @override
  Future<bool> get hasStepsPermission async => hasPermission;

  @override
  Future<bool> requestStepsPermission() async {
    requestCount++;
    hasPermission = requestResult;
    return requestResult;
  }

  @override
  Future<int> readTodaySteps() async {
    readCount++;
    return todaySteps;
  }
}
