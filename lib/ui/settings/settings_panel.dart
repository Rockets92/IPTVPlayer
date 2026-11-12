import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/brand.dart';
import '../../core/form_factor.dart';
import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../data/settings_store.dart';
import '../../state/app_controller.dart';
import '../../state/tuner_controller.dart';
import '../../state/vod_controller.dart';
import '../../sync/account_controller.dart';
import '../format.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/glass_field.dart';
import '../widgets/pin_dialog.dart';
import 'account_dialog.dart';
import 'epg_phone_dialog.dart';
import 'remote_setup_dialog.dart';

/// Impostazioni (tasto M): pannello laterale navigabile con il telecomando.
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    super.key,
    required this.onClose,
    required this.onToast,
  });
  final VoidCallback onClose;
  final ValueChanged<String> onToast;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  bool _dialogOpen = false;
  final _first = FocusNode(debugLabel: 'settings-first');
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _first.requestFocus());
  }

  @override
  void dispose() {
    _first.dispose();
    _scroll.dispose();
    super.dispose();
  }

  AppController get _app => context.read<AppController>();
  SettingsStore get _s => _app.settings;

  Future<String?> _edit({
    required String title,
    required String help,
    required String initial,
    String? hint,
    bool multiline = false,
  }) async {
    _dialogOpen = true;
    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) => _EditDialog(
        title: title,
        help: help,
        initial: initial,
        hint: hint,
        multiline: multiline,
      ),
      transitionBuilder: (context, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(
            begin: 0.97,
            end: 1.0,
          ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
    _dialogOpen = false;
    return result;
  }

  Future<void> _editMapping() async {
    final v = await _edit(
      title: 'Sorgente lista canali',
      help:
          'URL (https://…) o percorso di un file JSON con ordine, loghi e id EPG. '
          'Lascia vuoto per usare la lista integrata.',
      initial: _s.mappingSource,
      hint: 'https://server.it/canali.json',
    );
    if (v == null) return;
    await _s.setMappingSource(v);
    widget.onToast('Applicazione della nuova lista…');
    await _app.applyMapping();
    widget.onToast('Lista canali aggiornata · ${_app.mapping?.origin ?? ''}');
    if (mounted) setState(() {});
  }

  Future<void> _editEpg() async {
    final v = await _edit(
      title: 'Fonti EPG aggiuntive',
      help:
          'Un indirizzo XMLTV per riga (anche .xml.gz). Vengono lette dopo '
          'quelle indicate nella lista canali e prima della guida del provider.',
      initial: _s.extraEpgSources.join('\n'),
      hint: 'https://…/guida.xml.gz',
      multiline: true,
    );
    if (v == null) return;
    await _s.setExtraEpgSources(v.split('\n'));
    widget.onToast('Aggiornamento guida…');
    await _app.refreshEpg();
    if (mounted) setState(() {});
  }

  Future<String?> _pin(
    String title, {
    String? subtitle,
    bool Function(String)? validate,
  }) async {
    _dialogOpen = true;
    final v = await showPinDialog(
      context,
      title: title,
      subtitle: subtitle,
      validate: validate,
    );
    _dialogOpen = false;
    return v;
  }

  /// Nuovo PIN, chiesto due volte.
  Future<String?> _newPin() async {
    final a = await _pin(
      'Scegli un PIN',
      subtitle: '4 cifre per sbloccare i contenuti per adulti',
    );
    if (a == null || !mounted) return null;
    final b = await _pin('Conferma il PIN', subtitle: 'Ripeti le 4 cifre');
    if (b == null) return null;
    if (a != b) {
      widget.onToast('I due PIN non coincidono, nessuna modifica');
      return null;
    }
    return a;
  }

  Future<bool> _askCurrentPin() async =>
      await _pin(
        'PIN attuale',
        subtitle: 'Serve per cambiare il parental control',
        validate: _s.checkAdultPin,
      ) !=
      null;

  Future<void> _setAdult(AdultMode v) async {
    final was = _s.adultMode;
    if (v == was) return;
    // Il parental control si toglie solo con il PIN.
    if (was == AdultMode.pin && !await _askCurrentPin()) return;
    String? pin;
    if (v == AdultMode.pin) {
      pin = await _newPin();
      if (pin == null) return;
    }
    await _s.setAdultMode(v, pin: pin);
    if (!mounted) return;
    final tuner = context.read<TunerController>();
    final vod = context.read<VodController>();
    await _app.applyMapping();
    tuner.relockAdult();
    vod.relockAdult();
    widget.onToast(switch (v) {
      AdultMode.off => 'Contenuti per adulti nascosti',
      AdultMode.on => 'Contenuti per adulti attivi',
      AdultMode.pin => 'Contenuti per adulti protetti da PIN',
    });
    if (mounted) setState(() {});
  }

  Future<void> _changePin() async {
    if (!await _askCurrentPin()) return;
    final pin = await _newPin();
    if (pin == null) return;
    await _s.setAdultMode(AdultMode.pin, pin: pin);
    if (!mounted) return;
    context.read<TunerController>().relockAdult();
    context.read<VodController>().relockAdult();
    widget.onToast('PIN aggiornato');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (_dialogOpen || e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (isBackKey(k) ||
        k == LogicalKeyboardKey.keyM ||
        k == LogicalKeyboardKey.contextMenu) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) {
      final down = k == LogicalKeyboardKey.arrowDown;
      final moved = FocusManager.instance.primaryFocus?.focusInDirection(
        down ? TraversalDirection.down : TraversalDirection.up,
      );
      // Oltre l'ultima (o prima) voce selezionabile c'è ancora qualcosa da
      // vedere (logo e versione in fondo, titolo in cima): la lista scorre
      // fino al bordo invece di restare ferma.
      if (moved != true) _scrollToEdge(down);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollToEdge(bool end) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = end ? pos.maxScrollExtent : pos.minScrollExtent;
    if ((pos.pixels - target).abs() < 1) return;
    if (context.read<PerformanceProfile>().isLight) {
      pos.jumpTo(target);
    } else {
      pos.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final perf = context.read<PerformanceProfile>();
    final form = context.read<FormFactor>();
    final s = app.settings;
    final width = MediaQuery.sizeOf(context).width;
    final panelW = width < 600 ? width - 24 : 480.0;
    final acct = app.account;
    final mapping = app.mapping;

    return Focus(
      onKeyEvent: _onKey,
      child: FocusTraversalGroup(
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding:
                const EdgeInsets.all(12) + const EdgeInsets.only(right: 12),
            child: SizedBox(
              width: panelW,
              child: Glass(
                strong: true,
                radius: 30,
                // Tutte le voci costruite subito (niente lista "pigra"): il
                // focus del telecomando trova sempre la voce successiva,
                // anche quando è ancora fuori dallo schermo.
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 26, 14, 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _Row.inset,
                        ),
                        child: Text(
                          'Impostazioni',
                          style: AppText.display.copyWith(fontSize: 26),
                        ),
                      ),
                      const _Section('Account'),
                      Builder(
                        builder: (context) {
                          final acc = context.watch<AccountController>();
                          final inside = acc.stage == AccountStage.signedIn;
                          return _ActionRow(
                            focusNode: _first,
                            icon: inside
                                ? Icons.cloud_done_rounded
                                : Icons.account_circle_rounded,
                            title: inside
                                ? (acc.email ?? 'Account')
                                : 'Accedi o registrati',
                            subtitle: inside
                                ? 'Promemoria e preferenze sincronizzati · dispositivi collegati'
                                : 'Ritrova promemoria e preferenze su tutti i dispositivi',
                            onSelect: () async {
                              _dialogOpen = true;
                              await showAccountDialog(context);
                              _dialogOpen = false;
                            },
                          );
                        },
                      ),
                      const _Section('Lista canali'),
                      _InfoRow(
                        'In uso',
                        mapping == null
                            ? '—'
                            : '${mapping.name} · ${mapping.origin}',
                      ),
                      _InfoRow('Canali', '${app.channels.length}'),
                      _ActionRow(
                        icon: Icons.link_rounded,
                        title: 'Sorgente lista',
                        subtitle: s.mappingSource.isEmpty
                            ? 'Integrata (ordine Sky)'
                            : s.mappingSource,
                        onSelect: _editMapping,
                      ),
                      _ToggleRow(
                        icon: Icons.playlist_add_rounded,
                        title: 'Mostra canali non in lista',
                        subtitle:
                            'Gli altri canali del provider, dal numero ${mapping?.unmappedStartNumber ?? 1000}',
                        value: s.showUnmapped ?? mapping?.showUnmapped ?? false,
                        onChanged: (v) async {
                          await s.setShowUnmapped(v);
                          await app.applyMapping();
                          if (mounted) setState(() {});
                        },
                      ),
                      _ChoiceRow<AdultMode>(
                        icon: Icons.no_adult_content_rounded,
                        title: 'Abilita contenuti per adulti',
                        value: s.adultMode,
                        options: const {
                          AdultMode.off: 'No',
                          AdultMode.on: 'Sì',
                          AdultMode.pin: 'Sì con PIN',
                        },
                        onChanged: _setAdult,
                      ),
                      if (s.adultMode == AdultMode.pin)
                        _ActionRow(
                          icon: Icons.lock_reset_rounded,
                          title: 'Cambia PIN',
                          subtitle:
                              'Canali XXX dal 9000, film e serie per adulti',
                          onSelect: _changePin,
                        ),
                      _ActionRow(
                        icon: Icons.refresh_rounded,
                        title: 'Aggiorna canali dal provider',
                        onSelect: () async {
                          widget.onToast('Aggiornamento canali…');
                          await app.reloadChannels();
                          widget.onToast('${app.channels.length} canali');
                        },
                      ),

                      const _Section('Guida TV'),
                      _InfoRow(
                        'Stato',
                        app.epgLoading
                            ? (app.epgStatus ?? 'Aggiornamento…')
                            : app.epg.isEmpty
                            ? 'Non disponibile'
                            : '${app.epg.channelCount} canali · ${hm(app.epg.fetchedAt ?? DateTime.now())}',
                      ),
                      for (final r in app.epgReports.where((r) => !r.ok))
                        _InfoRow(
                          'Errore fonte',
                          _shortUrl(r.source),
                          warn: true,
                        ),
                      _ActionRow(
                        icon: Icons.sync_rounded,
                        title: 'Aggiorna guida ora',
                        onSelect: () {
                          widget.onToast('Aggiornamento guida…');
                          app.refreshEpg();
                        },
                      ),
                      _ActionRow(
                        icon: Icons.playlist_add_rounded,
                        title: 'Fonti EPG aggiuntive',
                        subtitle: s.extraEpgSources.isEmpty
                            ? 'Nessuna'
                            : '${s.extraEpgSources.length} configurate',
                        onSelect: _editEpg,
                      ),
                      if (!form.hidesQr)
                        _ActionRow(
                          icon: Icons.qr_code_2_rounded,
                          title: 'Aggiungi fonti EPG dal telefono',
                          subtitle: 'Inquadra il codice e incolla i link',
                          onSelect: () async {
                            await showEpgFromPhone(context);
                            if (mounted) setState(() {});
                          },
                        ),
                      _ToggleRow(
                        icon: Icons.event_note_rounded,
                        title: 'Usa la guida del provider',
                        subtitle:
                            'Completa i canali non coperti dalle fonti esterne',
                        value: s.useProviderEpg,
                        onChanged: (v) async {
                          await s.setUseProviderEpg(v);
                          setState(() {});
                        },
                      ),

                      const _Section('Riproduzione'),
                      _ChoiceRow<StreamFormat>(
                        icon: Icons.stream_rounded,
                        title: 'Formato stream',
                        value: s.streamFormat,
                        options: const {
                          StreamFormat.ts: 'MPEG-TS',
                          StreamFormat.hls: 'HLS',
                        },
                        onChanged: (v) async {
                          await s.setStreamFormat(v);
                          setState(() {});
                          widget.onToast(
                            'Formato ${v.label}: attivo dal prossimo cambio canale',
                          );
                        },
                      ),
                      _ChoiceRow<PerformanceMode>(
                        icon: Icons.speed_rounded,
                        title: 'Prestazioni',
                        value: s.performanceMode,
                        options: const {
                          PerformanceMode.auto: 'Auto',
                          PerformanceMode.full: 'Complete',
                          PerformanceMode.light: 'Leggere',
                        },
                        onChanged: (v) async {
                          await s.setPerformanceMode(v);
                          setState(() {});
                          widget.onToast('Applicato al prossimo avvio');
                        },
                      ),
                      _ChoiceRow<UiScale>(
                        icon: Icons.format_size_rounded,
                        title: 'Dimensione interfaccia',
                        value: s.uiScale,
                        options: const {
                          UiScale.auto: 'Auto',
                          UiScale.large: 'Grande',
                          UiScale.medium: 'Media',
                          UiScale.small: 'Piccola',
                        },
                        onChanged: (v) async {
                          await s.setUiScale(v);
                          app.settingsChanged();
                          setState(() {});
                        },
                      ),
                      _InfoRow(
                        'Profilo attivo',
                        '${perf.isLight ? 'Leggero' : 'Completo'} · ${perf.reason}',
                      ),

                      if (!form.hidesQr) ...[
                        const _Section('Telecomando'),
                        _ActionRow(
                          icon: Icons.phone_iphone_rounded,
                          title: 'Configura telecomando',
                          subtitle: 'Usa lo smartphone come telecomando, con elenco canali e guida',
                          onSelect: () async {
                            _dialogOpen = true;
                            await showRemoteSetup(context);
                            _dialogOpen = false;
                          },
                        ),
                      ],

                      const _Section('Abbonamento'),
                      _InfoRow(
                        'Tipo',
                        app.credentials?.isM3u ?? false
                            ? 'Playlist M3U'
                            : 'Xtream Codes',
                      ),
                      _InfoRow(
                        app.credentials?.isM3u ?? false ? 'Playlist' : 'Server',
                        app.credentials?.serverUrl ?? '—',
                      ),
                      if (!(app.credentials?.isM3u ?? false))
                        _InfoRow('Utente', app.credentials?.username ?? '—'),
                      if (acct != null && !(app.credentials?.isM3u ?? false))
                        _InfoRow(
                          'Scadenza',
                          acct.expiresAt == null
                              ? 'Illimitato'
                              : '${dayLong(acct.expiresAt!)} ${acct.expiresAt!.year}',
                        ),
                      if (acct?.maxConnections != null &&
                          !(app.credentials?.isM3u ?? false))
                        _InfoRow('Connessioni', '${acct!.maxConnections} max'),
                      _ActionRow(
                        icon: Icons.logout_rounded,
                        title: 'Cambia account',
                        subtitle: 'Torna alla schermata di configurazione',
                        onSelect: () async {
                          widget.onClose();
                          await app.logout();
                        },
                      ),

                      const _Section('Comandi'),
                      const _Shortcuts(),
                      const SizedBox(height: 18),
                      Center(
                        child: Column(
                          children: [
                            Image.asset(
                              Brand.logo,
                              width: 150,
                              cacheWidth: Brand.decodeSize(
                                150,
                                MediaQuery.devicePixelRatioOf(context),
                                Brand.logoWidth,
                              ),
                              semanticLabel: Brand.name,
                              filterQuality: FilterQuality.medium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${Brand.name} 0.1',
                              style: AppText.label.copyWith(
                                color: Palette.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _shortUrl(String u) {
    final uri = Uri.tryParse(u);
    return uri?.host.isNotEmpty == true ? uri!.host : u;
  }
}

/// Misure comuni delle voci: testo sempre sulla stessa colonna, dietro
/// la colonna delle icone, e stessa altezza minima per ogni voce.
abstract final class _Row {
  /// Margine orizzontale del contenuto dentro la voce.
  static const inset = 16.0;
  static const iconSlot = 22.0;
  static const iconGap = 16.0;

  /// Dove inizia il testo, rispetto al bordo della voce.
  static const text = inset + iconSlot + iconGap;
  static const minHeight = 44.0;
  static const padding = EdgeInsets.symmetric(horizontal: inset, vertical: 10);

  /// Spazio lasciato tra la voce col focus e i bordi del pannello.
  static const reveal = 72.0;

  /// Spazio tra una voce e l'altra.
  static const gap = EdgeInsets.symmetric(vertical: 3);
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(_Row.inset, 26, _Row.inset, 8),
    child: Text(title.toUpperCase(), style: AppText.overline),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.warn = false});
  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(_Row.text, 6, _Row.inset, 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label.copyWith(color: Palette.textTertiary)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppText.label.copyWith(
              color: warn ? const Color(0xFFFFB3B3) : Palette.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Struttura di ogni voce selezionabile: icona, titolo con sottotitolo e
/// un elemento a destra (freccia, interruttore, scelte).
class _RowBody extends StatelessWidget {
  const _RowBody({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: _Row.minHeight),
    child: Row(
      children: [
        SizedBox(
          width: _Row.iconSlot,
          child: icon == null
              ? null
              : Icon(icon, size: 20, color: Palette.textSecondary),
        ),
        const SizedBox(width: _Row.iconGap),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.headline.copyWith(fontSize: 15.5),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(color: Palette.textTertiary),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 14), trailing!],
      ],
    ),
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onSelect,
    this.subtitle,
    this.focusNode,
  });

  final FocusNode? focusNode;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _Row.gap,
    child: FocusTile(
      focusNode: focusNode,
      onSelect: onSelect,
      padding: _Row.padding,
      revealMargin: _Row.reveal,
      child: _RowBody(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: const Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: Palette.textTertiary,
        ),
      ),
    ),
  );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _Row.gap,
    child: FocusTile(
      onSelect: () => onChanged(!value),
      padding: _Row.padding,
      revealMargin: _Row.reveal,
      child: _RowBody(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: _Switch(value: value),
      ),
    ),
  );
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value});
  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 46,
      height: 28,
      padding: const EdgeInsets.all(3),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: value ? Palette.progress : null,
        color: value ? null : Colors.white.withValues(alpha: 0.14),
      ),
      child: Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scelta tra poche opzioni: OK cicla, il valore attivo è evidenziato.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
  });

  final IconData? icon;
  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final keys = options.keys.toList();
    return Padding(
      padding: _Row.gap,
      child: FocusTile(
        onSelect: () {
          final i = keys.indexOf(value);
          onChanged(keys[(i + 1) % keys.length]);
        },
        padding: _Row.padding,
        revealMargin: _Row.reveal,
        child: _RowBody(
          icon: icon,
          title: title,
          trailing: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.07),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final k in keys)
                  GestureDetector(
                    onTap: () => onChanged(k),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        gradient: k == value ? Palette.neon : null,
                      ),
                      child: Text(
                        options[k]!,
                        style: AppText.label.copyWith(
                          fontWeight: FontWeight.w600,
                          color: k == value
                              ? Colors.white
                              : Palette.textSecondary,
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

class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  /// (tasti, descrizione, nota tra parentesi).
  static const _groups = [
    (
      'Visione',
      [
        (['↑', '↓'], 'Canale successivo / precedente', null),
        (['0–9'], 'Vai al numero', null),
        (['⌫'], 'Canale precedente', null),
        (['+'], 'Versione +1 del canale', 'tasto rosso'),
        (['S'], 'Fonte del canale', 'tasto verde'),
      ],
    ),
    (
      'Info e guida',
      [
        (['OK'], 'Info canale', 'di nuovo OK: elenco'),
        (['←', '→'], 'Sfoglia gli altri canali', 'OK per guardare'),
        (['←', '→'], 'Con le info aperte: programmi prima e dopo', null),
        (['OK'], 'Su un programma futuro: promemoria', null),
      ],
    ),
    (
      'Pannelli',
      [
        (['L'], 'Elenco canali', null),
        (['G'], 'Guida TV', null),
        (['M'], 'Impostazioni', null),
        (['F'], 'Schermo intero', null),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (title, items) in _groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Text(
              title,
              style: AppText.label.copyWith(
                color: Palette.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  // Ogni comando prende il focus (senza azione): così col
                  // telecomando si scende a leggerli tutti.
                  FocusTile(
                    padding: EdgeInsets.zero,
                    radius: 14,
                    revealMargin: _Row.reveal,
                    child: _ShortcutRow(
                      keys: items[i].$1,
                      text: items[i].$2,
                      note: items[i].$3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keys, required this.text, this.note});

  final List<String> keys;
  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    child: Row(
      children: [
        SizedBox(
          width: 76,
          child: Wrap(spacing: 4, children: [for (final k in keys) _Cap(k)]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: text),
                if (note != null)
                  TextSpan(
                    text: '  ·  $note',
                    style: AppText.label.copyWith(color: Palette.textTertiary),
                  ),
              ],
            ),
            style: AppText.label.copyWith(
              color: Palette.textPrimary,
              fontSize: 14,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Tasto in rilievo, largo quanto il suo testo.
class _Cap extends StatelessWidget {
  const _Cap(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 28),
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.08),
        ],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          offset: const Offset(0, 1.5),
        ),
      ],
    ),
    child: Center(
      widthFactor: 1,
      child: Text(
        label,
        style: AppText.label.copyWith(
          color: Palette.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
      ),
    ),
  );
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.title,
    required this.help,
    required this.initial,
    this.hint,
    this.multiline = false,
  });

  final String title;
  final String help;
  final String initial;
  final String? hint;
  final bool multiline;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(
            type: MaterialType.transparency,
            child: Glass(
              strong: true,
              radius: 28,
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.title, style: AppText.title),
                  const SizedBox(height: 8),
                  Text(widget.help, style: AppText.body),
                  const SizedBox(height: 22),
                  widget.multiline
                      ? _MultilineField(controller: _c, hint: widget.hint)
                      : GlassField(
                          label: 'Valore',
                          controller: _c,
                          hint: widget.hint,
                          autofocus: true,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (v) => Navigator.pop(context, v),
                        ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: GlassButton(
                          label: 'Annulla',
                          primary: false,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GlassButton(
                          label: 'Salva',
                          onPressed: () => Navigator.pop(context, _c.text),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MultilineField extends StatelessWidget {
  const _MultilineField({required this.controller, this.hint});
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: TextField(
        controller: controller,
        autofocus: true,
        minLines: 4,
        maxLines: 8,
        keyboardType: TextInputType.multiline,
        style: AppText.label.copyWith(color: Palette.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: AppText.label.copyWith(color: Palette.textTertiary),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }
}
