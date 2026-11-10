// Synthesized splash sounds for the anime intro (Nov 7) and the
// Minecraft theme sounds (Feature 6, Nov 10).
//
// The reference HTML plays WebAudio oscillators — no audio files.
// This is the native equivalent: tones are synthesized in Dart as
// 16-bit PCM WAV bytes and played from memory via audioplayers.
// There are no audio assets in the repo.
//
// Best-effort by design: every failure is swallowed. The visuals
// never depend on audio, and a phone with no audio (or a test host
// with no audio plugin) just plays silent. There is NO mute toggle:
// sounds are always-on, per Steven's rule (Nov 10).

import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// One Minecraft tap/action sound kind (Feature 6). The preview
/// artifact's Web Audio tones, ported to Dart synthesis — see
/// [SplashSound.play] for the per-kind recipe.
enum MinecraftSoundKind {
  /// Generic tap: 720 Hz square + 980 Hz square.
  click,

  /// Block place / tab / picker / quest row / FAB: 340 Hz sine
  /// sliding to 680 Hz + a low 170 Hz triangle thump.
  pop,

  /// Day toggle / picker select: 880 Hz + 1174 Hz square beeps.
  select,

  /// XP chime: 1318 Hz + 1760 Hz triangle beeps.
  chime,

  /// Save ('Place Block'): C5/E5/G5/C6 triangle arpeggio +
  /// a high sine sparkle.
  levelup,

  /// 'Forge a Quiz': two low square clanks + a bright triangle.
  forge,

  /// Notification bell: 1568 Hz + 2093 Hz sine ring.
  bell,

  /// Like: 520 Hz sine sliding up to 920 Hz.
  like,
}

/// Oscillator waveform for [_addTone]. The original synthesizer
/// only had sine; Feature 6 adds square and triangle so the
/// preview's blocky tones port faithfully.
enum _Waveform { sine, square, triangle }

class SplashSound {
  static const int _sampleRate = 22050;

  /// Whoosh: sawtooth sweep 1400 -> 90 Hz over 0.3 s, gain envelope
  /// 0.0001 -> 0.07 (0.03 s) -> 0.0001 (0.32 s). Total 0.35 s.
  ///
  /// Legacy (Nov 7 anime intro): the splash now plays the
  /// Minecraft opening jingle ([openingJingle]) instead. Kept so
  /// any other caller keeps working.
  static void whoosh() {
    unawaited(_play(_whooshWav()));
  }

  /// Impact sting: three sine beeps — 110 Hz / 0.22 s / gain 0.12,
  /// 880 Hz at +0.02 s / 0.2 s / 0.07, 1320 Hz at +0.06 s / 0.22 s /
  /// 0.05. Mixed into one 0.3 s clip.
  ///
  /// Legacy (Nov 7 anime intro): the splash now plays the
  /// Minecraft opening jingle ([openingJingle]) instead. Kept so
  /// any other caller keeps working.
  static void impact() {
    unawaited(_play(_impactWav()));
  }

  /// Loading tick: short sine beep, 0.05 s, gain 0.03.
  static void tick(double freq) {
    unawaited(_play(_toneWav(freq, 0.05, 0.03)));
  }

  /// Insert pop: soft sine pop, 660 Hz / 0.09 s / gain 0.09 — the
  /// chime that plays the moment a scanned transaction lands in
  /// the Allowance list (never on menu open, scan, or finish).
  /// Best-effort like the rest of this class: silence on failure.
  ///
  /// This is the pre-Minecraft allowance pop, NOT the Minecraft
  /// [MinecraftSoundKind.pop] block-place sound ([tapPop]).
  static void pop() {
    unawaited(_play(_toneWav(660, 0.09, 0.09)));
  }

  /// Class-placement chime (Classes + menu, Feature 2): the same
  /// soft pop as [pop] — a single 660 Hz sine pop, 0.09 s, gain
  /// 0.09. Plays only when a class is placed into the timetable
  /// (manual add, Files scan, or Google Schedule import), never on
  /// menu open, form open, or any other success. Named separately
  /// from [pop] so the placement call sites read as what they are.
  /// Best-effort like the rest of this class: silence on failure.
  static void placeClass() {
    pop();
  }

