import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Stato del volume di sistema dopo una regolazione (se il sistema lo dice).
class SystemVolumeState {
  const SystemVolumeState({this.level, this.muted, this.systemOsd = false});

  /// 0–100, se noto.
  final int? level;
  final bool? muted;

  /// Il sistema mostra già il suo indicatore del volume.
  final bool systemOsd;
}

/// Volume del dispositivo su cui gira il player (non quello interno
/// dell'app): sulla Chromecast/TV Android è il volume di sistema (che con
/// l'HDMI-CEC comanda il televisore), su Windows/macOS/Linux il volume
/// generale del computer.
///
/// [adjust] restituisce null se la piattaforma non lo permette (iOS, web):
/// in quel caso si usa il volume dell'app.
class SystemVolume {
  static const _channel = MethodChannel('iptv_player/volume');

  /// La piattaforma gestisce il volume di sistema.
  static bool get supported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isWindows ||
          Platform.isMacOS ||
          Platform.isLinux);

  /// [direction]: +1 alza, -1 abbassa, 0 attiva/disattiva il muto.
  static Future<SystemVolumeState?> adjust(int direction) async {
    if (!supported) return null;
    try {
      if (Platform.isAndroid) return await _android(direction);
      if (Platform.isWindows) return _windows(direction);
      if (Platform.isMacOS) return await _mac(direction);
      if (Platform.isLinux) return await _linux(direction);
    } catch (e) {
      debugPrint('Volume di sistema non disponibile: $e');
    }
    return null;
  }

  // --- Android: AudioManager (con HDMI-CEC il comando arriva alla TV) -------

  static Future<SystemVolumeState?> _android(int direction) async {
    final r = await _channel.invokeMapMethod<String, Object?>('adjust', {
      'direction': direction,
    });
    if (r == null) return null;
    return SystemVolumeState(
      level: (r['level'] as num?)?.toInt(),
      muted: r['muted'] as bool?,
      systemOsd: true,
    );
  }

  // --- Windows: tasti multimediali del volume (come quelli della tastiera) --

  static void Function(int, int, int, int)? _keybdEvent;

  static SystemVolumeState? _windows(int direction) {
    final send = _keybdEvent ??= DynamicLibrary.open('user32.dll')
        .lookupFunction<
          Void Function(Uint8, Uint8, Uint32, IntPtr),
          void Function(int, int, int, int)
        >('keybd_event');
    const keyUp = 0x0002;
    final vk = switch (direction) {
      > 0 => 0xAF, // VK_VOLUME_UP
      < 0 => 0xAE, // VK_VOLUME_DOWN
      _ => 0xAD, // VK_VOLUME_MUTE
    };
    // Ogni pressione vale 2 punti: due pressioni come un passo da 4.
    final times = direction == 0 ? 1 : 2;
    for (var i = 0; i < times; i++) {
      send(vk, 0, 0, 0);
      send(vk, 0, keyUp, 0);
    }
    return const SystemVolumeState(systemOsd: true);
  }

  // --- macOS: AppleScript -----------------------------------------------------

  static Future<SystemVolumeState?> _mac(int direction) async {
    final script = switch (direction) {
      > 0 => 'set volume output volume ((output volume of (get volume settings)) + 6) without output muted',
      < 0 => 'set volume output volume ((output volume of (get volume settings)) - 6)',
      _ =>
        'set volume output muted (not (output muted of (get volume settings)))',
    };
    final set = await Process.run('osascript', ['-e', script]);
    if (set.exitCode != 0) return null;
    final get = await Process.run('osascript', [
      '-e',
      'set s to get volume settings',
      '-e',
      'return (output volume of s as text) & "," & (output muted of s as text)',
    ]);
    final parts = '${get.stdout}'.trim().split(',');
    return SystemVolumeState(
      level: int.tryParse(parts.first),
      muted: parts.length > 1 ? parts[1] == 'true' : null,
    );
  }

  // --- Linux: PulseAudio/PipeWire (pactl), altrimenti ALSA (amixer) ---------

  static Future<SystemVolumeState?> _linux(int direction) async {
    try {
      final args = switch (direction) {
        > 0 => ['set-sink-volume', '@DEFAULT_SINK@', '+5%'],
        < 0 => ['set-sink-volume', '@DEFAULT_SINK@', '-5%'],
        _ => ['set-sink-mute', '@DEFAULT_SINK@', 'toggle'],
      };
      final r = await Process.run('pactl', args);
      if (r.exitCode == 0) {
        if (direction > 0) {
          await Process.run('pactl', ['set-sink-mute', '@DEFAULT_SINK@', '0']);
        }
        final v = await Process.run('pactl', [
          'get-sink-volume',
          '@DEFAULT_SINK@',
        ]);
        final m = await Process.run('pactl', [
          'get-sink-mute',
          '@DEFAULT_SINK@',
        ]);
        final pct = RegExp(r'(\d+)%').firstMatch('${v.stdout}');
        return SystemVolumeState(
          level: pct == null ? null : int.parse(pct[1]!),
          muted: '${m.stdout}'.toLowerCase().contains('yes'),
        );
      }
    } on ProcessException {
      // pactl non installato: si prova con ALSA.
    }
    final arg = switch (direction) {
      > 0 => '5%+',
      < 0 => '5%-',
      _ => 'toggle',
    };
    final r = await Process.run('amixer', ['-q', 'set', 'Master', arg]);
    if (r.exitCode != 0) return null;
    final g = await Process.run('amixer', ['get', 'Master']);
    final out = '${g.stdout}';
    final pct = RegExp(r'\[(\d+)%\]').firstMatch(out);
    return SystemVolumeState(
      level: pct == null ? null : int.parse(pct[1]!),
      muted: out.contains('[off]'),
    );
  }
}
