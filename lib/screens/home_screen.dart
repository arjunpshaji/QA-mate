import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/recording_item.dart';
import '../providers/history_provider.dart';
import '../providers/recording_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/recording_control_pill.dart';
import '../widgets/reel_record_button.dart';
import '../widgets/touch_visualizer.dart';
import 'history_screen.dart';
import 'preview_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int _currentTabIndex = 0;
  int? _countdownNumber;
  Timer? _countdownTimer;
  Offset? _pillOffset;

  final List<Color> _accentColors = const [
    Color(0xFF4F6BFF), // Blue
    Color(0xFFFF7A00), // Orange
    Color(0xFF00BA88), // Green
    Color(0xFF9055FF), // Purple
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RecordingProvider>().lastCompletedRecording.addListener(_onRecordingCompletedFromOverlay);
      }
    });
  }

  void _onRecordingCompletedFromOverlay() {
    if (!mounted) return;
    final provider = context.read<RecordingProvider>();
    final item = provider.lastCompletedRecording.value;
    if (item != null) {
      provider.lastCompletedRecording.value = null; // consume event
      context.read<HistoryProvider>().loadHistory();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(recording: item),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    try {
      context.read<RecordingProvider>().lastCompletedRecording.removeListener(_onRecordingCompletedFromOverlay);
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final provider = context.read<RecordingProvider>();
      provider.refreshShowTouches();
      provider.checkPermissions();
    }
  }

  void _startCountdownAndRecord(RecordingProvider provider) {
    final countdown = provider.countdownSeconds;
    if (countdown <= 0) {
      _executeStartRecording(provider);
      return;
    }

    setState(() {
      _countdownNumber = countdown;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_countdownNumber != null && _countdownNumber! > 1) {
          _countdownNumber = _countdownNumber! - 1;
        } else {
          timer.cancel();
          _countdownNumber = null;
          _executeStartRecording(provider);
        }
      });
    });
  }

  Future<void> _executeStartRecording(RecordingProvider provider) async {
    final started = await provider.startRecording();
    if (!started && mounted) {
      if (provider.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage!),
            backgroundColor: AppTheme.recordRed,
          ),
        );
      }
    }
  }

  Future<void> _stopAndNavigate(RecordingProvider provider) async {
    final item = await provider.stopRecording();
    if (item != null && mounted) {
      context.read<HistoryProvider>().loadHistory();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(recording: item),
        ),
      );
    }
  }

  Future<void> _handleToggleShowTouch(
    BuildContext context,
    RecordingProvider provider,
    bool enabled,
  ) async {
    final success = await provider.toggleShowTouches(enabled);
    if (!success && enabled && context.mounted) {
      _showTouchPermissionDialog(context, provider);
    }
  }

  void _showTouchPermissionDialog(
    BuildContext context,
    RecordingProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        title: Row(
          children: const [
            Icon(Icons.touch_app_rounded, color: AppTheme.accentCyan),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Show Touches',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'To display touch circles on the screen across other apps during recording, Android requires permission.\n\n'
          'Option 1: Grant "Modify system settings" permission so Reel can display taps automatically.\n\n'
          'Option 2: Open Android Developer Options and enable "Show taps" manually.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.openDeveloperSettings();
            },
            child: const Text('Developer Options'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.openWriteSettings();
            },
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RecordingProvider>(
      builder: (context, recordingProv, _) {
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Stack(
            children: [
              // Main Tab Content
              IndexedStack(
                index: _currentTabIndex,
                children: [
                  _buildRecordTab(context, recordingProv),
                  const HistoryScreen(isTab: true),
                  const SettingsScreen(isTab: true),
                ],
              ),

              // Countdown Overlay
              if (_countdownNumber != null)
                Container(
                  color: Colors.black.withValues(alpha: 0.8),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_countdownNumber',
                          style: const TextStyle(
                            fontSize: 110,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Get ready to record...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Active Recording Overlay HUD
              if (recordingProv.isRecording)
                _buildActiveRecordingOverlay(context, recordingProv),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(),
        );
      },
    );
  }

  Widget _buildRecordTab(BuildContext context, RecordingProvider provider) {
    return SafeArea(
      child: Column(
        children: [
          // Reel Header & Storage Pill
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Reel. Logo
                RichText(
                  text: const TextSpan(
                    text: 'Reel',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.6,
                    ),
                    children: [
                      TextSpan(
                        text: '.',
                        style: TextStyle(
                          color: AppTheme.reelDotColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),

                // Cloud Storage Indicator Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_outlined,
                        color: AppTheme.textSecondary,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '3.2 of 10 GB',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Mini Linear Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          width: 30,
                          height: 4,
                          child: const LinearProgressIndicator(
                            value: 0.32,
                            backgroundColor: AppTheme.surfaceLight,
                            valueColor: AlwaysStoppedAnimation(Color(0xFF6E7CF0)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main Scrollable Area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  const SizedBox(height: 14),

                  // Hero Dial Record Button
                  ReelRecordButton(
                    isRecording: provider.isRecording,
                    onTap: () {
                      if (provider.isRecording) {
                        _stopAndNavigate(provider);
                      } else {
                        _startCountdownAndRecord(provider);
                      }
                    },
                  ),

                  const SizedBox(height: 20),

                  // Setting Shortcut Pill
                  GestureDetector(
                    onTap: () => setState(() => _currentTabIndex = 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.tune_rounded,
                            size: 14,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${provider.resolution}, ${provider.frameRate} fps, ${provider.countdownSeconds} s countdown',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Quick Toggles Row (Voice, Touches, Sound)
                  Row(
                    children: [
                      // Voice Card
                      Expanded(
                        child: _buildQuickToggleCard(
                          icon: Icons.mic_rounded,
                          title: 'Voice',
                          subtitle: provider.isAudioEnabled ? 'On' : 'Off',
                          isActive: provider.isAudioEnabled,
                          onTap: () => provider.toggleAudio(!provider.isAudioEnabled),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Touches Card
                      Expanded(
                        child: _buildQuickToggleCard(
                          icon: Icons.adjust_rounded,
                          title: 'Touches',
                          subtitle: provider.isShowTouchesEnabled ? 'On' : 'Off',
                          isActive: provider.isShowTouchesEnabled,
                          onTap: () => _handleToggleShowTouch(
                            context,
                            provider,
                            !provider.isShowTouchesEnabled,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Sound Card
                      Expanded(
                        child: _buildQuickToggleCard(
                          icon: provider.deviceSoundEnabled
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          title: 'Sound',
                          subtitle: provider.deviceSoundEnabled ? 'On' : 'Off',
                          isActive: provider.deviceSoundEnabled,
                          onTap: () => provider.toggleDeviceSound(!provider.deviceSoundEnabled),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Recent Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _currentTabIndex = 1),
                        child: const Text(
                          'See all',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6E7CF0),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Recent Horizontal Cards Carousel
                  Consumer<HistoryProvider>(
                    builder: (context, historyProv, _) {
                      final items = historyProv.items;

                      if (items.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            children: const [
                              Icon(
                                Icons.videocam_outlined,
                                color: AppTheme.textMuted,
                                size: 28,
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Tap Record to make your first screen video.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return SizedBox(
                        height: 140,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length.clamp(0, 6),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final accentColor = _accentColors[index % _accentColors.length];

                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _buildRecentCard(context, item, accentColor),
                            );
                          },
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickToggleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive ? AppTheme.borderSubtle : AppTheme.border,
            width: 1.2,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF232D48)
                    : AppTheme.surfaceLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 19,
                color: isActive ? const Color(0xFF8694FF) : AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isActive ? AppTheme.textSecondary : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentCard(
    BuildContext context,
    RecordingItem item,
    Color bannerColor,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PreviewScreen(recording: item),
          ),
        );
      },
      child: Container(
        width: 104,
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Colored Top Banner
            Container(
              height: 28,
              decoration: BoxDecoration(
                color: bannerColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(15),
                ),
              ),
            ),

            // Wireframe Mockup Preview Lines
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 5,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 5,
                      width: 65,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 5,
                      width: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Duration Badge
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.formattedDuration,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRecordingOverlay(
    BuildContext context,
    RecordingProvider provider,
  ) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final pillPosition = _pillOffset ?? Offset(screenSize.width - 295, topPadding + 16);

    return Positioned.fill(
      child: TouchVisualizer(
        child: Stack(
          children: [
            // Top Status Badge
            Positioned(
              top: topPadding + 16,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: provider.isPaused
                      ? const Color(0xFFFFB800)
                      : AppTheme.recordRed,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.circle, size: 8, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      provider.isPaused ? 'Paused' : 'Recording',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Draggable Floating Control Pill
            Positioned(
              left: pillPosition.dx.clamp(10.0, (screenSize.width - 275.0).clamp(10.0, screenSize.width)),
              top: pillPosition.dy.clamp(topPadding + 10.0, (screenSize.height - bottomPadding - 140.0).clamp(topPadding + 10.0, screenSize.height)),
              child: RecordingControlPill(
                provider: provider,
                onFinish: () => _stopAndNavigate(provider),
                onCancel: () => provider.cancelRecording(),
                onPauseResume: () => provider.togglePause(),
                onPanUpdate: (details) {
                  setState(() {
                    final current = _pillOffset ?? Offset(screenSize.width - 295, topPadding + 16);
                    _pillOffset = current + details.delta;
                  });
                },
              ),
            ),

            // Bottom Toast Helper Banner
            Positioned(
              bottom: 85,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B28).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: const [
                    Icon(
                      Icons.graphic_eq_rounded,
                      color: Color(0xFF00BA88),
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Recording your voice. Taps show as ripples in the video.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D111D),
        border: Border(
          top: BorderSide(color: Color(0xFF1E263C), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.radio_button_checked_rounded,
                label: 'Record',
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.grid_view_rounded,
                label: 'Library',
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.tune_rounded,
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _currentTabIndex == index;
    final color = isSelected ? Colors.white : AppTheme.textMuted;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _currentTabIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 22,
            color: isSelected && index == 0 ? AppTheme.recordRed : color,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