  /// Setup-success chime: three ascending sine beeps — C5 (523 Hz)
  /// / E5 (659 Hz) / G5 (784 Hz), staggered 0.09 s apart, gain
  /// 0.08–0.09, in one 0.6 s clip. Plays when a new user finishes
  /// Profile Setup (see SetupCelebrationOverlay). Best-effort like
  /// the rest of this class: silence on failure.
  static void celebration() {
    unawaited(_play(_chimeWav()));
  }

  /// Welcome-back chime: a gentle two-note success chime (E5
  /// 659 Hz / G5 784 Hz) plus a soft pop (990 Hz, 0.06 s) at the
  /// end, in one 0.5 s clip. Plays when a returning user signs in
  /// (see WelcomeBackOverlay). Best-effort like the rest of this
  /// class: silence on failure.
  static void welcomeBack() {
    unawaited(_play(_welcomeBackWav()));
  }

  /// Student-tab entrance chime (Feature 5): a quick cheerful
  /// arpeggio — C5 (523 Hz) / E5 (659 Hz) / G5 (784 Hz) / C6
  /// (1047 Hz), staggered 0.09 s apart, gain 0.07–0.09, in one
  /// 0.9 s clip. Plays once when the game-style entrance starts
  /// on the Student tab after the Welcome Back overlay. Same
  /// pattern as [celebration]: synthesized, no audio asset,
  /// best-effort, silence on failure.
  static void entrance() {
    unawaited(_play(_entranceWav()));
  }

  // ----- Minecraft theme sounds (Feature 6) -----

  /// Plays one Minecraft tap/action sound. Best-effort like the
  /// rest of this class: silence on failure, visuals never depend
  /// on audio. The [MinecraftTapAnimation] wrapper calls this once
  /// per tap, with the kind its tap target maps to.
  static void play(MinecraftSoundKind kind) {
    if (_recordPlayedKinds) _playedKinds.add(kind);
    unawaited(_play(wavFor(kind)));
  }

  /// Generic tap (see [MinecraftSoundKind.click]).
  static void tapClick() => play(MinecraftSoundKind.click);

  /// Block place / tab / picker / quest row / FAB
  /// (see [MinecraftSoundKind.pop]).
  static void tapPop() => play(MinecraftSoundKind.pop);

  /// Day toggle / picker select (see [MinecraftSoundKind.select]).
  static void tapSelect() => play(MinecraftSoundKind.select);

  /// XP chime (see [MinecraftSoundKind.chime]).
  static void xpChime() => play(MinecraftSoundKind.chime);

  /// Save ('Place Block') fanfare (see [MinecraftSoundKind.levelup]).
  static void levelUp() => play(MinecraftSoundKind.levelup);

  /// 'Forge a Quiz' clanks (see [MinecraftSoundKind.forge]).
  static void forgeQuiz() => play(MinecraftSoundKind.forge);

  /// Notification bell (see [MinecraftSoundKind.bell]).
  static void bellChime() => play(MinecraftSoundKind.bell);

  /// Like (see [MinecraftSoundKind.like]).
  static void likeSound() => play(MinecraftSoundKind.like);

  /// App-open jingle (Feature 6, Part B): a short blocky arpeggio
  /// in the level-up / XP-chime family — a low square block thump
  /// under C5 / E5 / G5 / C6 triangle notes plus a high sine
  /// sparkle, in one 0.55 s clip. Plays on the splash screen when
  /// the app opens, alongside the existing splash animation, so
  /// the theme's sound is heard from the very first moment.
  /// Replaces the old whoosh + impact sting on the splash; the
  /// loading ticks are unchanged. Best-effort, silence on failure.
  static void openingJingle() {
    if (_recordPlayedKinds) _openingJinglePlays++;
    unawaited(_play(openingJingleWav()));
  }

