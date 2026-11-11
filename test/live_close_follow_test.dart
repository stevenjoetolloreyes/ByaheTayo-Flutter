// Unit tests for Live close-follow (Nov 11, 2026): the pure
// zoom rules behind the Map tab's Live Follow camera — no
// device, no GPS, no live map. The follow camera settles at
// the close street-level zoom (18.3, the preview's settled
// zoom) and respects a manual zoom made during Live until
// Overview / My Location / Resume re-fits.
import 'package:estudyantego/features/live_follow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('liveCloseFollowZoom', () {
    test('settles at the preview settled zoom, 18.3', () {
      expect(liveCloseFollowZoom, 18.3);
    });

    test('is closer than the old follow zoom of 16', () {
      expect(liveCloseFollowZoom, greaterThan(16));
    });

    test('first-move ease-in is about one second', () {
      expect(liveCloseFollowEaseIn, const Duration(milliseconds: 1000));
    });
  });

  group('liveFollowZoom', () {
    test('no manual zoom -> the close follow zoom', () {
      expect(liveFollowZoom(), liveCloseFollowZoom);
      expect(liveFollowZoom(userZoom: null), liveCloseFollowZoom);
    });

    test('a manual zoom during Live wins and is respected', () {
      expect(liveFollowZoom(userZoom: 14.0), 14.0);
      expect(liveFollowZoom(userZoom: 19.0), 19.0);
      expect(liveFollowZoom(userZoom: 10.5), 10.5);
    });
  });

  group('liveGestureWasZoom', () {
    test('zoom unchanged -> a drag, not a zoom', () {
      expect(liveGestureWasZoom(startZoom: 18.3, zoom: 18.3), isFalse);
    });

    test('zoom moved a lot -> a pinch / double-tap zoom', () {
      expect(liveGestureWasZoom(startZoom: 18.3, zoom: 17.0), isTrue);
      expect(liveGestureWasZoom(startZoom: 14.0, zoom: 15.5), isTrue);
    });

    test('tiny drift under tolerance -> not a zoom', () {
      expect(liveGestureWasZoom(startZoom: 18.3, zoom: 18.4), isFalse);
      expect(liveGestureWasZoom(startZoom: 18.3, zoom: 18.15), isFalse);
    });

    test('custom tolerance is honoured', () {
      expect(
        liveGestureWasZoom(startZoom: 18.3, zoom: 18.4, tolerance: 0.05),
        isTrue,
      );
    });
  });

  group('liveTapZoomTarget at the new follow zoom', () {
    test('exactly at the close follow zoom the tap recentres', () {
      expect(liveTapZoomTarget(liveCloseFollowZoom), liveCloseFollowZoom);
    });

    test('a hair off the follow zoom still recentres', () {
      expect(liveTapZoomTarget(18.28), liveCloseFollowZoom);
    });

    test('away from the follow zoom it still steps by 2', () {
      expect(liveTapZoomTarget(16), 18);
      expect(liveTapZoomTarget(13), 15);
    });
  });
}
