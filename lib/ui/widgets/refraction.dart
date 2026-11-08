// ignore_for_file: prefer_initializing_formals

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Rifrazione reale per il vetro crystal: uno shader legge ciò che sta
/// dietro la lastra e lo devia come farebbe un vetro spesso con i bordi
/// arrotondati. Funziona solo con Impeller; altrove resta il crystal dipinto.
abstract final class GlassShader {
  static ui.FragmentProgram? _program;

  static bool get available =>
      _program != null && ui.ImageFilter.isShaderFilterSupported;

  static Future<void> load() async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/glass.frag');
    } catch (_) {
      _program = null;
    }
  }

  static ui.FragmentShader? create() => _program?.fragmentShader();
}

class RefractiveBackdrop extends SingleChildRenderObjectWidget {
  const RefractiveBackdrop({
    super.key,
    required this.enabled,
    required this.radius,
    this.density = 0,
    super.child,
  });

  final bool enabled;
  final double radius;

  /// 0 = lastra leggera, 1 = pannello con molto testo (vetro più scuro).
  final double density;

  @override
  RenderRefractiveBackdrop createRenderObject(BuildContext context) =>
      RenderRefractiveBackdrop(
        enabled: enabled,
        radius: radius,
        density: density,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRefractiveBackdrop renderObject,
  ) {
    renderObject
      ..enabled = enabled
      ..radius = radius
      ..density = density;
  }
}

class RenderRefractiveBackdrop extends RenderProxyBox {
  RenderRefractiveBackdrop({
    required bool enabled,
    required double radius,
    required double density,
  }) : _enabled = enabled,
       _radius = radius,
       _density = density;

  double _density;
  set density(double v) {
    if (v == _density) return;
    _density = v;
    markNeedsPaint();
  }

  /// Ultima posizione disegnata (pixel fisici). Se la lastra si sposta per
  /// una trasformazione dei genitori (animazioni di entrata) il disegno non
  /// viene rifatto da solo: dopo ogni fotogramma si controlla e si ridisegna.
  Rect? _painted;
  bool _watching = false;

  Rect _globalRect() {
    final dpr =
        ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1;
    final tl = localToGlobal(Offset.zero) * dpr;
    final br = localToGlobal(size.bottomRight(Offset.zero)) * dpr;
    return Rect.fromPoints(tl, br);
  }

  void _watch() {
    if (_watching) return;
    _watching = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _watching = false;
      if (!attached || !_enabled || !GlassShader.available) return;
      if (_globalRect() != _painted) markNeedsPaint();
      _watch();
    });
  }

  bool _enabled;
  set enabled(bool v) {
    if (v == _enabled) return;
    _enabled = v;
    markNeedsPaint();
  }

  double _radius;
  set radius(double v) {
    if (v == _radius) return;
    _radius = v;
    markNeedsPaint();
  }

  ui.FragmentShader? _shader;
  final LayerHandle<BackdropFilterLayer> _layer = LayerHandle();

  @override
  bool get alwaysNeedsCompositing => _enabled && GlassShader.available;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_enabled || !GlassShader.available) {
      _layer.layer = null;
      super.paint(context, offset);
      return;
    }
    final shader = _shader ??= GlassShader.create()!;
    final g = _painted = _globalRect();
    // Scala logico → fisico (comprende la riduzione dell'interfaccia su TV).
    final k = size.width > 0 ? g.width / size.width : 1.0;
    shader
      ..setFloat(2, g.left)
      ..setFloat(3, g.top)
      ..setFloat(4, g.width)
      ..setFloat(5, g.height)
      ..setFloat(6, _radius * k)
      ..setFloat(7, math.min(_radius * 1.4, 36) * k)
      ..setFloat(8, _density);
    _watch();
    final layer = _layer.layer ??= BackdropFilterLayer();
    layer.filter = ui.ImageFilter.shader(shader);
    context.pushLayer(layer, super.paint, offset);
  }

  @override
  void dispose() {
    _layer.layer = null;
    _shader?.dispose();
    super.dispose();
  }
}
