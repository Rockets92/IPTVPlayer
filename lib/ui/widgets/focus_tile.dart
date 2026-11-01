import 'package:flutter/material.dart';
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
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        widget.onFocusChange?.call(f);
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
          child: CustomPaint(
            foregroundPainter: _focused
                ? GlassEdgePainter(
                    radius: widget.radius,
                    accent: Palette.accent.withValues(alpha: 0.85),
                  )
                : (active
                      ? GlassEdgePainter(radius: widget.radius, intensity: 0.5)
                      : null),
            child: AnimatedContainer(
              duration: perf.fast,
              curve: Curves.easeOutCubic,
              padding: widget.padding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius),
                gradient: _focused
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.20),
                          Colors.white.withValues(alpha: 0.08),
                        ],
                      )
                    : null,
                color: _focused
                    ? null
                    : _hover
                    ? Colors.white.withValues(alpha: 0.07)
                    : widget.selected
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.transparent,
                boxShadow: _focused && !perf.isLight
                    ? [
                        BoxShadow(
                          color: Palette.accent.withValues(alpha: 0.18),
                          blurRadius: 24,
                          spreadRadius: -4,
                        ),
                      ]
                    : null,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
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
