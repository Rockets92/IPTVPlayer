import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/epg/epg_models.dart';
import '../data/settings_store.dart';
import '../domain/channel.dart';
import '../player/system_volume.dart';
import '../player/playback_engine.dart';
import 'app_controller.dart';

/// Logica di zapping "da decoder": numeri, su/giù, canale precedente,
/// banner informativo, failover automatico tra stream.
class TunerController extends ChangeNotifier {
  TunerController({required this.app, required this.engine}) {
    engine.state.addListener(_onPlayback);
    app.addListener(_onAppChanged);
  }

  final AppController app;
  final PlaybackEngine engine;

  static const zapDebounce = Duration(milliseconds: 360);
  static const digitTimeout = Duration(milliseconds: 1700);
  static const bannerDuration = Duration(seconds: 5);
  static const browseDuration = Duration(seconds: 8);
  static const connectTimeout = Duration(seconds: 16);
  static const stallTimeout = Duration(seconds: 20);

  List<Channel> get channels => app.channels;

  int _current = -1;
  int? _previous;
  int? _pending;

  /// Ordine in cui provare le fonti del canale corrente: prima quella scelta
  /// dall'utente (o la principale), poi le altre per il failover.
  List<int> _order = const [];
  int _try = 0;
  int _retries = 0;
  String? _currentId;
  int _attempt = 0;
  int _failedAttempt = -1;

  /// Canale in visione.
  Channel? get current =>
      _current >= 0 && _current < channels.length ? channels[_current] : null;

  /// Canale mostrato nel banner: quello che si sta sfogliando con ←→,
  /// oppure durante lo zapping rapido quello che sta per essere sintonizzato.
  Channel? get displayed {
    final i = _browse ?? _pending ?? _current;
    return i >= 0 && i < channels.length ? channels[i] : null;
  }

  int get currentIndex => _current;

  /// Versione +1 del canale in visione (stream della lista non in elenco).
  bool timeshift = false;

  List<ChannelSource> _src(Channel c) =>
      timeshift && c.plusOne.isNotEmpty ? c.plusOne : c.sources;

  String _choiceKey(Channel c) => timeshift ? '${c.id}+1' : c.id;

  /// Fonti del canale in visione (quelle del +1 se attivo).
  List<ChannelSource> get activeSources {
    final c = current;
    return c == null ? const [] : _src(c);
  }

  /// Il canale in visione ha una versione +1 (o è il +1 di un altro).
  bool get canTogglePlusOne {
    final c = current;
    return c != null && (c.hasPlusOne || c.baseChannelId != null);
  }

  /// Tasto +1: passa alla versione di un'ora dopo e ritorno.
  void togglePlusOne() {
    final c = current;
    if (c == null) return;
    // +1 presente nell'elenco: si va su quel canale (e viceversa).
    final target = c.plusOneChannelId ?? c.baseChannelId;
    if (target != null && !timeshift) {
      final idx = channels.indexWhere((x) => x.id == target);
      if (idx >= 0) _tune(idx, showBanner: true);
      return;
    }
    if (c.plusOne.isEmpty) return;
    timeshift = !timeshift;
    _resetSources(c);
    _retries = 0;
    signalMessage = null;
    _showBanner();
    _play();
  }

  /// Indice della fonte in uso nel canale corrente.
  int get sourceIndex {
    final c = current;
    if (c == null || _src(c).isEmpty || _order.isEmpty) return 0;
    return _order[_try.clamp(0, _order.length - 1)].clamp(
      0,
      _src(c).length - 1,
    );
  }

  ChannelSource? get currentSource {
    final c = current;
    return c == null || _src(c).isEmpty ? null : _src(c)[sourceIndex];
  }

  /// Passa a un'altra fonte del canale in visione e la ricorda per la volta
  /// successiva (anche dopo il riavvio).
  void selectSource(int index) {
    final c = current;
    if (c == null || index < 0 || index >= _src(c).length) return;
    unawaited(
      app.settings.setSourceChoice(
        _choiceKey(c),
        index == 0 ? null : _src(c)[index].label,
      ),
    );
    if (index == sourceIndex &&
        engine.state.value.status == PlaybackStatus.playing) {
      return;
    }
    _resetSources(c, start: index);
    _retries = 0;
    signalMessage = null;
    _play();
  }

  int _preferredSource(Channel c) {
    final label = app.settings.sourceChoice(_choiceKey(c));
    if (label == null) return 0;
    final i = _src(c).indexWhere((s) => s.label == label);
    return i < 0 ? 0 : i;
  }

  void _resetSources(Channel c, {int? start}) {
    final first = start ?? _preferredSource(c);
    _order = [
      first,
      for (var i = 0; i < _src(c).length; i++)
        if (i != first) i,
    ];
    _try = 0;
  }

