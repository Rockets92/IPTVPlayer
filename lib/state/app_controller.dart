import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/heavy_work.dart';
import '../core/performance.dart';
import '../data/epg/epg_models.dart';
import '../data/epg/epg_repository.dart';
import '../data/live_source.dart';
import '../data/m3u/m3u_client.dart';
import '../data/mapping/channel_mapping.dart';
import '../data/mapping/mapping_repository.dart';
import '../data/settings_store.dart';
import '../data/xtream/xtream_models.dart';
import '../domain/channel.dart';
import '../domain/channel_matcher.dart';

enum AppPhase { booting, setup, loading, ready, failed }

/// Stato globale: account, lista canali, guida.
class AppController extends ChangeNotifier {
  AppController({
    required this.settings,
    required this.perf,
    MappingRepository? mappingRepository,
    EpgRepository? epgRepository,
    LiveSource Function(XtreamCredentials)? clientFactory,
  }) : _mappingRepo = mappingRepository ?? MappingRepository(),
       _epgRepo = epgRepository ?? EpgRepository(),
       _clientFactory = clientFactory ?? LiveSource.create;

  final SettingsStore settings;
  final PerformanceProfile perf;
  final MappingRepository _mappingRepo;
  final EpgRepository _epgRepo;
  final LiveSource Function(XtreamCredentials) _clientFactory;

  AppPhase phase = AppPhase.booting;
  String loadingMessage = '';
  String? failure;

  XtreamCredentials? credentials;
  XtreamAccountInfo? account;
  LiveSource? _client;

  /// Fonte della lista in uso (Xtream o M3U).
  LiveSource? get source => _client;

  /// Indirizzi diretti degli stream (liste M3U).
  Map<int, String> _directUrls = const {};

  /// Guida dichiarata nell'intestazione della playlist M3U.
  String? _m3uEpg;

  ChannelMapping? mapping;
  List<Channel> channels = const [];

  EpgSchedule epg = EpgSchedule.empty();
  bool epgLoading = false;
  String? epgStatus;
  List<EpgSourceReport> epgReports = const [];
  final _shortEpgTried = <String>{};

  /// Firma della guida in memoria (null: nessuna o da riverificare).
  String? _epgSig;

  /// Prossimo aggiornamento automatico o nuovo tentativo.
  Timer? _epgTimer;

  /// Tentativi falliti di fila: allungano l'attesa fra un tentativo e l'altro.
  int _epgFailures = 0;

  /// Aggiornamento chiesto mentre un altro era in corso: parte subito dopo.
  bool _epgPending = false;

  /// Attese fra i tentativi quando la guida non si scarica (rete non ancora
  /// pronta dopo l'accensione o lo standby, server lento): poi ogni 15 minuti.
  static const epgRetryDelays = [
    Duration(seconds: 20),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
  ];

  bool _disposed = false;

  // Categorie e canali per categoria si ricalcolano solo quando cambia la
  // lista: elenco canali e guida li chiedono a ogni tasto e a ogni riga.
  List<String>? _groups;
  final _channelsIn = <String, List<Channel>>{};
  List<Channel>? _cacheOf;
  ChannelMapping? _cacheMapping;

  void _checkCaches() {
    if (identical(_cacheOf, channels) && identical(_cacheMapping, mapping)) {
      return;
    }
    _cacheOf = channels;
    _cacheMapping = mapping;
    _groups = null;
    _channelsIn.clear();
  }

  List<String> get groups {
    _checkCaches();
    return _groups ??= List.unmodifiable(_computeGroups());
  }

  List<String> _computeGroups() {
    final seen = <String>{};
    final out = [
      for (final c in channels)
        if (seen.add(c.group)) c.group,
    ];
    // Categorie "vista" (Vetrina): dopo la categoria automatica che le
    // precede nella lista (es. dopo Eventi), altrimenti in fondo.
    final views = <String>{for (final c in channels) ...c.extraGroups}
        .where((g) => !seen.contains(g));
    final dyn = mapping?.dynamicGroups ?? const [];
    for (final v in views) {
      final at = dyn.indexWhere((g) => g.name == v);
      var pos = out.length;
      for (var i = at - 1; i >= 0; i--) {
        final p = out.indexOf(dyn[i].name);
        if (p >= 0) {
          pos = p + 1;
          break;
        }
      }
      out.insert(pos, v);
    }
    return out;
  }

