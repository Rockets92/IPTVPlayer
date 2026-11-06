import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/epg/epg_models.dart';
import '../data/xtream/xtream_models.dart';
import '../domain/channel.dart';
import '../state/app_controller.dart';
import '../state/reminder_controller.dart';
import '../state/tuner_controller.dart';
import '../state/vod_controller.dart';
import 'game_pads.dart';
import 'remote_hooks.dart';
import 'remote_keys.dart';

/// Piccolo server web sulla rete di casa: lo smartphone, inquadrando un QR,
/// apre il telecomando (PWA) o il modulo per compilare i dati della lista.
///
/// Ogni richiesta deve portare il codice segreto [token] contenuto nel QR,
/// così nessun altro dispositivo della rete può comandare l'app.
class RemoteServer extends ChangeNotifier {
  RemoteServer({
    required this.prefs,
    required this.app,
    required this.tuner,
    required this.reminders,
    this.vod,
    GamePads? pads,
  }) : pads = pads ?? GamePads();

  /// Telefoni usati come controller nella sala giochi.
  final GamePads pads;

  final SharedPreferences prefs;
  final AppController app;
  final TunerController tuner;
  final ReminderController reminders;

  /// Film e serie (liste Xtream): "Continua a guardare" sul telefono.
  final VodController? vod;

  static const firstPort = 8787;
  static const _kToken = 'remote.token';
  static const _kGamesToken = 'games.token';

  /// Codice dei controller dei giochi: diverso da [token], così chi gioca
  /// col proprio telefono non può comandare il resto del player.
  late String gamesToken;

  HttpServer? _server;
  String? host;
  int? port;
  String? error;
  late String token;

  /// Ultima richiesta dal telefono: serve a mostrare "connesso".
  DateTime? lastSeen;

  /// Registrato dalla schermata di primo avvio: riceve i dati inviati dal
  /// telefono e restituisce null se la connessione riesce, o il messaggio
  /// d'errore da mostrare sul telefono.
  /// Primo avvio: dati della lista dal telefono, più una fonte EPG
  /// aggiuntiva facoltativa.
  Future<String?> Function(XtreamCredentials c, String? extraEpg)? setupHandler;

  bool get running => _server != null && host != null;
  String? get baseUrl => running ? 'http://$host:$port' : null;
  String? get remoteUrl => running ? '$baseUrl/remote?t=$token' : null;
  String? get setupUrl => running ? '$baseUrl/setup?t=$token' : null;
  String? get epgUrl => running ? '$baseUrl/epg?t=$token' : null;
  String? get padUrl => running ? '$baseUrl/pad?g=$gamesToken' : null;

  /// Fonti EPG aggiuntive (dalle impostazioni), cambiate dal telefono.
  List<String> get extraEpgSources => app.settings.extraEpgSources;