  bool bannerVisible = false;

  /// Canale in anteprima con ←→ (il video resta su quello corrente).
  int? _browse;
  bool get browsing => _browse != null;

  /// Si sta guardando l'anteprima di un canale diverso da quello in visione.
  bool get browsingOther => _browse != null && _browse != _current;

  /// Banner aperto con OK sul canale corrente: ←→ sfogliano la sua guida.
  bool infoMode = false;

  /// Programma mostrato rispetto a quello in onda (0 = ora, 1 = il successivo).
  int epgOffset = 0;
  String digits = '';
  bool muted = false;

  /// Canale per adulti protetto da PIN in attesa di sblocco.
  bool locked = false;

  /// Cresce ogni volta che serve chiedere il PIN (lo schermo apre il dialogo).
  int pinRequest = 0;
  bool _adultUnlocked = false;

  bool _needsPin(Channel c) =>
      c.adult && app.settings.adultMode == AdultMode.pin && !_adultUnlocked;

  /// PIN giusto: il canale parte e i canali per adulti restano sbloccati
  /// finché non si torna su un canale normale.
  bool unlock(String pin) {
    if (!app.settings.checkAdultPin(pin)) return false;
    _adultUnlocked = true;
    locked = false;
    signalMessage = null;
    _retries = 0;
    _try = 0;
    _play();
    return true;
  }

  /// PIN annullato: si torna al canale di prima (o al primo non protetto).
  void cancelUnlock() {
    if (!locked) return;
    final p = _previous;
    if (p != null && p < channels.length && !_needsPin(channels[p])) {
      _tune(p, showBanner: true);
      return;
    }
    final i = channels.indexWhere((c) => !_needsPin(c));
    if (i >= 0) _tune(i, showBanner: true);
  }

  /// Da chiamare quando cambia l'impostazione dei canali per adulti.
  void relockAdult() {
    _adultUnlocked = false;
    final c = current;
    if (c != null && _needsPin(c) && !locked) {
      _current = -1;
      _tune(channels.indexOf(c), showBanner: true);
    }
  }

  /// Messaggio di stato per l'utente (nessun segnale, tentativo...).
  String? signalMessage;
  bool get hasSignalIssue => signalMessage != null;

  Timer? _bannerTimer;
  Timer? _zapTimer;
  Timer? _digitTimer;
  Timer? _watchdog;
  Timer? _stall;
  Timer? _retryTimer;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Avvio: riprende l'ultimo canale visto, come un decoder.
  void start() {
    if (channels.isEmpty) return;
    final lastId = app.settings.lastChannelId;
    var idx = lastId == null ? -1 : channels.indexWhere((c) => c.id == lastId);
    if (idx < 0) idx = 0;
    _tune(idx, showBanner: true);
  }

  void _onAppChanged() {
    // La lista è stata ricaricata: si mantiene il canale corrente per id.
    final id = _currentId;
    if (id == null) return;
    if (_current < channels.length && channels[_current].id == id) return;
    final idx = channels.indexWhere((c) => c.id == id);
    if (idx >= 0) {
      _current = idx;
      _notify();
    }
  }

  // --- Comandi -----------------------------------------------------------------

  void zap(int delta) {
    if (channels.isEmpty) return;
    final base = _pending ?? (_current < 0 ? 0 : _current);
    final n = channels.length;
    final idx = ((base + delta) % n + n) % n;
    _pending = idx;
    _browse = null;
    infoMode = false;
    epgOffset = 0;
    _showBanner();
    final c = channels[idx];
    unawaited(app.ensureEpg(c));
    _zapTimer?.cancel();
    _zapTimer = Timer(zapDebounce, () {
      final p = _pending;
      if (p != null) _tune(p);
    });
    _notify();
  }

  void tuneTo(Channel c) {
    final idx = channels.indexOf(c);
    if (idx >= 0) _tune(idx, showBanner: true);
  }

  void previousChannel() {
    final p = _previous;
    if (p != null && p < channels.length) _tune(p, showBanner: true);
  }

  void inputDigit(int d) {
    if (digits.length >= 4) digits = '';
    digits += '$d';
    _digitTimer?.cancel();
    if (digits.length == 4) {
      commitDigits();
      return;
    }
    _digitTimer = Timer(digitTimeout, commitDigits);
    _notify();
  }

  void clearDigits() {
    _digitTimer?.cancel();
    digits = '';
    _notify();
  }

  /// Anteprima del canale che verrà sintonizzato con le cifre digitate.
  Channel? get digitsTarget {
    final n = int.tryParse(digits);
    if (n == null) return null;
    final i = indexForNumber(n);
    return i == null ? null : channels[i];
  }

