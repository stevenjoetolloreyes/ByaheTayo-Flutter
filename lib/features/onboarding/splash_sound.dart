// Synthesized splash sounds for the anime intro (Nov 7).
//
// The reference HTML plays WebAudio oscillators — no audio files.
// This is the native equivalent: tones are synthesized in Dart as
// 16-bit PCM WAV bytes and played from memory via audioplayers.
// There are no audio assets in the repo.
//
// Best-effort by design: every failure is swallowed. The splash
// visuals never depend on audio, and a phone with no audio (or a
// test host with no audio plugin) just plays silent.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

class SplashSound {
  static const int _sampleRate = 22050;

  /// Whoosh: sawtooth sweep 1400 -> 90 Hz over 0.3 s, gain envelope
  /// 0.0001 -> 0.07 (0.03 s) -> 0.0001 (0.32 s). Total 0.35 s.
  static void whoosh() {
    unawaited(_play(_whooshWav()));
  }

  /// Impact sting: three sine beeps — 110 Hz / 0.22 s / gain 0.12,
  /// 880 Hz at +0.02 s / 0.2 s / 0.07, 1320 Hz at +0.06 s / 0.22 s /
  /// 0.05. Mixed into one 0.3 s clip.
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
  static void pop() {
    unawaited(_play(_toneWav(660, 0.09, 0.09)));
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

  /// Adds a sine beep into [samples], starting at [startSec] for
  /// [durSec], with the reference's exponential gain envelope
  /// (0.0001 -> peak in 0.02 s -> 0.0001 at the end).
  static void _addTone(
    Float64List samples,
    double freq,
    double startSec,
    double durSec,
    double peak,
  ) {
    final start = (startSec * _sampleRate).round();
    final end = math.min(samples.length, start + (durSec * _sampleRate).round());
    for (var i = start; i < end; i++) {
      final t = (i - start) / _sampleRate;
      samples[i] += math.sin(2 * math.pi * freq * t) *
          _expEnvelope(t, 0.02, durSec, peak);
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
