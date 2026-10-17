import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/recording_provider.dart';
import '../theme/app_theme.dart';

enum CaptureSourceMode { entireScreen, activeWindow, specificApp }

class RecordSetupSheet extends StatefulWidget {
  final Future<void> Function() onStart;

  const RecordSetupSheet({
    super.key,
    required this.onStart,
  });

  static Future<void> show(
    BuildContext context, {
    required Future<void> Function() onStart,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecordSetupSheet(onStart: onStart),
    );
  }

  @override
  State<RecordSetupSheet> createState() => _RecordSetupSheetState();
}

class _RecordSetupSheetState extends State<RecordSetupSheet> {
  CaptureSourceMode _sourceMode = CaptureSourceMode.entireScreen;
  bool _cameraBubble = false;
  bool _countdown = true;
  double _mockMicLevel = 0.35;
  Timer? _micLevelTimer;

  @override
  void initState() {
    super.initState();
    _startMicLevelAnimation();
  }

  void _startMicLevelAnimation() {
    _micLevelTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (mounted) {
        setState(() {
          _mockMicLevel = 0.2 + Random().nextDouble() * 0.65;
        });
      }
    });
  }

  @override
  void dispose() {
    _micLevelTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordingProv = context.watch<RecordingProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: AppTheme.border),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Record Setup',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Capture Source
          Text(
            'CAPTURE SOURCE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildSourceChip(
                mode: CaptureSourceMode.entireScreen,
                label: 'Entire Screen',
                icon: Icons.fullscreen_rounded,
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 8),
              _buildSourceChip(
                mode: CaptureSourceMode.activeWindow,
                label: 'Window',
                icon: Icons.crop_landscape_rounded,
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 8),
              _buildSourceChip(
                mode: CaptureSourceMode.specificApp,
                label: 'App',
                icon: Icons.apps_rounded,
                colorScheme: colorScheme,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Microphone audio toggle & Level meter
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            recordingProv.isAudioEnabled
                                ? Icons.mic_rounded
                                : Icons.mic_off_rounded,
                            size: 20,
                            color: recordingProv.isAudioEnabled
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Microphone Audio',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                recordingProv.isAudioEnabled
                                    ? 'Active · Default Device'
                                    : 'Muted',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Switch.adaptive(
                        value: recordingProv.isAudioEnabled,
                        onChanged: recordingProv.toggleAudio,
                      ),
                    ],
                  ),
                  if (recordingProv.isAudioEnabled) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: _mockMicLevel,
                        minHeight: 4,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Camera Bubble Toggle
          _buildToggleRow(
            icon: Icons.videocam_rounded,
            title: 'Camera Bubble',
            subtitle: 'Draggable picture-in-picture circle',
            value: _cameraBubble,
            colorScheme: colorScheme,
            onChanged: (val) => setState(() => _cameraBubble = val),
          ),
          const SizedBox(height: 10),

          // 3-2-1 Countdown Toggle
          _buildToggleRow(
            icon: Icons.timer_outlined,
            title: '3-2-1 Countdown',
            subtitle: 'Prepare your workspace before capture',
            value: _countdown,
            colorScheme: colorScheme,
            onChanged: (val) => setState(() => _countdown = val),
          ),
          const SizedBox(height: 20),

          // Start Button (Matching Primary Button)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: Container(
              decoration: BoxDecoration(
                gradient: AppTheme.recordGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.recordRed.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                key: const ValueKey('start_recording_sheet_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.fiber_manual_record_rounded, size: 20),
                label: const Text(
                  'Start Recording',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  await widget.onStart();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceChip({
    required CaptureSourceMode mode,
    required String label,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _sourceMode == mode;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _sourceMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ColorScheme colorScheme,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: value ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
