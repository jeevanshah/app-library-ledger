import 'package:flutter/material.dart';

/// Subtle press feedback: scales the child down while pressed and springs
/// back on release. Uses a [Listener] rather than a gesture recogniser, so
/// it never competes with the child's own tap handling.
class PressableScale extends StatefulWidget {
  final Widget child;
  final double scale;

  const PressableScale({super.key, required this.child, this.scale = 0.92});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
