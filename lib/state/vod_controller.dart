import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/settings_store.dart';
import '../domain/channel_matcher.dart';
import '../data/vod/vod_models.dart';
import '../data/xtream/xtream_client.dart';
import '../data/xtream/xtream_models.dart';
import 'app_controller.dart';

/// Film o serie.
enum VodKind { movies, series }

/// Ordinamento della griglia.
enum VodSort {
  recent('Recenti'),
  name('A-Z'),
  rating('Voto'),
  year('Anno');

  const VodSort(this.label);
  final String label;
}

/// Categoria speciale in cima all'elenco.
abstract final class VodCategories {
  static const all = '*all';
  static const continueWatching = '*continue';
}

/// Dove si era arrivati con un film o un episodio.
@immutable
class WatchEntry {
  const WatchEntry({
    required this.key,
    required this.position,
    required this.duration,
    required this.at,
    required this.title,
    this.poster,
    this.seriesId,
    this.episodeId,
    this.extension = 'mp4',
    this.label,
    this.adult = false,
  });

  /// Titolo per adulti: segue l'impostazione dei contenuti per adulti.
  final bool adult;

  /// `m:<id>` per i film, `s:<seriesId>` per le serie (ultimo episodio).
  final String key;
  final Duration position;
  final Duration duration;
  final DateTime at;
  final String title;
  final String? poster;
  final int? seriesId;
  final int? episodeId;
  final String extension;

  /// Es. "S01E03 · Titolo episodio".
  final String? label;

  double get fraction => duration.inSeconds <= 0
      ? 0
      : (position.inSeconds / duration.inSeconds).clamp(0, 1);

  /// Visto quasi tutto: non si propone di riprendere.
  bool get finished =>
      duration.inSeconds > 0 && duration.inSeconds - position.inSeconds < 150;

  Map<String, Object?> toJson() => {
    'p': position.inSeconds,
    'd': duration.inSeconds,
    't': at.millisecondsSinceEpoch ~/ 1000,
    'n': title,
    'i': ?poster,
    's': ?seriesId,
    'e': ?episodeId,
    'x': extension,
    'l': ?label,
    if (adult) 'a': 1,
  };

  static WatchEntry? fromJson(String key, Object? j) {
    if (j is! Map) return null;
    int i(String k) => (j[k] as num?)?.toInt() ?? 0;
    return WatchEntry(
      key: key,
      position: Duration(seconds: i('p')),
      duration: Duration(seconds: i('d')),
      at: DateTime.fromMillisecondsSinceEpoch(i('t') * 1000),
      title: '${j['n'] ?? ''}',
      poster: j['i'] as String?,
      seriesId: (j['s'] as num?)?.toInt(),
      episodeId: (j['e'] as num?)?.toInt(),
      extension: (j['x'] as String?) ?? 'mp4',
      label: j['l'] as String?,
      adult: j['a'] == 1,
    );
  }
}

/// Catalogo di film e serie del provider Xtream, con ricerca, filtri e
/// "continua a guardare".
class VodController extends ChangeNotifier {
  VodController({required AppController this.app, required this.prefs})
    : _fixed = null {
    _loadProgress();
    app!.addListener(_onApp);
  }

  /// Per le prove: catalogo da un client fisso.
  @visibleForTesting
  VodController.withClient(XtreamClient client, {required this.prefs})
    : app = null,
      _fixed = client {
    _loadProgress();
  }

  final AppController? app;
  final XtreamClient? _fixed;
  final SharedPreferences prefs;

  static const _kProgress = 'vod.progress.v1';
  static const _maxProgress = 300;

  XtreamClient? get client {
    if (_fixed != null) return _fixed;
    final s = app?.source;
    return s is XtreamClient ? s : null;
  }

  /// Film e serie esistono solo con le liste Xtream.
  bool get available => client != null;

  // --- Contenuti per adulti -------------------------------------------------

  AdultMode? _testMode;

  /// Stessa impostazione dei canali per adulti.
  AdultMode get adultMode =>
      _testMode ?? app?.settings.adultMode ?? AdultMode.off;

  @visibleForTesting
  set adultModeForTest(AdultMode m) {
    _testMode = m;
    _adultUnlocked = false;
    notifyListeners();
  }

  bool _adultUnlocked = false;

  /// Categorie per adulti elencate (con "Sì" o "Sì con PIN").
  bool get adultListed => adultMode != AdultMode.off;

  /// Titoli per adulti visibili adesso (attivi, o PIN già inserito).
  bool get adultOpen =>
      adultMode == AdultMode.on ||
      (adultMode == AdultMode.pin && _adultUnlocked);

  /// PIN giusto: film e serie per adulti restano aperti fino al cambio
  /// d'impostazione o al riavvio.
  bool unlockAdult(String pin) {
    final ok = app?.settings.checkAdultPin(pin) ?? false;
    if (ok) {
      _adultUnlocked = true;
      notifyListeners();
    }
    return ok;
  }

  void relockAdult() {
    _adultUnlocked = false;
    notifyListeners();
  }

