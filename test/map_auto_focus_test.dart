// Unit tests for the Map tab's one-time auto-focus on open
// (Nov 11, 2026). Pure guard decision only — no map widget,
// no Geolocator mock needed, so these run without a platform view.
import 'package:estudyantego/features/map_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  test('does not fire when it already fired', () {
    expect(
      shouldAutoFocusOnLocation(
        alreadyDone: true,
        locationServiceEnabled: true,
        permission: LocationPermission.whileInUse,
      ),
      isFalse,
    );
  });

  test('does not fire when the location service is off', () {
    expect(
      shouldAutoFocusOnLocation(
        alreadyDone: false,
        locationServiceEnabled: false,
        permission: LocationPermission.always,
      ),
      isFalse,
    );
  });

  test('does not fire when permission is denied', () {
    expect(
      shouldAutoFocusOnLocation(
        alreadyDone: false,
        locationServiceEnabled: true,
        permission: LocationPermission.denied,
      ),
      isFalse,
    );
  });

  test('does not fire when permission is denied forever', () {
    expect(
      shouldAutoFocusOnLocation(
        alreadyDone: false,
        locationServiceEnabled: true,
        permission: LocationPermission.deniedForever,
      ),
      isFalse,
    );
  });

  test('fires when permission is already granted (whileInUse)', () {
    expect(
      shouldAutoFocusOnLocation(
        alreadyDone: false,
        locationServiceEnabled: true,
        permission: LocationPermission.whileInUse,
      ),
      isTrue,
    );
  });

  test('fires when permission is already granted (always)', () {
    expect(
      shouldAutoFocusOnLocation(
        alreadyDone: false,
        locationServiceEnabled: true,
        permission: LocationPermission.always,
      ),
      isTrue,
    );
  });
}