  /// Numero esatto, altrimenti il primo canale successivo (comportamento decoder).
  int? indexForNumber(int n) {
    if (channels.isEmpty) return null;
    final exact = channels.indexWhere((c) => c.number == n);
    if (exact >= 0) return exact;
    final next = channels.indexWhere((c) => c.number > n);
    return next >= 0 ? next : null;
  }

  void commitDigits() {
    _digitTimer?.cancel();
    final n = int.tryParse(digits);
    digits = '';
    if (n != null) {
      final i = indexForNumber(n);
      if (i != null) {
        _tune(i, showBanner: true);
        return;
      }
    }
    _notify();
  }

  /// Anteprima di un altro canale senza cambiare il video (←→).
  /// La prima pressione mostra il canale in visione, le successive scorrono.
  void browse(int delta) {
    if (channels.isEmpty) return;
    final n = channels.length;
    if (_browse == null || !bannerVisible) {
      _browse = _current < 0 ? 0 : _current;
    } else {
      _browse = ((_browse! + delta) % n + n) % n;
    }
    infoMode = false;
    epgOffset = 0;
    unawaited(app.ensureEpg(channels[_browse!]));
    _showBanner(duration: browseDuration);
  }

  /// OK durante l'anteprima: si passa al canale sfogliato.
  void confirmBrowse() {
    final b = _browse;
    if (b == null) return;
    _browse = null;
    if (b == _current) {
      // Era il canale in visione: si chiude l'anteprima e basta.
      hideBanner();
      return;
    }
    _tune(b, showBanner: true);
  }

  /// OK a schermo libero: informazioni sul canale in visione.
  void showInfo() {
    _browse = null;
    _pending = null;
    infoMode = true;
    epgOffset = 0;
    _showBanner(duration: browseDuration);
  }

  /// Programma futuro mostrato nel banner mentre si sfoglia la guida del
  /// canale in diretta (per prenotare un promemoria con OK).
  EpgProgramme? get infoProgramme {
    final c = current;
    if (c == null || !infoMode || epgOffset <= 0 || timeshift) return null;
    final list = app.epg.forChannel(c.id);
    final base = app.epg.indexNear(c.id, DateTime.now());
    final i = base + epgOffset;
    if (base < 0 || i < 0 || i >= list.length) return null;
    final p = list[i];
    return p.startTime.isAfter(DateTime.now()) ? p : null;
  }

  /// ←→ con le informazioni aperte, ↑↓ durante l'anteprima dei canali:
  /// programma precedente o successivo del canale mostrato nel banner.
  void stepEpg(int delta) {
    final c = displayed;
    if (c == null) return;
    final now = DateTime.now();
    final list = app.epg.forChannel(c.id);
    final base = app.epg.indexNear(c.id, now);
    if (base >= 0) {
      epgOffset = (epgOffset + delta).clamp(-base, list.length - 1 - base);
    }
    _showBanner(duration: browseDuration);
  }

  void toggleBanner() {
    if (bannerVisible) {
      hideBanner();
    } else {
      _showBanner();
    }
  }

  void showBanner({Duration? duration}) => _showBanner(duration: duration);

  void hideBanner() {
    _bannerTimer?.cancel();
    if (!bannerVisible) return;
    bannerVisible = false;
    _browse = null;
    infoMode = false;
    epgOffset = 0;
    _notify();
  }

  /// Mantiene il banner visibile finché l'utente interagisce (es. hover).
  void holdBanner() => _showBanner(duration: const Duration(seconds: 8));

  /// Volume 0–100, a passi di 5 come un televisore.
  int volume = 100;

  /// Ultima variazione di volume o muto: l'indicatore resta visibile poco.
  DateTime? volumeChangedAt;

  /// Volume: si regola quello del dispositivo (TV, PC…); solo dove non è
  /// possibile (iOS, web) si usa il volume interno dell'app.
  void changeVolume(int delta) =>
      unawaited(_systemVolume(delta > 0 ? 1 : -1, () => _appVolume(delta)));

  void toggleMute() => unawaited(_systemVolume(0, _appMute));

  Future<void> _systemVolume(int direction, void Function() fallback) async {
    final st = await SystemVolume.adjust(direction);
    if (st == null) return fallback();
    if (st.level != null) volume = st.level!.clamp(0, 100);
    if (st.muted != null) muted = st.muted!;
    // Se il sistema mostra già il suo indicatore non se ne aggiunge un altro.
    if (!st.systemOsd && st.level != null) volumeChangedAt = DateTime.now();
    _notify();
  }

  void _appVolume(int delta) {
    volume = (volume + delta).clamp(0, 100);
    if (muted && delta > 0) {
      muted = false;
      unawaited(engine.setMuted(false));
    }
    unawaited(engine.setVolume(volume.toDouble()));
    volumeChangedAt = DateTime.now();
    _notify();
  }

