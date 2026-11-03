import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'focus_tile.dart';
import 'glass.dart';
import 'glass_field.dart';

/// Domanda con due risposte (es. "Vuoi uscire?" Sì / No), comoda col
/// telecomando: ←→ per scegliere, OK per confermare, Indietro = No.
/// Il focus parte su "No", così un tasto premuto per sbaglio non conferma.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String yes = 'Sì',
  String no = 'No',
  IconData? icon,
}) async {
  final r = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) =>
        _Confirm(title: title, message: message, yes: yes, no: no, icon: icon),
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
  return r ?? false;
}

class _Confirm extends StatelessWidget {
  const _Confirm({
    required this.title,
    required this.message,
    required this.yes,
    required this.no,
    required this.icon,
  });

  final String title;
  final String? message;
  final String yes;
  final String no;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Focus(
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && isBackKey(e.logicalKey)) {
          Navigator.pop(context, false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: width < 480 ? width - 24 : 400,
            child: Glass(
              strong: true,
              radius: 26,
              padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 22, color: Palette.textSecondary),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          style: AppText.headline.copyWith(fontSize: 20),
                        ),
                      ),
                    ],
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      message!,
                      style: AppText.body.copyWith(
                        color: Palette.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: GlassButton(
                          label: yes,
                          primary: false,
                          onPressed: () => Navigator.pop(context, true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GlassButton(
                          label: no,
                          autofocus: true,
                          onPressed: () => Navigator.pop(context, false),
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
