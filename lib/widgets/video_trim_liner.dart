import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class VideoTrimLiner extends StatelessWidget {
  final Duration totalDuration;
  final Duration trimStart;
  final Duration trimEnd;
  final ValueChanged<Duration> onTrimStartChanged;
  final ValueChanged<Duration> onTrimEndChanged;
  final VoidCallback onReset;
  final bool isPlaying;
  final Duration? currentPosition;
  final VoidCallback? onPlayPause;
  final ValueChanged<Duration>? onSeek;

  const VideoTrimLiner({
    super.key,
    required this.totalDuration,
    required this.trimStart,
    required this.trimEnd,
    required this.onTrimStartChanged,
    required this.onTrimEndChanged,
    required this.onReset,
    this.isPlaying = false,
    this.currentPosition,
    this.onPlayPause,
    this.onSeek,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTotalDuration = totalDuration.inMilliseconds > 0
        ? totalDuration
        : const Duration(seconds: 5);

    final isTrimmed = trimStart > Duration.zero || trimEnd < effectiveTotalDuration;
    final selectedDuration = (trimEnd - trimStart).isNegative
        ? Duration.zero
        : (trimEnd - trimStart);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isTrimmed
              ? AppTheme.cyanAccent.withValues(alpha: 0.5)
              : AppTheme.border,
          width: isTrimmed ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: (isTrimmed ? AppTheme.cyanAccent : AppTheme.primary)
                .withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with Duration, Play Cut Button & Reset
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 10,
            spacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.cyanAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.content_cut_rounded,
                      color: AppTheme.cyanAccent,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Trim Video Range',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Play Trimmed Section Button
                    if (onPlayPause != null) ...[
                      GestureDetector(
                        onTap: onPlayPause,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isPlaying
                                  ? [AppTheme.recordRed, const Color(0xFFDC2626)]
                                  : [AppTheme.cyanAccent, AppTheme.primary],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: (isPlaying
                                        ? AppTheme.recordRed
                                        : AppTheme.cyanAccent)
                                    .withValues(alpha: 0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isPlaying ? 'Pause' : 'Play Trim',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // Selected duration badge
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text(
                        'Cut: ${_formatDuration(selectedDuration)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.cyanAccent,
                        ),
                      ),
                    ),
                    if (isTrimmed) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onReset,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.border.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Reset',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Timeline Trimmer Slider with Filmstrip & Playhead
          LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              final totalMs = effectiveTotalDuration.inMilliseconds.toDouble();

              final startFrac = (trimStart.inMilliseconds / totalMs).clamp(0.0, 1.0);
              final endFrac = (trimEnd.inMilliseconds / totalMs).clamp(0.0, 1.0);

              const handleWidth = 20.0;
              final usableWidth = (trackWidth - (handleWidth * 2)).clamp(1.0, double.infinity);

              final startX = startFrac * usableWidth;
              final endX = endFrac * usableWidth + handleWidth;

              // Playhead position
              final currentMs = currentPosition?.inMilliseconds.toDouble() ??
                  trimStart.inMilliseconds.toDouble();
              final posFrac = (currentMs / totalMs).clamp(0.0, 1.0);
              final needleX = (posFrac * usableWidth) + (handleWidth / 2);

              return Column(
                children: [
                  SizedBox(
                    height: 54,
                    child: GestureDetector(
                      key: const ValueKey('trim_timeline_slider'),
                      behavior: HitTestBehavior.translucent,
                      onTap: () {},
                      onTapDown: (details) {
                        if (onSeek == null) return;
                        final localX = details.localPosition.dx;
                        final frac = ((localX - handleWidth) / usableWidth)
                            .clamp(0.0, 1.0);
                        final targetMs = (frac * totalMs).toInt();
                        onSeek!(Duration(milliseconds: targetMs));
                      },
                      child: Stack(
                        children: [
                          // Background Filmstrip Track
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: CustomPaint(
                                painter: _FilmstripPainter(),
                              ),
                            ),
                          ),

                          // Dimmed Left Region (before start)
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: startX + handleWidth,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(10),
                                ),
                              ),
                            ),
                          ),

                          // Dimmed Right Region (after end)
                          Positioned(
                            left: endX,
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: const BorderRadius.horizontal(
                                  right: Radius.circular(10),
                                ),
                              ),
                            ),
                          ),

                          // Active Glowing Selection Area
                          Positioned(
                            left: startX,
                            width: ((endX + handleWidth) - startX)
                                .clamp(handleWidth * 2, trackWidth),
                            top: 0,
                            bottom: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppTheme.cyanAccent,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),

                          // Playhead Needle
                          if (currentPosition != null)
                            Positioned(
                              left: needleX.clamp(0.0, trackWidth - 3),
                              top: 0,
                              bottom: 0,
                              width: 3,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.cyanAccent.withValues(alpha: 0.8),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Left Trim Handle (Start)
                          Positioned(
                            left: startX,
                            top: 0,
                            bottom: 0,
                            width: handleWidth,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (details) {
                                final newPixel = (startX + details.delta.dx)
                                    .clamp(0.0, endX - handleWidth - 10);
                                final newFrac = (newPixel / usableWidth).clamp(0.0, 1.0);
                                final newMs = (newFrac * totalMs).toInt();
                                final target = Duration(milliseconds: newMs);
                                onTrimStartChanged(target);
                                onSeek?.call(target);
                              },
                              child: _buildHandle(
                                isLeft: true,
                                color: AppTheme.cyanAccent,
                              ),
                            ),
                          ),

                          // Right Trim Handle (End)
                          Positioned(
                            left: endX,
                            top: 0,
                            bottom: 0,
                            width: handleWidth,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (details) {
                                final currentRightPixel = endX - handleWidth;
                                final newPixel = (currentRightPixel + details.delta.dx)
                                    .clamp(startX + 10, usableWidth);
                                final newFrac = (newPixel / usableWidth).clamp(0.0, 1.0);
                                final newMs = (newFrac * totalMs).toInt();
                                final target = Duration(milliseconds: newMs);
                                onTrimEndChanged(target);
                                onSeek?.call(target);
                              },
                              child: _buildHandle(
                                isLeft: false,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Bottom Time Labels (Start point vs Current / Total vs End point)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Start: ${_formatDuration(trimStart)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.cyanAccent,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Text(
                          currentPosition != null
                              ? 'Playhead: ${_formatDuration(currentPosition!)}'
                              : 'Total: ${_formatDuration(effectiveTotalDuration)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: currentPosition != null
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: currentPosition != null
                                ? Colors.white
                                : AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Text(
                          'End: ${_formatDuration(trimEnd)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHandle({required bool isLeft, required Color color}) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.horizontal(
          left: isLeft ? const Radius.circular(8) : Radius.zero,
          right: !isLeft ? const Radius.circular(8) : Radius.zero,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _FilmstripPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1.0;

    const spacing = 12.0;
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 10),
        Offset(x, size.height - 10),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
