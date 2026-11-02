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
import '../../state/app_controller.dart';
import '../../state/reminder_controller.dart';
import '../../state/tuner_controller.dart';
import '../keys.dart';
import '../settings/settings_panel.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/pin_dialog.dart';
import 'channel_list_overlay.dart';
import 'guide_overlay.dart';
import 'number_entry.dart';
import 'reminder_popup.dart';
import 'signal_overlay.dart';
import 'source_picker.dart';
import 'volume_indicator.dart';
import 'zap_banner.dart';

enum _Panel { none, list, guide, settings, sources }

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
  String? _lastEpgStatus;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    if (_isMobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _tuner.start());
    context.read<AppController>().addListener(_onApp);
    _reminders.addListener(_onReminder);
    _tuner.addListener(_onTuner);
  }

  int _pinSeen = 0;
  bool _pinOpen = false;

  /// Canale per adulti protetto: si chiede il PIN.
  Future<void> _onTuner() async {
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

  /// Un promemoria scatta: si chiude ciò che è aperto e l'avviso prende i tasti.
  void _onReminder() {
    if (_reminders.due == null || !mounted) return;
    if (_panel != _Panel.none) setState(() => _panel = _Panel.none);
    _tuner.hideBanner();
    _rootFocus.requestFocus();
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
    final c = _tuner.current;
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
    context.read<AppController>().removeListener(_onApp);
    _reminders.removeListener(_onReminder);
    _tuner.removeListener(_onTuner);
    WakelockPlus.disable().catchError((_) {});
    if (_isMobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const []);
    }
    _toastTimer?.cancel();
    _cursorTimer?.cancel();
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

  void _open(_Panel p) {
    _tuner.hideBanner();
    setState(() => _panel = p);
  }

  void _close() {
    setState(() => _panel = _Panel.none);
    _rootFocus.requestFocus();
  }

  Future<void> _toggleFullscreen() async {
    if (!_isDesktop) return;
    final fs = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!fs);
  }

  /// Indietro: chiude ciò che è aperto, poi (su mobile) doppio tocco per uscire.
  void _back() {
    if (_panel != _Panel.none) return _close();
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
      SystemNavigator.pop();
      return;
    }
    _backPressedAt = now;
    _showToast('Premi di nuovo Indietro per uscire');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
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
    final repeat = e is KeyRepeatEvent;

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
      if (_tuner.digits.isNotEmpty) {
        _tuner.commitDigits();
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
    } else if (k == LogicalKeyboardKey.keyL) {
      _open(_Panel.list);
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
      _tuner.previousChannel();
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
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

  void _onBannerAction(BannerAction a) => switch (a) {
    BannerAction.list => _open(_Panel.list),
    BannerAction.guide => _open(_Panel.guide),
    BannerAction.settings => _open(_Panel.settings),
    BannerAction.sources => _open(_Panel.sources),
    BannerAction.plusOne => _plusOne(),
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
                      if (_panel != _Panel.none) return _close();
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
                        gradient: _panel == _Panel.none
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
                          child: ZapBanner(onAction: _onBannerAction),
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
                      _Panel.settings => SettingsPanel(
                        key: const ValueKey(_Panel.settings),
                        onClose: _close,
                        onToast: _showToast,
                      ),
                    },
                  ),
                ),

                // 8. Promemoria in arrivo
                Positioned(
                  top: margin,
                  right: margin,
                  child: Consumer<ReminderController>(
                    builder: (context, rc, _) => _Reveal(
                      visible: rc.due != null,
                      offset: const Offset(0.2, 0),
                      child: rc.due == null
                          ? const SizedBox(width: 420)
                          : ReminderPopup(
                              reminder: rc.due!,
                              onGo: _acceptReminder,
                              onDismiss: rc.resolve,
                            ),
                    ),
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
