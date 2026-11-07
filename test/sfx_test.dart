import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/games/sfx.dart';

void main() {
  test('ogni suono è un WAV 8 bit valido e breve', () {
    final dir = Platform.environment['SFX_OUT'];
    for (final s in Sfx.values) {
      final w = SfxPlayer.render(s);
      expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(w.sublist(8, 12)), 'WAVE');
      final seconds = (w.length - 44) / 22050;
      expect(seconds, greaterThan(0.02));
      expect(seconds, lessThan(2.5));
      if (dir != null) File('$dir/${s.name}.wav').writeAsBytesSync(w);
    }
  });
}
