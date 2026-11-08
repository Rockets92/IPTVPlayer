import 'package:flutter/material.dart';

/// Stile delle lastre di vetro.
///
/// - `classic`: vetro lucido con sfocatura dello sfondo (liquid glass).
/// - `crystal`: vetro supertrasparente senza sfocatura, come una goccia
///   d'acqua: lo sfondo resta nitido e la lastra si legge solo dai riflessi,
///   dal menisco scuro lungo i bordi e dalla luce che si concentra sul lato
///   opposto. I testi ricevono un alone scuro per restare leggibili su
///   qualsiasi immagine.
enum GlassLook { classic, crystal }

/// Stile corrente, letto dal tema: cambiare il tema ridisegna tutto.
@immutable
class GlassLookTheme extends ThemeExtension<GlassLookTheme> {
  const GlassLookTheme(this.look);

  final GlassLook look;

  bool get crystal => look == GlassLook.crystal;

  static GlassLook of(BuildContext context) =>
      Theme.of(context).extension<GlassLookTheme>()?.look ?? GlassLook.classic;

  /// Alone per i testi sul vetro crystal: un contorno scuro stretto che
  /// stacca ogni lettera, più un'ombra morbida che crea un piccolo fondo
  /// locale sotto le parole senza velare la lastra.
  static const List<Shadow> textShadows = [
    Shadow(color: Color(0xF2000000), blurRadius: 1, offset: Offset(0, 0.5)),
    Shadow(color: Color(0xCC000000), blurRadius: 3),
    Shadow(color: Color(0x8C000000), blurRadius: 10),
  ];

  @override
  GlassLookTheme copyWith({GlassLook? look}) =>
      GlassLookTheme(look ?? this.look);

  @override
  GlassLookTheme lerp(GlassLookTheme? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// Ricostruisce tutta l'interfaccia dopo un cambio di stile: molti widget
/// leggono i colori della palette nel proprio build e non dipendono dal tema.
void rebuildAllWidgets() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(mark);
  });
}
