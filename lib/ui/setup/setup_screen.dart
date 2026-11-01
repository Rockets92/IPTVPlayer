import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/brand.dart';
import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../data/xtream/xtream_models.dart';
import '../../state/app_controller.dart';
import '../format.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass.dart';
import '../widgets/glass_field.dart';

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
  final _userNode = FocusNode();
  final _passNode = FocusNode();

  bool _busy = false;
  String? _error;
  XtreamAccountInfo? _success;

  @override
  void initState() {
    super.initState();
    final c = context.read<AppController>().credentials;
    if (c != null) {
      _server.text = c.serverUrl;
      _user.text = c.username;
    }
  }

  @override
  void dispose() {
    for (final c in [_server, _user, _pass]) {
      c.dispose();
    }
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
    final server = XtreamCredentials.normalizeServer(_server.text);
    final user = _user.text.trim();
    final pass = _pass.text;
    if (server.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Compila indirizzo, nome utente e password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppController>();
    try {
      final info = await app.connect(
        XtreamCredentials(serverUrl: server, username: user, password: pass),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _success = info;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      unawaited(app.enter());
    } on XtreamException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Errore imprevisto: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final card = _buildCard(perf);
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
                          SizedBox(width: 460, child: card),
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
            'Inserisci i dati Xtream Codes forniti dal tuo provider. '
            'Ti basterà farlo una sola volta.',
            style: AppText.body,
          ),
          const SizedBox(height: 28),
          GlassField(
            label: 'Server',
            hint: 'http://dominio.tv:8080',
            controller: _server,
            keyboardType: TextInputType.url,
            autofocus: true,
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
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _connect(),
          ),
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
            'Suggerimento: puoi incollare nel campo Server anche il link M3U '
            'completo, i campi si compilano da soli.',
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
          exp == null
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
  const _BrandBlock({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final align = compact
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(size: 56),
        SizedBox(height: compact ? 18 : 28),
        Text(
          Brand.name,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: AppText.display.copyWith(
            fontSize: compact ? 34 : 54,
            fontWeight: FontWeight.w600,
            letterSpacing: compact ? -0.8 : -1.6,
          ),
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
        if (!compact) ...[
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
    return SizedBox(
      width: size * 1.3,
      height: size,
      child: Glass(
        radius: size * 0.3,
        shadow: false,
        child: Center(
          child: Container(
            width: size * 0.26,
            height: size * 0.26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Colors.white, Palette.accent],
              ),
              boxShadow: [
                BoxShadow(
                  color: Palette.accent.withValues(alpha: 0.8),
                  blurRadius: size * 0.4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
