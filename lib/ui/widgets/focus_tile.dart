import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import 'glass.dart';

/// Tasti che equivalgono a "OK" su telecomando, tastiera e gamepad.
bool isSelectKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.enter ||
    k == LogicalKeyboardKey.numpadEnter ||
    k == LogicalKeyboardKey.select ||
    k == LogicalKeyboardKey.space ||
    k == LogicalKeyboardKey.gameButtonA;

bool isBackKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.escape ||
    k == LogicalKeyboardKey.goBack ||
    k == LogicalKeyboardKey.browserBack ||
    k == LogicalKeyboardKey.backspace ||
    k == LogicalKeyboardKey.gameButtonB;

/// Fa scorrere la lista che contiene [context] perché l'elemento resti ad
/// almeno [margin] dai bordi visibili.
void revealWithMargin(BuildContext context, double margin) {
  final box = context.findRenderObject();
  final pos = Scrollable.maybeOf(context)?.position;
  if (box == null || pos == null || !box.attached) return;
  final vp = RenderAbstractViewport.maybeOf(box);
  if (vp == null) return;
  final atTop = vp.getOffsetToReveal(box, 0).offset;
  final atBottom = vp.getOffsetToReveal(box, 1).offset;
  double? target;
  if (pos.pixels > atTop - margin) {
    target = atTop - margin;
  } else if (pos.pixels < atBottom + margin) {
    target = atBottom + margin;
  }
  if (target == null) return;
  target = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
  if ((target - pos.pixels).abs() < 1) return;
  final light = context.read<PerformanceProfile>().isLight;
  if (light) {
    pos.jumpTo(target);
  } else {
    pos.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }
}

/// Elemento selezionabile con D-pad, mouse e tocco, con stato di focus
/// evidente da 3 metri (proiettore) ma discreto.
class FocusTile extends StatefulWidget {
  const FocusTile({
    super.key,
    required this.child,
    this.onSelect,
    this.focusNode,
    this.autofocus = false,
    this.radius = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.selected = false,
    this.onFocusChange,
    this.revealMargin,
  });

  final Widget child;
  final VoidCallback? onSelect;
  final FocusNode? focusNode;
  final bool autofocus;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Evidenzia l'elemento come "attivo" (es. canale in visione).
  final bool selected;
  final ValueChanged<bool>? onFocusChange;

  /// Se impostato, la lista scorre per lasciare almeno questo spazio tra la
  /// voce col focus e i bordi, invece di fermarla a filo del bordo.
  final double? revealMargin;

  @override
  State<FocusTile> createState() => _FocusTileState();
}

class _FocusTileState extends State<FocusTile> {
  bool _focused = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final active = _focused || _hover;
    // Sul profilo leggero niente dissolvenza: il focus salta e basta.
    final duration = perf.isLight
        ? Duration.zero
        : const Duration(milliseconds: 110);
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        widget.onFocusChange?.call(f);
        final m = widget.revealMargin;
        if (f && m != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) revealWithMargin(context, m);
          });
        }
      },
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && isSelectKey(e.logicalKey)) {
          widget.onSelect?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: widget.onSelect == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelect,
          // Sfondo e contorno del focus sono un unico strato che appare e
          // scompare insieme: prima il contorno saltava subito sulla voce
          // nuova mentre lo sfondo sfumava, lasciando un alone in ritardo.
          child: Stack(
            children: [
              if (widget.selected && !active)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.radius),
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
              Positioned.fill(
                child: _Layer(
                  visible: _hover && !_focused,
                  duration: duration,
                  child: CustomPaint(
                    foregroundPainter: GlassEdgePainter(
                      radius: widget.radius,
                      intensity: 0.5,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.radius),
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: _Layer(
                  visible: _focused,
                  duration: duration,
                  child: CustomPaint(
                    foregroundPainter: GlassEdgePainter(
                      radius: widget.radius,
                      accent: Palette.accent.withValues(alpha: 0.85),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.radius),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.20),
                            Colors.white.withValues(alpha: 0.08),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(padding: widget.padding, child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Strato che compare e scompare in dissolvenza, tutto insieme.
class _Layer extends StatelessWidget {
  const _Layer({
    required this.visible,
    required this.duration,
    required this.child,
  });

  final bool visible;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: duration == Duration.zero
        ? Visibility.maintain(visible: visible, child: child)
        : AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: child,
          ),
  );
}

/// Tasto stilizzato per i suggerimenti ("OK", "G", "↑↓").
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.white.withValues(alpha: 0.10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: AppText.overline.copyWith(
          letterSpacing: 0.4,
          color: Palette.textSecondary,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

class KeyHint extends StatelessWidget {
  const KeyHint(this.keyLabel, this.text, {super.key});
  final String keyLabel;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyCap(keyLabel),
        const SizedBox(width: 7),
        Text(text, style: AppText.label.copyWith(color: Palette.textTertiary)),
      ],
    );
  }
}
