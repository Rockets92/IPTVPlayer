import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../data/epg/epg_models.dart';
import '../../player/playback_engine.dart';
import '../../player/system_volume.dart';
import '../../state/app_controller.dart';
import '../../state/reminder_controller.dart';
import '../../state/tuner_controller.dart';
import '../../state/vod_controller.dart';
import '../home/home_hub.dart';
import '../../data/vod/vod_models.dart';
import '../vod/vod_browser.dart';
import '../vod/vod_detail.dart';
import '../keys.dart';
import '../settings/settings_panel.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/pin_dialog.dart';
import 'channel_keypad.dart';
import 'channel_list_overlay.dart';
import 'guide_overlay.dart';
import 'number_entry.dart';
import '../games/games_hub.dart';
import '../widgets/confirm_dialog.dart';
import 'reminder_popup.dart';
import 'signal_overlay.dart';
import '../../remote/remote_hooks.dart';
import 'source_picker.dart';
import 'volume_indicator.dart';
import 'zap_banner.dart';

enum _Panel { none, list, guide, settings, sources, games, vod, home, keypad }

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Schermata principale: video a tutto schermo e livelli in vetro.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _rootFocus = FocusNode(debugLabel: 'player');
  _Panel _panel = _Panel.none;
  String? _toast;
  Timer? _toastTimer;
  DateTime? _backPressedAt;
  bool _cursorVisible = true;
  Timer? _cursorTimer;
  late final TunerController _tuner = context.read<TunerController>();
  late final AppController _app = context.read<AppController>();
  late final PlaybackEngine _engine = context.read<PlaybackEngine>();
  String? _lastEpgStatus;

  @override
  void initState() {
    super.initState();
    RemoteHooks.resume = _resumeVod;
    WakelockPlus.enable().catchError((_) {});
    if (_isMobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tuner.start();
      // Promemoria già scattato prima che il player fosse pronto.
      _onReminder();
    });
    _app.addListener(_onApp);
    _reminders.addListener(_onReminder);
    _tuner.addListener(_onTuner);
  }

  int _pinSeen = 0;
  bool _pinOpen = false;

  /// Azione del banner scelta col telecomando (null: menu non attivo).
  int? _menu;

  /// Canale per adulti protetto: si chiede il PIN.
  Future<void> _onTuner() async {
    if (_menu != null && !_tuner.bannerVisible && mounted) {
      setState(() => _menu = null);
    }
    if (_tuner.pinRequest == _pinSeen || !_tuner.locked || _pinOpen) return;
    _pinSeen = _tuner.pinRequest;
    final c = _tuner.current;
    if (c == null || !mounted) return;
    _pinOpen = true;
    if (_panel != _Panel.none) setState(() => _panel = _Panel.none);
    final pin = await showPinDialog(
      context,
      title: 'Canale protetto',
      subtitle: '${c.number}  ${c.name}\nInserisci il PIN per guardarlo',
      validate: _tuner.unlock,
    );
    _pinOpen = false;
    if (!mounted) return;
    _rootFocus.requestFocus();
    if (pin == null) _tuner.cancelUnlock();
  }

  late final ReminderController _reminders = context.read<ReminderController>();

  Reminder? _reminderShown;

  /// Un promemoria scatta: si chiude tutto ciò che è aperto (pannelli e
  /// finestre) e l'avviso compare sopra a tutto, con il focus già su
  /// "Vai al canale".
  Future<void> _onReminder() async {
    final r = _reminders.due;
    if (r == null || !mounted || identical(r, _reminderShown)) return;
    _reminderShown = r;
    if (_panel != _Panel.none || _menu != null) {
      _leavePanel(_Panel.none);
      setState(() {
        _panel = _Panel.none;
        _menu = null;
      });
    }
    _tuner.hideBanner();
    final me = ModalRoute.of(context);
    if (me != null) Navigator.of(context).popUntil((route) => route == me);
    final answer = await showReminderDialog(context, r);
    _reminderShown = null;
    if (!mounted) return;
    _rootFocus.requestFocus();
    if (!identical(_reminders.due, r)) {
      // Già risolto altrove; se nel frattempo ne è scattato un altro, si mostra.
      if (_reminders.due != null) _onReminder();
      return;
    }
    switch (answer) {
      case ReminderAnswer.go:
        _acceptReminder();
      case ReminderAnswer.snooze:
        _reminders.snooze();
        _showToast('Ti avviso 1 minuto prima dell\'inizio');
      case ReminderAnswer.dismiss:
        _reminders.resolve();
    }
  }

  void _acceptReminder() {
    final r = _reminders.due;
    if (r == null) return;
    final app = context.read<AppController>();
    final c = app.channels.where((c) => c.id == r.channelId).firstOrNull;
    _reminders.resolve();
    if (c != null) {
      _tuner.tuneTo(c);
    } else {
      _showToast('Canale non più disponibile');
    }
  }

  void _toggleReminder(EpgProgramme p) {
    final c = _tuner.displayed;
    if (c == null) return;
    final on = _reminders.toggle(c, p);
    _tuner.showBanner(duration: TunerController.browseDuration);
    _showToast(
      on
          ? 'Promemoria impostato: ti avviso 5 minuti prima'
          : 'Promemoria annullato',
    );
  }

  @override
  void dispose() {
    if (RemoteHooks.resume == _resumeVod) RemoteHooks.resume = null;
    _app.removeListener(_onApp);
    _reminders.removeListener(_onReminder);
    _tuner.removeListener(_onTuner);
    WakelockPlus.disable().catchError((_) {});
    if (_isMobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const []);
    }
    _toastTimer?.cancel();
    _cursorTimer?.cancel();
    _okHold?.cancel();
    _rootFocus.dispose();
    super.dispose();
  }

  void _onApp() {
    final app = context.read<AppController>();
    // Primo avvio senza cache: la lista arriva dopo, si parte appena c'è.
    if (_tuner.current == null && app.channels.isNotEmpty) _tuner.start();
    final status = app.epgStatus;
    if (status != _lastEpgStatus &&
        status == 'Guida aggiornata' &&
        _lastEpgStatus != null) {
      _showToast('Guida TV aggiornata');
    }
    _lastEpgStatus = status;
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  VodKind _vodKind = VodKind.movies;

  /// Film o serie: la TV si ferma finché si resta nel catalogo.
  void _openVod(VodKind k) {
    if (!context.read<VodController>().available) {
      _showToast('Film e serie sono disponibili solo con le liste Xtream');
      return;
    }
    _vodKind = k;
    _open(_Panel.vod);
  }

  /// Si esce dal pannello aperto: audio e diretta tornano come prima.
  void _leavePanel(_Panel next) {
    if (_panel == next) return;
    if (_panel == _Panel.games) {
      unawaited(
        context.read<PlaybackEngine>().setMuted(
          !SystemVolume.supported && _tuner.muted,
        ),
      );
    }
    if (_panel == _Panel.vod) _tuner.resume();
  }

  /// Da "Continua a guardare": catalogo sotto, scheda del titolo sopra.
  void _resumeVod(VodKind kind, VodItem item) {
    _openVod(kind);
    if (_panel != _Panel.vod) return;
    // Dopo che il catalogo ha preso il focus.
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (mounted && _panel == _Panel.vod) {
        showVodDetail(context, kind: kind, item: item);
      }
    });
  }

  /// Scelta dalla schermata TV / Film / Serie / Giochi.
  void _onHome(HomeChoice c) => switch (c) {
    HomeChoice.live => _closeAll(),
    HomeChoice.movies => _openVod(VodKind.movies),
    HomeChoice.series => _openVod(VodKind.series),
    HomeChoice.games => _open(_Panel.games),
  };

  /// Pannelli da cui si è arrivati: Indietro torna al precedente.
  final _history = <_Panel>[];

  /// Voce del menu del banner da cui si è aperto il pannello: Indietro
  /// riporta lì invece che a schermo libero.
  int? _menuReturn;

  void _open(_Panel p) {
    if (_panel == _Panel.none) {
      _history.clear();
      _menuReturn = null;
    } else if (_panel != p) {
      final i = _history.indexOf(p);
      if (i >= 0) {
        _history.removeRange(i, _history.length);
      } else {
        _history.add(_panel);
      }
    }
    _show(p);
  }

  void _show(_Panel p) {
    _tuner.hideBanner();
    _leavePanel(p);
    // Film e serie: la TV si ferma finché si resta nel catalogo.
    if (p == _Panel.vod && _panel != _Panel.vod) _tuner.suspend();
    // Nella sala giochi il canale resta sotto, ma senza audio.
    if (p == _Panel.games) {
      unawaited(context.read<PlaybackEngine>().setMuted(true));
    }
    setState(() {
      _menu = null;
      _panel = p;
    });
  }

  /// Menu del banner col telecomando: ←→ scelgono, OK apre, ↑/Indietro esce.
  KeyEventResult _onMenuKey(KeyEvent e, LogicalKeyboardKey k) {
    final actions = bannerActions(_tuner);
    final i = (_menu ?? 0).clamp(0, actions.length - 1);
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight) {
      final d = k == LogicalKeyboardKey.arrowRight ? 1 : -1;
      setState(() => _menu = (i + d).clamp(0, actions.length - 1));
      _tuner.holdBanner();
    } else if (e is KeyRepeatEvent) {
      return KeyEventResult.handled;
    } else if (isSelectKey(k)) {
      setState(() => _menu = null);
      _onBannerAction(actions[i]);
      if (_panel != _Panel.none) _menuReturn = i;
    } else if (k == LogicalKeyboardKey.arrowUp || isBackKey(k)) {
      setState(() => _menu = null);
      _tuner.holdBanner();
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _tuner.holdBanner();
    } else {
      setState(() => _menu = null);
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Chiusura chiesta da un pannello: con Indietro si torna al livello
  /// precedente, altrimenti (canale scelto, tocco sul video…) si chiude tutto.
  void _close() => backKeyActive ? _goBack() : _closeAll();

  void _closeAll() {
    _history.clear();
    _menuReturn = null;
    _leavePanel(_Panel.none);
    setState(() => _panel = _Panel.none);
    _rootFocus.requestFocus();
  }

  /// Un livello indietro: pannello precedente, poi menu del banner da cui
  /// si era partiti, infine la TV a schermo libero.
  void _goBack() {
    if (_history.isNotEmpty) {
      _show(_history.removeLast());
      return;
    }
    final menu = _menuReturn;
    _closeAll();
    if (menu != null && _tuner.current != null) {
      _tuner.showInfo();
      _tuner.holdBanner();
      setState(() => _menu = menu);
    }
  }

  Future<void> _toggleFullscreen() async {
    if (!_isDesktop) return;
    final fs = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!fs);
  }

  /// Indietro: chiude ciò che è aperto, poi (su mobile) doppio tocco per uscire.
  void _back() {
    if (_panel != _Panel.none) return _goBack();
    if (_tuner.digits.isNotEmpty) return _tuner.clearDigits();
    if (_tuner.bannerVisible) return _tuner.hideBanner();
    if (_isDesktop) {
      windowManager.isFullScreen().then((fs) {
        if (fs) windowManager.setFullScreen(false);
      });
      return;
    }
    final now = DateTime.now();
    if (_backPressedAt != null &&
        now.difference(_backPressedAt!) < const Duration(seconds: 2)) {
      _backPressedAt = null;
      unawaited(_confirmExit());
      return;
    }
    _backPressedAt = now;
    _showToast('Premi di nuovo Indietro per uscire');
  }

  bool _exitAsked = false;

  /// Secondo Indietro: si chiede conferma prima di uscire.
  Future<void> _confirmExit() async {
    if (_exitAsked) return;
    _exitAsked = true;
    final yes = await showConfirmDialog(
      context,
      title: 'Vuoi uscire?',
      message: 'Il player si chiude.',
      icon: Icons.logout_rounded,
    );
    _exitAsked = false;
    if (yes) {
      // Android: il video si rilascia prima di chiudere l'attività. Altrimenti
      // la superficie video consegna ancora fotogrammi a un motore Flutter
      // già staccato e l'app va in crash ("FlutterJNI is not attached").
      if (!kIsWeb && Platform.isAndroid) {
        await _engine.dispose().timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      }
      await SystemNavigator.pop();
    } else if (mounted) {
      _rootFocus.requestFocus();
    }
  }

  /// OK tenuto premuto: allo scadere si apre il tastierino a schermo.
  Timer? _okHold;

  /// OK a schermo libero: l'azione parte al rilascio, così tenendolo
  /// premuto per [keypadHoldDuration] si apre invece il tastierino.
  /// I tasti del telefono (senza rilascio) agiscono subito come prima.
  KeyEventResult? _onOkHold(KeyEvent e, LogicalKeyboardKey k) {
    if (!isSelectKey(k)) return null;
    if (e is KeyUpEvent) {
      if (_okHold == null) return null;
      final short = _okHold!.isActive;
      _okHold!.cancel();
      _okHold = null;
      if (short) _onSelect();
      return KeyEventResult.handled;
    }
    if (e is KeyRepeatEvent) {
      return _okHold != null ? KeyEventResult.handled : null;
    }
    // Telefono, o numero già in digitazione: OK agisce subito.
    if (e.physicalKey == const PhysicalKeyboardKey(0) ||
        _tuner.digits.isNotEmpty) {
      return null;
    }
    _okHold?.cancel();
    _okHold = Timer(keypadHoldDuration, () {
      // Il rilascio può non arrivare (un avviso ha preso il focus):
      // si apre solo se OK è ancora giù e non c'è altro aperto.
      if (!mounted ||
          _panel != _Panel.none ||
          _reminders.due != null ||
          !HardwareKeyboard.instance.logicalKeysPressed.contains(k)) {
        _okHold = null;
        return;
      }
      _open(_Panel.keypad);
    });
    return KeyEventResult.handled;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    if (e is KeyUpEvent && _panel == _Panel.none) {
      return _onOkHold(e, k) ?? KeyEventResult.ignored;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Avviso di promemoria: OK va al canale, Indietro annulla.
    if (_reminders.due != null) {
      if (e is KeyRepeatEvent) return KeyEventResult.handled;
      if (isSelectKey(k)) {
        _acceptReminder();
        return KeyEventResult.handled;
      }
      if (isBackKey(k)) {
        _reminders.resolve();
        return KeyEventResult.handled;
      }
    }
    // Con un pannello aperto i tasti appartengono al pannello (e alla
    // navigazione direzionale del focus).
    if (_panel != _Panel.none) return KeyEventResult.ignored;
    if (_menu != null && _tuner.bannerVisible) {
      final r = _onMenuKey(e, k);
      if (r == KeyEventResult.handled) return r;
    }
    if (_onOkHold(e, k) case final r?) return r;
    final repeat = e is KeyRepeatEvent;
    // Informazioni aperte (OK): ↓ entra nel menu (canali, guida, impostazioni…).
    if (k == LogicalKeyboardKey.arrowDown &&
        !repeat &&
        _tuner.infoMode &&
        _tuner.bannerVisible) {
      setState(() => _menu = 0);
      _tuner.holdBanner();
      return KeyEventResult.handled;
    }

    // Anteprima dei canali (←→): ↑↓ sfogliano i programmi del canale
    // mostrato, senza sintonizzarlo.
    if (_tuner.browsing &&
        _tuner.bannerVisible &&
        (k == LogicalKeyboardKey.arrowUp ||
            k == LogicalKeyboardKey.arrowDown)) {
      _tuner.stepEpg(k == LogicalKeyboardKey.arrowDown ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.channelUp ||
        k == LogicalKeyboardKey.pageUp) {
      _tuner.zap(1);
    } else if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.channelDown ||
        k == LogicalKeyboardKey.pageDown) {
      _tuner.zap(-1);
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight) {
      final d = k == LogicalKeyboardKey.arrowRight ? 1 : -1;
      // Con le informazioni aperte (OK) si sfoglia la guida del canale,
      // altrimenti si sfogliano gli altri canali senza cambiare il video.
      if (_tuner.infoMode && _tuner.bannerVisible) {
        _tuner.stepEpg(d);
      } else {
        _tuner.browse(d);
      }
    } else if (repeat) {
      return KeyEventResult.ignored;
    } else if (digitForKey(k) case final d?) {
      _tuner.inputDigit(d);
    } else if (isSelectKey(k)) {
      _onSelect();
    } else if (k == LogicalKeyboardKey.keyL) {
      _open(_Panel.list);
    } else if (k == LogicalKeyboardKey.keyV ||
        k == LogicalKeyboardKey.colorF2Yellow) {
      _openVod(VodKind.movies);
    } else if (k == LogicalKeyboardKey.keyT ||
        k == LogicalKeyboardKey.colorF3Blue) {
      _openVod(VodKind.series);
    } else if (k == LogicalKeyboardKey.keyH) {
      _open(_Panel.home);
    } else if (k == LogicalKeyboardKey.keyJ) {
      _open(_Panel.games);
    } else if (k == LogicalKeyboardKey.keyG || k == LogicalKeyboardKey.guide) {
      _open(_Panel.guide);
    } else if (k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd ||
        k == LogicalKeyboardKey.colorF0Red) {
      _plusOne();
    } else if (k == LogicalKeyboardKey.keyS ||
        k == LogicalKeyboardKey.colorF1Green) {
      if (_tuner.current != null) _open(_Panel.sources);
    } else if (k == LogicalKeyboardKey.keyM ||
        k == LogicalKeyboardKey.contextMenu ||
        k == LogicalKeyboardKey.settings) {
      _open(_Panel.settings);
    } else if (k == LogicalKeyboardKey.keyI || k == LogicalKeyboardKey.info) {
      if (_tuner.infoMode && _tuner.bannerVisible) {
        _tuner.hideBanner();
      } else {
        _tuner.showInfo();
      }
    } else if (k == LogicalKeyboardKey.backspace ||
        k == LogicalKeyboardKey.keyP ||
        k == LogicalKeyboardKey.mediaLast) {
      // Con il banner aperto (o un numero in digitazione) prima si chiude
      // quello; il canale precedente solo a schermo libero.
      if (_tuner.digits.isNotEmpty) {
        _tuner.clearDigits();
      } else if (_tuner.bannerVisible) {
        _tuner.hideBanner();
      } else {
        _tuner.previousChannel();
      }
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
    } else if (SystemVolume.supported &&
        (k == LogicalKeyboardKey.audioVolumeUp ||
            k == LogicalKeyboardKey.audioVolumeDown ||
            k == LogicalKeyboardKey.audioVolumeMute)) {
      // Tasti del volume fisici: li gestisce il sistema (TV, PC…).
      return KeyEventResult.ignored;
    } else if (k == LogicalKeyboardKey.audioVolumeMute ||
        k == LogicalKeyboardKey.keyK) {
      _tuner.toggleMute();
    } else if (k == LogicalKeyboardKey.audioVolumeUp) {
      _tuner.changeVolume(5);
    } else if (k == LogicalKeyboardKey.audioVolumeDown) {
      _tuner.changeVolume(-5);
    } else if (isBackKey(k)) {
      _back();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// OK a schermo libero (o col banner aperto).
  void _onSelect() {
    if (_tuner.digits.isNotEmpty) {
      _tuner.commitDigits();
    } else if (_tuner.browsing &&
        _tuner.bannerVisible &&
        _tuner.infoProgramme != null) {
      // Programma futuro di un canale in anteprima: OK lo prenota
      // (o annulla) senza cambiare canale.
      _toggleReminder(_tuner.infoProgramme!);
    } else if (_tuner.browsing && _tuner.bannerVisible) {
      _tuner.confirmBrowse();
    } else if (_tuner.signalMessage == 'Canale non disponibile') {
      _tuner.retry();
    } else if (_tuner.infoMode &&
        _tuner.bannerVisible &&
        _tuner.infoProgramme != null) {
      // Programma futuro nel banner: OK lo prenota (o annulla).
      _toggleReminder(_tuner.infoProgramme!);
    } else if (_tuner.infoMode && _tuner.bannerVisible) {
      // Secondo OK: elenco completo dei canali.
      _open(_Panel.list);
    } else {
      _tuner.showInfo();
    }
  }

  void _onHover() {
    if (!_isDesktop) return;
    if (!_cursorVisible) setState(() => _cursorVisible = true);
    _cursorTimer?.cancel();
    _cursorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _panel == _Panel.none) {
        setState(() => _cursorVisible = false);
      }
    });
  }

  void _plusOne() {
    if (_tuner.canTogglePlusOne) {
      _tuner.togglePlusOne();
    } else {
      _showToast('Nessuna versione +1 per questo canale');
    }
  }

  Future<void> _toggleFavorite() async {
    final c = _tuner.current;
    if (c == null) return;
    final on = await context.read<AppController>().toggleFavorite(c);
    _tuner.holdBanner();
    _showToast(
      on ? '${c.name} aggiunto ai preferiti' : '${c.name} tolto dai preferiti',
    );
  }

  void _onBannerAction(BannerAction a) => switch (a) {
    BannerAction.list => _open(_Panel.list),
    BannerAction.guide => _open(_Panel.guide),
    BannerAction.settings => _open(_Panel.settings),
    BannerAction.sources => _open(_Panel.sources),
    BannerAction.plusOne => _plusOne(),
    BannerAction.home => _open(_Panel.home),
    BannerAction.keypad => _open(_Panel.keypad),
    BannerAction.favorite => _toggleFavorite(),
  };

  @override
  Widget build(BuildContext context) {
    final engine = context.read<PlaybackEngine>();
    final perf = context.read<PerformanceProfile>();
    final tuner = context.watch<TunerController>();
    final size = MediaQuery.sizeOf(context);
    final margin = size.width < 760 ? 12.0 : 32.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: MouseRegion(
            cursor: _cursorVisible || _panel != _Panel.none
                ? MouseCursor.defer
                : SystemMouseCursors.none,
            onHover: (_) => _onHover(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Video
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (_panel != _Panel.none) return _closeAll();
                      tuner.toggleBanner();
                    },
                    onDoubleTap: _isDesktop
                        ? _toggleFullscreen
                        : () => _open(_Panel.guide),
                    onLongPress: () => _open(_Panel.list),
                    onVerticalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v.abs() < 250 || _panel != _Panel.none) return;
                      tuner.zap(v < 0 ? 1 : -1);
                    },
                    child: RepaintBoundary(child: engine.buildView(context)),
                  ),
                ),

                // 2. Velatura inferiore quando il banner è visibile (leggibilità).
                IgnorePointer(
                  child: AnimatedOpacity(
                    duration: perf.medium,
                    opacity: tuner.bannerVisible || _panel != _Panel.none
                        ? 1
                        : 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        // Il tastierino lascia vedere il video.
                        gradient:
                            _panel == _Panel.none || _panel == _Panel.keypad
                            ? const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: [0.45, 1],
                                colors: [Colors.transparent, Color(0x99000000)],
                              )
                            : LinearGradient(
                                colors: [
                                  Colors.black.withValues(alpha: 0.55),
                                  Colors.black.withValues(alpha: 0.25),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),

                // 3. Stato segnale
                const IgnorePointer(child: Center(child: SignalOverlay())),

                // 4. Banner zapping
                Positioned(
                  left: margin,
                  right: margin,
                  bottom: margin,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1320),
                      child: MouseRegion(
                        onHover: (_) => tuner.holdBanner(),
                        child: _Reveal(
                          visible: tuner.bannerVisible && _panel == _Panel.none,
                          offset: const Offset(0, 0.25),
                          child: ZapBanner(
                            onAction: _onBannerAction,
                            menuIndex: tuner.bannerVisible ? _menu : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 5. Numero digitato
                Positioned(
                  top: margin,
                  right: margin,
                  child: _Reveal(
                    visible: tuner.digits.isNotEmpty,
                    offset: const Offset(0.15, 0),
                    child: const NumberEntry(),
                  ),
                ),

                // 5b. Volume
                Positioned(
                  top: margin,
                  left: 0,
                  right: 0,
                  child: const Center(child: VolumeIndicator()),
                ),

                // 6. Pannelli
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: perf.medium,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, a) {
                      final key = child.key;
                      final dx = key == const ValueKey(_Panel.list)
                          ? -0.06
                          : key == const ValueKey(_Panel.settings)
                          ? 0.06
                          : 0.0;
                      final dy = key == const ValueKey(_Panel.guide)
                          ? 0.03
                          : 0.0;
                      return FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(
                            begin: Offset(dx, dy),
                            end: Offset.zero,
                          ).animate(a),
                          child: child,
                        ),
                      );
                    },
                    child: switch (_panel) {
                      _Panel.none => const SizedBox.shrink(
                        key: ValueKey(_Panel.none),
                      ),
                      _Panel.list => ChannelListOverlay(
                        key: const ValueKey(_Panel.list),
                        onClose: _close,
                      ),
                      _Panel.guide => GuideOverlay(
                        key: const ValueKey(_Panel.guide),
                        onClose: _close,
                      ),
                      _Panel.sources => SourcePicker(
                        key: const ValueKey(_Panel.sources),
                        onClose: _close,
                      ),
                      _Panel.games => GamesHub(
                        key: const ValueKey(_Panel.games),
                        prefs: context.read<AppController>().settings.prefs,
                        onClose: _close,
                      ),
                      _Panel.home => HomeHub(
                        key: const ValueKey(_Panel.home),
                        onPick: _onHome,
                        onClose: _close,
                        onResume: _resumeVod,
                      ),
                      _Panel.vod => VodBrowser(
                        key: const ValueKey(_Panel.vod),
                        initial: _vodKind,
                        onClose: _close,
                        onGames: () => _open(_Panel.games),
                      ),
                      _Panel.keypad => ChannelKeypad(
                        key: const ValueKey(_Panel.keypad),
                        onClose: _close,
                      ),
                      _Panel.settings => SettingsPanel(
                        key: const ValueKey(_Panel.settings),
                        onClose: _close,
                        onToast: _showToast,
                      ),
                    },
                  ),
                ),

                // 7. Notifiche brevi
                Positioned(
                  top: margin,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: _Reveal(
                        visible: _toast != null,
                        offset: const Offset(0, -0.4),
                        child: Glass(
                          radius: 20,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Text(
                            _toast ?? '',
                            style: AppText.label.copyWith(
                              color: Palette.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Comparsa con dissolvenza e leggero scorrimento; nessun costo quando nascosto.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.visible,
    required this.child,
    this.offset = Offset.zero,
  });
  final bool visible;
  final Widget child;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: perf.medium,
        curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
        offset: visible ? Offset.zero : offset,
        child: AnimatedOpacity(
          duration: perf.medium,
          curve: Curves.easeOut,
          opacity: visible ? 1 : 0,
          child: Visibility(
            visible: true,
            maintainState: true,
            child: TickerMode(enabled: visible, child: child),
          ),
        ),
      ),
    );
  }
}
