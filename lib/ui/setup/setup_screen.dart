import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/brand.dart';
import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../data/xtream/xtream_models.dart';
import '../../remote/remote_server.dart';
import '../../state/app_controller.dart';
import '../format.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass.dart';
import '../widgets/glass_field.dart';
import '../widgets/qr_card.dart';

/// Su TV e telefono il campo in primo piano aprirebbe subito la tastiera.
bool get _desktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Primo avvio: indirizzo del server Xtream e credenziali.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _playlist = TextEditingController();
  final _epg = TextEditingController();

  /// Fonte EPG aggiuntiva facoltativa (per le liste Xtream).
  final _extraEpg = TextEditingController();
  final _extraEpgNode = FocusNode();
  ListKind _kind = ListKind.xtream;
  late final RemoteServer _remote = context.read<RemoteServer>();
  final _userNode = FocusNode();
  final _passNode = FocusNode();

  bool _busy = false;
  String? _error;
  XtreamAccountInfo? _success;

  @override
  void initState() {
    super.initState();
    final c = context.read<AppController>().credentials;
    if (c != null && c.isM3u) {
      _kind = ListKind.m3u;
      _playlist.text = c.serverUrl;
      _epg.text = c.epgUrl ?? '';
    } else if (c != null) {
      _server.text = c.serverUrl;
      _user.text = c.username;
    }
    _remote.setupHandler = _fromPhone;
  }

  /// Dati inviati dallo smartphone: si compilano i campi e si connette.
  Future<String?> _fromPhone(XtreamCredentials c, String? extraEpg) async {
    if (!mounted) return 'Il player non è pronto.';
    setState(() {
      _kind = c.kind;
      if (extraEpg != null) _extraEpg.text = extraEpg;
      if (c.isM3u) {
        _playlist.text = c.serverUrl;
        _epg.text = c.epgUrl ?? '';
      } else {
        _server.text = c.serverUrl;
        _user.text = c.username;
        _pass.text = c.password;
      }
    });
    return _connectWith(c);
  }

  @override
  void dispose() {
    if (_remote.setupHandler == _fromPhone) _remote.setupHandler = null;
    for (final c in [_server, _user, _pass, _playlist, _epg, _extraEpg]) {
      c.dispose();
    }
    _extraEpgNode.dispose();
    _userNode.dispose();
    _passNode.dispose();
    super.dispose();
  }

  /// Se l'utente incolla un link M3U completo, i campi si compilano da soli.
  void _onServerChanged(String v) {
    final parsed = XtreamCredentials.tryParseLink(v);
    if (parsed == null) return;
    setState(() {
      _server.text = parsed.serverUrl;
      _user.text = parsed.username;
      _pass.text = parsed.password;
      _error = null;
    });
  }

  Future<void> _connect() async {
    if (_busy) return;
    final XtreamCredentials c;
    if (_kind == ListKind.m3u) {
      final url = _playlist.text.trim();
      if (url.isEmpty) {
        setState(() => _error = 'Inserisci l\'indirizzo della playlist M3U.');
        return;
      }
      final epg = _epg.text.trim();
      // Un link M3U di un pannello Xtream funziona meglio come Xtream.
      c =
          XtreamCredentials.tryParseLink(url) ??
          XtreamCredentials.m3u(url, epgUrl: epg.isEmpty ? null : epg);
    } else {
      final server = XtreamCredentials.normalizeServer(_server.text);
      final user = _user.text.trim();
      final pass = _pass.text;
      if (server.isEmpty || user.isEmpty || pass.isEmpty) {
        setState(() => _error = 'Compila indirizzo, nome utente e password.');
        return;
      }
      c = XtreamCredentials(serverUrl: server, username: user, password: pass);
    }
    await _connectWith(c);
  }

  /// Restituisce null se la connessione riesce, altrimenti il messaggio.
  Future<String?> _connectWith(XtreamCredentials c) async {
    if (_busy) return 'Connessione già in corso, attendi.';
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppController>();
    // Fonte EPG aggiuntiva: si salva prima, così la guida la legge subito.
    final extra = _extraEpg.text.trim();
    if (!c.isM3u && extra.isNotEmpty) {
      final list = app.settings.extraEpgSources;
      if (!list.contains(extra)) {
        await app.settings.setExtraEpgSources([...list, extra]);
      }
    }
    try {
      final info = await app.connect(c);
      if (!mounted) return null;
      setState(() {
        _busy = false;
        _success = info;
      });
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 1100))
            .then((_) => app.enter()),
      );
      return null;
    } on XtreamException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      return e.message;
    } catch (e) {
      final msg = 'Errore imprevisto: $e';
      if (mounted) {
        setState(() {
          _busy = false;
          _error = msg;
        });
      }
      return msg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width >= 720 && size.width > size.height;
    final wide = landscape && size.width >= 980 && size.height >= 760;
    final card = _buildCard(perf);
    if (landscape && !wide) return _buildCompactLandscape(card);
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: wide
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: Row(
                        children: [
                          const Expanded(child: _BrandBlock()),
                          const SizedBox(width: 72),
                          SizedBox(
                            width: 460,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                card,
                                if (_success == null) ...[
                                  const SizedBox(height: 16),
                                  const _PhoneSetup(),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        children: [
                          const _BrandBlock(compact: true),
                          const SizedBox(height: 32),
                          card,
                          if (_success == null) ...[
                            const SizedBox(height: 16),
                            const _PhoneSetup(),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// TV e schermi bassi (Chromecast, Android TV): il QR resta sempre in
  /// vista a sinistra, il modulo scorre a destra seguendo il focus.
  Widget _buildCompactLandscape(Widget card) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _BrandBlock(features: false),
                            if (_success == null) ...[
                              const SizedBox(height: 28),
                              const _PhoneSetup(qrSize: 150),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 40),
                    SizedBox(
                      width: 430,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: card,
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

  Widget _buildCard(PerformanceProfile perf) {
    return Glass(
      radius: 30,
      strong: true,
      padding: const EdgeInsets.fromLTRB(32, 34, 32, 30),
      child: AnimatedSwitcher(
        duration: perf.medium,
        switchInCurve: Curves.easeOutCubic,
        child: _success != null ? _buildSuccess(_success!) : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return AutofillGroup(
      child: Column(
        key: const ValueKey('form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Collega la tua lista',
            style: AppText.display.copyWith(fontSize: 26),
          ),
          const SizedBox(height: 8),
          Text(
            'Inserisci i dati forniti dal tuo provider, oppure inquadra il '
            'codice QR e compilali comodamente dallo smartphone.',
            style: AppText.body,
          ),
          const SizedBox(height: 22),
          _KindSwitch(
            autofocus: !_desktop,
            value: _kind,
            onChanged: (k) => setState(() {
              _kind = k;
              _error = null;
            }),
          ),
          const SizedBox(height: 20),
          if (_kind == ListKind.xtream) ...[
            GlassField(
              label: 'Server',
              hint: 'http://dominio.tv:8080',
              controller: _server,
              keyboardType: TextInputType.url,
              autofocus: _desktop,
              autofillHints: const [AutofillHints.url],
              onChanged: _onServerChanged,
              onSubmitted: (_) => _userNode.requestFocus(),
            ),
            const SizedBox(height: 18),
            GlassField(
              label: 'Nome utente',
              controller: _user,
              focusNode: _userNode,
              autofillHints: const [AutofillHints.username],
              onSubmitted: (_) => _passNode.requestFocus(),
            ),
            const SizedBox(height: 18),
            GlassField(
              label: 'Password',
              controller: _pass,
              focusNode: _passNode,
              obscure: true,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _extraEpgNode.requestFocus(),
            ),
            const SizedBox(height: 18),
            GlassField(
              label: 'Fonte EPG aggiuntiva (facoltativa)',
              hint: 'https://…/guida.xml.gz',
              controller: _extraEpg,
              focusNode: _extraEpgNode,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _connect(),
            ),
          ] else ...[
            GlassField(
              label: 'Indirizzo playlist M3U',
              hint: 'https://…/lista.m3u',
              controller: _playlist,
              keyboardType: TextInputType.url,
              autofocus: _desktop,
              onSubmitted: (_) => _passNode.requestFocus(),
            ),
            const SizedBox(height: 18),
            GlassField(
              label: 'Guida TV XMLTV (facoltativa)',
              hint: 'https://…/guida.xml.gz',
              controller: _epg,
              focusNode: _passNode,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _connect(),
            ),
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _error == null
                ? const SizedBox(height: 26)
                : Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: Palette.danger,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: AppText.body.copyWith(
                              color: const Color(0xFFFFB3B3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          GlassButton(label: 'Connetti', busy: _busy, onPressed: _connect),
          const SizedBox(height: 18),
          Text(
            _kind == ListKind.xtream
                ? 'Suggerimento: puoi incollare nel campo Server anche il link '
                      'M3U completo, i campi si compilano da soli.'
                : 'Se la playlist indica già la sua guida (url-tvg) puoi '
                      'lasciare vuoto il campo della guida. Film e serie '
                      'vengono ignorati: restano solo i canali live.',
            style: AppText.label.copyWith(
              color: Palette.textTertiary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(XtreamAccountInfo info) {
    final exp = info.expiresAt;
    return Column(
      key: const ValueKey('ok'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF9CCEFF), Color(0xFF5B95FF)],
            ),
            boxShadow: [
              BoxShadow(
                color: Palette.accentDeep.withValues(alpha: 0.5),
                blurRadius: 36,
                spreadRadius: -6,
              ),
            ],
          ),
          child: const Icon(Icons.check_rounded, size: 38, color: Palette.ink),
        ),
        const SizedBox(height: 24),
        Text('Connesso', style: AppText.display),
        const SizedBox(height: 8),
        Text(
          _kind == ListKind.m3u
              ? 'Playlist caricata'
              : exp == null
              ? 'Abbonamento attivo'
              : 'Abbonamento attivo fino al ${dayLong(exp)} ${exp.year}',
          textAlign: TextAlign.center,
          style: AppText.body,
        ),
        const SizedBox(height: 28),
        const SizedBox(
          width: 160,
          child: LinearProgressIndicator(
            minHeight: 2,
            color: Palette.accent,
            backgroundColor: Color(0x22FFFFFF),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock({this.compact = false, this.features = true});
  final bool compact;
  final bool features;

  @override
  Widget build(BuildContext context) {
    final align = compact
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          Brand.logo,
          width: compact ? 300 : 460,
          semanticLabel: Brand.name,
          filterQuality: FilterQuality.medium,
        ),
        const SizedBox(height: 10),
        Text(
          Brand.tagline,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: AppText.title.copyWith(
            color: Palette.textSecondary,
            fontWeight: FontWeight.w400,
            fontSize: compact ? 17 : 22,
          ),
        ),
        if (!compact && features) ...[
          const SizedBox(height: 44),
          const _Feature(
            'Zapping istantaneo',
            'Numeri, su e giù, canale precedente: come un decoder.',
          ),
          const SizedBox(height: 20),
          const _Feature(
            'La tua numerazione',
            'Ordine, loghi e guida TV definiti da un semplice file JSON.',
          ),
          const SizedBox(height: 20),
          const _Feature(
            'Guida sempre presente',
            'In onda ora e dopo, da fonti EPG esterne o dal provider.',
          ),
        ],
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.title, this.text);
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 7),
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Palette.accent,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.headline),
              const SizedBox(height: 3),
              Text(text, style: AppText.body),
            ],
          ),
        ),
      ],
    );
  }
}

/// Marchio: un "schermo" in vetro con un punto di luce.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        Brand.icon,
        width: size,
        height: size,
        semanticLabel: Brand.name,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// Scelta del tipo di lista.
class _KindSwitch extends StatelessWidget {
  const _KindSwitch({
    required this.value,
    required this.onChanged,
    this.autofocus = false,
  });
  final ListKind value;
  final bool autofocus;
  final ValueChanged<ListKind> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget item(ListKind k, String label) {
      final on = k == value;
      return Expanded(
        child: FocusableActionDetector(
          autofocus: autofocus && on,
          mouseCursor: SystemMouseCursors.click,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                onChanged(k);
                return null;
              },
            ),
          },
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return GestureDetector(
                onTap: () => onChanged(k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: on
                        ? Colors.white.withValues(alpha: 0.92)
                        : focused
                        ? Colors.white.withValues(alpha: 0.14)
                        : null,
                  ),
                  child: Text(
                    label,
                    style: AppText.label.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: on ? Palette.ink : Palette.textSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.07),
      ),
      child: Row(
        children: [
          item(ListKind.xtream, 'Xtream Codes'),
          const SizedBox(width: 4),
          item(ListKind.m3u, 'Lista M3U'),
        ],
      ),
    );
  }
}

/// QR per compilare i dati dallo smartphone.
class _PhoneSetup extends StatelessWidget {
  const _PhoneSetup({this.qrSize = 112});
  final double qrSize;

  @override
  Widget build(BuildContext context) {
    final remote = context.watch<RemoteServer>();
    final url = remote.setupUrl;
    return Glass(
      radius: 26,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          if (url != null)
            QrCode(data: url, size: qrSize)
          else
            SizedBox(
              width: qrSize + 12,
              height: qrSize + 12,
              child: const Icon(
                Icons.wifi_off_rounded,
                color: Palette.textTertiary,
                size: 36,
              ),
            ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compila dallo smartphone',
                  style: AppText.headline.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  url != null
                      ? 'Inquadra il codice con la fotocamera: si apre un '
                            'modulo dove scrivere i dati comodamente. Telefono e '
                            'player devono essere sulla stessa rete Wi-Fi.'
                      : remote.error ??
                            'Collega il player alla rete di casa per usare lo '
                                'smartphone.',
                  style: AppText.label.copyWith(
                    color: Palette.textSecondary,
                    height: 1.4,
                  ),
                ),
                if (url != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    remote.baseUrl!,
                    style: AppText.mono.copyWith(
                      color: Palette.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
