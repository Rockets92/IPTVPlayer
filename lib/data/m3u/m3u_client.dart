import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import '../epg/epg_models.dart';
import '../live_source.dart';
import '../xtream/xtream_client.dart';
import '../xtream/xtream_models.dart';

/// Contenuto di una playlist M3U già interpretata.
class M3uPlaylist {
  const M3uPlaylist({required this.streams, this.epgUrl});

  /// Solo canali live: film e serie (mp4, mkv, /movie/, /series/) sono esclusi.
  final List<XtreamLiveStream> streams;

  /// Guida indicata nell'intestazione (`url-tvg` / `x-tvg-url`).
  final String? epgUrl;

  /// Interpreta il testo di una playlist M3U / M3U8 "estesa".
  static M3uPlaylist parse(String text) {
    final streams = <XtreamLiveStream>[];
    String? epg;
    Map<String, String>? attrs;
    String? title;
    String? group;
    var id = 0;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTM3U')) {
        final a = _attributes(line);
        epg = a['url-tvg'] ?? a['x-tvg-url'] ?? a['tvg-url'];
        if (epg != null) epg = epg.split(',').first.trim();
        continue;
      }
      if (line.startsWith('#EXTINF')) {
        attrs = _attributes(line);
        final comma = _titleComma(line);
        title = comma < 0 ? null : line.substring(comma + 1).trim();
        group = attrs['group-title'];
        continue;
      }
      if (line.startsWith('#EXTGRP:')) {
        group ??= line.substring(8).trim();
        continue;
      }
      if (line.startsWith('#')) continue;
      // Riga dell'indirizzo: chiude la voce.
      final url = line;
      final a = attrs ?? const {};
      final name = (title?.isNotEmpty ?? false)
          ? title!
          : (a['tvg-name'] ?? url.split('/').last);
      attrs = null;
      title = null;
      final g = group;
      group = null;
      if (_isVod(url)) continue;
      id++;
      streams.add(
        XtreamLiveStream(
          streamId: id,
          name: name,
          icon: _nonEmpty(a['tvg-logo']),
          epgChannelId: _nonEmpty(a['tvg-id']),
          categoryId: _nonEmpty(g),
          number: int.tryParse(a['tvg-chno'] ?? ''),
          url: url,
        ),
      );
    }
    return M3uPlaylist(streams: streams, epgUrl: _nonEmpty(epg));
  }

  static String? _nonEmpty(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  static final _attr = RegExp(r'([\w-]+)="([^"]*)"');

  static Map<String, String> _attributes(String line) => {
    for (final m in _attr.allMatches(line)) m[1]!.toLowerCase(): m[2]!,
  };

  /// La virgola che separa gli attributi dal nome (fuori dalle virgolette).
  static int _titleComma(String line) {
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') quoted = !quoted;
      if (c == ',' && !quoted) return i;
    }
    return -1;
  }

  static bool _isVod(String url) {
    final u = url.toLowerCase().split('?').first;
    return u.contains('/movie/') ||
        u.contains('/series/') ||
        RegExp(r'\.(mp4|mkv|avi|mov|wmv|flv|m4v|mp3|aac)$').hasMatch(u);
  }
}

/// Lista M3U: la playlist si scarica una volta e da lì escono canali,
/// categorie (group-title) e indirizzi diretti dei flussi.
class M3uClient implements LiveSource {
  M3uClient(this.credentials, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final XtreamCredentials credentials;
  final http.Client _http;
  Future<M3uPlaylist>? _playlist;

  static const _timeout = Duration(seconds: 60);

  DateTime? _loadedAt;

  /// La playlist scaricata da meno di due minuti si riusa (es. tra la
  /// verifica e il caricamento dei canali), altrimenti si riscarica.
  Future<M3uPlaylist> _load() {
    final at = _loadedAt;
    if (_playlist != null &&
        (at == null ||
            DateTime.now().difference(at) < const Duration(minutes: 2))) {
      return _playlist!;
    }
    final f = _download();
    _playlist = f;
    _loadedAt = null;
    f.then(
      (p) {
        _loadedAt = DateTime.now();
        _headerEpg = p.epgUrl;
      },
      onError: (_) {
        if (identical(_playlist, f)) _playlist = null;
      },
    );
    return f;
  }

  Future<M3uPlaylist> _download() async {
    final uri = Uri.tryParse(credentials.serverUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const XtreamException(
        'Indirizzo della playlist non valido: deve iniziare con http:// o https://',
      );
    }
    final http.Response r;
    try {
      r = await _http
          .get(
            uri,
            headers: {'User-Agent': XtreamClient.userAgent, 'Accept': '*/*'},
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const XtreamException(
        'La playlist non risponde. Riprova tra poco.',
      );
    } catch (_) {
      throw const XtreamException(
        'Impossibile scaricare la playlist. Controlla l\'indirizzo e la connessione.',
      );
    }
    if (r.statusCode >= 400) {
      throw XtreamException(
        'Il server della playlist ha risposto con errore ${r.statusCode}.',
      );
    }
    final bytes = r.bodyBytes;
    final list = await Isolate.run(
      () => M3uPlaylist.parse(utf8.decode(bytes, allowMalformed: true)),
    );
    if (list.streams.isEmpty) {
      throw const XtreamException(
        'La playlist non contiene canali live (o non è un file M3U).',
      );
    }
    return list;
  }

  @override
  Future<XtreamAccountInfo> authenticate() async {
    await _load();
    return const XtreamAccountInfo(status: 'Active');
  }

  @override
  Future<List<XtreamCategory>> liveCategories() async {
    final p = await _load();
    final seen = <String>{};
    return [
      for (final s in p.streams)
        if (s.categoryId != null && seen.add(s.categoryId!))
          XtreamCategory(s.categoryId!, s.categoryId!),
    ];
  }

  @override
  Future<List<XtreamLiveStream>> liveStreams() async => (await _load()).streams;

  String? _headerEpg;

  /// Guida dichiarata nell'intestazione della playlist (dopo il download).
  String? get headerEpg => _headerEpg;

  @override
  Uri? get xmltvUri {
    final u = credentials.epgUrl ?? _headerEpg;
    return u == null ? null : Uri.tryParse(u);
  }

  /// Le M3U hanno l'indirizzo in ogni stream: vedi [XtreamLiveStream.url].
  @override
  String liveUrl(int streamId, {String extension = 'ts'}) => '';

  @override
  Future<List<EpgProgramme>> shortEpg(int streamId, {int limit = 6}) async =>
      const [];

  @override
  void close() => _http.close();
}
