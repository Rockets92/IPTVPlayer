import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Effetti sonori della sala giochi.
enum Sfx {
  move,
  select,
  start,
  pause,
  eat,
  bonus,
  coin,
  bounce,
  brick,
  wall,
  hurt,
  over,
  win,
  level,
  crash,
  flip,
  match,
  miss,
  bomb,
}

/// Suoni a 8 bit come le console dei primi anni '90: onde quadre e rumore,
/// generati al volo (nessun file da scaricare) e suonati con libmpv.
class SfxPlayer {
  SfxPlayer({required this.light});

  /// Dispositivi leggeri: un solo canale audio invece di tre.
  final bool light;
  bool enabled = true;

  final _players = <Player>[];
  final _media = <Sfx, Media>{};
  int _next = 0;
  Future<void>? _ready;
  bool _disposed = false;

  Future<void> init() => _ready ??= _init();

  /// Il file WAV di un suono (per i test).
  @visibleForTesting
  static Uint8List render(Sfx s) => _Synth.render(s);

  Future<void> _init() async {
    try {
      for (final s in Sfx.values) {
        _media[s] = await Media.memory(_Synth.render(s));
      }
      for (var i = 0; i < (light ? 1 : 3); i++) {
        if (_disposed) return;
        final p = Player(
          configuration: const PlayerConfiguration(
            vo: 'null',
            libass: false,
            logLevel: MPVLogLevel.error,
          ),
        );
        final n = p.platform;
        if (n is NativePlayer) {
          // Avvio immediato: niente cache, buffer audio corto.
          await n.setProperty('cache', 'no');
          await n.setProperty('audio-buffer', '0.03');
          await n.setProperty('audio-display', 'no');
        }
        _players.add(p);
      }
    } catch (e) {
      debugPrint('Suoni dei giochi non disponibili: $e');
    }
  }

  void play(Sfx s) {
    if (!enabled || _players.isEmpty || _disposed) return;
    final m = _media[s];
    if (m == null) return;
    final p = _players[_next++ % _players.length];
    unawaited(p.open(m).catchError((_) {}));
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final p in _players) {
      await p.dispose();
    }
    _players.clear();
  }
}

/// Sintetizzatore: note quadre con inviluppo, glissati e rumore.
abstract final class _Synth {
  static const rate = 22050;

  static double _hz(String note) {
    const names = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final octave = int.parse(note[note.length - 1]);
    final n = names.indexOf(note.substring(0, note.length - 1));
    return 440 * pow(2, (n - 9) / 12 + (octave - 4)).toDouble();
  }

  static Uint8List render(Sfx s) {
    final out = <double>[];
    void tone(
      double f0,
      double f1,
      double ms, {
      double duty = 0.5,
      double vol = 0.55,
      double decay = 1,
      bool vibrato = false,
    }) {
      final n = (rate * ms / 1000).round();
      var phase = 0.0;
      for (var i = 0; i < n; i++) {
        final t = i / n;
        var f = f0 + (f1 - f0) * t;
        if (vibrato) f *= 1 + 0.012 * sin(i / rate * 2 * pi * 9);
        phase = (phase + f / rate) % 1;
        // Attacco rapido e coda che si spegne: suono "chip".
        final env = min(1.0, i / (rate * 0.002)) * (1 - t * decay);
        out.add((phase < duty ? 1.0 : -1.0) * vol * env);
      }
    }

    void rest(double ms) =>
        out.addAll(List.filled((rate * ms / 1000).round(), 0.0));

    void notes(
      List<String> ns,
      double ms, {
      double duty = 0.5,
      double vol = 0.5,
    }) {
      for (final n in ns) {
        if (n == '-') {
          rest(ms);
        } else {
          tone(_hz(n), _hz(n), ms, duty: duty, vol: vol, decay: 0.6);
        }
      }
    }

    void noise(double ms, {double vol = 0.5, int period = 1}) {
      final n = (rate * ms / 1000).round();
      var lfsr = 0x7FFF;
      var v = 1.0;
      for (var i = 0; i < n; i++) {
        if (i % period == 0) {
          final bit = (lfsr ^ (lfsr >> 1)) & 1;
          lfsr = (lfsr >> 1) | (bit << 14);
          v = (lfsr & 1) == 1 ? 1.0 : -1.0;
        }
        final t = i / n;
        out.add(v * vol * pow(1 - t, 2).toDouble());
      }
    }

    switch (s) {
      case Sfx.move:
        tone(990, 990, 28, duty: 0.25, vol: 0.35);
      case Sfx.select:
        notes(['E5', 'B5'], 45, duty: 0.25);
      case Sfx.start:
        notes(['C5', 'E5', 'G5', 'C6', '-', 'G5', 'C6'], 70, duty: 0.25);
      case Sfx.pause:
        notes(['G5', 'C5'], 60, duty: 0.25);
      case Sfx.eat:
        tone(520, 1180, 70, duty: 0.25, vol: 0.45);
      case Sfx.bonus:
        notes(['C6', 'E6', 'G6', 'C7'], 45, duty: 0.125);
      case Sfx.coin:
        notes(['B5'], 50, duty: 0.25);
        tone(_hz('E6'), _hz('E6'), 220, duty: 0.25, vol: 0.45);
      case Sfx.bounce:
        tone(440, 440, 35, duty: 0.5, vol: 0.4);
      case Sfx.brick:
        tone(880, 700, 45, duty: 0.25, vol: 0.4);
      case Sfx.wall:
        tone(260, 260, 25, duty: 0.5, vol: 0.3);
      case Sfx.hurt:
        tone(700, 120, 420, duty: 0.5, vol: 0.5, vibrato: true);
      case Sfx.over:
        notes(['G4', 'E4', 'C4'], 170, vol: 0.5);
        tone(_hz('C3'), _hz('C3') * 0.94, 520, vol: 0.5, vibrato: true);
      case Sfx.win:
        notes(['C5', 'E5', 'G5', 'C6', '-', 'A5', 'C6', '-'], 90, duty: 0.25);
        tone(_hz('E6'), _hz('E6'), 420, duty: 0.25, vol: 0.45, vibrato: true);
      case Sfx.level:
        notes(['G5', 'A5', 'B5', 'D6', 'G6'], 65, duty: 0.25);
      case Sfx.crash:
        noise(420, vol: 0.6, period: 3);
        tone(160, 50, 200, vol: 0.4);
      case Sfx.flip:
        noise(30, vol: 0.3);
      case Sfx.match:
        notes(['E5', 'A5', 'E6'], 60, duty: 0.25);
      case Sfx.miss:
        tone(180, 150, 160, duty: 0.5, vol: 0.35);
      case Sfx.bomb:
        noise(300, vol: 0.6, period: 6);
    }
    rest(60); // piccola coda di silenzio: niente "click" finale

    // WAV 8 bit mono, come le schede audio dell'epoca.
    final data = Uint8List(out.length);
    for (var i = 0; i < out.length; i++) {
      data[i] = (128 + out[i].clamp(-1.0, 1.0) * 120).round();
    }
    final b = BytesBuilder();
    void u32(int v) =>
        b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
    void u16(int v) =>
        b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
    b.add('RIFF'.codeUnits);
    u32(36 + data.length);
    b.add('WAVEfmt '.codeUnits);
    u32(16);
    u16(1); // PCM
    u16(1); // mono
    u32(rate);
    u32(rate); // byte al secondo
    u16(1);
    u16(8);
    b.add('data'.codeUnits);
    u32(data.length);
    b.add(data);
    return b.toBytes();
  }
}
