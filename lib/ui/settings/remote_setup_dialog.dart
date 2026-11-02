import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../remote/remote_server.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/glass_field.dart';
import '../widgets/qr_card.dart';

/// "Configura telecomando": QR che apre sullo smartphone il telecomando.
Future<void> showRemoteSetup(BuildContext context) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Telecomando',
  barrierColor: Colors.black.withValues(alpha: 0.55),
  transitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (context, _, _) => const _RemoteSetup(),
  transitionBuilder: (context, a, _, child) =>
      FadeTransition(opacity: a, child: child),
);

class _RemoteSetup extends StatelessWidget {
  const _RemoteSetup();

  @override
  Widget build(BuildContext context) {
    final remote = context.watch<RemoteServer>();
    final url = remote.remoteUrl;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 760;

    final steps = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Telecomando sullo smartphone', style: AppText.title),
        const SizedBox(height: 8),
        Text(
          'Tutti i tasti del telecomando, CH e volume, l\'elenco canali e la '
          'guida TV, direttamente sul telefono.',
          style: AppText.body,
        ),
        const SizedBox(height: 18),
        const _Step(
          1,
          'Collega il telefono alla stessa rete Wi-Fi del player.',
        ),
        const _Step(2, 'Inquadra il codice con la fotocamera e apri il link.'),
        const _Step(
          3,
          'Salvalo come app: su iPhone Condividi → "Aggiungi alla schermata '
          'Home", su Android menu ⋮ → "Aggiungi a schermata Home".',
        ),
        if (url != null) ...[
          const SizedBox(height: 10),
          SelectableText(
            remote.baseUrl!,
            style: AppText.mono.copyWith(color: Palette.textTertiary),
          ),
        ],
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
              width: 190,
              child: GlassButton(
                label: 'Nuovo codice',
                primary: false,
                onPressed: remote.resetToken,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Un nuovo codice scollega i telefoni già configurati.',
          style: AppText.label.copyWith(color: Palette.textTertiary),
        ),
      ],
    );

    final qr = url != null
        ? QrCode(data: url, size: wide ? 220 : 180)
        : SizedBox(
            width: 220,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 40,
                  color: Palette.textTertiary,
                ),
                const SizedBox(height: 10),
                Text(
                  remote.error ?? 'Il player non è collegato a una rete.',
                  textAlign: TextAlign.center,
                  style: AppText.body,
                ),
              ],
            ),
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
                child: wide
                    ? Row(
                        children: [
                          qr,
                          const SizedBox(width: 34),
                          Expanded(child: steps),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [qr, const SizedBox(height: 22), steps],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.text);
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Text(
            '$n',
            style: AppText.label.copyWith(
              color: Palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: AppText.label.copyWith(
                color: Palette.textSecondary,
                height: 1.4,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
