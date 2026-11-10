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
                    PadGrid(
                      keys: _keys,
                      selected: _sel,
                      onTap: (i) {
                        setState(() => _sel = i);
                        _press(_keys[i]);
                      },
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

/// Griglia 3 colonne del tastierino a schermo. L'evidenziazione del tasto
/// scelto è un'unica pastiglia che scorre da un tasto all'altro, invece di
/// spegnersi su uno e accendersi sull'altro.
class PadGrid extends StatelessWidget {
  const PadGrid({
    super.key,
    required this.keys,
    required this.selected,
    required this.onTap,
  });

  final List<String> keys;
  final int selected;
  final void Function(int index) onTap;

  /// Durata dello scorrimento tra due tasti.
  static const slide = Duration(milliseconds: 180);
  static const _gap = 10.0;
  static const _ratio = 1.6;

  @override
  Widget build(BuildContext context) {
    final rows = (keys.length / 3).ceil();
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 2 * _gap) / 3;
        final h = w / _ratio;
        Offset at(int i) => Offset((i % 3) * (w + _gap), (i ~/ 3) * (h + _gap));
        final sel = at(selected);
        return SizedBox(
          height: rows * h + (rows - 1) * _gap,
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: slide,
                curve: Curves.easeOutCubic,
                left: sel.dx,
                top: sel.dy,
                width: w,
                height: h,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: Palette.neon,
                      boxShadow: [
                        BoxShadow(
                          color: Palette.accent.withValues(alpha: 0.4),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < keys.length; i++)
                Positioned(
                  left: at(i).dx,
                  top: at(i).dy,
                  width: w,
                  height: h,
                  child: PadKey(
                    label: keys[i],
                    focused: i == selected,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Tasto del tastierino a schermo (PIN, numero canale): cifra o simbolo
/// (⌫ cancella, ✕ annulla, ✓ conferma). Acceso quando ha il focus.
class PadKey extends StatelessWidget {
  const PadKey({
    super.key,
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
      '✓' => Icons.check_rounded,
      _ => null,
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: PadGrid.slide,
          curve: Curves.easeOutCubic,
          // Il colore del tasto scelto è l'evidenziazione che scorre sotto
          // (PadGrid): il tasto si limita a lasciarla vedere.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withValues(alpha: focused ? 0 : 0.08),
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
