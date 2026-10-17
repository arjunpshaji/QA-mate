import 'package:flutter/material.dart';
import '../providers/recording_provider.dart';
import '../theme/app_theme.dart';

class RecordingIndicator extends StatefulWidget {
  final RecordingProvider provider;

  const RecordingIndicator({super.key, required this.provider});

  @override
  State<RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<RecordingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final elapsed = provider.elapsed;
    final isNearLimit = provider.isNearLimit;
    final isCritical = provider.isCriticalLimit;
    final remaining = provider.remainingTime;

    final progressRatio =
        (elapsed.inSeconds / RecordingProvider.maxDuration.inSeconds).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Warning Banner when approaching 5-minute limit
        if (isNearLimit) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isCritical
                  ? AppTheme.recordRed.withValues(alpha: 0.15)
                  : AppTheme.warningAmber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isCritical
                    ? AppTheme.recordRed.withValues(alpha: 0.6)
                    : AppTheme.warningAmber.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: isCritical ? AppTheme.recordRed : AppTheme.warningAmber,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isCritical
                        ? 'Auto-stopping in ${remaining.inSeconds}s!'
                        : 'Nearing 5 min limit (${_formatDuration(remaining)} remaining)',
                    style: TextStyle(
                      color: isCritical ? AppTheme.recordRed : AppTheme.warningAmber,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Main Timer Card with Glassmorphic styling
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isCritical
                  ? AppTheme.recordRed.withValues(alpha: 0.8)
                  : (isNearLimit ? AppTheme.warningAmber : AppTheme.border),
              width: isCritical ? 2.0 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: (isCritical ? AppTheme.recordRed : AppTheme.primary)
                    .withValues(alpha: 0.15),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pulsing Red Dot
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isCritical
                                  ? AppTheme.recordRed
                                  : const Color(0xFFFF334B),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.recordRed.withValues(alpha: 0.7),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 14),

                    // Elapsed Time
                    Text(
                      _formatDuration(elapsed),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        letterSpacing: 1.5,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),

                    // Max Duration Tag
                    const SizedBox(width: 8),
                    Text(
                      '/ ${_formatDuration(RecordingProvider.maxDuration)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Progress Bar towards 5 min limit
              SizedBox(
                width: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progressRatio,
                    minHeight: 5,
                    backgroundColor: AppTheme.border.withValues(alpha: 0.5),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isCritical
                          ? AppTheme.recordRed
                          : (isNearLimit
                              ? AppTheme.warningAmber
                              : AppTheme.cyanAccent),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