  Future<void> start() async {
    if (kIsWeb || _server != null) return;
    token = prefs.getString(_kToken) ?? _newToken();
    await prefs.setString(_kToken, token);
    gamesToken = prefs.getString(_kGamesToken) ?? _newToken();
    await prefs.setString(_kGamesToken, gamesToken);
    for (var p = firstPort; p < firstPort + 10; p++) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, p);
        port = p;
        break;
      } catch (_) {}
    }
    final server = _server;
    if (server == null) {
      error = 'Nessuna porta libera tra $firstPort e ${firstPort + 9}';
      notifyListeners();
      return;
    }
    host = await lanAddress();
    if (host == null) error = 'Nessuna rete Wi-Fi o cavo trovata';
    server.listen(
      (r) => unawaited(_handle(r).catchError((Object _) {})),
      onError: (Object _) {},
    );
    notifyListeners();
  }

  /// Un nuovo codice rende inutilizzabili i telecomandi già salvati.
  Future<void> resetToken() async {
    token = _newToken();
    await prefs.setString(_kToken, token);
    notifyListeners();
  }

  /// Ricalcola l'indirizzo (es. dopo un cambio di rete).
  Future<void> refreshAddress() async {
    host = await lanAddress();
    error = host == null ? 'Nessuna rete Wi-Fi o cavo trovata' : null;
    notifyListeners();
  }

  static String _newToken() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Indirizzo IPv4 della rete di casa, scartando VPN e schede virtuali.
  static Future<String?> lanAddress() async {
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
      const virtual = [
        'vethernet',
        'virtualbox',
        'vmware',
        'vmnet',
        'docker',
        'wsl',
        'tun',
        'tap',
        'utun',
        'hyper-v',
        'zerotier',
        'tailscale',
      ];
      int score(NetworkInterface i, InternetAddress a) {
        final n = i.name.toLowerCase();
        if (virtual.any(n.contains)) return 0;
        final ip = a.address;
        if (ip.startsWith('192.168.')) return 4;
        if (ip.startsWith('10.')) return 3;
        final m = RegExp(r'^172\.(\d+)\.').firstMatch(ip);
        if (m != null) {
          final b = int.parse(m[1]!);
          if (b >= 16 && b <= 31) return 2;
        }
        return 1;
      }

      String? best;
      var bestScore = 0;
      for (final i in list) {
        for (final a in i.addresses) {
          if (a.isLoopback || a.isLinkLocal) continue;
          final s = score(i, a);
          if (s > bestScore) {
            best = a.address;
            bestScore = s;
          }
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  // --- Richieste --------------------------------------------------------------

  Future<void> _handle(HttpRequest r) async {
    final path = r.uri.path;
    final res = r.response;
    res.headers.set('Cache-Control', 'no-store');

    // File pubblici: icone e service worker non contengono nulla di privato.
    switch (path) {
      case '/icon-192.png' || '/icon-512.png' || '/apple-touch-icon.png':
        return _asset(res, 'assets/remote$path', ContentType('image', 'png'));
      case '/sw.js':
        return _text(
          res,
          await rootBundle.loadString('assets/remote/sw.js'),
          ContentType('application', 'javascript', charset: 'utf-8'),
        );
    }

    // Controller dei giochi: hanno un codice a parte.
    if (path == '/pad' || path == '/pad/ws') {
      if (r.uri.queryParameters['g'] != gamesToken) {
        res.statusCode = HttpStatus.forbidden;
        return _text(
          res,
          _page(
            'Codice non valido',
            'Inquadra di nuovo il QR della sala giochi sulla TV.',
          ),
          ContentType.html,
        );
      }
      if (path == '/pad') {
        final html = (await rootBundle.loadString('assets/remote/pad.html'))
            .replaceAll('{{GTOKEN}}', gamesToken);
        return _text(res, html, ContentType.html);
      }
      if (!WebSocketTransformer.isUpgradeRequest(r)) {
        res.statusCode = HttpStatus.badRequest;
        return res.close();
      }
      final ws = await WebSocketTransformer.upgrade(r);
      ws.pingInterval = const Duration(seconds: 5);
      return pads.attach(ws);
    }

    final t = r.uri.queryParameters['t'] ?? r.headers.value('x-token');
    if (t != token) {
      res.statusCode = HttpStatus.forbidden;
      return _text(
        res,
        _page(
          'Codice non valido',
          'Inquadra di nuovo il QR mostrato dal player: il codice è cambiato '
              'o il link è incompleto.',
        ),
        ContentType.html,
      );
    }
    lastSeen = DateTime.now();

    switch ((r.method, path)) {
      case ('GET', '/' || '/remote'):
        return _html(res, 'assets/remote/remote.html');
      case ('GET', '/epg'):
        return _html(res, 'assets/remote/epg.html');
      case ('GET', '/api/epg-sources'):
        return _json(res, {'sources': app.settings.extraEpgSources});
      case ('POST', '/api/epg-sources'):
        return _json(res, await _editEpgSources(await _body(r)));
      case ('GET', '/setup'):
        return _html(res, 'assets/remote/setup.html');
      case ('GET', '/manifest.webmanifest'):
        return _json(res, _manifest(), type: 'application/manifest+json');
      case ('GET', '/api/state'):
        return _json(res, _state());
      case ('GET', '/api/channels'):
        return _json(res, _channels());
      case ('GET', '/api/epg'):
        return _json(res, _epg(r.uri.queryParameters['id']));
      case ('POST', '/api/key'):
        final body = await _body(r);
        final k = '${body['key'] ?? ''}';
        if (k == 'volup' || k == 'voldown' || k == 'mute') {
          // Il volume vale anche con un pannello aperto.
          if (k == 'mute') {
            tuner.toggleMute();
          } else {
            tuner.changeVolume(k == 'volup' ? 5 : -5);
          }
        } else {
          dispatchRemoteKey(k);
        }
        return _json(res, _state());
      case ('GET', '/api/vod'):
        return _json(res, _vodState());
      case ('POST', '/api/vod/resume'):
        final body = await _body(r);
        final key = '${body['key'] ?? ''}';
        final hit = vod
            ?.resumeAll(limit: 50)
            .where((e) => e.$2.key == key)
            .firstOrNull;
        final item = hit == null ? null : vod!.itemFor(hit.$1, hit.$2);
        final open = RemoteHooks.resume;
        if (hit == null || item == null || open == null) {
          return _json(res, {
            ..._vodState(),
            'error': 'Titolo non disponibile',
          });
        }
        open(hit.$1, item);
        return _json(res, _vodState());
      case ('POST', '/api/search'):
        final body = await _body(r);
        final search = RemoteHooks.search;
        if (search == null) {
          return _json(res, {'ok': false});
        }
        search('${body['q'] ?? ''}');
        return _json(res, {'ok': true});
      case ('POST', '/api/tune'):
        final body = await _body(r);
        final c = _byId('${body['id']}');
        if (c != null) tuner.tuneTo(c);
        return _json(res, _state());
      case ('POST', '/api/reminder'):
        final body = await _body(r);
        final c = _byId('${body['id']}');
        final start = body['start'];
        final p = c == null
            ? null
            : app.epg
                  .forChannel(c.id)
                  .where((p) => p.start == start)
                  .firstOrNull;
        if (c == null || p == null) {
          return _json(res, {'error': 'Programma non trovato'});
        }
        final on = reminders.toggle(c, p);
        return _json(res, {'reminded': on});
      case ('GET', '/api/reminders'):
        return _json(res, _reminders());
      case ('POST', '/api/reminders'):
        final body = await _body(r);
        final rem = reminders.byKey('${body['key']}');
        if (rem == null) {
          return _json(res, {
            ..._reminders(),
            'error': 'Promemoria non trovato',
          });
        }
        if (body['delete'] == true) {
          reminders.remove(rem);
        } else {
          final days = body['days'];
          reminders.setRepeat(
            rem,
            ReminderRepeat.parse(body['repeat']),
            days is List
                ? days.whereType<num>().map((e) => e.toInt()).toList()
                : null,
          );
        }
        return _json(res, _reminders());
      case ('POST', '/api/setup'):
        return _json(res, await _setup(await _body(r)));
      case ('GET', '/api/info'):
        return _json(res, {
          'phase': app.phase.name,
          'setup': setupHandler != null,
        });
    }
    res.statusCode = HttpStatus.notFound;
    return _text(res, 'Non trovato', ContentType.text);
  }

  Channel? _byId(String id) =>
      app.channels.where((c) => c.id == id).firstOrNull;

  Map<String, Object?> _programme(EpgProgramme? p) => p == null
      ? const {}
      : {'t': p.title, 's': p.start, 'e': p.end, 'd': p.description};

  Map<String, Object?> _state() {
    final c = tuner.displayed ?? tuner.current;
    final now = DateTime.now();
    return {
      'phase': app.phase.name,
      'volume': tuner.volume,
      'muted': tuner.muted,
      'locked': tuner.locked,
      'timeshift': tuner.timeshift,
      'browsing': tuner.browsing,
      'vod': vod?.available ?? false,
      'searching': RemoteHooks.search != null,
      if (c != null)
        'channel': {
          'id': c.id,
          'n': c.number,
          'name': c.name,
          'g': c.group,
          'logo': c.logoUrl,
          'plus1': c.hasPlusOne,
          'sources': c.sources.length,
        },
      if (c != null) 'now': _programme(app.epg.nowOn(c.id, now)),
      if (c != null) 'next': _programme(app.epg.nextOn(c.id, now)),
      if (tuner.current != null) 'current': tuner.current!.id,
    };
  }

  Map<String, Object?> _vodState() => {
    'available': vod?.available ?? false,
    'resume': [
      for (final (kind, w)
          in vod?.resumeAll() ?? const <(VodKind, WatchEntry)>[])
        {
          'key': w.key,
          'kind': kind == VodKind.movies ? 'movie' : 'series',
          't': w.title,
          'poster': w.poster,
          'label': w.label,
          'f': w.fraction,
          'left': (w.duration - w.position).inMinutes,
        },
    ],
  };

  Map<String, Object?> _reminders() => {
    'reminders': [
      for (final r in reminders.items)
        {
          'key': r.key,
          'id': r.channelId,
          'n': r.channelNumber,
          'name': r.channelName,
          't': r.title,
          's': r.start,
          'repeat': r.repeat.name,
          'days': r.weekDays,
          'label': r.repeatLabel,
        },
    ],
  };

  Map<String, Object?> _channels() {
    final now = DateTime.now();
    final direct = {for (final c in app.channels) c.group};
    return {
      'groups': app.groups,
      // Categorie "vista" (Vetrina): canali nell'ordine in cui compaiono,
      // ogni vetrina seguita dai suoi canali collegati.
      'views': {
        for (final g in app.groups)
          if (!direct.contains(g)) g: [for (final c in app.channelsIn(g)) c.id],
      },
      'current': tuner.current?.id,
      'channels': [
        for (final c in app.channels)
          {
            'id': c.id,
            'n': c.number,
            'name': c.name,
            'g': c.group,
            'logo': c.logoUrl,
            'now': app.epg.nowOn(c.id, now)?.title,
            if (c.adult) 'x': true,
          },
      ],
    };
  }

  Map<String, Object?> _epg(String? id) {
    final c = id == null ? tuner.current : _byId(id);
    if (c == null) return {'programmes': const []};
    unawaited(app.ensureEpg(c));
    final from = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3 * 3600;
    final to = from + 30 * 3600;
    return {
      'id': c.id,
      'n': c.number,
      'name': c.name,
      'programmes': [
        for (final p in app.epg.forChannel(c.id))
          if (p.end > from && p.start < to)
            {..._programme(p), if (reminders.isSet(c.id, p)) 'r': true},
      ],
    };
  }

  Future<Map<String, Object?>> _editEpgSources(Map<String, Object?> b) async {
    final list = [...app.settings.extraEpgSources];
    final add = '${b['add'] ?? ''}'.trim();
    final remove = '${b['remove'] ?? ''}'.trim();
    if (add.isNotEmpty) {
      final uri = Uri.tryParse(add);
      if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
        return {
          'sources': list,
          'error': 'Indirizzo non valido: deve iniziare con http:// o https://',
        };
      }
      if (list.contains(add)) {
        return {'sources': list, 'error': 'Questa fonte c\'è già.'};
      }
      list.add(add);
    }
    if (remove.isNotEmpty) list.remove(remove);
    await app.settings.setExtraEpgSources(list);
    notifyListeners();
    unawaited(app.refreshEpg());
    return {'sources': app.settings.extraEpgSources};
  }

  Future<Map<String, Object?>> _setup(Map<String, Object?> b) async {
    final handler = setupHandler;
    if (handler == null) {
      return {
        'error':
            'Il player è già configurato. Per cambiare lista usa '
            '"Cambia account" nelle impostazioni.',
      };
    }
    final XtreamCredentials c;
    if (b['kind'] == 'm3u') {
      final url = '${b['playlist'] ?? ''}'.trim();
      final epg = '${b['epg'] ?? ''}'.trim();
      if (url.isEmpty) {
        return {'error': 'Inserisci l\'indirizzo della playlist.'};
      }
      // Un link M3U di un pannello Xtream si usa come Xtream: più veloce
      // e con la guida del provider.
      c =
          XtreamCredentials.tryParseLink(url) ??
          XtreamCredentials.m3u(url, epgUrl: epg.isEmpty ? null : epg);
    } else {
      final server = XtreamCredentials.normalizeServer('${b['server'] ?? ''}');
      final user = '${b['user'] ?? ''}'.trim();
      final pass = '${b['pass'] ?? ''}';
      if (server.isEmpty || user.isEmpty || pass.isEmpty) {
        return {'error': 'Compila server, nome utente e password.'};
      }
      c = XtreamCredentials(serverUrl: server, username: user, password: pass);
    }
    final extra = '${b['extraEpg'] ?? ''}'.trim();
    final err = await handler(c, extra.isEmpty ? null : extra);
    return err == null ? {'ok': true} : {'error': err};
  }

  Map<String, Object?> _manifest() => {
    'name': 'Telecomando B&B IPTV Player',
    'short_name': 'Telecomando',
    'start_url': '/remote?t=$token',
    'scope': '/',
    'display': 'standalone',
    'orientation': 'portrait',
    'background_color': '#05040e',
    'theme_color': '#05040e',
    'icons': [
      {'src': '/icon-192.png', 'sizes': '192x192', 'type': 'image/png'},
      {'src': '/icon-512.png', 'sizes': '512x512', 'type': 'image/png'},
      {
        'src': '/icon-512.png',
        'sizes': '512x512',
        'type': 'image/png',
        'purpose': 'maskable',
      },
    ],
  };

  // --- Risposte ---------------------------------------------------------------

  Future<Map<String, Object?>> _body(HttpRequest r) async {
    try {
      final text = await utf8.decodeStream(r);
      final j = jsonDecode(text);
      return j is Map ? j.cast<String, Object?>() : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> _html(HttpResponse res, String asset) async {
    final html = (await rootBundle.loadString(asset))
        .replaceAll('{{TOKEN}}', token);
    return _text(res, html, ContentType.html);
  }

  Future<void> _asset(HttpResponse res, String asset, ContentType type) async {
    try {
      final data = await rootBundle.load(asset);
      res.headers.contentType = type;
      res.headers.set('Cache-Control', 'public, max-age=86400');
      res.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } catch (_) {
      res.statusCode = HttpStatus.notFound;
    }
    await res.close();
  }

  Future<void> _json(
    HttpResponse res,
    Object body, {
    String type = 'application/json',
  }) => _text(res, jsonEncode(body), ContentType.parse('$type; charset=utf-8'));

  Future<void> _text(HttpResponse res, String body, ContentType type) async {
    res.headers.contentType = type;
    res.add(utf8.encode(body));
    await res.close();
  }

  static String _page(String title, String text) =>
      '<!doctype html><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>$title</title><body style="font-family:system-ui;background:#05040e;'
      'color:#eef2fa;padding:32px;line-height:1.5"><h2>$title</h2><p>$text</p>';

  @override
  void dispose() {
    unawaited(_server?.close(force: true));
    super.dispose();
  }
}
