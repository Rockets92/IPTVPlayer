import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/performance.dart';
import '../data/epg/epg_models.dart';
import '../data/epg/epg_repository.dart';
import '../data/mapping/channel_mapping.dart';
import '../data/mapping/mapping_repository.dart';
import '../data/settings_store.dart';
import '../data/xtream/xtream_client.dart';
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
    XtreamClient Function(XtreamCredentials)? clientFactory,
  }) : _mappingRepo = mappingRepository ?? MappingRepository(),
       _epgRepo = epgRepository ?? EpgRepository(),
       _clientFactory = clientFactory ?? XtreamClient.new;

  final SettingsStore settings;
  final PerformanceProfile perf;
  final MappingRepository _mappingRepo;
  final EpgRepository _epgRepo;
  final XtreamClient Function(XtreamCredentials) _clientFactory;

  AppPhase phase = AppPhase.booting;
  String loadingMessage = '';
  String? failure;

  XtreamCredentials? credentials;
  XtreamAccountInfo? account;
  XtreamClient? _client;

  ChannelMapping? mapping;
  List<Channel> channels = const [];

  EpgSchedule epg = EpgSchedule.empty();
  bool epgLoading = false;
  String? epgStatus;
  List<EpgSourceReport> epgReports = const [];
  final _shortEpgTried = <String>{};

  bool _disposed = false;

  List<String> get groups {
    final seen = <String>{};
    return [
      for (final c in channels)
        if (seen.add(c.group)) c.group,
    ];
  }

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
    channels = const [];
    epg = EpgSchedule.empty();
    phase = AppPhase.setup;
    _notify();
  }

  String streamUrl(ChannelSource s) =>
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
          _rebuild(cached.$1, cached.$2);
          if (channels.isNotEmpty) {
            phase = AppPhase.ready;
            _notify();
            unawaited(_refreshEpg());
            unawaited(_refreshStreamsQuietly());
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
      _rebuild(streams, catMap);
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

  void _rebuild(List<XtreamLiveStream> streams, Map<String, String> cats) {
    channels = ChannelMatcher(preferLighterStreams: perf.preferLighterStreams)
        .build(
          mapping: mapping!,
          streams: streams,
          categoryNames: cats,
          showUnmapped: settings.showUnmapped,
        );
  }

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
      _rebuild(streams, catMap);
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
      if (cached != null) _rebuild(cached.$1, cached.$2);
    } catch (_) {
      return;
    }
    _shortEpgTried.clear();
    epg = EpgSchedule.empty();
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
    if (settings.useProviderEpg && _client != null)
      _client!.xmltvUri.toString(),
  ];

  Future<void> refreshEpg() => _refreshEpg(force: true);

  Future<void> _refreshEpg({bool force = false}) async {
    if (epgLoading || channels.isEmpty) return;
    final sig = _epgSignature;
    if (!force) {
      final cached = await _epgRepo.loadCache(sig);
      if (cached != null && !cached.isEmpty) {
        epg = cached;
        epgStatus = 'Guida aggiornata';
        _notify();
        final age = DateTime.now().difference(cached.fetchedAt!);
        if (age < EpgRepository.cacheTtl) return;
      }
    }
    epgLoading = true;
    epgStatus = 'Aggiornamento guida…';
    _notify();
    try {
      final (schedule, reports) = await _epgRepo.fetch(
        sources: _epgSources(),
        channels: channels,
        perf: perf,
        signature: sig,
        onProgress: (m) {
          epgStatus = m;
          _notify();
        },
      );
      epgReports = reports;
      if (!schedule.isEmpty) {
        // I dati "short EPG" già scaricati restano validi per i canali scoperti.
        final merged = Map<String, List<EpgProgramme>>.of(schedule.raw);
        for (final e in epg.raw.entries) {
          merged.putIfAbsent(e.key, () => e.value);
        }
        epg = EpgSchedule(merged, fetchedAt: schedule.fetchedAt);
        epgStatus = 'Guida aggiornata';
      } else {
        epgStatus = 'Guida non disponibile';
      }
    } catch (e) {
      epgStatus = 'Guida non disponibile';
    } finally {
      epgLoading = false;
      _notify();
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
          [s.streamId, s.name, s.icon, s.epgChannelId, s.categoryId, s.number],
      ];
      await Isolate.run(
        () => File(path).writeAsStringSync(jsonEncode({'c': cats, 's': rows})),
      );
    } catch (_) {}
  }

  Future<(List<XtreamLiveStream>, Map<String, String>)?>
  _readStreamCache() async {
    try {
      final f = await _streamCacheFile();
      if (!await f.exists()) return null;
      final path = f.path;
      return await Isolate.run(() {
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
            ),
        ];
        return (streams, cats);
      });
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
    _client?.close();
    super.dispose();
  }
}
