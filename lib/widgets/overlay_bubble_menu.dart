import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../models/overlay_event.dart';

/// App wrapper for the floating overlay window
class OverlayBubbleMenuApp extends StatelessWidget {
  const OverlayBubbleMenuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: OverlayBubbleMenu(),
      ),
    );
  }
}

/// The floating overlay widget that renders over any other app
class OverlayBubbleMenu extends StatefulWidget {
  const OverlayBubbleMenu({super.key});

  @override
  State<OverlayBubbleMenu> createState() => _OverlayBubbleMenuState();
}

class _OverlayBubbleMenuState extends State<OverlayBubbleMenu>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  int _elapsedSeconds = 0;
  bool _isPaused = false;
  bool _isAudioEnabled = true;
  bool _isTouchesEnabled = false;
  bool _isStopping = false;

  StreamSubscription? _dataSubscription;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.85, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen to data broadcasts from the main app
    _dataSubscription = FlutterOverlayWindow.overlayListener.listen((raw) {
      if (raw == null) return;
      try {
        Map<String, dynamic> data;
        if (raw is String) {
          data = jsonDecode(raw) as Map<String, dynamic>;
        } else if (raw is Map) {
          data = Map<String, dynamic>.from(raw);
        } else {
          return;
        }

        if (data['type'] == 'state_update') {
          if (!mounted) return;
          final update = OverlayStateUpdate.fromMap(data);
          setState(() {
            _elapsedSeconds = update.elapsedSeconds;
            _isPaused = update.isPaused;
            _isAudioEnabled = update.isAudioEnabled;
            _isTouchesEnabled = update.isTouchesEnabled;
          });
        }
      } catch (e) {
        debugPrint('Error parsing overlay data: $e');
      }
    });

    // Request initial state synchronization immediately upon isolate start
    _sendAction(OverlayAction.requestSync);
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _sendAction(String action, [dynamic payload]) {
    final actionEvent = OverlayAction(action: action, payload: payload);
    FlutterOverlayWindow.shareData(actionEvent.toJson());
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
    });
    _sendAction('pause_resume');
  }

  void _toggleMic() {
    setState(() {
      _isAudioEnabled = !_isAudioEnabled;
    });
    _sendAction('toggle_mic');
  }

  void _toggleTouches() {
    setState(() {
      _isTouchesEnabled = !_isTouchesEnabled;
    });
    _sendAction('toggle_touches');
  }

  void _stopRecording() {
    if (_isStopping) return;
    setState(() {
      _isStopping = true;
    });
    _sendAction('stop');
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });

    // Resize overlay window in dp to accommodate expanded menu or compact pill
    if (_isExpanded) {
      FlutterOverlayWindow.resizeOverlay(
        WindowSize.matchParent,
        220,
        true,
      );
    } else {
      FlutterOverlayWindow.resizeOverlay(
        WindowSize.matchParent,
        96,
        true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final elapsedStr = _formatDuration(_elapsedSeconds);

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - 20,
          ),
          // Clicking anywhere on the widget that isn't a specific button redirects to the app
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _sendAction('open_app');
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: const Color(0xFF141926).withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(_isExpanded ? 24 : 9999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x77000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Main Compact Pill Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Drag Grip Handle
                          const Padding(
                            padding: EdgeInsets.only(right: 6, left: 2),
                            child: Icon(
                              Icons.drag_indicator_rounded,
                              color: Color(0xFF6B7A99),
                              size: 18,
                            ),
                          ),

                          // Pulsing Red / Paused Amber Recording Indicator Dot
                          ScaleTransition(
                            scale: _pulseScale,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _isPaused
                                    ? const Color(0xFFFFB800)
                                    : const Color(0xFFFF3B5C),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _isPaused
                                        ? const Color(0x99FFB800)
                                        : const Color(0x99FF3B5C),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // Monospace Tabular Elapsed Timer
                          Text(
                            elapsedStr,
                            style: TextStyle(
                              fontFamily: 'Courier',
                              fontFeatures: const [FontFeature.tabularFigures()],
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _isPaused
                                  ? const Color(0xFFFFB800)
                                  : Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Pause / Resume Button
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _togglePause,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: _isPaused
                                    ? const Color(0xFF4A3810)
                                    : const Color(0xFF222C44),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isPaused
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                                color: _isPaused
                                    ? const Color(0xFFFFB800)
                                    : Colors.white,
                                size: 17,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),

                          // Microphone Mute Toggle Button
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleMic,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: const BoxDecoration(
                                color: Color(0xFF222C44),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isAudioEnabled
                                    ? Icons.mic_rounded
                                    : Icons.mic_off_rounded,
                                color: _isAudioEnabled
                                    ? Colors.white
                                    : const Color(0xFFFF3B5C),
                                size: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),

                          // Expand / Collapse Menu Toggle Button
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleExpanded,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: _isExpanded
                                    ? const Color(0xFF5E6AD2)
                                    : const Color(0xFF222C44),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.tune_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // Finish / Stop Recording Button
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _stopRecording,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF3B5C),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x66FF3B5C),
                                    blurRadius: 10,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: _isStopping
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                      ),
                                    )
                                  : Container(
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

                  // Expanded Quick Toggles Menu Drawer
                  if (_isExpanded) ...[
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            // Toggle Touches
                            _buildOverlayAction(
                              icon: Icons.adjust_rounded,
                              label: 'Touches',
                              isActive: _isTouchesEnabled,
                              onTap: _toggleTouches,
                            ),
                            const SizedBox(width: 12),

                            // Toggle Mic
                            _buildOverlayAction(
                              icon: _isAudioEnabled
                                  ? Icons.mic_rounded
                                  : Icons.mic_off_rounded,
                              label: _isAudioEnabled ? 'Mic On' : 'Mic Off',
                              isActive: _isAudioEnabled,
                              onTap: _toggleMic,
                            ),
                            const SizedBox(width: 12),

                            // Pause / Resume
                            _buildOverlayAction(
                              icon: _isPaused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              label: _isPaused ? 'Resume' : 'Pause',
                              isActive: !_isPaused,
                              onTap: _togglePause,
                            ),
                            const SizedBox(width: 12),

                            // Discard Action
                            _buildOverlayAction(
                              icon: Icons.delete_outline_rounded,
                              label: 'Discard',
                              isActive: false,
                              color: const Color(0xFFFF3B5C),
                              onTap: () => _sendAction('discard'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayAction({
    required IconData icon,
    required String label,
    required bool isActive,
    Color? color,
    required VoidCallback onTap,
  }) {
    final activeColor = color ?? const Color(0xFF6E7CF0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withValues(alpha: 0.22)
                  : const Color(0xFF222C44),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? activeColor
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? activeColor : Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : const Color(0xFF909EB4),
            ),
          ),
        ],
      ),
    );
  }
}
