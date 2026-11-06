import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Tasti del telecomando sullo smartphone → tasti dell'app.
///
/// Si passa per il focus come un tasto vero, così ogni schermata (elenco,
/// guida, impostazioni, PIN, promemoria) reagisce come col telecomando fisico.
const remoteKeys = <String, LogicalKeyboardKey>{
  'up': LogicalKeyboardKey.arrowUp,
  'down': LogicalKeyboardKey.arrowDown,
  'left': LogicalKeyboardKey.arrowLeft,
  'right': LogicalKeyboardKey.arrowRight,
  'ok': LogicalKeyboardKey.enter,
  'back': LogicalKeyboardKey.escape,
  'chup': LogicalKeyboardKey.channelUp,
  'chdown': LogicalKeyboardKey.channelDown,
  'volup': LogicalKeyboardKey.audioVolumeUp,
  'voldown': LogicalKeyboardKey.audioVolumeDown,
  'mute': LogicalKeyboardKey.audioVolumeMute,
  'info': LogicalKeyboardKey.keyI,
  'list': LogicalKeyboardKey.keyL,
  'guide': LogicalKeyboardKey.keyG,
  'menu': LogicalKeyboardKey.keyM,
  'source': LogicalKeyboardKey.keyS,
  'prev': LogicalKeyboardKey.keyP,
  'fullscreen': LogicalKeyboardKey.keyF,
  // Sezioni: schermata "Cosa guardiamo?", Film, Serie, Giochi.
  'home': LogicalKeyboardKey.keyH,
  'movies': LogicalKeyboardKey.keyV,
  'series': LogicalKeyboardKey.keyT,
  'games': LogicalKeyboardKey.keyJ,
  // Riproduzione di film ed episodi.
  'playpause': LogicalKeyboardKey.mediaPlayPause,
  'rew': LogicalKeyboardKey.mediaRewind,
  'ffwd': LogicalKeyboardKey.mediaFastForward,
  'stop': LogicalKeyboardKey.mediaStop,
  'audio': LogicalKeyboardKey.keyA,
  'red': LogicalKeyboardKey.colorF0Red,
  'green': LogicalKeyboardKey.colorF1Green,
  'yellow': LogicalKeyboardKey.colorF2Yellow,
  'blue': LogicalKeyboardKey.colorF3Blue,
  '0': LogicalKeyboardKey.digit0,
  '1': LogicalKeyboardKey.digit1,
  '2': LogicalKeyboardKey.digit2,
  '3': LogicalKeyboardKey.digit3,
  '4': LogicalKeyboardKey.digit4,
  '5': LogicalKeyboardKey.digit5,
  '6': LogicalKeyboardKey.digit6,
  '7': LogicalKeyboardKey.digit7,
  '8': LogicalKeyboardKey.digit8,
  '9': LogicalKeyboardKey.digit9,
};

/// Consegna il tasto al widget che ha il focus, risalendo fino a chi lo
/// gestisce, come fa Flutter con la tastiera.
bool dispatchRemoteKey(String name) {
  final key = remoteKeys[name];
  if (key == null) return false;
  final event = KeyDownEvent(
    physicalKey: const PhysicalKeyboardKey(0),
    logicalKey: key,
    timeStamp: Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
    ),
  );
  FocusNode? node =
      FocusManager.instance.primaryFocus ?? FocusManager.instance.rootScope;
  while (node != null) {
    final r = node.onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
    if (r == KeyEventResult.handled) return true;
    if (r == KeyEventResult.skipRemainingHandlers) return false;
    node = node.parent;
  }
  return false;
}
