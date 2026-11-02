import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/brand.dart';
import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../data/settings_store.dart';
import '../../state/app_controller.dart';
import '../../state/tuner_controller.dart';
import '../format.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/glass_field.dart';
import '../widgets/pin_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _first.requestFocus());
  }

  @override
  void dispose() {
    _first.dispose();
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
      subtitle: '4 cifre per sbloccare i canali per adulti',
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
    await _app.applyMapping();
    tuner.relockAdult();
    widget.onToast(switch (v) {
      AdultMode.off => 'Canali per adulti nascosti',
      AdultMode.on => 'Canali per adulti attivi, categoria XXX',
      AdultMode.pin => 'Canali per adulti protetti da PIN',
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
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final perf = context.read<PerformanceProfile>();
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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 26, 14, 26),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'Impostazioni',
                        style: AppText.display.copyWith(fontSize: 26),
                      ),
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
                      focusNode: _first,
                      icon: Icons.link_rounded,
                      title: 'Sorgente lista',
                      subtitle: s.mappingSource.isEmpty
                          ? 'Integrata (ordine Sky)'
                          : s.mappingSource,
                      onSelect: _editMapping,
                    ),
                    _ToggleRow(
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
                      title: 'Abilita canali per adulti',
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
                        subtitle: 'Canali della categoria XXX dal 900',
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
                      _InfoRow('Errore fonte', _shortUrl(r.source), warn: true),
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
                    _ToggleRow(
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
                    _InfoRow(
                      'Profilo attivo',
                      '${perf.isLight ? 'Leggero' : 'Completo'} · ${perf.reason}',
                    ),

                    const _Section('Abbonamento'),
                    _InfoRow('Server', app.credentials?.serverUrl ?? '—'),
                    _InfoRow('Utente', app.credentials?.username ?? '—'),
                    if (acct != null)
                      _InfoRow(
                        'Scadenza',
                        acct.expiresAt == null
                            ? 'Illimitato'
                            : '${dayLong(acct.expiresAt!)} ${acct.expiresAt!.year}',
                      ),
                    if (acct?.maxConnections != null)
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
                      child: Text(
                        '${Brand.name} 0.1',
                        style: AppText.label.copyWith(
                          color: Palette.textTertiary,
                        ),
                      ),
                    ),
                  ],
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

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 30, 14, 10),
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
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: AppText.label.copyWith(color: Palette.textTertiary),
          ),
        ),
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
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: FocusTile(
      focusNode: focusNode,
      onSelect: onSelect,
      child: Row(
        children: [
          Icon(icon, size: 20, color: Palette.textSecondary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.headline.copyWith(fontSize: 15.5)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(color: Palette.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: Palette.textTertiary,
          ),
        ],
      ),
    ),
  );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: FocusTile(
      onSelect: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.headline.copyWith(fontSize: 15.5)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: AppText.label.copyWith(color: Palette.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          _Switch(value: value),
        ],
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
  });

  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final keys = options.keys.toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: FocusTile(
        onSelect: () {
          final i = keys.indexOf(value);
          onChanged(keys[(i + 1) % keys.length]);
        },
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppText.headline.copyWith(fontSize: 15.5),
              ),
            ),
            Container(
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
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          color: k == value
                              ? Colors.white.withValues(alpha: 0.92)
                              : null,
                        ),
                        child: Text(
                          options[k]!,
                          style: AppText.label.copyWith(
                            fontWeight: FontWeight.w600,
                            color: k == value
                                ? Palette.ink
                                : Palette.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  static const _items = [
    ('↑ ↓', 'Canale successivo / precedente'),
    ('0–9', 'Vai al numero'),
    ('OK', 'Info canale · di nuovo OK: elenco canali'),
    ('← →', 'Sfoglia gli altri canali (OK per guardare)'),
    ('← →', 'Con le info aperte: programmi prima e dopo'),
    ('L', 'Elenco canali'),
    ('G', 'Guida TV'),
    ('S', 'Fonte del canale'),
    ('+', 'Versione +1 del canale (tasto rosso)'),
    ('⌫', 'Canale precedente'),
    ('M', 'Impostazioni'),
    ('F', 'Schermo intero'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      children: [
        for (final (k, t) in _items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: KeyCap(k),
                  ),
                ),
                Expanded(child: Text(t, style: AppText.label)),
              ],
            ),
          ),
      ],
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
