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

/// Astrazione del motore video, così l'interfaccia è testabile senza libmpv.
abstract class PlaybackEngine {
  ValueListenable<PlaybackSnapshot> get state;
  Future<void> open(String url);
  Future<void> stop();
  Future<void> setMuted(bool muted);

  /// Volume 0–100 (indipendente dal muto).
  Future<void> setVolume(double volume);
  Widget buildView(BuildContext context);
  Future<void> dispose();
}
