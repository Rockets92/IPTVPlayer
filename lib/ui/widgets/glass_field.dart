import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import 'glass.dart';

/// Campo di testo coerente con il vetro: etichetta sopra, focus luminoso.
class GlassField extends StatefulWidget {
  const GlassField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.focusNode,
    this.autofillHints,
    this.enabled = true,
  });

  final String label;
  final String? hint;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final FocusNode? focusNode;
  final Iterable<String>? autofillHints;
  final bool enabled;

  @override
  State<GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<GlassField> {
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  bool _focused = false;
  late bool _obscured = widget.obscure;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  void _onFocus() => setState(() => _focused = _node.hasFocus);

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: AnimatedDefaultTextStyle(
            duration: perf.fast,
            style: AppText.overline.copyWith(
              color: _focused ? Palette.accent : Palette.textTertiary,
            ),
            child: Text(widget.label.toUpperCase()),
          ),
        ),
        AnimatedContainer(
          duration: perf.fast,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: _focused ? 0.10 : 0.055),
            boxShadow: _focused && !perf.isLight
                ? [
                    BoxShadow(
                      color: Palette.accent.withValues(alpha: 0.16),
                      blurRadius: 22,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: CustomPaint(
            foregroundPainter: GlassEdgePainter(
              radius: 14,
              intensity: 0.55,
              accent: _focused ? Palette.accent.withValues(alpha: 0.8) : null,
            ),
            child: Row(
              children: [
                Expanded(
                  // Col telecomando su/giù passano al campo vicino invece di
                  // muovere il cursore (i campi sono su una riga sola).
                  child: Shortcuts(
                    shortcuts: const {
                      SingleActivator(LogicalKeyboardKey.arrowDown):
                          NextFocusIntent(),
                      SingleActivator(LogicalKeyboardKey.arrowUp):
                          PreviousFocusIntent(),
                    },
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _node,
                      enabled: widget.enabled,
                      autofocus: widget.autofocus,
                      obscureText: _obscured,
                      keyboardType: widget.keyboardType,
                      textInputAction: widget.textInputAction,
                      onSubmitted: widget.onSubmitted,
                      onChanged: widget.onChanged,
                      autofillHints: widget.autofillHints,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: AppText.headline.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      cursorWidth: 2,
                      cursorRadius: const Radius.circular(2),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: widget.hint,
                        hintStyle: AppText.headline.copyWith(
                          fontWeight: FontWeight.w400,
                          color: Palette.textTertiary,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 17,
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.obscure)
                  // Il tasto "mostra" non entra nella navigazione col
                  // telecomando: si passa dalla password al pulsante.
                  ExcludeFocus(
                    child: IconButton(
                      tooltip: _obscured ? 'Mostra' : 'Nascondi',
                      onPressed: () => setState(() => _obscured = !_obscured),
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: Palette.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Pulsante primario: vetro chiaro con accento, stato di caricamento.
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.primary = true,
    this.icon,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool primary;
  final IconData? icon;
  final bool autofocus;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _focused = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final enabled = widget.onPressed != null && !widget.busy;
    final lit = _focused || _hover;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      enabled: enabled,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: perf.fast,
          height: 54,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: widget.primary
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: lit
                        ? const [Palette.accent, Palette.magenta]
                        : const [Palette.accent, Palette.violet],
                  )
                : null,
            color: widget.primary
                ? null
                : Colors.white.withValues(alpha: lit ? 0.14 : 0.07),
            boxShadow: widget.primary && !perf.isLight
                ? [
                    BoxShadow(
                      color: Palette.accentDeep.withValues(
                        alpha: lit ? 0.55 : 0.35,
                      ),
                      blurRadius: lit ? 30 : 20,
                      spreadRadius: -6,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
            border: _focused
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.9),
                    width: 2,
                  )
                : null,
          ),
          child: AnimatedOpacity(
            duration: perf.fast,
            opacity: enabled || widget.busy ? 1 : 0.5,
            child: widget.busy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: widget.primary ? Palette.ink : Palette.textPrimary,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          size: 20,
                          color: widget.primary
                              ? Palette.ink
                              : Palette.textPrimary,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        widget.label,
                        style: AppText.headline.copyWith(
                          color: widget.primary
                              ? Palette.ink
                              : Palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
