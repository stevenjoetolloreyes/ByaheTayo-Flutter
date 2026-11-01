// Unit tests for the church-preview sheet rule: when a route preview
// was opened from a church (the church panel's DIRECTIONS flow), the
// Nearby Routes browsing chrome hides from the bottom sheet so only
// the church route card shows. Pure helper only — no GoogleMap widget
// needed, so these run without a platform view. The widget itself
// gates on showBrowsingChrome, and the _churchPreview flag lifecycle
// (set in _selectChurchDestination; cleared on card X, hub/route
// selection, swap, and navigation end) is documented beside the flag.
import 'package:estudyantego/features/map_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browsing chrome shows in normal Nearby Routes browsing', () {
    expect(showBrowsingChrome(false), isTrue);
  });

  test('browsing chrome hides in a church-originated preview', () {
    expect(showBrowsingChrome(true), isFalse);
  });

  test('the gate is exactly the church-preview flag, nothing else', () {
    // No other sheet state may hide the chrome: the helper takes
    // only the flag, so normal hub routes, searches, and filters
    // always keep the browsing rows and the stops list.
    for (final flag in [false, true]) {
      expect(showBrowsingChrome(flag), equals(!flag));
    }
  });
}