  /// Canali di una categoria. Nelle categorie "vista" (Vetrina) ogni canale
  /// è seguito dai suoi canali collegati, per raggiungerli subito.
  List<Channel> channelsIn(String group) {
    _checkCaches();
    return _channelsIn[group] ??= List.unmodifiable(_computeChannelsIn(group));
  }

  List<Channel> _computeChannelsIn(String group) {
    final direct = channels.where((c) => c.group == group).toList();
    if (direct.isNotEmpty) return direct;
    final byId = {for (final c in channels) c.id: c};
    final out = <Channel>[];
    final seen = <String>{};
    for (final c in channels.where((c) => c.extraGroups.contains(group))) {
      if (seen.add(c.id)) out.add(c);
      for (final id in c.linked) {
        final l = byId[id];
        if (l != null && seen.add(l.id)) out.add(l);
      }
    }
    return out;
  }

  /// Canali preferiti, in ordine di numero.
  List<Channel> get favoriteChannels {
    final fav = settings.favorites.toSet();
    if (fav.isEmpty) return const [];
    return [
      for (final c in channels)
        if (fav.contains(c.id)) c,
    ];
  }

  bool isFavorite(String channelId) => settings.isFavorite(channelId);

  /// Aggiunge o toglie un preferito; true se ora è preferito.
  Future<bool> toggleFavorite(Channel c) async {
    final on = await settings.toggleFavorite(c.id);
    _notify();
    return on;
  }