  bool isAdultCategory(VodKind kind, String? id) =>
      id != null && catalog(kind).adultCategories.contains(id);

  bool isAdult(VodKind kind, VodItem i) =>
      i.adult || isAdultCategory(kind, i.categoryId);

  static final _catPrefix = RegExp(
    r'^\s*[\[|(]?\s*([A-Za-z]{2,3})\s*[\]|):\-]',
  );

  /// Categorie per adulti: quelle col nome esplicito ("XXX", "Adult"…) e,
  /// dopo la prima, quelle che non somigliano alle categorie normali (i
  /// pannelli mettono in fondo un elenco di nomi di attori).
  static Set<String> detectAdult(
    List<XtreamCategory> cats,
    List<VodItem> items,
  ) {
    final out = <String>{};
    var first = -1;
    for (var i = 0; i < cats.length; i++) {
      if (ChannelMatcher.isAdultCategory(cats[i].name)) {
        out.add(cats[i].id);
        if (first < 0) first = i;
      }
    }
    if (first >= 0) {
      String? prefix(String n) =>
          _catPrefix.firstMatch(n)?.group(1)?.toUpperCase();
      final legit = {for (final c in cats.take(first)) ?prefix(c.name)};
      for (final c in cats.skip(first + 1)) {
        final p = prefix(c.name);
        if (p == null || !legit.contains(p)) out.add(c.id);
      }
    }
    // Categorie in cui il provider segna come per adulti la maggior parte
    // dei titoli.
    final flagged = <String, int>{};
    final total = <String, int>{};
    for (final i in items) {
      final id = i.categoryId;
      if (id == null) continue;
      total[id] = (total[id] ?? 0) + 1;
      if (i.adult) flagged[id] = (flagged[id] ?? 0) + 1;
    }
    for (final e in flagged.entries) {
      if (e.value * 2 > (total[e.key] ?? 0)) out.add(e.key);
    }
    return out;
  }

  Object? _source;
  AdultMode? _lastMode;
  void _onApp() {
    final mode = adultMode;
    if (mode != _lastMode) {
      _lastMode = mode;
      _adultUnlocked = false;
      notifyListeners();
    }
    if (!identical(app?.source, _source)) {
      _source = app?.source;
      _catalogs.clear();
      notifyListeners();
    }
  }

  final _catalogs = <VodKind, VodCatalog>{};

  VodCatalog catalog(VodKind kind) => _catalogs[kind] ??= VodCatalog();

  /// Scarica categorie ed elenco (una volta per sessione, o se richiesto).
  Future<void> load(VodKind kind, {bool force = false}) async {
    final c = catalog(kind);
    final cl = client;
    if (cl == null) return;
    if (c.loading || (c.loaded && !force)) return;
    c
      ..loading = true
      ..error = null;
    notifyListeners();
    try {
      final (cats, items) = kind == VodKind.movies
          ? (await cl.vodCategories(), await cl.vodStreams())
          : (await cl.seriesCategories(), await cl.series());
      c
        ..categories = cats
        ..items = items
        ..adultCategories = detectAdult(cats, items)
        ..loaded = true;
    } catch (e) {
      c.error = e is XtreamException
          ? e.message
          : 'Impossibile caricare il catalogo. Riprova.';
    } finally {
      c.loading = false;
      notifyListeners();
    }
  }

  /// Elementi da mostrare per categoria, ricerca e ordinamento.
  List<VodItem> query(
    VodKind kind, {
    required String category,
    String search = '',
    VodSort sort = VodSort.recent,
  }) {
    final c = catalog(kind);
    Iterable<VodItem> items = c.items;
    final open = adultOpen;
    if (category != VodCategories.all &&
        category != VodCategories.continueWatching &&
        !open &&
        c.adultCategories.contains(category)) {
      return const [];
    }
    if (category == VodCategories.continueWatching) {
      final ids = {
        for (final w in continueWatching(kind))
          kind == VodKind.movies ? int.parse(w.key.substring(2)) : w.seriesId,
      };
      final byId = {for (final i in c.items) i.id: i};
      return [
        for (final id in ids)
          if (byId[id] != null) byId[id]!,
      ];
    }
    if (category != VodCategories.all) {
      items = items.where((i) => i.categoryId == category);
    } else if (!(open && search.trim().isNotEmpty)) {
      // "Tutti" e le copertine restano puliti; con i contenuti aperti i
      // titoli per adulti si trovano cercandoli o nelle loro categorie.
      items = items.where((i) => !isAdult(kind, i));
    }
    final q = _fold(search.trim());
    if (q.isNotEmpty) {
      final words = q.split(' ');
      items = items.where((i) {
        final t = _fold(i.title);
        return words.every(t.contains);
      });
    }
    final out = items.toList();
    switch (sort) {
      case VodSort.recent:
        out.sort((a, b) => b.added.compareTo(a.added));
      case VodSort.name:
        out.sort((a, b) => _fold(a.title).compareTo(_fold(b.title)));
      case VodSort.rating:
        out.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      case VodSort.year:
        out.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    }
    return out;
  }

