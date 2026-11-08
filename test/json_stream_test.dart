import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/heavy_work.dart';
import 'package:iptv_player/data/json_utils.dart';

List<Object?> scan(String json) {
  final out = <Object?>[];
  forEachJsonArrayElement(Uint8List.fromList(utf8.encode(json)), out.add);
  return out;
}

void main() {
  test('stesso risultato di jsonDecode, un elemento alla volta', () {
    const json = '''
﻿ [
  {"name": "Rai 1 HEVC ( hermes )", "stream_id": 1, "x": [1, {"a": "]"}]},
  {"name": "Virgolette \\" e graffe } { dentro", "stream_id": "2"},
  {"name": "Città – ü 🎬", "stream_id": 3, "n": null},
  42, "testo, con virgola", true, null, [1, 2]
]''';
    expect(scan(json), jsonDecode(json.replaceFirst('﻿', '')));
  });

  test('array vuoto e documento non array', () {
    expect(scan('[]'), isEmpty);
    expect(scan('  [ ]  '), isEmpty);
    final out = <Object?>[];
    final isList = forEachJsonArrayElement(
      Uint8List.fromList(utf8.encode('{"a": 1}')),
      out.add,
    );
    expect(isList, isFalse);
    expect(out, [
      {'a': 1},
    ]);
  });

  test('JSON troncato o non valido: errore come jsonDecode', () {
    expect(() => scan('[{"a": 1}, {"b": '), throwsFormatException);
    expect(() => scan('[{"a": 1}}'), throwsFormatException);
    expect(() => scan('[{"a": 1},, {"b": 2}]'), throwsFormatException);
  });

  test(
    'HeavyWork in fila: un lavoro alla volta, anche se uno fallisce',
    () async {
      HeavyWork.serialize = true;
      addTearDown(() => HeavyWork.serialize = false);
      var running = 0, peak = 0;
      Future<int> job(int v, {bool fail = false}) => HeavyWork.run(() async {
        running++;
        if (running > peak) peak = running;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
        if (fail) throw StateError('x');
        return v;
      });
      final a = job(1);
      final b = job(2, fail: true);
      final c = job(3);
      expect(await a, 1);
      await expectLater(b, throwsStateError);
      expect(await c, 3);
      expect(peak, 1);
    },
  );
}
