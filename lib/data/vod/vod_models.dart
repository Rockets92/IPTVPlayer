import 'package:flutter/foundation.dart';

import '../json_utils.dart';

/// Film o serie in un elenco: quanto basta per la griglia di locandine.
@immutable
class VodItem {
  const VodItem({
    required this.id,
    required this.name,
    this.poster,
    this.categoryId,
    this.rating,
    this.added = 0,
    this.year,
    this.extension = 'mp4',
    this.plot,
    this.genre,
    this.adult = false,
  });

  /// `stream_id` per i film, `series_id` per le serie.
  final int id;
  final String name;
  final String? poster;
  final String? categoryId;

  /// Voto 0–10, se il provider lo indica.
  final double? rating;

  /// Data di aggiunta o ultimo aggiornamento (secondi Unix).
  final int added;
  final int? year;

  /// Contenitore del file (solo film): mp4, mkv…
  final String extension;
  final String? plot;
  final String? genre;

  /// Segnalato dal provider come contenuto per adulti (`is_adult`).
  final bool adult;

  /// Nome senza prefissi tipo "IT: " o "|IT| " usati dai pannelli.
  String get title => cleanTitle(name);

  static final _prefix = RegExp(
    r'^\s*(?:[\[|(]\s*[A-Z]{2,3}\s*[\]|)]|[A-Z]{2,3}\s*[:|\-])\s*',
  );
  static final _yearSuffix = RegExp(r'\s*[\(\[]((?:19|20)\d\d)[\)\]]\s*$');

  static String cleanTitle(String name) {
    var s = name.replaceFirst(_prefix, '').trim();
    s = s.replaceFirst(_yearSuffix, '').trim();
    return s.isEmpty ? name.trim() : s;
  }

  static int? _year(Map<String, Object?> j, String name) {
    for (final k in ['year', 'releaseDate', 'release_date', 'releasedate']) {
      final m = RegExp(r'(19|20)\d\d').firstMatch(asString(j[k]));
      if (m != null) return int.parse(m.group(0)!);
    }
    final m = _yearSuffix.firstMatch(name);
    return m == null ? null : int.parse(m.group(1)!);
  }

  static double? _rating(Object? v) {
    final s = asString(v).replaceAll(',', '.').trim();
    final d = double.tryParse(s);
    if (d == null || d <= 0) return null;
    // Alcuni pannelli danno il voto su 5.
    return d > 10 ? null : d;
  }

  static VodItem? movieFromJson(Map<String, Object?> j) {
    final id = asInt(j['stream_id']);
    if (id == null) return null;
    final name = asString(j['name']).trim();
    return VodItem(
      id: id,
      name: name,
      poster: asNonEmptyString(j['stream_icon']),
      categoryId: asNonEmptyString(j['category_id']),
      rating: _rating(j['rating']),
      added: asInt(j['added']) ?? 0,
      year: _year(j, name),
      extension: asNonEmptyString(j['container_extension']) ?? 'mp4',
      adult: asString(j['is_adult']) == '1',
    );
  }

  static VodItem? seriesFromJson(Map<String, Object?> j) {
    final id = asInt(j['series_id']);
    if (id == null) return null;
    final name = asString(j['name']).trim();
    return VodItem(
      id: id,
      name: name,
      poster: asNonEmptyString(j['cover']),
      categoryId: asNonEmptyString(j['category_id']),
      rating: _rating(j['rating']),
      added: asInt(j['last_modified']) ?? 0,
      year: _year(j, name),
      plot: asNonEmptyString(j['plot']),
      genre: asNonEmptyString(j['genre']),
      adult: asString(j['is_adult']) == '1',
    );
  }
}

/// Scheda di un film (get_vod_info).
@immutable
class MovieInfo {
  const MovieInfo({
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.duration,
    this.backdrop,
    this.year,
    this.rating,
  });

  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final Duration? duration;
  final String? backdrop;
  final int? year;
  final double? rating;

