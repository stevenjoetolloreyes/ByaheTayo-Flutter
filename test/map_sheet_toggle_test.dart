// Unit tests for the Map tab's logo-button bottom-sheet toggle.
// Pure logic only — the sheet widget itself needs a platform map
// view, so widget presence is covered by analyze, not here.
// What these prove: the toggle's offset + tooltip rules.
import 'package:estudyantego/features/map_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapControlsBottomOffset', () {
    test('sheet shown floats above the sheet', () {
      expect(
        mapControlsBottomOffset(sheetHidden: false),
        190,
      );
    });

    test('sheet hidden drops controls to the bottom', () {
      expect(
        mapControlsBottomOffset(sheetHidden: true),
        16,
      );
    });
  });

  group('sheetToggleTooltip', () {
    test('shown sheet offers to hide it', () {
      expect(sheetToggleTooltip(false), 'Hide bottom panel');
    });

    test('hidden sheet offers to show it', () {
      expect(sheetToggleTooltip(true), 'Show bottom panel');
    });
  });
}
