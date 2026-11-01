import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/brand.dart';
import '../core/performance.dart';
import 'playback_engine.dart';

/// Motore basato su libmpv (media_kit): decodifica hardware su tutte le
/// piattaforme, ottimo con MPEG-TS e HLS dei pannelli Xtream.
class MediaKitEngine implements PlaybackEngine {
  MediaKitEngine(this._perf) {
    _player = Player(
      configuration: PlayerConfiguration(
        title: Brand.name,
        bufferSize: _perf.playerBufferBytes,
        logLevel: MPVLogLevel.error,
        // Niente sottotitoli ASS: meno memoria e avvio più rapido.
        libass: false,
      ),
    );
    _video = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        // Sui box da 1 GB si limita la texture a 720p: la GPU ringrazia.
        width: _perf.isLight ? 1280 : null,
        height: _perf.isLight ? 720 : null,
      ),
    );
    _ready = _configure();
    _subs.addAll([
      _player.stream.playing.listen((p) {
        if (p) {
          _set(
            _state.value.copyWith(
              status: PlaybackStatus.playing,
              clearError: true,
            ),
          );
        }
      }),
      _player.stream.buffering.listen((b) {
        _set(_state.value.copyWith(buffering: b));
      }),
      _player.stream.width.listen((w) => _set(_state.value.copyWith(width: w))),
      _player.stream.height.listen(
        (h) => _set(_state.value.copyWith(height: h)),
      ),
      _player.stream.error.listen((e) {
        // libmpv segnala come "errore" anche problemi non bloccanti (es.
        // dispositivo audio assente): conta solo se il canale non è partito.
        if (_state.value.status != PlaybackStatus.connecting) return;
        _set(_state.value.copyWith(status: PlaybackStatus.failed, error: e));
      }),
      _player.stream.completed.listen((done) {
        // Uno stream live che "finisce" è un segnale interrotto.
        if (done && _state.value.status != PlaybackStatus.idle) {
          _set(
            _state.value.copyWith(
              status: PlaybackStatus.failed,
              error: 'Segnale interrotto',
            ),
          );
        }
      }),
    ]);
  }

  final PerformanceProfile _perf;
  late final Player _player;
  late final VideoController _video;
  late final Future<void> _ready;
  final _subs = <StreamSubscription<Object?>>[];
  final _state = ValueNotifier(const PlaybackSnapshot());

  @override
  ValueListenable<PlaybackSnapshot> get state => _state;

  void _set(PlaybackSnapshot s) => _state.value = s;

  Future<void> _configure() async {
    final p = _player.platform;
    if (p is! NativePlayer) return;
    final props = <String, String>{
      // Live: si privilegia la ripartenza rapida rispetto alla cache lunga.
      'cache': 'yes',
      'cache-secs': _perf.isLight ? '6' : '12',
      'demuxer-max-bytes': _perf.demuxerMaxBytes,
      'demuxer-max-back-bytes': _perf.isLight ? '1MiB' : '8MiB',
      'demuxer-readahead-secs': _perf.isLight ? '4' : '8',
      'network-timeout': '12',
      'stream-lavf-o': 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=4',
      'user-agent': 'IPTVPlayer/0.1',
      'keep-open': 'no',
      'audio-display': 'no',
    };
    for (final e in props.entries) {
      try {
        await p.setProperty(e.key, e.value);
      } catch (_) {}
    }
  }

  @override
  Future<void> open(String url) async {
    await _ready;
    _set(
      const PlaybackSnapshot(
        status: PlaybackStatus.connecting,
        buffering: true,
      ),
    );
    await _player.open(Media(url), play: true);
  }

  @override
  Future<void> stop() async {
    _set(const PlaybackSnapshot());
    await _player.stop();
  }

  @override
  Future<void> setMuted(bool muted) => _player.setVolume(muted ? 0 : 100);

  @override
  Widget buildView(BuildContext context) => Video(
    controller: _video,
    controls: NoVideoControls,
    fill: Colors.black,
    fit: BoxFit.contain,
    filterQuality: _perf.isLight ? FilterQuality.low : FilterQuality.medium,
    // Il blocco schermo è gestito a livello di app.
    wakelock: false,
    pauseUponEnteringBackgroundMode: !kIsWeb,
    resumeUponEnteringForegroundMode: true,
  );

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
    _state.dispose();
  }
}
