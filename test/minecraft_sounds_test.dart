// Minecraft theme sounds (Feature 6): the Dart-synthesized WAV
// bytes for every sound kind are valid (RIFF header, 22050 Hz
// mono 16-bit PCM, expected duration/sample count, non-silent);
// the tap wrapper plays its sound kind exactly once per tap
// (owned and observed modes, shared components, reduced motion,
// disabled plays nothing); and the splash screen plays the
// app-open jingle exactly once on app open.
//
// Audio cannot be heard in tests — the synthesis and the wiring
// are what is verified here. Playback itself is best-effort
// (silence on failure) by design.
import 'dart:typed_data';

import 'package:estudyantego/features/minecraft_tap_animation.dart';
import 'package:estudyantego/features/minecraft_theme.dart';
import 'package:estudyantego/features/onboarding/splash_screen.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/onboarding/splash_sound.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleRate = 22050;

/// Reads a little-endian uint32 out of WAV bytes.
int _u32(Uint8List bytes, int offset) =>
    bytes.buffer.asByteData().getUint32(offset, Endian.little);

/// Reads a little-endian uint16 out of WAV bytes.
int _u16(Uint8List bytes, int offset) =>
    bytes.buffer.asByteData().getUint16(offset, Endian.little);

String _ascii(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(bytes.sublist(offset, offset + length));

/// Asserts a WAV clip is well-formed for the expected duration and
/// is not silent: valid RIFF/WAVE header, PCM mono 16-bit at
/// 22050 Hz, the expected sample count, and at least one nonzero
/// sample.
void _expectValidWav(Uint8List wav, double durationSeconds) {
  expect(_ascii(wav, 0, 4), 'RIFF');
  expect(_ascii(wav, 8, 4), 'WAVE');
  expect(_ascii(wav, 12, 4), 'fmt ');
  expect(_u32(wav, 16), 16); // fmt chunk size
  expect(_u16(wav, 20), 1); // PCM
  expect(_u16(wav, 22), 1); // mono
  expect(_u32(wav, 24), _sampleRate);
  expect(_u16(wav, 34), 16); // bits per sample
  expect(_ascii(wav, 36, 4), 'data');
  final expectedSamples = (_sampleRate * durationSeconds).round();
  expect(_u32(wav, 40), expectedSamples * 2);
  expect(wav.length, 44 + expectedSamples * 2);
  final data = wav.buffer.asByteData();
  var nonSilent = false;
  for (var i = 0; i < expectedSamples; i++) {
    if (data.getInt16(44 + i * 2, Endian.little) != 0) {
      nonSilent = true;
      break;
    }
  }
  expect(nonSilent, isTrue, reason: 'WAV must not be silent');
}

void main() {
  setUp(SplashSound.clearPlayedKindsForTest);

  group('Minecraft sound synthesis', () {
    test('every tap kind synthesizes a valid WAV of its duration', () {
      for (final kind in MinecraftSoundKind.values) {
        _expectValidWav(
          SplashSound.wavFor(kind),
          SplashSound.durationFor(kind),
        );
      }
    });

    test('durations match the preview recipes', () {
      expect(SplashSound.durationFor(MinecraftSoundKind.click), 0.07);
      expect(SplashSound.durationFor(MinecraftSoundKind.pop), 0.11);
      expect(SplashSound.durationFor(MinecraftSoundKind.select), 0.12);
      expect(SplashSound.durationFor(MinecraftSoundKind.chime), 0.23);
      expect(SplashSound.durationFor(MinecraftSoundKind.levelup), 0.52);
      expect(SplashSound.durationFor(MinecraftSoundKind.forge), 0.32);
      expect(SplashSound.durationFor(MinecraftSoundKind.bell), 0.28);
      expect(SplashSound.durationFor(MinecraftSoundKind.like), 0.10);
    });

    test('different kinds synthesize different bytes', () {
      final click = SplashSound.wavFor(MinecraftSoundKind.click);
      final pop = SplashSound.wavFor(MinecraftSoundKind.pop);
      final levelup = SplashSound.wavFor(MinecraftSoundKind.levelup);
      expect(click, isNot(pop));
      expect(pop, isNot(levelup));
      expect(click, isNot(levelup));
    });

    test('opening jingle synthesizes a valid 0.55 s WAV', () {
      _expectValidWav(
        SplashSound.openingJingleWav(),
        SplashSound.openingJingleDuration,
      );
      expect(SplashSound.openingJingleDuration, 0.55);
    });

    test('opening jingle differs from the level-up fanfare', () {
      expect(
        SplashSound.openingJingleWav(),
        isNot(SplashSound.wavFor(MinecraftSoundKind.levelup)),
      );
    });
  });

  group('MinecraftTapAnimation sound wiring', () {
    testWidgets('owned tap plays its sound kind exactly once', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MinecraftTapAnimation(
                onTap: () => taps++,
                sound: MinecraftSoundKind.pop,
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
      );
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(
        SplashSound.playedKindsForTest,
        [MinecraftSoundKind.pop],
      );
    });

    testWidgets('default sound is click', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MinecraftTapAnimation(
                onTap: () {},
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
      );
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pumpAndSettle();
      expect(
        SplashSound.playedKindsForTest,
        [MinecraftSoundKind.click],
      );
    });

    testWidgets('observed tap plays its sound kind exactly once', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MinecraftTapAnimation(
                sound: MinecraftSoundKind.select,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => taps++,
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
        ),
      );
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(
        SplashSound.playedKindsForTest,
        [MinecraftSoundKind.select],
      );
    });

    testWidgets('two taps play the sound twice, once per tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MinecraftTapAnimation(
                onTap: () {},
                sound: MinecraftSoundKind.bell,
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
      );
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pumpAndSettle();
      expect(
        SplashSound.playedKindsForTest,
        [MinecraftSoundKind.bell, MinecraftSoundKind.bell],
      );
    });

    testWidgets('disabled wrapper plays no sound', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MinecraftTapAnimation(
                onTap: () {},
                enabled: false,
                sound: MinecraftSoundKind.pop,
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
      );
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pumpAndSettle();
      expect(SplashSound.playedKindsForTest, isEmpty);
    });

    testWidgets('reduced motion: tap still sounds once, no animation', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: MinecraftTapAnimation(
                  onTap: () => taps++,
                  sound: MinecraftSoundKind.like,
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
      await tester.tap(find.byKey(const Key('tap-target')));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(
        SplashSound.playedKindsForTest,
        [MinecraftSoundKind.like],
      );
      expect(find.byKey(const Key('minecraft-tap-squash')), findsNothing);
    });
  });

  group('Minecraft shared-component sound wiring', () {
    testWidgets('MinecraftBlockButton defaults to click', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MinecraftBlockButton(
                label: 'Save',
                onPressed: () => taps++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(MinecraftBlockButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(
        SplashSound.playedKindsForTest,
        [MinecraftSoundKind.click],
      );
    });

    testWidgets('MinecraftBlockButton plays its configured sound', (
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
                sound: MinecraftSoundKind.forge,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(MinecraftBlockButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(
        SplashSound.playedKindsForTest,
        [MinecraftSoundKind.forge],
      );
    });

    testWidgets('MinecraftBlockButton Save plays levelup', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MinecraftBlockButton(
                label: 'Place Block (Save)',
                onPressed: () => taps++,
                sound: MinecraftSoundKind.levelup,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(MinecraftBlockButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(
        SplashSound.playedKindsForTest,
        [MinecraftSoundKind.levelup],
      );
    });

    testWidgets('MinecraftFabButton defaults to pop', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MinecraftFabButton(
                onPressed: () => taps++,
                child: const Icon(Icons.add),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(MinecraftFabButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(
        SplashSound.playedKindsForTest,
        [MinecraftSoundKind.pop],
      );
    });

    testWidgets('MinecraftQuestCard defaults to pop', (tester) async {
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
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(
        SplashSound.playedKindsForTest,
        [MinecraftSoundKind.pop],
      );
    });
  });

  group('Splash opening jingle', () {
    testWidgets('plays exactly once when the app opens', (tester) async {
      AppStartDestination? handed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SplashScreen(
              resolve: () async => AppStartDestination.dashboard,
              onDestination: (next) => handed = next,
            ),
          ),
        ),
      );
      // initState already fired the jingle, before any pump.
      expect(SplashSound.openingJinglePlaysForTest, 1);
      await tester.pumpAndSettle();
      expect(SplashSound.openingJinglePlaysForTest, 1);
      expect(handed, AppStartDestination.dashboard);
    });
  });
}