  static MovieInfo fromJson(Object? json) {
    final info = json is Map ? json['info'] : null;
    if (info is! Map) return const MovieInfo();
    final j = info.cast<String, Object?>();
    final secs = asInt(j['duration_secs']);
    final backdrop = j['backdrop_path'];
    return MovieInfo(
      plot: asNonEmptyString(j['plot'] ?? j['description']),
      cast: asNonEmptyString(j['cast'] ?? j['actors']),
      director: asNonEmptyString(j['director']),
      genre: asNonEmptyString(j['genre']),
      duration: secs != null && secs > 0
          ? Duration(seconds: secs)
          : _parseDuration(asString(j['duration'])),
      backdrop: backdrop is List && backdrop.isNotEmpty
          ? asNonEmptyString(backdrop.first)
          : asNonEmptyString(backdrop),
      year: VodItem._year(j, ''),
      rating: VodItem._rating(j['rating']),
    );
  }

  static Duration? _parseDuration(String s) {
    final m = RegExp(r'^(\d+):(\d\d):(\d\d)$').firstMatch(s.trim());
    if (m == null) return null;
    return Duration(
      hours: int.parse(m.group(1)!),
      minutes: int.parse(m.group(2)!),
      seconds: int.parse(m.group(3)!),
    );
  }
}

/// Episodio di una serie.
@immutable
class Episode {
  const Episode({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    this.extension = 'mp4',
    this.plot,
    this.duration,
    this.image,
  });

  final int id;
  final int season;
  final int number;
  final String title;
  final String extension;
  final String? plot;
  final Duration? duration;
  final String? image;

  static final _code = RegExp(
    r'S\d+\s*E\d+\s*(?:[-–:|]\s*)?',
    caseSensitive: false,
  );

  /// "Serie - S01E02 - Il patto" → "Il patto" (nome serie e codice sono già
  /// mostrati a parte).
  static String cleanTitle(String raw) {
    final t = raw.trim();
    final m = _code.firstMatch(t);
    if (m != null) {
      final rest = t.substring(m.end).trim();
      return rest;
    }
    return VodItem.cleanTitle(t);
  }

  String get code =>
      'S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')}';
}

/// Scheda di una serie (get_series_info): stagioni ed episodi.
@immutable
class SeriesInfo {
  const SeriesInfo({
    required this.seasons,
    this.plot,
    this.cast,
    this.backdrop,
  });

  /// Stagione → episodi in ordine.
  final Map<int, List<Episode>> seasons;
  final String? plot;
  final String? cast;
  final String? backdrop;

  List<int> get seasonNumbers => seasons.keys.toList()..sort();

  static SeriesInfo fromJson(Object? json) {
    if (json is! Map) return const SeriesInfo(seasons: {});
    final info = json['info'] is Map
        ? (json['info'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final out = <int, List<Episode>>{};
    final eps = json['episodes'];
    // Di solito una mappa "1": [...], "2": [...]; a volte una lista di liste.
    final groups = eps is Map
        ? eps.values
        : eps is List
        ? eps
        : const <Object?>[];
    for (final g in groups) {
      if (g is! List) continue;
      for (final e in g) {
        if (e is! Map) continue;
        final j = e.cast<String, Object?>();
        final id = asInt(j['id']);
        if (id == null) continue;
        final season = asInt(j['season']) ?? 1;
        final number = asInt(j['episode_num']) ?? 0;
        final ei = j['info'] is Map
            ? (j['info'] as Map).cast<String, Object?>()
            : const <String, Object?>{};
        final secs = asInt(ei['duration_secs']);
        (out[season] ??= []).add(
          Episode(
            id: id,
            season: season,
            number: number,
            title: Episode.cleanTitle(asString(j['title'])),
            extension: asNonEmptyString(j['container_extension']) ?? 'mp4',
            plot: asNonEmptyString(ei['plot']),
            duration: secs != null && secs > 0 ? Duration(seconds: secs) : null,
            image: asNonEmptyString(ei['movie_image']),
          ),
        );
      }
    }
    for (final l in out.values) {
      l.sort((a, b) => a.number.compareTo(b.number));
    }
    final backdrop = info['backdrop_path'];
    return SeriesInfo(
      seasons: out,
      plot: asNonEmptyString(info['plot']),
      cast: asNonEmptyString(info['cast']),
      backdrop: backdrop is List && backdrop.isNotEmpty
          ? asNonEmptyString(backdrop.first)
          : asNonEmptyString(backdrop),
    );
  }
}
