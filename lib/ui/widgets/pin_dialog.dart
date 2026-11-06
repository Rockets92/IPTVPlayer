import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../keys.dart';
import 'focus_tile.dart';
import 'glass.dart';

/// Lunghezza del PIN del parental control.
const pinLength = 4;

/// Chiede un PIN di 4 cifre. Si usa con le cifre del telecomando o della
/// tastiera, con le frecce + OK sul tastierino a schermo, o col tocco.
///
/// Con [validate] il dialogo resta aperto finché il PIN non è giusto
/// (o l'utente annulla). Restituisce il PIN inserito, o null se annullato.
Future<String?> showPinDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  bool Function(String pin)? validate,
}) => showGeneralDialog<String>(
  context: context,
  barrierDismissible: true,
  barrierLabel: title,
  barrierColor: Colors.black.withValues(alpha: 0.55),
  transitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (context, _, _) =>
      PinDialog(title: title, subtitle: subtitle, validate: validate),
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

class PinDialog extends StatefulWidget {
  const PinDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.validate,
  });

  final String title;
  final String? subtitle;
  final bool Function(String pin)? validate;

  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  final _focus = FocusNode(debugLabel: 'pin');
  String _pin = '';
  String? _error;

  /// Tasti del tastierino a schermo: 1-9, cancella, 0, annulla.
  static const _keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '⌫',
    '0',
    '✕',
  ];
  int _sel = 4; // il "5" al centro

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _digit(String d) {
    if (_pin.length >= pinLength) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == pinLength) _submit();
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    final v = widget.validate;
    if (v != null && !v(_pin)) {
      setState(() {
        _pin = '';
        _error = 'PIN errato, riprova';
      });
      return;
    }
    Navigator.pop(context, _pin);
  }

  void _press(String k) {
    switch (k) {
      case '⌫':
        _back();
      case '✕':
        Navigator.pop(context);
      default:
        _digit(k);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final d = digitForKey(k);
    if (d != null) {
      _digit('$d');
    } else if (k == LogicalKeyboardKey.backspace ||
        k == LogicalKeyboardKey.delete) {
      _back();
    } else if (isBackKey(k)) {
      Navigator.pop(context);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      setState(() => _sel = _sel % 3 == 0 ? _sel + 2 : _sel - 1);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      setState(() => _sel = _sel % 3 == 2 ? _sel - 2 : _sel + 1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      setState(() => _sel = (_sel - 3) % 12);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      setState(() => _sel = (_sel + 3) % 12);
    } else if (isSelectKey(k)) {
      _press(_keys[_sel]);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: 340,
              child: Glass(
                strong: true,
                radius: 30,
                padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_rounded,
                      size: 26,
                      color: Palette.warm,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: AppText.title.copyWith(fontSize: 20),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.subtitle!,
                        textAlign: TextAlign.center,
                        style: AppText.label.copyWith(
                          color: Palette.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < pinLength; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _pin.length
                                  ? Palette.textPrimary
                                  : Colors.transparent,
                              border: Border.all(
                                color: _error != null
                                    ? Palette.danger
                                    : Colors.white.withValues(alpha: 0.5),
                                width: 1.6,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(
                      height: 30,
                      child: Center(
                        child: Text(
                          _error ?? '',
                          style: AppText.label.copyWith(color: Palette.danger),
                        ),
                      ),
                    ),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.6,
                      children: [
                        for (var i = 0; i < _keys.length; i++)
                          _PadKey(
                            label: _keys[i],
                            focused: i == _sel,
                            onTap: () {
                              setState(() => _sel = i);
                              _press(_keys[i]);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        KeyHint('0-9', 'PIN'),
                        KeyHint('Indietro', 'Annulla'),
                      ],
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
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.label,
    required this.focused,
    required this.onTap,
  });

  final String label;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (label) {
      '⌫' => Icons.backspace_outlined,
      '✕' => Icons.close_rounded,
      _ => null,
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: focused ? Palette.neon : null,
            color: focused ? null : Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          alignment: Alignment.center,
          child: icon != null
              ? Icon(
                  icon,
                  size: 20,
                  color: focused ? Palette.textPrimary : Palette.textSecondary,
                )
              : Text(
                  label,
                  style: AppText.title.copyWith(
                    fontSize: 22,
                    color: Palette.textPrimary,
                  ),
                ),
        ),
      ),
    );
  }
}
