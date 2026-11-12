import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/form_factor.dart';
import '../../core/theme.dart';
import '../../remote/remote_server.dart';
import '../../sync/account_config.dart';
import '../../sync/account_controller.dart';
import '../../sync/sync_engine.dart';
import '../format.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/glass_field.dart';
import '../widgets/qr_card.dart';

/// Impostazioni → Account: accesso con email e codice, oppure dal telefono
/// col QR; a login fatto, dispositivi collegati e uscita.
Future<void> showAccountDialog(BuildContext context) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Account',
  barrierColor: Colors.black.withValues(alpha: 0.55),
  transitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (context, _, _) => const _AccountDialog(),
  transitionBuilder: (context, a, _, child) =>
      FadeTransition(opacity: a, child: child),
);

class _AccountDialog extends StatefulWidget {
  const _AccountDialog();

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  Future<List<AccountDevice>>? _devices;
  String? _devicesError;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _loadDevices(AccountController a) {
    _devices = a.devices().catchError((Object e) {
      _devicesError = '$e';
      return <AccountDevice>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AccountController>();
    final remote = context.watch<RemoteServer>();
    final form = context.read<FormFactor>();
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 760;

    if (a.stage == AccountStage.signedIn && _devices == null) _loadDevices(a);
    if (a.stage != AccountStage.signedIn) _devices = null;

    final Widget body = switch (a.stage) {
      AccountStage.signedIn => _signedIn(a),
      AccountStage.codeSent => _codeStep(a),
      AccountStage.signedOut => _emailStep(a),
    };

    final inside = a.stage == AccountStage.signedIn;
    final qrUrl = form.hidesQr
        ? null
        : inside
        ? AccountConfig.remoteWebUrl
        : remote.accountUrl;
    final qr = qrUrl == null
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrCode(data: qrUrl, size: wide ? 200 : 170),
              const SizedBox(height: 10),
              SizedBox(
                width: 200,
                child: Text(
                  inside
                      ? 'Telecomando unico: inquadra col telefono e accedi '
                            'con lo stesso account'
                      : form.qrProminent
                      ? 'Inquadra col telefono: scrivi lì email e codice'
                      : 'Oppure accedi dal telefono',
                  textAlign: TextAlign.center,
                  style: AppText.label.copyWith(color: Palette.textTertiary),
                ),
              ),
            ],
          );

    return Focus(
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && isBackKey(e.logicalKey)) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(
            type: MaterialType.transparency,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Glass(
                strong: true,
                radius: 30,
                padding: const EdgeInsets.all(30),
                child: SingleChildScrollView(
                  child: wide && qr != null
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: body),
                            const SizedBox(width: 34),
                            qr,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            body,
                            if (qr != null) ...[
                              const SizedBox(height: 24),
                              Center(child: qr),
                            ],
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

  Widget _error(AccountController a) => a.error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            a.error!,
            style: AppText.label.copyWith(color: const Color(0xFFFFB3B3)),
          ),
        );

  Widget _emailStep(AccountController a) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Accedi o registrati', style: AppText.title),
      const SizedBox(height: 8),
      Text(
        'Con l\'account ritrovi promemoria, "continua a guardare" e '
        'preferenze su tutti i tuoi dispositivi. Ti mandiamo un codice via '
        'email: niente password, e se l\'account non esiste lo creiamo.',
        style: AppText.body,
      ),
      const SizedBox(height: 18),
      if (!a.available)
        Text(
          'Servizio account non raggiungibile: controlla la connessione e '
          'riapri l\'app.',
          style: AppText.body.copyWith(color: const Color(0xFFFFB3B3)),
        )
      else ...[
        GlassField(
          label: 'Email',
          controller: _email,
          hint: 'nome@esempio.it',
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _send(a),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 230,
          child: GlassButton(
            label: 'Mandami il codice',
            busy: a.busy,
            onPressed: a.busy ? null : () => _send(a),
          ),
        ),
      ],
      _error(a),
    ],
  );

  Future<void> _send(AccountController a) async {
    if (await a.sendCode(_email.text)) _code.clear();
  }

  Widget _codeStep(AccountController a) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Controlla la posta', style: AppText.title),
      const SizedBox(height: 8),
      Text(
        'Abbiamo mandato un codice a ${a.pendingEmail}. Se non lo trovi, '
        'guarda anche nello spam.',
        style: AppText.body,
      ),
      const SizedBox(height: 18),
      GlassField(
        label: 'Codice',
        controller: _code,
        hint: '123456',
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        textInputAction: TextInputAction.done,
        autofocus: true,
        onSubmitted: (_) => a.verifyCode(_code.text),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 150,
            child: GlassButton(
              label: 'Accedi',
              busy: a.busy,
              onPressed: a.busy ? null : () => a.verifyCode(_code.text),
            ),
          ),
          SizedBox(
            width: 190,
            child: GlassButton(
              label: 'Altra email',
              primary: false,
              onPressed: a.cancelCode,
            ),
          ),
        ],
      ),
      _error(a),
    ],
  );

  Widget _signedIn(AccountController a) {
    final engine = a.engine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Il tuo account', style: AppText.title),
        const SizedBox(height: 6),
        Text(a.email ?? '', style: AppText.body),
        const SizedBox(height: 4),
        if (engine != null)
          ListenableBuilder(
            listenable: engine,
            builder: (context, _) =>
                Text(_syncLabel(engine), style: AppText.label),
          ),
        const SizedBox(height: 20),
        Text('DISPOSITIVI COLLEGATI', style: AppText.overline),
        const SizedBox(height: 8),
        FutureBuilder<List<AccountDevice>>(
          future: _devices,
          builder: (context, snap) {
            final list = snap.data;
            if (list == null) {
              return Text('Caricamento…', style: AppText.label);
            }
            if (list.isEmpty) {
              return Text(
                _devicesError == null
                    ? 'Nessun dispositivo registrato'
                    : 'Elenco non disponibile: $_devicesError',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppText.label,
              );
            }
            return Column(
              children: [
                for (final d in list)
                  _DeviceRow(
                    device: d,
                    onRemove: d.isThis
                        ? null
                        : () async {
                            await a.removeDevice(d.id);
                            setState(() => _loadDevices(a));
                          },
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 150,
              child: GlassButton(
                label: 'Chiudi',
                autofocus: true,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            SizedBox(
              width: 200,
              child: GlassButton(
                label: 'Sincronizza ora',
                primary: false,
                onPressed: () async {
                  await a.syncNow();
                  if (mounted) setState(() => _loadDevices(a));
                },
              ),
            ),
            SizedBox(
              width: 150,
              child: GlassButton(
                label: 'Esci',
                primary: false,
                onPressed: a.signOut,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Uscendo, i dati restano su questo dispositivo ma non si '
          'sincronizzano più. I dati della lista IPTV non escono mai dal '
          'dispositivo.',
          style: AppText.label.copyWith(color: Palette.textTertiary),
        ),
      ],
    );
  }

  static String _syncLabel(SyncEngine e) {
    if (e.error != null) return e.error!;
    final t = e.lastSync;
    if (t == null) return 'Sincronizzazione in corso…';
    return 'Sincronizzato alle ${hm(t)}';
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, this.onRemove});
  final AccountDevice device;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final icon = switch (device.kind) {
      'tv' => Icons.tv_rounded,
      'phone' => Icons.phone_iphone_rounded,
      'tablet' => Icons.tablet_mac_rounded,
      _ => Icons.computer_rounded,
    };
    final row = Row(
      children: [
        Icon(icon, size: 20, color: Palette.textSecondary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.isThis ? '${device.name} · questo' : device.name,
                style: AppText.headline.copyWith(fontSize: 15),
              ),
              Text(
                'Visto ${dayShort(device.lastSeen)} alle ${hm(device.lastSeen)}',
                style: AppText.label.copyWith(color: Palette.textTertiary),
              ),
            ],
          ),
        ),
        if (onRemove != null)
          Text(
            'Scollega',
            style: AppText.label.copyWith(color: Palette.textSecondary),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: onRemove == null
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: row,
            )
          : FocusTile(
              onSelect: onRemove!,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: row,
            ),
    );
  }
}
