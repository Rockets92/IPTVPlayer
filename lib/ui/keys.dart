import 'package:flutter/services.dart';

const _row = [
  LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];
const _pad = [
  LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];

/// Cifra associata al tasto (tastiera, tastierino, telecomando), o null.
int? digitForKey(LogicalKeyboardKey k) {
  final a = _row.indexOf(k);
  if (a >= 0) return a;
  final b = _pad.indexOf(k);
  return b >= 0 ? b : null;
}
