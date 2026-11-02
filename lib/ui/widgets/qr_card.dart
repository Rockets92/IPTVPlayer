import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';

/// Codice QR su fondo bianco (si legge bene anche da lontano), con
/// l'indirizzo scritto sotto per chi preferisce digitarlo.
class QrCode extends StatelessWidget {
  const QrCode({super.key, required this.data, this.size = 180});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(size * 0.06),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(size * 0.1),
      boxShadow: [
        BoxShadow(
          color: Palette.accentDeep.withValues(alpha: 0.35),
          blurRadius: 30,
          spreadRadius: -8,
        ),
      ],
    ),
    child: QrImageView(
      data: data,
      size: size,
      padding: EdgeInsets.zero,
      backgroundColor: Colors.white,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.circle,
        color: Palette.ink,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.circle,
        color: Palette.ink,
      ),
    ),
  );
}
