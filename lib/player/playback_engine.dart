import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum PlaybackStatus { idle, connecting, playing, failed }

@immutable
class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.status = PlaybackStatus.idle,
    this.buffering = false,
    this.width,
    this.height,
    this.error,
  });

  final PlaybackStatus status;
  final bool buffering;
  final int? width;
  final int? height;
  final String? error;

  /// Risoluzione reale del segnale, come la mostrerebbe un decoder.
  String? get resolutionBadge {
    final h = height;
    if (h == null || h == 0) return null;
    if (h >= 2000) return '4K';
    if (h >= 1000) return 'FHD';
    if (h >= 700) return 'HD';
    return 'SD';
  }

  PlaybackSnapshot copyWith({
    PlaybackStatus? status,
    bool? buffering,
    int? width,
    int? height,
    String? error,
    bool clearError = false,
  }) => PlaybackSnapshot(
    status: status ?? this.status,
    buffering: buffering ?? this.buffering,
    width: width ?? this.width,
    height: height ?? this.height,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Traccia audio o sottotitoli selezionabile.
@immutable
class TrackOption {
  const TrackOption(this.id, this.label);
  final String id;
  final String label;
}

/// Stato della riproduzione di un film o di un episodio.
@immutable
class VodState {
  const VodState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.ended = false,
    this.audio = const [],
    this.subtitles = const [],
    this.audioId,
    this.subtitleId,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool ended;
  final List<TrackOption> audio;
  final List<TrackOption> subtitles;
  final String? audioId;
  final String? subtitleId;

  VodState copyWith({
    Duration? position,
    Duration? duration,
    bool? playing,
    bool? ended,
    List<TrackOption>? audio,
    List<TrackOption>? subtitles,
    String? audioId,
    String? subtitleId,
  }) => VodState(
    position: position ?? this.position,
    duration: duration ?? this.duration,
    playing: playing ?? this.playing,
    ended: ended ?? this.ended,
    audio: audio ?? this.audio,
    subtitles: subtitles ?? this.subtitles,
    audioId: audioId ?? this.audioId,
    subtitleId: subtitleId ?? this.subtitleId,
  );
}

/// Astrazione del motore video, così l'interfaccia è testabile senza libmpv.
abstract class PlaybackEngine {
  ValueListenable<PlaybackSnapshot> get state;
  Future<void> open(String url);

  /// Film o episodio: si può mettere in pausa, spostarsi e cambiare tracce.
  Future<void> openVod(String url, {Duration? start});
  ValueListenable<VodState> get vod;
  Future<void> seek(Duration position);
  Future<void> playOrPause();
  Future<void> setAudioTrack(String id);

  /// `no` spegne i sottotitoli.
  Future<void> setSubtitleTrack(String id);
  Future<void> stop();
  Future<void> setMuted(bool muted);

  /// Volume 0–100 (indipendente dal muto).
  Future<void> setVolume(double volume);
  Widget buildView(BuildContext context);
  Future<void> dispose();
}