  /// Synthesized WAV bytes for one [MinecraftSoundKind], for
  /// tests: audio cannot be heard in tests, but the synthesis is
  /// verifiable (valid WAV header, expected duration/sample
  /// count, non-silent samples).
  @visibleForTesting
  static Uint8List wavFor(MinecraftSoundKind kind) {
    return switch (kind) {
      MinecraftSoundKind.click => _clickWav(),
      MinecraftSoundKind.pop => _minecraftPopWav(),
      MinecraftSoundKind.select => _selectWav(),
      MinecraftSoundKind.chime => _chimeXpWav(),
      MinecraftSoundKind.levelup => _levelUpWav(),
      MinecraftSoundKind.forge => _forgeWav(),
      MinecraftSoundKind.bell => _bellWav(),
      MinecraftSoundKind.like => _likeWav(),
    };
  }

  /// Total clip duration in seconds for one [MinecraftSoundKind].
  @visibleForTesting
  static double durationFor(MinecraftSoundKind kind) {
    return switch (kind) {
      MinecraftSoundKind.click => 0.07,
      MinecraftSoundKind.pop => 0.11,
      MinecraftSoundKind.select => 0.12,
      MinecraftSoundKind.chime => 0.23,
      MinecraftSoundKind.levelup => 0.52,
      MinecraftSoundKind.forge => 0.32,
      MinecraftSoundKind.bell => 0.28,
      MinecraftSoundKind.like => 0.10,
    };
  }

  /// Synthesized WAV bytes for the app-open jingle, for tests.
  @visibleForTesting
  static Uint8List openingJingleWav() {
    const duration = 0.55;
    final count = (_sampleRate * duration).round();
    final samples = Float64List(count);
    // Low block thump under the arpeggio.
    _addTone(samples, 130, 0.0, 0.08, 0.10, waveform: _Waveform.square);
    _addTone(samples, 523.25, 0.0, 0.14, 0.10, waveform: _Waveform.triangle);
    _addTone(samples, 659.25, 0.08, 0.14, 0.10, waveform: _Waveform.triangle);
    _addTone(samples, 783.99, 0.16, 0.14, 0.10, waveform: _Waveform.triangle);
    _addTone(samples, 1046.50, 0.24, 0.22, 0.11, waveform: _Waveform.triangle);
    _addTone(samples, 2093, 0.40, 0.12, 0.05);
    return _encodeWav(samples);
  }

  /// Total clip duration of the app-open jingle, in seconds.
  @visibleForTesting
  static const double openingJingleDuration = 0.55;

  // Test-only play log: recording is OFF in production (the list
  // would grow forever). Tests enable it by calling
  // [clearPlayedKindsForTest] first; [play] then records each kind
  // synchronously, so a test can assert a tap played its sound
  // exactly once without waiting on audio.
  static bool _recordPlayedKinds = false;
  static final List<MinecraftSoundKind> _playedKinds = [];
  static int _openingJinglePlays = 0;

  @visibleForTesting
  static List<MinecraftSoundKind> get playedKindsForTest =>
      List.unmodifiable(_playedKinds);

  @visibleForTesting
  static int get openingJinglePlaysForTest => _openingJinglePlays;

  @visibleForTesting
  static void clearPlayedKindsForTest() {
    _playedKinds.clear();
    _openingJinglePlays = 0;
    _recordPlayedKinds = true;
  }

  // ----- Minecraft WAV builders (Feature 6) -----
  //
  // Each recipe ports the approved preview artifact's Web Audio
  // tones to Dart. Where the preview leaves a second tone's volume
  // unspecified, 0.09–0.10 is used (just under the lead tone).

  static Uint8List _clickWav() {
    final count = (_sampleRate * durationFor(MinecraftSoundKind.click))
        .round();
    final samples = Float64List(count);
    _addTone(samples, 720, 0.0, 0.045, 0.11, waveform: _Waveform.square);
    _addTone(samples, 980, 0.03, 0.04, 0.09, waveform: _Waveform.square);
    return _encodeWav(samples);
  }

  static Uint8List _minecraftPopWav() {
    final count = (_sampleRate * durationFor(MinecraftSoundKind.pop)).round();
    final samples = Float64List(count);
    // 340 Hz sine sliding up to 680 Hz, plus a low triangle thump.
    _addTone(samples, 340, 0.0, 0.11, 0.22, endFreq: 680);
    _addTone(samples, 170, 0.0, 0.07, 0.12, waveform: _Waveform.triangle);
    return _encodeWav(samples);
  }

