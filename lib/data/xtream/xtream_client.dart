import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/heavy_work.dart';
import '../epg/epg_models.dart';
import '../json_utils.dart';
import '../live_source.dart';
import '../vod/vod_models.dart';
import 'xtream_models.dart';

/// Client per l'API "player_api.php" dei pannelli Xtream Codes.
class XtreamClient implements LiveSource {
  XtreamClient(this.credentials, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final XtreamCredentials credentials;
  final http.Client _http;

  static const _timeout = Duration(seconds: 20);

  /// Alcuni pannelli rispondono 503/403 a client che non riconoscono: se
  /// succede si riprova presentandosi come i player più diffusi.
  static const _userAgents = [
    'IPTVPlayer/0.1',
    'okhttp/4.12.0',
    'VLC/3.0.21 LibVLC/3.0.21',
  ];
  static int _uaIndex = 0;

  /// User-Agent che il server accetta, usato anche per i flussi video.
  static String get userAgent => _userAgents[_uaIndex];

  static const _transient = {429, 502, 503, 504, 520, 521, 522, 524};

  Uri _api([Map<String, String> extra = const {}]) =>
      Uri.parse('${credentials.serverUrl}/player_api.php').replace(
        queryParameters: {
          'username': credentials.username,
          'password': credentials.password,
          ...extra,
        },
      );

  Future<String> _get(Uri uri) async =>
      utf8.decode(await _getBytes(uri), allowMalformed: true);

  /// Risposta grezza: gli elenchi grandi si decodificano direttamente dai
  /// byte, senza passare da una stringa con l'intero documento.
  Future<Uint8List> _getBytes(Uri uri) async {
    http.Response? res;
    // Errori temporanei: nuovi tentativi con attesa crescente, cambiando
    // User-Agent se il server continua a rifiutare.
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
      }
      try {
        res = await _http
            .get(uri, headers: {'User-Agent': userAgent, 'Accept': '*/*'})
            .timeout(_timeout);
      } on TimeoutException {
        throw const XtreamException(
          'Il server non risponde. Riprova tra poco.',
        );
      } catch (_) {
        throw const XtreamException(
          'Impossibile raggiungere il server. Controlla l\'indirizzo e la connessione.',
        );
      }
      final code = res.statusCode;
      final rejected = _transient.contains(code) || code == 403;
      if (!rejected) break;
      if (attempt >= 1 && _uaIndex < _userAgents.length - 1) _uaIndex++;
    }
    final r = res!;
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw const XtreamException('Credenziali non valide o account bloccato.');
    }
    if (_transient.contains(r.statusCode)) {
      throw XtreamException(
        'Il server non è disponibile in questo momento (errore ${r.statusCode}). '
        'Se dal PC funziona, controlla che l\'indirizzo sia identico '
        '(http/https e porta), disattiva la VPN o prova con un\'altra rete.',
      );
    }
    if (r.statusCode >= 400) {
      throw XtreamException(
        'Il server ha risposto con errore ${r.statusCode}.',
      );
    }
    return r.bodyBytes;
  }

  /// Verifica le credenziali e restituisce lo stato dell'abbonamento.
  @override
  Future<XtreamAccountInfo> authenticate() async {
    final body = await _get(_api());
    final Object? json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      throw const XtreamException(
        'Risposta non valida: l\'indirizzo non sembra un server Xtream Codes.',
      );
    }
    if (json is! Map) {
      throw const XtreamException('Credenziali non valide.');
    }
    final user = json['user_info'];
    if (user is! Map || asInt(user['auth']) == 0) {
      throw const XtreamException('Nome utente o password errati.');
    }
    final info = XtreamAccountInfo.fromJson(user.cast<String, Object?>());
    if (!info.isActive) {
      throw XtreamException('Abbonamento non attivo (stato: ${info.status}).');
    }
    return info;
  }

  @override
  Future<List<XtreamCategory>> liveCategories() async {
    final body = await _get(_api({'action': 'get_live_categories'}));
    final json = jsonDecode(body);
    if (json is! List) return const [];
    return [
      for (final e in json)
        if (e is Map) XtreamCategory.fromJson(e.cast<String, Object?>()),
    ];
  }

  /// Elenco dei canali live. Il JSON può superare diversi MB: la
  /// decodifica avviene fuori dal thread UI, un elemento alla volta.
  @override
  Future<List<XtreamLiveStream>> liveStreams() => HeavyWork.run(() async {
    final body = await _getBytes(_api({'action': 'get_live_streams'}));
    return Isolate.run(() => _parseStreams(body));
  });

  static List<XtreamLiveStream> _parseStreams(Uint8List body) {
    final out = <XtreamLiveStream>[];
    final isList = forEachJsonArrayElement(body, (e) {
      if (e is Map) {
        final s = XtreamLiveStream.tryFromJson(e.cast<String, Object?>());
        if (s != null) out.add(s);
      }
    });
    return isList ? out : const [];
  }

  // --- Film e serie ----------------------------------------------------------

  Future<List<XtreamCategory>> _categories(String action) async {
    final body = await _get(_api({'action': action}));
    final json = jsonDecode(body);
    if (json is! List) return const [];
    return [
      for (final e in json)
        if (e is Map) XtreamCategory.fromJson(e.cast<String, Object?>()),
    ];
  }

  Future<List<XtreamCategory>> vodCategories() =>
      _categories('get_vod_categories');

  Future<List<XtreamCategory>> seriesCategories() =>
      _categories('get_series_categories');

  /// Tutti i film: elenco anche di decine di migliaia di titoli, decodificato
  /// fuori dal thread UI.
  Future<List<VodItem>> vodStreams() => HeavyWork.run(() async {
    final body = await _getBytes(_api({'action': 'get_vod_streams'}));
    return Isolate.run(() => _parseItems(body, series: false));
  });

  Future<List<VodItem>> series() => HeavyWork.run(() async {
    final body = await _getBytes(_api({'action': 'get_series'}));
    return Isolate.run(() => _parseItems(body, series: true));
  });

  static List<VodItem> _parseItems(Uint8List body, {required bool series}) {
    final out = <VodItem>[];
    final isList = forEachJsonArrayElement(body, (e) {
      if (e is! Map) return;
      final j = e.cast<String, Object?>();
      final v = series ? VodItem.seriesFromJson(j) : VodItem.movieFromJson(j);
      if (v != null) out.add(v);
    });
    return isList ? out : const [];
  }

  Future<MovieInfo> movieInfo(int id) async {
    final body = await _get(_api({'action': 'get_vod_info', 'vod_id': '$id'}));
    try {
      return MovieInfo.fromJson(jsonDecode(body));
    } catch (_) {
      return const MovieInfo();
    }
  }

  Future<SeriesInfo> seriesInfo(int id) async {
    final body = await _get(
      _api({'action': 'get_series_info', 'series_id': '$id'}),
    );
    return Isolate.run(() {
      try {
        return SeriesInfo.fromJson(jsonDecode(body));
      } catch (_) {
        return const SeriesInfo(seasons: {});
      }
    });
  }

  String _path(String kind, int id, String ext) =>
      '${credentials.serverUrl}/$kind/'
      '${Uri.encodeComponent(credentials.username)}/'
      '${Uri.encodeComponent(credentials.password)}/$id.$ext';

  String movieUrl(int id, String ext) => _path('movie', id, ext);

  String episodeUrl(int id, String ext) => _path('series', id, ext);

  /// EPG XMLTV completa del provider.
  @override
  Uri get xmltvUri => Uri.parse('${credentials.serverUrl}/xmltv.php').replace(
    queryParameters: {
      'username': credentials.username,
      'password': credentials.password,
    },
  );

  @override
  String liveUrl(int streamId, {String extension = 'ts'}) =>
      '${credentials.serverUrl}/live/'
      '${Uri.encodeComponent(credentials.username)}/'
      '${Uri.encodeComponent(credentials.password)}/$streamId.$extension';

  /// Guida breve per un singolo canale (fallback quando manca l'XMLTV).
  @override
  Future<List<EpgProgramme>> shortEpg(int streamId, {int limit = 6}) async {
    final body = await _get(
      _api({
        'action': 'get_short_epg',
        'stream_id': '$streamId',
        'limit': '$limit',
      }),
    );
    final json = jsonDecode(body);
    final list = json is Map ? json['epg_listings'] : null;
    if (list is! List) return const [];
    final out = <EpgProgramme>[];
    for (final e in list) {
      if (e is! Map) continue;
      final start = asInt(e['start_timestamp']);
      final end = asInt(e['stop_timestamp']);
      if (start == null || end == null || end <= start) continue;
      out.add(
        EpgProgramme(
          start: start,
          end: end,
          title: _b64(e['title']),
          description: asNonEmptyString(_b64(e['description'])),
        ),
      );
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  static String _b64(Object? v) {
    final s = asString(v);
    if (s.isEmpty) return s;
    try {
      return utf8.decode(base64.decode(s), allowMalformed: true).trim();
    } catch (_) {
      return s;
    }
  }

  @override
  void close() => _http.close();
}
