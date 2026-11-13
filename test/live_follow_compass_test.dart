// Compass heading for Live Follow (Nov 13, 2026 — Steven:
// rotating the phone while stopped should turn the map, like
// Google Maps). The heading now comes from the built-in
// native channel (MainActivity.kt, "com.estudyantego.app/
// compass") instead of the removed flutter_compass_v2 plugin
// — the plugin's AAR was compiled against compileSdk 33
// while its androidx deps need 34+, so the Actions build
// failed at checkReleaseAarMetadata. What is pinned here:
// the blend rule the stream feeds on, how the native event
// payload is parsed, and that the channel delivers events.
import 'dart:async';

import 'package:estudyantego/features/live_follow.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('blendLiveHeading', () {
    test('no compass (null heading) falls back to GPS bearing', () {
      expect(
        blendLiveHeading(
          gpsBearing: 270,
          compassHeading: null,
          speedKmh: 0,
        ),
        270,
      );
      expect(
        blendLiveHeading(
          gpsBearing: 90,
          compassHeading: null,
          speedKmh: 60,
        ),
        90,
      );
    });

    test('stopped: the compass steers, so rotating the phone turns the map', () {
      expect(
        blendLiveHeading(
          gpsBearing: 0,
          compassHeading: 270,
          speedKmh: 0,
        ),
        270,
      );
      // No speed sample yet (null) counts as stopped, not moving.
      expect(
        blendLiveHeading(
          gpsBearing: 0,
          compassHeading: 180,
          speedKmh: null,
        ),
        180,
      );
    });

    test('slow (5 km/h): the compass still steers', () {
      expect(
        blendLiveHeading(
          gpsBearing: 0,
          compassHeading: 45,
          speedKmh: 5,
        ),
        45,
      );
    });

    test('moving at speed: GPS bearing wins, even when the compass disagrees wildly', () {
      expect(
        blendLiveHeading(
          gpsBearing: 90,
          compassHeading: 270,
          speedKmh: 60,
        ),
        90,
      );
      expect(
        blendLiveHeading(
          gpsBearing: 180,
          compassHeading: 0,
          speedKmh: 11,
        ),
        180,
      );
    });

    test('wrap-around: GPS 350, compass 10 while stopped → 10', () {
      expect(
        blendLiveHeading(
          gpsBearing: 350,
          compassHeading: 10,
          speedKmh: 0,
        ),
        10,
      );
    });
  });

  group('smoothCompassHeading', () {
    test('eases toward the reading along the shortest arc', () {
      // 350 → 10 is +20° across the seam; a quarter of the way is 355.
      expect(
        smoothCompassHeading(previous: 350, compass: 10),
        closeTo(355, 0.001),
      );
      // 10 → 350 is −20° across the seam; a quarter of the way is 5.
      expect(
        smoothCompassHeading(previous: 10, compass: 350),
        closeTo(5, 0.001),
      );
      // Plain case: 90 → 100 is +10°; a quarter of the way is 92.5.
      expect(
        smoothCompassHeading(previous: 90, compass: 100),
        closeTo(92.5, 0.001),
      );
    });

    test('a wild single-reading jump is ignored (uncalibrated sensor)', () {
      expect(
        smoothCompassHeading(previous: 0, compass: 100),
        0,
      );
      expect(
        smoothCompassHeading(previous: 180, compass: 0),
        180,
      );
    });

    test('a jump of exactly 90° is still accepted', () {
      expect(
        smoothCompassHeading(previous: 0, compass: 90),
        closeTo(22.5, 0.001),
      );
    });
  });

  group('parseNativeCompassEvent', () {
    test('a well-formed native event parses (heading + accuracy)', () {
      final reading = parseNativeCompassEvent(
        <String, Object?>{'heading': 270.0, 'accuracy': 3},
      );
      expect(reading, isNotNull);
      expect(reading!.heading, 270);
      expect(reading.accuracy, 3);
    });

    test('a missing accuracy is accepted (not reported yet)', () {
      final reading = parseNativeCompassEvent(
        <String, Object?>{'heading': 45.5},
      );
      expect(reading, isNotNull);
      expect(reading!.heading, closeTo(45.5, 0.001));
      expect(reading.accuracy, isNull);
    });

    test('boundary headings 0 and 360 are accepted', () {
      expect(
        parseNativeCompassEvent(<String, Object?>{'heading': 0})?.heading,
        0,
      );
      expect(
        parseNativeCompassEvent(<String, Object?>{'heading': 360})?.heading,
        360,
      );
    });

    test('malformed events parse to null (never a guessed heading)', () {
      expect(parseNativeCompassEvent(null), isNull);
      expect(parseNativeCompassEvent('270'), isNull);
      expect(
        parseNativeCompassEvent(<String, Object?>{'accuracy': 3}),
        isNull,
      );
      expect(
        parseNativeCompassEvent(<String, Object?>{'heading': '270'}),
        isNull,
      );
      expect(
        parseNativeCompassEvent(
          <String, Object?>{'heading': double.nan},
        ),
        isNull,
      );
      expect(
        parseNativeCompassEvent(
          <String, Object?>{'heading': double.infinity},
        ),
        isNull,
      );
      expect(
        parseNativeCompassEvent(<String, Object?>{'heading': -1}),
        isNull,
      );
      expect(
        parseNativeCompassEvent(<String, Object?>{'heading': 361}),
        isNull,
      );
    });
  });

  group('isCompassReadingUsable', () {
    test('an unreliable sensor (status 0) is ignored', () {
      expect(
        isCompassReadingUsable(
          const NativeCompassReading(heading: 90, accuracy: 0),
        ),
        isFalse,
      );
    });

    test('low / medium / high accuracy are usable', () {
      for (final accuracy in [1, 2, 3]) {
        expect(
          isCompassReadingUsable(
            NativeCompassReading(heading: 90, accuracy: accuracy),
          ),
          isTrue,
        );
      }
    });

    test('a missing accuracy is usable (as before)', () {
      expect(
        isCompassReadingUsable(
          const NativeCompassReading(heading: 90),
        ),
        isTrue,
      );
    });
  });

  testWidgets('native channel events arrive and parse (mocked platform)',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = StandardMethodCodec();
    messenger.setMockMethodCallHandler(
      const MethodChannel(liveCompassChannelName),
      (MethodCall call) async {
        if (call.method == 'listen') {
          // Simulate the native side emitting one reading as
          // soon as Dart subscribes.
          unawaited(
            messenger.handlePlatformMessage(
              liveCompassChannelName,
              codec.encodeSuccessEnvelope(
                <String, Object?>{'heading': 270.0, 'accuracy': 3},
              ),
              (_) {},
            ),
          );
        }
        return null;
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel(liveCompassChannelName),
        null,
      ),
    );
    final first = await const EventChannel(liveCompassChannelName)
        .receiveBroadcastStream()
        .first;
    final reading = parseNativeCompassEvent(first);
    expect(reading, isNotNull);
    expect(reading!.heading, 270);
    expect(reading.accuracy, 3);
    expect(isCompassReadingUsable(reading), isTrue);
  });
}
