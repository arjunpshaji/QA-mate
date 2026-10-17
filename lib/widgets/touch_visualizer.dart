import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/recording_provider.dart';
import '../theme/app_theme.dart';

/// Wraps child widget and visibly renders touch circles under fingers
/// when "Show Touch" is enabled in RecordingProvider.
class TouchVisualizer extends StatefulWidget {
  final Widget child;

  const TouchVisualizer({
    super.key,
    required this.child,
  });

  @override
  State<TouchVisualizer> createState() => _TouchVisualizerState();
}

class _TouchVisualizerState extends State<TouchVisualizer> {
  final Map<int, Offset> _pointers = {};

  void _onPointerDown(PointerDownEvent event) {
    setState(() {
      _pointers[event.pointer] = event.position;
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointers.containsKey(event.pointer)) {
      setState(() {
        _pointers[event.pointer] = event.position;
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    setState(() {
      _pointers.remove(event.pointer);
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    setState(() {
      _pointers.remove(event.pointer);
    });
  }

  @override
  Widget build(BuildContext context) {
    RecordingProvider? provider;
    try {
      provider = Provider.of<RecordingProvider?>(context, listen: true);
    } catch (_) {
      provider = null;
    }

    final isShowTouches = provider?.isShowTouchesEnabled ?? false;

    if (!isShowTouches) {
      return widget.child;
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_pointers.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('touch_visualizer_painter'),
                  painter: _TouchIndicatorPainter(
                    pointerPositions: _pointers.values.toList(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TouchIndicatorPainter extends CustomPainter {
  final List<Offset> pointerPositions;

  _TouchIndicatorPainter({required this.pointerPositions});

  @override
  void paint(Canvas canvas, Size size) {
    for (final pos in pointerPositions) {
      // Outer glow ring
      final glowPaint = Paint()
        ..color = AppTheme.cyanAccent.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 28, glowPaint);

      // Inner translucent bubble
      final bubblePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 20, bubblePaint);

      // Accent border ring
      final borderPaint = Paint()
        ..color = AppTheme.cyanAccent.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(pos, 20, borderPaint);

      // Center pinpoint indicator
      final centerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 4.5, centerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TouchIndicatorPainter oldDelegate) {
    return true;
  }
}
