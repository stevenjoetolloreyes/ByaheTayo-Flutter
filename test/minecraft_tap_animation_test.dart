// Minecraft tap animation tests (Feature 5): the squash plays on
// tap and settles, the tap action still fires exactly once (owned
// and observed modes), reduced motion disables the animation,
// the reward variant shows the music note, and the ring/bits
// appear at the tap point.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:estudyantego/features/minecraft_tap_animation.dart';
import 'package:estudyantego/features/minecraft_theme.dart';

const _squashKey = Key('minecraft-tap-squash');
const _ringKey = Key('minecraft-tap-ring');
const _noteKey = Key('minecraft-tap-note');

double _squashScale(WidgetTester tester) {
  final transform = tester.widget<Transform>(find.byKey(_squashKey));
  return transform.transform.storage[0];
}

Color _ringColor(WidgetTester tester) {
  final container = tester.widget<Container>(find.byKey(_ringKey));
  final decoration = container.decoration! as BoxDecoration;
  final border = decoration.border! as Border;
  return border.top.color;
}

Widget _ownedApp({
  required VoidCallback onTap,
  bool reward = false,
  bool effects = true,
  bool enabled = true,
  bool disableAnimations = false,
}) {
  final child = MinecraftTapAnimation(
    onTap: onTap,
    reward: reward,
    effects: effects,
    enabled: enabled,
    child: Container(
      key: const Key('tap-target'),
      width: 200,
      height: 100,
      color: Colors.white,
    ),
  );
  final app = MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
  if (!disableAnimations) return app;
  return MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: app,
  );
}

Widget _observedApp({required VoidCallback onTap, bool reward = false}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: MinecraftTapAnimation(
          reward: reward,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Container(
                key: const Key('tap-target'),
                width: 200,
                height: 100,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('MinecraftTapAnimation owned-tap mode', () {
    testWidgets('squash plays on tap and settles at scale 1', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_ownedApp(onTap: () => taps++));
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pump();
      // Mid-squash (140ms of the 280ms squash): off 1.0.
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.byKey(_squashKey), findsOneWidget);
      expect(_squashScale(tester), isNot(closeTo(1.0, 0.01)));
      expect(find.byKey(_ringKey), findsOneWidget);
      // Settled: scale back to 1 and the effects unmounted.
      await tester.pumpAndSettle();
      expect(_squashScale(tester), closeTo(1.0, 0.001));
      expect(find.byKey(_ringKey), findsNothing);
      expect(taps, 1);
    });

    testWidgets('tap action fires exactly once, even on a rapid re-tap', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(_ownedApp(onTap: () => taps++));
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(taps, 2);
    });

    testWidgets('reduced motion: no animation, tap still fires once', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _ownedApp(onTap: () => taps++, disableAnimations: true),
      );
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.byKey(_squashKey), findsNothing);
      expect(find.byKey(_ringKey), findsNothing);
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('disabled: no animation, tap still fires once', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_ownedApp(onTap: () => taps++, enabled: false));
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.byKey(_squashKey), findsNothing);
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('effects off: squash plays, no ring or bits', (tester) async {
      await tester.pumpWidget(_ownedApp(onTap: () {}, effects: false));
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(_squashScale(tester), isNot(closeTo(1.0, 0.01)));
      expect(find.byKey(_ringKey), findsNothing);
      expect(find.byKey(const Key('minecraft-tap-bit-0')), findsNothing);
      await tester.pumpAndSettle();
    });
  });

  group('MinecraftTapAnimation observed mode', () {
    testWidgets('child tap fires exactly once and effects play', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(_observedApp(onTap: () => taps++));
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(taps, 1);
      expect(find.byKey(_squashKey), findsOneWidget);
      expect(find.byKey(_ringKey), findsOneWidget);
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('ring and bits appear at the tap point', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_observedApp(onTap: () => taps++));
      final targetCenter = tester.getCenter(
        find.byKey(const Key('tap-target')),
      );
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // The ring is centered on the tap point.
      final ringCenter = tester.getCenter(find.byKey(_ringKey));
      expect(ringCenter.dx, closeTo(targetCenter.dx, 1.0));
      expect(ringCenter.dy, closeTo(targetCenter.dy, 1.0));
      // All six 9px pixel bits are present, in the preview colors.
      for (var i = 0; i < 6; i++) {
        expect(find.byKey(Key('minecraft-tap-bit-$i')), findsOneWidget);
      }
      final bit1 = tester.widget<Container>(
        find.byKey(const Key('minecraft-tap-bit-1')),
      );
      expect(bit1.color, MinecraftColors.gold);
      await tester.pumpAndSettle();
    });

    testWidgets('ordinary tap: grey ring, no music note', (tester) async {
      await tester.pumpWidget(_observedApp(onTap: () {}));
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_ringColor(tester), MinecraftColors.stone);
      expect(find.byKey(_noteKey), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('reward tap: gold ring and a rising music note', (
      tester,
    ) async {
      await tester.pumpWidget(_observedApp(onTap: () {}, reward: true));
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pump();
      // Gold ring, checked before the ring starts fading (270ms).
      await tester.pump(const Duration(milliseconds: 100));
      expect(_ringColor(tester), MinecraftColors.goldDark);
      // The note is mid-rise at 350ms.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(_noteKey), findsOneWidget);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
      await tester.pumpAndSettle();
      // The note unmounts once the timeline finishes.
      expect(find.byKey(_noteKey), findsNothing);
    });
  });

  group('MinecraftTapAnimation on shared components', () {
    testWidgets('MinecraftBlockButton still fires once, with squash', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MinecraftBlockButton(
                label: 'Forge a Quiz',
                onPressed: () => taps++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(MinecraftBlockButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(taps, 1);
      expect(find.byKey(_squashKey), findsOneWidget);
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('MinecraftQuestCard still fires once, with squash', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MinecraftQuestCard(
                badgeLetter: 'Q',
                title: 'Test quest',
                details: 'A quest card',
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(MinecraftQuestCard));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(taps, 1);
      expect(find.byKey(_squashKey), findsOneWidget);
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });
}
