import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/games/bricks_game.dart';
import 'package:iptv_player/ui/games/racer_game.dart';
import 'package:iptv_player/ui/games/space_game.dart';
import 'package:iptv_player/ui/games/sfx.dart';

void main() {
  test('mattoncini: ogni quadro si costruisce e si gioca', () {
    final g = BricksGame()..reset();
    for (var n = 1; n <= BricksGame.stageCount + 1; n++) {
      g.goTo(n);
      expect(g.bricks, isNotEmpty);
      g.onKey(LogicalKeyboardKey.enter);
      for (var i = 0; i < 600 && !g.over; i++) {
        g.update(1 / 60);
        for (final b in g.balls) {
          expect(b.x, inInclusiveRange(0, BricksGame.w));
        }
      }
    }
  });

  test('corsa notturna: le auto nella stessa corsia non si compenetrano', () {
    final g = RacerGame()..reset();
    for (var i = 0; i < 60 * 120 && !g.over; i++) {
      g.update(1 / 60);
      for (final a in g.cars) {
        for (final b in g.cars) {
          if (identical(a, b) || a.lane != b.lane) continue;
          expect((a.y - b.y).abs(), greaterThanOrEqualTo(16.9));
        }
      }
      // Si scansa sempre: corsia a caso ogni tanto.
      if (i % 40 == 0) {
        g.onKey(
          i.isEven
              ? LogicalKeyboardKey.arrowLeft
              : LogicalKeyboardKey.arrowRight,
        );
      }
    }
    expect(g.engine == null || g.engine! >= 0, isTrue);
  });

  test('astro pattuglia: ondate, nave madre e fine partita', () {
    final g = SpaceGame()..reset();
    final sounds = <Sfx>{};
    g.onSound = sounds.add;
    for (var i = 0; i < 60 * 240 && !g.over; i++) {
      g.update(1 / 60);
      if (i % 300 == 0) g.onKey(LogicalKeyboardKey.enter);
    }
    expect(g.wave, greaterThan(1));
    expect(sounds, contains(Sfx.shoot));
    expect(sounds, contains(Sfx.boom));
  });

  test('il motore è un loop WAV valido', () {
    final w = SfxPlayer.renderEngine();
    expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
    expect(w.length, greaterThan(4000));
  });

  test('mattoncini: la pallina non va mai quasi in orizzontale', () {
    final g = BricksGame()..reset();
    g.onKey(LogicalKeyboardKey.enter);
    // Pallina lanciata quasi in piano: al passo dopo è di nuovo ripida.
    g.balls.first
      ..vx = 100
      ..vy = -2;
    for (var i = 0; i < 60 * 30 && !g.over; i++) {
      g.update(1 / 60);
      for (final b in g.balls) {
        final v = sqrt(b.vx * b.vx + b.vy * b.vy);
        if (v > 0) expect(b.vy.abs() / v, greaterThan(0.39));
      }
    }
  });
}
