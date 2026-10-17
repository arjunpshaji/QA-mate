import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Radial dial painter that renders tick marks around the hero record button.
class ReelDialTicksPainter extends CustomPainter {
  final Color tickColor;
  final int tickCount;
  final double progress; // 0.0 to 1.0 (can animate during recording or countdown)
  final Color activeTickColor;

  const ReelDialTicksPainter({
    this.tickColor = AppTheme.dialTick,
    this.activeTickColor = AppTheme.recordRed,
    this.tickCount = 48,
    this.progress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 2;
    final innerRadius = outerRadius - 9;

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0;

    for (int i = 0; i < tickCount; i++) {
      final angle = (i * 2 * math.pi / tickCount) - (math.pi / 2);
      final isMajor = i % 4 == 0;
      final currentInnerRadius = isMajor ? innerRadius - 3 : innerRadius;

      final startX = center.dx + currentInnerRadius * math.cos(angle);
      final startY = center.dy + currentInnerRadius * math.sin(angle);
      final endX = center.dx + outerRadius * math.cos(angle);
      final endY = center.dy + outerRadius * math.sin(angle);

      final activeRatio = i / tickCount;
      if (progress > 0 && activeRatio <= progress) {
        paint.color = activeTickColor;
      } else {
        paint.color = tickColor.withValues(alpha: isMajor ? 0.75 : 0.45);
      }

      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ReelDialTicksPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.tickColor != tickColor ||
        oldDelegate.activeTickColor != activeTickColor;
  }
}

/// Hero Record Button featuring the glowing coral gradient and surrounding dial ticks.
class ReelRecordButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isRecording;
  final double size;

  const ReelRecordButton({
    super.key,
    required this.onTap,
    this.isRecording = false,
    this.size = 220,
  });

  @override
  State<ReelRecordButton> createState() => _ReelRecordButtonState();
}

class _ReelRecordButtonState extends State<ReelRecordButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _pulseScale = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isRecording) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ReelRecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double buttonDiameter = widget.size * 0.78;

    return Center(
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer Radial Ticks
                CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: ReelDialTicksPainter(
                    progress: widget.isRecording ? 1.0 : 0.0,
                  ),
                ),

                // Subtle Radial Ambient Glow
                Container(
                  width: buttonDiameter + 24,
                  height: buttonDiameter + 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.recordRed.withValues(alpha: 0.22),
                        blurRadius: 36,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),

                // Center Glowing Record Disk
                ScaleTransition(
                  scale: _pulseScale,
                  child: Container(
                    width: buttonDiameter,
                    height: buttonDiameter,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(-0.2, -0.3),
                        radius: 0.85,
                        colors: [
                          Color(0xFFFF526F),
                          Color(0xFFFF3B5C),
                          Color(0xFFDC2446),
                        ],
                        stops: [0.0, 0.55, 1.0],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE02A4C).withValues(alpha: 0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      widget.isRecording ? 'Stop' : 'Record',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.4,
                        shadows: [
                          Shadow(
                            color: Color(0x66000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
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