  static Uint8List _selectWav() {
    final count = (_sampleRate * durationFor(MinecraftSoundKind.select))
        .round();
    final samples = Float64List(count);
    _addTone(samples, 880, 0.0, 0.05, 0.10, waveform: _Waveform.square);
    _addTone(samples, 1174, 0.05, 0.07, 0.10, waveform: _Waveform.square);
    return _encodeWav(samples);
  }

  static Uint8List _chimeXpWav() {
    final count = (_sampleRate * durationFor(MinecraftSoundKind.chime))
        .round();
    final samples = Float64List(count);
    _addTone(samples, 1318, 0.0, 0.12, 0.12, waveform: _Waveform.triangle);
    _addTone(samples, 1760, 0.07, 0.16, 0.11, waveform: _Waveform.triangle);
    return _encodeWav(samples);
  }

  static Uint8List _levelUpWav() {
    final count = (_sampleRate * durationFor(MinecraftSoundKind.levelup))
        .round();
    final samples = Float64List(count);
    _addTone(samples, 523.25, 0.0, 0.14, 0.11, waveform: _Waveform.triangle);
    _addTone(samples, 659.25, 0.07, 0.14, 0.11, waveform: _Waveform.triangle);
    _addTone(samples, 783.99, 0.14, 0.14, 0.11, waveform: _Waveform.triangle);
    _addTone(samples, 1046.50, 0.21, 0.14, 0.11, waveform: _Waveform.triangle);
    _addTone(samples, 1568, 0.30, 0.22, 0.10);
    return _encodeWav(samples);
  }

  static Uint8List _forgeWav() {
    final count = (_sampleRate * durationFor(MinecraftSoundKind.forge))
        .round();
    final samples = Float64List(count);
    _addTone(samples, 160, 0.0, 0.09, 0.12, waveform: _Waveform.square);
    _addTone(samples, 120, 0.09, 0.09, 0.12, waveform: _Waveform.square);
    _addTone(samples, 1318, 0.18, 0.14, 0.11, waveform: _Waveform.triangle);
    return _encodeWav(samples);
  }

  static Uint8List _bellWav() {
    final count = (_sampleRate * durationFor(MinecraftSoundKind.bell)).round();
    final samples = Float64List(count);
    _addTone(samples, 1568, 0.0, 0.28, 0.12);
    _addTone(samples, 2093, 0.02, 0.18, 0.09);
    return _encodeWav(samples);
  }

  static Uint8List _likeWav() {
    final count = (_sampleRate * durationFor(MinecraftSoundKind.like)).round();
    final samples = Float64List(count);
    // 520 Hz sine sliding up to 920 Hz.
    _addTone(samples, 520, 0.0, 0.10, 0.14, endFreq: 920);
    return _encodeWav(samples);
  }

  static Future<void> _play(Uint8List wav) async {
    try {
      final player = AudioPlayer();
      await player.play(BytesSource(wav));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await player.dispose();
    } catch (_) {
      // Best-effort: silence must never break the splash.
    }
  }

  static Uint8List _whooshWav() {
    const duration = 0.35;
    final count = (_sampleRate * duration).round();
    final samples = Float64List(count);
    for (var i = 0; i < count; i++) {
      final t = i / _sampleRate;
      // Sawtooth phase: integrate the swept frequency
      // f(t) = 1400 * (90/1400)^(t/0.3).
      final phase = 1400 * 0.3 / math.log(90 / 1400) *
          (math.pow(90 / 1400, t / 0.3) - 1);
      final saw = 2 * (phase - phase.floor()) - 1;
      samples[i] = saw * _expEnvelope(t, 0.03, 0.32, 0.07);
    }
    return _encodeWav(samples);
  }

  static Uint8List _impactWav() {
    const duration = 0.3;
    final count = (_sampleRate * duration).round();
    final samples = Float64List(count);
    _addTone(samples, 110, 0.0, 0.22, 0.12);
    _addTone(samples, 880, 0.02, 0.2, 0.07);
    _addTone(samples, 1320, 0.06, 0.22, 0.05);
    return _encodeWav(samples);
  }

  static Uint8List _toneWav(double freq, double duration, double gain) {
    final count = (_sampleRate * duration).round();
    final samples = Float64List(count);
    _addTone(samples, freq, 0.0, duration, gain);
    return _encodeWav(samples);
  }

