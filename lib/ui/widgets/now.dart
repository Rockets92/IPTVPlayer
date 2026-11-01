import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';

/// Ricostruisce il figlio allo scoccare di ogni minuto (orologio, avanzamento).
class NowBuilder extends StatefulWidget {
  const NowBuilder({
    super.key,
    required this.builder,
    this.everySecond = false,
  });

  final Widget Function(BuildContext context, DateTime now) builder;

  /// Aggiornamento più fitto (barra di avanzamento nel banner).
  final bool everySecond;

  @override
  State<NowBuilder> createState() => _NowBuilderState();
}

class _NowBuilderState extends State<NowBuilder> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final light = context.read<PerformanceProfile>().isLight;
    final now = DateTime.now();
    final Duration wait;
    if (widget.everySecond && !light) {
      wait = Duration(milliseconds: 1000 - now.millisecond);
    } else {
      wait = Duration(seconds: 60 - now.second, milliseconds: -now.millisecond);
    }
    _timer = Timer(wait, () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}
