// Compass heading for Live Follow (Nov 13, 2026 — Steven:
// rotating the phone while stopped should turn the map, like
// Google Maps). Pure-logic tests only — the magnetometer
// stream cannot run in flutter test, so what is pinned here
// is the blend rule it feeds on: which source steers the
// heading, and how compass readings are smoothed.
import 'package:estudyantego/features/live_follow.dart';
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
}