  static Uint8List _chimeWav() {
    const duration = 0.6;
    final count = (_sampleRate * duration).round();
    final samples = Float64List(count);
    _addTone(samples, 523.25, 0.0, 0.2, 0.08);
    _addTone(samples, 659.25, 0.09, 0.2, 0.08);
    _addTone(samples, 783.99, 0.18, 0.28, 0.09);
    return _encodeWav(samples);
  }

  static Uint8List _welcomeBackWav() {
    const duration = 0.5;
    final count = (_sampleRate * duration).round();
    final samples = Float64List(count);
    _addTone(samples, 659.25, 0.0, 0.2, 0.08);
    _addTone(samples, 783.99, 0.09, 0.22, 0.08);
    _addTone(samples, 990, 0.32, 0.06, 0.05);
    return _encodeWav(samples);
  }

  static Uint8List _entranceWav() {
    const duration = 0.9;
    final count = (_sampleRate * duration).round();
    final samples = Float64List(count);
    _addTone(samples, 523.25, 0.0, 0.22, 0.07);
    _addTone(samples, 659.25, 0.09, 0.22, 0.08);
    _addTone(samples, 783.99, 0.18, 0.24, 0.08);
    _addTone(samples, 1046.50, 0.27, 0.4, 0.09);
    return _encodeWav(samples);
  }

  /// Adds a beep into [samples], starting at [startSec] for
  /// [durSec], with the reference's exponential gain envelope
  /// (0.0001 -> peak in 0.02 s -> 0.0001 at the end).
  ///
  /// [waveform] selects the oscillator shape (sine by default, as
  /// before). [endFreq] slides the frequency linearly from [freq]
  /// to [endFreq] over the tone (a port of the preview's
  /// frequency ramps, e.g. the pop's 340 -> 680 Hz rise); null
  /// keeps a constant frequency.
  static void _addTone(
    Float64List samples,
    double freq,
    double startSec,
    double durSec,
    double peak, {
    _Waveform waveform = _Waveform.sine,
    double? endFreq,
  }) {
    final start = (startSec * _sampleRate).round();
    final end = math.min(samples.length, start + (durSec * _sampleRate).round());
    final total = end - start;
    // Phase is accumulated sample by sample so a slide stays in
    // tune; for a constant frequency this matches sin(2*pi*f*t).
    var phase = 0.0;
    for (var i = start; i < end; i++) {
      final n = i - start;
      final t = n / _sampleRate;
      final f = endFreq == null
          ? freq
          : freq + (endFreq - freq) * (n / math.max(1, total));
      phase += 2 * math.pi * f / _sampleRate;
      final value = switch (waveform) {
        _Waveform.sine => math.sin(phase),
        _Waveform.square => math.sin(phase) >= 0 ? 1.0 : -1.0,
        _Waveform.triangle => 2 / math.pi * math.asin(math.sin(phase)),
      };
      samples[i] += value * _expEnvelope(t, 0.02, durSec, peak);
    }
  }

  /// Exponential gain envelope matching the reference's
  /// exponentialRampToValueAtTime: 0.0001 -> [peak] in [attackSec],
  /// then -> 0.0001 by [totalSec].
  static double _expEnvelope(
    double t,
    double attackSec,
    double totalSec,
    double peak,
  ) {
    const floor = 0.0001;
    if (t >= totalSec) return floor;
    if (t <= attackSec) {
      return floor * math.pow(peak / floor, t / attackSec);
    }
    final k = (t - attackSec) / (totalSec - attackSec);
    return peak * math.pow(floor / peak, k);
  }

  /// Encodes float samples (-1..1) as a 16-bit PCM mono WAV.
  static Uint8List _encodeWav(Float64List samples) {
    final dataSize = samples.length * 2;
    final bytes = ByteData(44 + dataSize);
    void writeString(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    bytes.setUint32(4, 36 + dataSize, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, 1, Endian.little); // mono
    bytes.setUint32(24, _sampleRate, Endian.little);
    bytes.setUint32(28, _sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    writeString(36, 'data');
    bytes.setUint32(40, dataSize, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i].clamp(-1.0, 1.0);
      bytes.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}
