import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/channel.dart';
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

  /// Canale mostrato nel banner (durante lo zapping rapido può precedere quello in visione).
  Channel? get displayed {
    final i = _pending ?? _current;
    return i >= 0 && i < channels.length ? channels[i] : null;
  }

  int get currentIndex => _current;

  /// Indice della fonte in uso nel canale corrente.
  int get sourceIndex {
    final c = current;
    if (c == null || c.sources.isEmpty || _order.isEmpty) return 0;
    return _order[_try.clamp(0, _order.length - 1)].clamp(
      0,
      c.sources.length - 1,
    );
  }

  ChannelSource? get currentSource {
    final c = current;
    return c == null || c.sources.isEmpty ? null : c.sources[sourceIndex];
  }

  /// Passa a un'altra fonte del canale in visione e la ricorda per la volta
  /// successiva (anche dopo il riavvio).
  void selectSource(int index) {
    final c = current;
    if (c == null || index < 0 || index >= c.sources.length) return;
    unawaited(
      app.settings.setSourceChoice(
        c.id,
        index == 0 ? null : c.sources[index].label,
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
    final label = app.settings.sourceChoice(c.id);
    if (label == null) return 0;
    final i = c.sources.indexWhere((s) => s.label == label);
    return i < 0 ? 0 : i;
  }

  void _resetSources(Channel c, {int? start}) {
    final first = start ?? _preferredSource(c);
    _order = [
      first,
      for (var i = 0; i < c.sources.length; i++)
        if (i != first) i,
    ];
    _try = 0;
  }

  bool bannerVisible = false;
  String digits = '';
  bool muted = false;

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
    _notify();
  }

  /// Mantiene il banner visibile finché l'utente interagisce (es. hover).
  void holdBanner() => _showBanner(duration: const Duration(seconds: 8));

  void toggleMute() {
    muted = !muted;
    unawaited(engine.setMuted(muted));
    _notify();
  }

  void retry() {
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
    if (idx == _current && engine.state.value.status != PlaybackStatus.failed) {
      if (showBanner) _showBanner();
      return;
    }
    if (_current >= 0 && _current != idx) _previous = _current;
    _current = idx;
    final c = channels[idx];
    _currentId = c.id;
    _resetSources(c);
    _retries = 0;
    unawaited(app.settings.setLastChannelId(c.id));
    unawaited(app.ensureEpg(c));
    if (showBanner) _showBanner();
    _play();
  }

  void _play() {
    final c = current;
    _retryTimer?.cancel();
    if (c == null || c.sources.isEmpty) {
      signalMessage = 'Canale non disponibile';
      _notify();
      return;
    }
    // La lista può essere stata ricaricata con fonti diverse.
    if (_order.length != c.sources.length) _resetSources(c);
    if (_retries == 0 && _try == 0) signalMessage = null;
    _attempt++;
    final src = c.sources[sourceIndex];
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
    if (_failedAttempt == _attempt) return;
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
