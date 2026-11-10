import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Che tipo di dispositivo è: decide dove ha senso il QR "dallo smartphone".
///
/// - [tv]: Chromecast, Android TV, proiettori, box senza touch. Niente
///   tastiera comoda: il QR è la via principale per scrivere i dati e il
///   telefono è il telecomando migliore.
/// - [phone]: ha già touch e tastiera, il QR non serve (sarebbe il telefono
///   che inquadra sé stesso).
/// - [tablet] e [desktop]: si scrive bene anche lì, ma configurare dal
///   telefono o usarlo come telecomando può far comodo: il QR resta come
///   opzione secondaria, chiusa finché non la si apre.
enum FormFactor {
  tv,
  phone,
  tablet,
  desktop;

  /// Il QR va mostrato subito, in primo piano.
  bool get qrProminent => this == tv;

  /// Il QR non va mostrato per niente.
  bool get hidesQr => this == phone;

  static const _channel = MethodChannel('iptv_player/device');

  /// Forzabile per prove: `--dart-define=FORM_FACTOR=phone`.
  static const _forced = String.fromEnvironment('FORM_FACTOR');

  static Future<FormFactor> resolve() async {
    for (final f in values) {
      if (f.name == _forced) return f;
    }
    if (kIsWeb) return desktop;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return desktop;
    }
    if (Platform.isAndroid) {
      try {
        final info = await _channel.invokeMapMethod<String, Object?>(
          'formFactor',
        );
        if (info != null) {
          final tv =
              info['television'] == true ||
              info['leanback'] == true ||
              info['touchscreen'] == false;
          if (tv) return FormFactor.tv;
          final sw = (info['smallestWidthDp'] as num?)?.toDouble() ?? 0;
          if (sw > 0) return sw >= 600 ? tablet : phone;
        }
      } catch (_) {
        // Canale non disponibile (vecchia build nativa): si va a misura.
      }
    }
    return _bySize();
  }

  /// iOS, o Android senza risposta dal canale: lato corto dello schermo.
  static FormFactor _bySize() {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) return phone;
    final v = views.first;
    final logical = v.physicalSize / v.devicePixelRatio;
    return logical.shortestSide >= 600 ? tablet : phone;
  }
}