  /// Un'impostazione che cambia l'aspetto (es. dimensione interfaccia).
  void settingsChanged() => _notify();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    credentials = settings.credentials;
    account = settings.account;
    if (credentials == null) {
      phase = AppPhase.setup;
      _notify();
      return;
    }
    _client = _clientFactory(credentials!);
    await _load(preferCache: true);
  }

  /// Primo avvio o cambio account: verifica e salva le credenziali.
  Future<XtreamAccountInfo> connect(XtreamCredentials c) async {
    final client = _clientFactory(c);
    final info = await client.authenticate();
    _client?.close();
    _client = client;
    credentials = c;
    account = info;
    _m3uEpg = null;
    await settings.setCredentials(c);
    await settings.setAccount(info);
    await _clearStreamCache();
    return info;
  }

  /// Dopo `connect`: carica canali e guida.
  Future<void> enter() => _load(preferCache: false);

  Future<void> retry() => _load(preferCache: true);

  Future<void> reloadChannels() => _load(preferCache: false, silent: true);

  Future<void> logout() async {
    await settings.clearAccount();
    await _clearStreamCache();
    _client?.close();
    _client = null;
    credentials = null;
    account = null;
    _m3uEpg = null;
    _directUrls = const {};
    channels = const [];
    _resetEpg();
    phase = AppPhase.setup;
    _notify();
  }

  String streamUrl(ChannelSource s) =>
      _directUrls[s.streamId] ??
      _client!.liveUrl(s.streamId, extension: settings.streamFormat.extension);

  // ---------------------------------------------------------------------------

  Future<void> _load({required bool preferCache, bool silent = false}) async {
    if (!silent) {
      phase = AppPhase.loading;
      failure = null;
      loadingMessage = 'Preparazione della lista canali';
      _notify();
    }
    try {
      mapping = await _mappingRepo.load(source: settings.mappingSource);

      // Avvio istantaneo: si usa l'ultima lista nota e la si aggiorna dopo.
      if (preferCache) {
        final cached = await _readStreamCache();
        if (cached != null) {
          await _rebuild(cached.$1, cached.$2);
          if (channels.isNotEmpty) {
            phase = AppPhase.ready;
            _notify();
            // La guida salvata si mostra subito; lo scaricamento parte dopo
            // l'aggiornamento della lista, così usa i canali definitivi e non
            // si somma al suo picco di memoria.
            unawaited(_showEpgCache());
            unawaited(
              _refreshStreamsQuietly()
                  .timeout(const Duration(minutes: 2), onTimeout: () {})
                  .whenComplete(() => _refreshEpg()),
            );
            return;
          }
        }
      }

      if (!silent) {
        loadingMessage = 'Download dei canali dal provider';
        _notify();
      }
      final client = _client!;
      final results = await Future.wait([
        client.liveCategories().catchError((_) => <XtreamCategory>[]),
        client.liveStreams(),
      ]);
      final cats = results[0] as List<XtreamCategory>;
      final streams = results[1] as List<XtreamLiveStream>;
      final catMap = {for (final c in cats) c.id: c.name};
      _noteM3uEpg(client);
      await _rebuild(streams, catMap);
      unawaited(_writeStreamCache(streams, catMap));
      if (channels.isEmpty) {
        throw const XtreamException(
          'Il provider non ha restituito canali live per questo account.',
        );
      }
      phase = AppPhase.ready;
      _notify();
      unawaited(_refreshEpg());
    } catch (e) {
      if (silent) return;
      failure = e is XtreamException
          ? e.message
          : 'Errore durante il caricamento: $e';
      phase = AppPhase.failed;
      _notify();
    }
  }

  void _noteM3uEpg(LiveSource client) {
    if (client is M3uClient && client.headerEpg != null) {
      _m3uEpg = client.headerEpg;
    }
  }

  int _rebuildGen = 0;

  /// Abbina gli stream del provider alla lista canali. Con migliaia di stream
  /// richiede secondi sui box più lenti: si fa in un isolate, così il thread
  /// dell'interfaccia resta libero (prima bloccava l'avvio fino all'ANR).
  /// Restituisce false se nel frattempo è partito un abbinamento più recente.
  Future<bool> _rebuild(
    List<XtreamLiveStream> streams,
    Map<String, String> cats,
  ) async {
    final gen = ++_rebuildGen;
    final built = await _matchInIsolate(
      mapping!,
      streams,
      cats,
      preferLighter: perf.preferLighterStreams,
      showUnmapped: settings.showUnmapped,
      includeAdult: settings.adultMode != AdultMode.off,
    );
    if (gen != _rebuildGen) return false;
    _directUrls = {
      for (final s in streams)
        if (s.url != null) s.streamId: s.url!,
    };
    channels = built;
    return true;
  }

  // Statico: la chiusura inviata all'isolate non deve catturare il controller.
  static Future<List<Channel>> _matchInIsolate(
    ChannelMapping mapping,
    List<XtreamLiveStream> streams,
    Map<String, String> cats, {
    required bool preferLighter,
    required bool? showUnmapped,
    required bool includeAdult,
  }) => Isolate.run(
    () => ChannelMatcher(preferLighterStreams: preferLighter).build(
      mapping: mapping,
      streams: streams,
      categoryNames: cats,
      showUnmapped: showUnmapped,
      includeAdult: includeAdult,
    ),
  );

  Future<void> _refreshStreamsQuietly() async {
    try {
      final client = _client;
      if (client == null) return;
      final results = await Future.wait([
        client.liveCategories().catchError((_) => <XtreamCategory>[]),
        client.liveStreams(),
      ]);
      final cats = results[0] as List<XtreamCategory>;
      final streams = results[1] as List<XtreamLiveStream>;
      final catMap = {for (final c in cats) c.id: c.name};
      if (streams.isEmpty) return;
      _noteM3uEpg(client);
      if (!await _rebuild(streams, catMap)) return;
      _notify();
      await _writeStreamCache(streams, catMap);
    } catch (_) {
      // Offline o server lento: resta valida la lista in cache.
    }
  }

  /// Riapplica la mappatura (es. dopo averla cambiata nelle impostazioni).
  Future<void> applyMapping() async {
    try {
      mapping = await _mappingRepo.load(source: settings.mappingSource);
      final cached = await _readStreamCache();
      if (cached != null) await _rebuild(cached.$1, cached.$2);
    } catch (_) {
      return;
    }
    _resetEpg();
    _notify();
    await _refreshEpg(force: true);
  }

  // --- EPG -------------------------------------------------------------------

  String get _epgSignature {
    final m = mapping;
    return [
      m?.id,
      m?.revision,
      m?.origin,
      channels.length,
      ..._epgSources(),
    ].join('|');
  }

  List<String> _epgSources() => [
    ...?mapping?.epgSources.map((s) => s.url),
    ...settings.extraEpgSources,
    if (settings.useProviderEpg) ?_providerEpg,
  ];

  String? get _providerEpg {
    final c = credentials;
    if (c != null && c.isM3u) return c.epgUrl ?? _m3uEpg;
    return _client?.xmltvUri?.toString();
  }

  /// Aggiornamento chiesto dall'utente (o dopo aver cambiato le fonti).
  Future<void> refreshEpg() => _refreshEpg(force: true);

  /// Al ritorno in primo piano (anche dopo lo standby): se la guida manca,
  /// è vecchia o l'ultimo tentativo è fallito, la si riscarica subito
  /// invece di aspettare il prossimo tentativo programmato.
  void ensureEpgFresh() {
    if (epgLoading || channels.isEmpty || phase != AppPhase.ready) return;
    final at = epg.fetchedAt;
    final stale =
        epg.isEmpty ||
        at == null ||
        _epgSig != _epgSignature ||
        DateTime.now().difference(at) >= perf.epgRefreshEvery;
    if (stale || _epgFailures > 0) unawaited(_refreshEpg());
  }

  void _resetEpg() {
    _epgTimer?.cancel();
    _epgTimer = null;
    _epgFailures = 0;
    _epgPending = false;
    _epgSig = null;
    _shortEpgTried.clear();
    epg = EpgSchedule.empty();
  }

  /// Mostra la guida salvata, se corrisponde ai canali e alle fonti attuali.
  Future<void> _showEpgCache() async {
    if (channels.isEmpty) return;
    final sig = _epgSignature;
    if (_epgSig == sig && !epg.isEmpty) return;
    final cached = await _epgRepo.loadCache(sig);
    if (cached == null || cached.isEmpty || sig != _epgSignature) return;
    // Nel frattempo può essere arrivata una guida più recente.
    final current = epg.fetchedAt;
    if (_epgSig == sig &&
        current != null &&
        !current.isBefore(cached.fetchedAt!)) {
      return;
    }
    epg = cached;
    _epgSig = sig;
    if (!epgLoading) epgStatus = 'Guida aggiornata';
    _notify();
  }

  /// Quando partirà il prossimo tentativo dopo un errore (null se la guida
  /// è a posto o non è previsto).
  DateTime? get epgRetryAt => _epgFailures > 0 ? _epgTimerAt : null;
  DateTime? _epgTimerAt;

  void _scheduleEpg(Duration after) {
    _epgTimer?.cancel();
    if (_disposed) return;
    _epgTimerAt = DateTime.now().add(after);
    _epgTimer = Timer(after, () {
      _epgTimer = null;
      unawaited(_refreshEpg(force: true));
    });
  }

  Future<void> _refreshEpg({bool force = false}) async {
    if (_disposed || channels.isEmpty) return;
    if (epgLoading) {
      // Prima veniva ignorato: es. cambio fonti durante un download.
      if (force) _epgPending = true;
      return;
    }
    _epgTimer?.cancel();
    _epgTimer = null;
    var sig = _epgSignature;
    if (!force) {
      await _showEpgCache();
      sig = _epgSignature;
      final at = epg.fetchedAt;
      if (_epgSig == sig && !epg.isEmpty && at != null) {
        final age = DateTime.now().difference(at);
        if (age < perf.epgRefreshEvery) {
          _epgFailures = 0;
          _scheduleEpg(perf.epgRefreshEvery - age);
          return;
        }
      }
      if (epgLoading) return;
    }
    final sources = _epgSources();
    if (sources.isEmpty) {
      epgStatus = epg.isEmpty ? 'Nessuna fonte per la guida' : epgStatus;
      _notify();
      return;
    }
    epgLoading = true;
    epgStatus = 'Aggiornamento guida…';
    _notify();
    var ok = false;
    var partial = false;
    try {
      final (schedule, reports) = await _epgRepo.fetch(
        sources: sources,
        channels: channels,
        perf: perf,
        signature: sig,
        onProgress: (m) {
          epgStatus = m;
          _notify();
        },
      );
      if (_disposed) return;
      epgReports = reports;
      if (!schedule.isEmpty) {
        // I dati "short EPG" già scaricati restano validi per i canali scoperti.
        final merged = Map<String, List<EpgProgramme>>.of(schedule.raw);
        for (final e in epg.raw.entries) {
          merged.putIfAbsent(e.key, () => e.value);
        }
        epg = EpgSchedule(merged, fetchedAt: schedule.fetchedAt);
        _epgSig = sig;
        epgStatus = 'Guida aggiornata';
        ok = true;
        partial = reports.any((r) => !r.ok);
      }
    } catch (e) {
      debugPrint('Guida TV: $e');
    } finally {
      epgLoading = false;
    }
    if (_disposed) return;
    if (ok) {
      _epgFailures = 0;
      // Una fonte non ha risposto: la si riprova prima del solito.
      _scheduleEpg(
        partial && perf.epgRefreshEvery > const Duration(minutes: 30)
            ? const Duration(minutes: 30)
            : perf.epgRefreshEvery,
      );
    } else {
      final wait =
          epgRetryDelays[_epgFailures.clamp(0, epgRetryDelays.length - 1)];
      _epgFailures++;
      // Se resta la guida precedente la si continua a mostrare.
      epgStatus = epg.isEmpty
          ? 'Guida non disponibile'
          : 'Guida non aggiornata';
      _scheduleEpg(wait);
    }
    _notify();
    if (_epgPending) {
      _epgPending = false;
      unawaited(_refreshEpg(force: true));
    }
  }

  /// Fallback per un singolo canale tramite `get_short_epg` del provider.
  Future<void> ensureEpg(Channel c) async {
    if (epg.has(c.id) || epgLoading || !_shortEpgTried.add(c.id)) return;
    final client = _client;
    if (client == null || c.sources.isEmpty) return;
    try {
      final list = await client.shortEpg(c.sources.first.streamId);
      if (list.isEmpty) return;
      epg = epg.withChannel(c.id, list);
      _notify();
    } catch (_) {}
  }

  // --- Cache lista provider -------------------------------------------------

  Future<File> _streamCacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}streams_cache.json');
  }

  Future<void> _writeStreamCache(
    List<XtreamLiveStream> streams,
    Map<String, String> cats,
  ) async {
    try {
      final f = await _streamCacheFile();
      await f.parent.create(recursive: true);
      final path = f.path;
      final rows = [
        for (final s in streams)
          [
            s.streamId,
            s.name,
            s.icon,
            s.epgChannelId,
            s.categoryId,
            s.number,
            s.url,
          ],
      ];
      final epg = _m3uEpg;
      await HeavyWork.run(
        () => Isolate.run(
          () => File(path)
              .writeAsStringSync(jsonEncode({'c': cats, 's': rows, 'g': epg})),
        ),
      );
    } catch (_) {}
  }

  Future<(List<XtreamLiveStream>, Map<String, String>)?>
  _readStreamCache() async {
    try {
      final f = await _streamCacheFile();
      if (!await f.exists()) return null;
      final path = f.path;
      final (streams, cats, epg) = await HeavyWork.run(
        () => Isolate.run(() {
          final j = jsonDecode(File(path).readAsStringSync()) as Map;
          final cats = (j['c'] as Map).cast<String, String>();
          final streams = [
            for (final r in j['s'] as List)
              XtreamLiveStream(
                streamId: r[0] as int,
                name: r[1] as String,
                icon: r[2] as String?,
                epgChannelId: r[3] as String?,
                categoryId: r[4] as String?,
                number: r[5] as int?,
                url: r.length > 6 ? r[6] as String? : null,
              ),
          ];
          return (streams, cats, j['g'] as String?);
        }),
      );
      _m3uEpg ??= epg;
      return (streams, cats);
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearStreamCache() async {
    try {
      final f = await _streamCacheFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _epgTimer?.cancel();
    _client?.close();
    super.dispose();
  }
}