  /// Numero di titoli per categoria (per l'elenco a sinistra).
  Map<String, int> counts(VodKind kind) {
    final c = catalog(kind);
    if (c._counts != null && c._countsOf == c.items) return c._counts!;
    final m = <String, int>{};
    for (final i in c.items) {
      final id = i.categoryId;
      if (id != null) m[id] = (m[id] ?? 0) + 1;
    }
    c
      .._counts = m
      .._countsOf = c.items;
    return m;
  }

  static String _fold(String s) {
    const from = 'àáâäèéêëìíîïòóôöùúûüç';
    const to = 'aaaaeeeeiiiioooouuuuc';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  // --- Schede ---------------------------------------------------------------

  final _movieInfo = <int, Future<MovieInfo>>{};
  final _seriesInfo = <int, Future<SeriesInfo>>{};

  Future<MovieInfo> movieInfo(int id) => _movieInfo[id] ??=
      (client?.movieInfo(id) ?? Future.value(const MovieInfo())).catchError((
        Object _,
      ) {
        _movieInfo.remove(id);
        return const MovieInfo();
      });

  Future<SeriesInfo> seriesInfo(int id) => _seriesInfo[id] ??=
      (client?.seriesInfo(id) ?? Future.value(const SeriesInfo(seasons: {})))
          .catchError((Object _) {
            _seriesInfo.remove(id);
            return const SeriesInfo(seasons: {});
          });

  String movieUrl(VodItem m) => client!.movieUrl(m.id, m.extension);

  String episodeUrl(Episode e) => client!.episodeUrl(e.id, e.extension);

  // --- Continua a guardare ---------------------------------------------------

  final _progress = <String, WatchEntry>{};

  /// Posizione di un film o di un episodio (`e:<id>`).
  final _episodePos = <int, Duration>{};

  void _loadProgress() {
    final raw = prefs.getString(_kProgress);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return;
      for (final e in j.entries) {
        final k = '${e.key}';
        if (k.startsWith('e:')) {
          final id = int.tryParse(k.substring(2));
          final p = (e.value as num?)?.toInt();
          if (id != null && p != null) _episodePos[id] = Duration(seconds: p);
          continue;
        }
        final w = WatchEntry.fromJson(k, e.value);
        if (w != null) _progress[k] = w;
      }
    } catch (_) {}
  }

  Timer? _saveTimer;

  void _save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      final sorted = _progress.values.toList()
        ..sort((a, b) => b.at.compareTo(a.at));
      final keep = sorted.take(_maxProgress);
      final eps = _episodePos.entries.toList();
      unawaited(
        prefs.setString(
          _kProgress,
          jsonEncode({
            for (final w in keep) w.key: w.toJson(),
            for (final e in eps.skip(
              eps.length > _maxProgress * 4 ? eps.length - _maxProgress * 4 : 0,
            ))
              'e:${e.key}': e.value.inSeconds,
          }),
        ),
      );
    });
  }

  WatchEntry? progressOf(String key) => _progress[key];

  Duration? episodePosition(int episodeId) => _episodePos[episodeId];

  /// Titoli iniziati e non finiti, dal più recente.
  List<WatchEntry> continueWatching(VodKind kind) {
    final prefix = kind == VodKind.movies ? 'm:' : 's:';
    return _progress.values
        .where(
          (w) =>
              w.key.startsWith(prefix) &&
              !w.finished &&
              (adultOpen || !_adultEntry(kind, w)),
        )
        .toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  bool _adultEntry(VodKind kind, WatchEntry w) {
    if (w.adult) return true;
    final id = kind == VodKind.movies
        ? int.tryParse(w.key.substring(2))
        : w.seriesId;
    final i = catalog(kind).byId[id];
    return i != null && isAdult(kind, i);
  }

  /// Annota la posizione (chiamato durante la visione e all'uscita).
  void remember(WatchEntry w) {
    if (w.position.inSeconds < 20 && !_progress.containsKey(w.key)) return;
    _progress[w.key] = w;
    final ep = w.episodeId;
    if (ep != null) _episodePos[ep] = w.position;
    _save();
    notifyListeners();
  }

  void forget(String key) {
    if (_progress.remove(key) != null) {
      _save();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    app?.removeListener(_onApp);
    _saveTimer?.cancel();
    super.dispose();
  }
}

class VodCatalog {
  List<XtreamCategory> categories = const [];
  List<VodItem> items = const [];
  bool loading = false;
  bool loaded = false;
  String? error;
  Set<String> adultCategories = const {};
  Map<int, VodItem>? _byId;
  List<VodItem>? _byIdOf;

  Map<int, VodItem> get byId {
    if (_byId == null || !identical(_byIdOf, items)) {
      _byId = {for (final i in items) i.id: i};
      _byIdOf = items;
    }
    return _byId!;
  }

  Map<String, int>? _counts;
  List<VodItem>? _countsOf;
}
