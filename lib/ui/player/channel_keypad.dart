import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/tuner_controller.dart';
import '../keys.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/pin_dialog.dart';
import 'number_entry.dart';

/// Pressione su OK che apre il tastierino a schermo.
const keypadHoldDuration = Duration(milliseconds: 800);

/// Telecomando digitale: tastierino numerico a schermo per scegliere il
/// canale col numero dove il telecomando non ha le cifre (Chromecast,
/// proiettori…). Si apre tenendo premuto OK o dal menu del banner.
///
/// Frecce per scegliere il tasto, OK per premerlo, ✓ per andare al canale.
/// Le cifre non scadono come quelle del telecomando: si ha tutto il tempo
/// di arrivare al tasto giusto.
class ChannelKeypad extends StatefulWidget {
  const ChannelKeypad({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<ChannelKeypad> createState() => _ChannelKeypadState();
}

class _ChannelKeypadState extends State<ChannelKeypad> {
  static const _maxDigits = 4;
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
    '✓',
  ];
  static const _ok = 11;

  final _focus = FocusNode(debugLabel: 'keypad');
  String _digits = '';
  int _sel = 4; // il "5" al centro: ogni tasto è a due passi al massimo

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _digit(int d) {
    if (_digits.length >= _maxDigits) return;
    setState(() {
      _digits += '$d';
      // Numero completo: si passa da soli su ✓.
      if (_digits.length == _maxDigits) _sel = _ok;
    });
  }

  void _delete() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  void _confirm() {
    final n = int.tryParse(_digits);
    if (n == null) return;
    if (context.read<TunerController>().tuneNumber(n)) {
      widget.onClose();
    } else {
      // Nessun canale da quel numero in su: si ricomincia.
      setState(() => _digits = '');
    }
  }

  void _press(int i) => switch (_keys[i]) {
    '⌫' => _delete(),
    '✓' => _confirm(),
    final d => _digit(int.parse(d)),
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    // OK ancora tenuto dopo l'apertura: le ripetizioni non premono tasti.
    if (e is KeyRepeatEvent && isSelectKey(k)) return KeyEventResult.handled;
    if (digitForKey(k) case final d?) {
      if (e is KeyDownEvent) _digit(d);
    } else if (k == LogicalKeyboardKey.backspace ||
        k == LogicalKeyboardKey.delete) {
      // Backspace della tastiera cancella; con niente da cancellare chiude.
      _digits.isEmpty ? widget.onClose() : _delete();
    } else if (isBackKey(k)) {
      if (e is KeyDownEvent) widget.onClose();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      setState(() => _sel = _sel % 3 == 0 ? _sel + 2 : _sel - 1);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      setState(() => _sel = _sel % 3 == 2 ? _sel - 2 : _sel + 1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      setState(() => _sel = (_sel - 3) % 12);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      setState(() => _sel = (_sel + 3) % 12);
    } else if (isSelectKey(k)) {
      _press(_sel);
    } else if (k == LogicalKeyboardKey.audioVolumeUp ||
        k == LogicalKeyboardKey.audioVolumeDown ||
        k == LogicalKeyboardKey.audioVolumeMute) {
      // Il volume resta al player (o al sistema).
      return KeyEventResult.ignored;
    }
    // Tutto il resto si ferma qui: niente zapping mentre si digita.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final margin = MediaQuery.sizeOf(context).width < 760 ? 12.0 : 32.0;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.all(margin),
          child: Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NumberEntry(digits: _digits),
                  const SizedBox(height: 12),
                  Glass(
                    radius: 26,
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.6,
                          children: [
                            for (var i = 0; i < _keys.length; i++)
                              PadKey(
                                label: _keys[i],
                                focused: i == _sel,
                                onTap: () {
                                  setState(() => _sel = i);
                                  _press(i);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Wrap(
                          spacing: 16,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            KeyHint('✓', 'Vai al canale'),
                            KeyHint('Indietro', 'Chiudi'),
                          ],
                        ),
                      ],
                    ),
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