  void _appMute() {
    volumeChangedAt = DateTime.now();
    muted = !muted;
    unawaited(engine.setMuted(muted));
    _notify();
  }

  void retry() {
    if (locked) {
      pinRequest++;
      _notify();
      return;
    }
    _retries = 0;
    _try = 0;
    _play();
  }

  // --- Interni -----------------------------------------------------------------

  void _showBanner({Duration? duration}) {
    bannerVisible = true;
    _bannerTimer?.cancel();
    _bannerTimer = Timer(duration ?? bannerDuration, hideBanner);
    _notify();
  }

  void _tune(int idx, {bool showBanner = false}) {
    _zapTimer?.cancel();
    _pending = null;
    _browse = null;
    infoMode = false;
    epgOffset = 0;
    if (idx == _current && locked) {
      pinRequest++;
      _showBanner();
      return;
    }
    if (idx == _current && engine.state.value.status != PlaybackStatus.failed) {
      if (showBanner) _showBanner();
      return;
    }
    if (_current >= 0 && _current != idx) _previous = _current;
    _current = idx;
    final c = channels[idx];
    _currentId = c.id;
    timeshift = false;
    _resetSources(c);
    _retries = 0;
    unawaited(app.settings.setLastChannelId(c.id));
    unawaited(app.ensureEpg(c));
    if (!c.adult) _adultUnlocked = false;
    locked = _needsPin(c);
    if (locked) {
      // Canale protetto: niente video finché non si inserisce il PIN.
      _retryTimer?.cancel();
      _watchdog?.cancel();
      _stall?.cancel();
      unawaited(engine.stop());
      signalMessage = 'Canale protetto · inserisci il PIN';
      pinRequest++;
      _showBanner();
      return;
    }
    if (showBanner) _showBanner();
    _play();
  }

  void _play() {
    if (locked) return;
    final c = current;
    _retryTimer?.cancel();
    if (c == null || _src(c).isEmpty) {
      signalMessage = 'Canale non disponibile';
      _notify();
      return;
    }
    // La lista può essere stata ricaricata con fonti diverse.
    if (_order.length != _src(c).length) _resetSources(c);
    if (_retries == 0 && _try == 0) signalMessage = null;
    _attempt++;
    final src = _src(c)[sourceIndex];
    _stall?.cancel();
    _stall = null;
    _watchdog?.cancel();
    _watchdog = Timer(connectTimeout, () {
      _watchdog = null;
      if (engine.state.value.status == PlaybackStatus.connecting) _fail();
    });
    unawaited(engine.open(app.streamUrl(src)).catchError((_) => _fail()));
    _notify();
  }

  void _onPlayback() {
    final s = engine.state.value;
    switch (s.status) {
      case PlaybackStatus.playing:
        _watchdog?.cancel();
        _watchdog = null;
        _retries = 0;
        if (signalMessage != null) {
          signalMessage = null;
          _notify();
        }
        // Buffering prolungato a canale avviato = segnale bloccato.
        if (s.buffering) {
          _stall ??= Timer(stallTimeout, () {
            _stall = null;
            final now = engine.state.value;
            if (now.status == PlaybackStatus.playing && now.buffering) _fail();
          });
        } else {
          _stall?.cancel();
          _stall = null;
        }
      case PlaybackStatus.failed:
        _fail();
      case PlaybackStatus.idle || PlaybackStatus.connecting:
        break;
    }
  }

  void _fail() {
    // Errore e "fine stream" possono arrivare insieme: un solo failover per tentativo.
    if (_failedAttempt == _attempt || locked) return;
    _failedAttempt = _attempt;
    _watchdog?.cancel();
    _watchdog = null;
    _stall?.cancel();
    _stall = null;
    final c = current;
    if (c == null) return;
    // 1) stream alternativo dello stesso canale
    if (_try + 1 < _order.length) {
      _try++;
      signalMessage = 'Ricerca segnale…';
      _notify();
      _play();
      return;
    }
    // 2) nuovi tentativi con attesa crescente
    if (_retries < 3) {
      _retries++;
      _try = 0;
      signalMessage = 'Segnale assente · nuovo tentativo';
      _notify();
      _retryTimer?.cancel();
      _retryTimer = Timer(Duration(seconds: 2 * _retries * _retries), _play);
      return;
    }
    signalMessage = 'Canale non disponibile';
    _showBanner(duration: const Duration(seconds: 8));
  }

  @override
  void dispose() {
    _disposed = true;
    engine.state.removeListener(_onPlayback);
    app.removeListener(_onAppChanged);
    for (final t in [
      _bannerTimer,
      _zapTimer,
      _digitTimer,
      _watchdog,
      _stall,
      _retryTimer,
    ]) {
      t?.cancel();
    }
    super.dispose();
  }
}
