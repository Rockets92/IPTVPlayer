import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../remote/remote_server.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/glass_field.dart';
import '../widgets/qr_card.dart';

/// "Aggiungi fonti EPG dal telefono": QR che apre sullo smartphone una
/// pagina dove incollare gli indirizzi, senza tastiera virtuale.
Future<void> showEpgFromPhone(BuildContext context) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Fonti EPG',
  barrierColor: Colors.black.withValues(alpha: 0.55),
  transitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (context, _, _) => const _EpgFromPhone(),
  transitionBuilder: (context, a, _, child) =>
      FadeTransition(opacity: a, child: child),
);

class _EpgFromPhone extends StatelessWidget {
  const _EpgFromPhone();

  @override
  Widget build(BuildContext context) {
    // Si aggiorna quando dal telefono si aggiunge o toglie una fonte.
    final remote = context.watch<RemoteServer>();
    final url = remote.epgUrl;
    final sources = remote.extraEpgSources;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 760;

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Fonti EPG dal telefono', style: AppText.title),
        const SizedBox(height: 8),
        Text(
          'Inquadra il codice con la fotocamera del telefono (sulla stessa '
          'rete Wi-Fi) e incolla lì gli indirizzi delle guide XMLTV: '
          'compaiono qui e la guida si aggiorna da sola.',
          style: AppText.body,
        ),
        const SizedBox(height: 16),
        Text(
          'FONTI AGGIUNTIVE',
          style: AppText.overline.copyWith(color: Palette.textTertiary),
        ),
        const SizedBox(height: 8),
        if (sources.isEmpty)
          Text(
            'Nessuna, per ora.',
            style: AppText.label.copyWith(color: Palette.textTertiary),
          )
        else
          for (final s in sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: Palette.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.mono.copyWith(
                        color: Palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 18),
        SizedBox(
          width: 150,
          child: GlassButton(
            label: 'Fatto',
            autofocus: true,
            onPressed: () => Navigator.pop(context),
          ),
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
                Icon(
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
                          Expanded(child: SingleChildScrollView(child: info)),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [qr, const SizedBox(height: 22), info],
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
