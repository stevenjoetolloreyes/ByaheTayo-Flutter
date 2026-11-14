// Follow-camera bearing freeze for Live Follow (Nov 14, 2026 —
// Steven's Aragan videos: Google Maps holds north-up while he
// is stopped at home, but EstudyanteGO spun the map around the
// stationary arrow — the compass kept steering the camera
// bearing while GPS was lost indoors. What is pinned here:
// the camera holds its last bearing while GPS is lost or the
// bus is stopped, follows the live bearing again once it is
// really moving, and resumes along the shortest arc in capped
// steps so it never spins in one glide.)
import 'package:estudyantego/features/live_follow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('liveCameraBearing', () {
    test('(a) GPS lost: compass swings do not change the camera bearing',
        () {
      // The arrow sits grey with the amber lost ring at home;
      // the compass drifts 66° -> 176° indoors, but the camera
      // must stay put.
      for (final liveBearing in [66.0, 120.0, 176.0, 300.0, 10.0]) {
        expect(
          liveCameraBearing(
            gpsLost: true,
            speedKmh: 25,
            liveBearing: liveBearing,
            lastCameraBearing: 30,
          ),
          30,
        );
      }
      // Even a moving speed does not unfreeze the camera while
      // the signal is lost: the speed is stale, the fix is not.
      expect(
        liveCameraBearing(
          gpsLost: true,
          speedKmh: 60,
          liveBearing: 200,
          lastCameraBearing: 45,
        ),
        45,
      );
    });

    test('(c) stopped with GPS locked: compass swings do not move the camera',
        () {
      // Stopped at 0 km/h, crawling at 1 km/h, or no speed
      // sample yet: the map holds north-up / the last bearing.
      for (final speed in [0.0, 0.5, 1.0, null]) {
        expect(
          liveCameraBearing(
            gpsLost: false,
            speedKmh: speed,
            liveBearing: 200,
            lastCameraBearing: 30,
          ),
          30,
        );
      }
      // Exactly at the moving threshold still counts as stopped.
      expect(
        liveCameraBearing(
          gpsLost: false,
          speedKmh: liveMinMovingKmh,
          liveBearing: 200,
          lastCameraBearing: 30,
        ),
        30,
      );
    });

    test('(b) moving with GPS locked: the camera follows the live bearing',
        () {
      // A small bearing change is applied at once.
      expect(
        liveCameraBearing(
          gpsLost: false,
          speedKmh: 20,
          liveBearing: 45,
          lastCameraBearing: 30,
        ),
        45,
      );
      // Just above the moving threshold already follows.
      expect(
        liveCameraBearing(
          gpsLost: false,
          speedKmh: 3.1,
          liveBearing: 50,
          lastCameraBearing: 30,
        ),
        50,
      );
    });

    test('(b) following converges over repeated ticks after a hold', () {
      // After a long stop the compass has drifted 120° away;
      // each 150 ms tick steps at most 30° toward it.
      var bearing = 30.0;
      bearing = liveCameraBearing(
        gpsLost: false,
        speedKmh: 20,
        liveBearing: 150,
        lastCameraBearing: bearing,
      );
      expect(bearing, 60);
      bearing = liveCameraBearing(
        gpsLost: false,
        speedKmh: 20,
        liveBearing: 150,
        lastCameraBearing: bearing,
      );
      expect(bearing, 90);
      bearing = liveCameraBearing(
        gpsLost: false,
        speedKmh: 20,
        liveBearing: 150,
        lastCameraBearing: bearing,
      );
      expect(bearing, 120);
      bearing = liveCameraBearing(
        gpsLost: false,
        speedKmh: 20,
        liveBearing: 150,
        lastCameraBearing: bearing,
      );
      expect(bearing, 150);
    });

    test('(d) resume takes the shortest arc across the 0/360 seam', () {
      // 350° -> 10° passes through 0 (a +20° step), never
      // through 180 (a -340° spin).
      expect(
        liveCameraBearing(
          gpsLost: false,
          speedKmh: 20,
          liveBearing: 10,
          lastCameraBearing: 350,
        ),
        10,
      );
      // 10° -> 350° is a -20° step through 0, not +340°.
      expect(
        liveCameraBearing(
          gpsLost: false,
          speedKmh: 20,
          liveBearing: 350,
          lastCameraBearing: 10,
        ),
        350,
      );
    });

    test('(d) a large resume gap is capped, never applied in one move',
        () {
      // 0° -> 180°: the camera steps +30°, not 180°.
      expect(
        liveCameraBearing(
          gpsLost: false,
          speedKmh: 20,
          liveBearing: 180,
          lastCameraBearing: 0,
        ),
        30,
      );
      // 0° -> 200°: the shortest arc is backwards (-160°), so
      // the camera steps -30° (to 330°), not +200°.
      expect(
        liveCameraBearing(
          gpsLost: false,
          speedKmh: 20,
          liveBearing: 200,
          lastCameraBearing: 0,
        ),
        330,
      );
      // 0° -> 90°: a +90° gap is capped to one +30° step.
      expect(
        liveCameraBearing(
          gpsLost: false,
          speedKmh: 20,
          liveBearing: 90,
          lastCameraBearing: 0,
        ),
        30,
      );
    });
  });
}
