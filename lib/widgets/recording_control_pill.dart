import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/recording_provider.dart';
import '../theme/app_theme.dart';

/// A floating, draggable control pill displaying the active recording status,
/// elapsed timer, pause/resume, audio mute toggle, discard, and finish action.
class RecordingControlPill extends StatefulWidget {
  final RecordingProvider provider;
  final VoidCallback onFinish;
  final VoidCallback onCancel;
  final VoidCallback? onPauseResume;
  final void Function(DragUpdateDetails details)? onPanUpdate;

  const RecordingControlPill({
    super.key,
    required this.provider,
    required this.onFinish,
    required this.onCancel,
    this.onPauseResume,
    this.onPanUpdate,
  });

  @override
  State<RecordingControlPill> createState() => _RecordingControlPillState();
}

class _RecordingControlPillState extends State<RecordingControlPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _handlePauseResume() {
    HapticFeedback.lightImpact();
    if (widget.onPauseResume != null) {
      widget.onPauseResume!();
    } else {
      widget.provider.togglePause();
    }
  }

  void _handleToggleAudio() {
    HapticFeedback.lightImpact();
    widget.provider.toggleAudio(!widget.provider.isAudioEnabled);
  }

  void _handleCancel() {
    HapticFeedback.mediumImpact();
    widget.onCancel();
  }

  void _handleFinish() {
    HapticFeedback.heavyImpact();
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) {
        final elapsedStr = _formatDuration(widget.provider.elapsed);
        final isPaused = widget.provider.status == RecordingStatus.paused;
        final isNearLimit = widget.provider.isNearLimit;
        final isCritical = widget.provider.isCriticalLimit;

        // Visual alert colors for approaching the 5-minute cap
        Color timerColor = Colors.white;
        if (isCritical) {
          timerColor = const Color(0xFFFF4864);
        } else if (isNearLimit || isPaused) {
          timerColor = const Color(0xFFFFB800);
        }

        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            onPanUpdate: widget.onPanUpdate,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF141926).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(9999), // Strict Pill shape
                border: Border.all(
                  color: isCritical
                      ? const Color(0xFFFF4864).withValues(alpha: 0.5)
                      : isNearLimit
                          ? const Color(0xFFFFB800).withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.14),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isCritical
                        ? const Color(0x66FF4864)
                        : Colors.black.withValues(alpha: 0.5),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Drag handle dots
                  const Padding(
                    padding: EdgeInsets.only(right: 6, left: 2),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: Color(0xFF6B7A99),
                      size: 20,
                    ),
                  ),

                  // Pulsing recording indicator dot
                  ScaleTransition(
                    scale: isPaused
                        ? const AlwaysStoppedAnimation(1.0)
                        : _pulseScale,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isPaused
                            ? const Color(0xFFFFB800)
                            : isCritical
                                ? const Color(0xFFFF3B5C)
                                : AppTheme.recordRed,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: isPaused
                                ? const Color(0x99FFB800)
                                : const Color(0x99FF3B5C),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Monospace Tabular Timer
                  Tooltip(
                    message: isPaused
                        ? 'Paused'
                        : '${widget.provider.remainingTime.inMinutes}:${(widget.provider.remainingTime.inSeconds % 60).toString().padLeft(2, '0')} remaining',
                    child: Text(
                      elapsedStr,
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: timerColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Pause / Resume button
                  IconButton(
                    tooltip: isPaused ? 'Resume' : 'Pause',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: Icon(
                      isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      color: isPaused ? const Color(0xFFFFB800) : Colors.white,
                      size: 20,
                    ),
                    onPressed: _handlePauseResume,
                  ),
                  const SizedBox(width: 2),

                  // Mic mute/unmute button
                  IconButton(
                    tooltip: widget.provider.isAudioEnabled ? 'Mute' : 'Unmute',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: Icon(
                      widget.provider.isAudioEnabled
                          ? Icons.mic_rounded
                          : Icons.mic_off_rounded,
                      color: widget.provider.isAudioEnabled
                          ? Colors.white
                          : AppTheme.recordRed,
                      size: 20,
                    ),
                    onPressed: _handleToggleAudio,
                  ),
                  const SizedBox(width: 2),

                  // Discard / Cancel button
                  IconButton(
                    tooltip: 'Discard',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF909EB4),
                      size: 20,
                    ),
                    onPressed: _handleCancel,
                  ),
                  const SizedBox(width: 6),

                  // Stop / Finish button
                  GestureDetector(
                    key: const ValueKey('pill_finish_btn'),
                    onTap: _handleFinish,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.recordRed,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.recordRed.withValues(alpha: 0.45),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
