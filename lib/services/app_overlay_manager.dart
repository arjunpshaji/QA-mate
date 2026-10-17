import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../models/overlay_event.dart';

/// Service to manage showing, updating, and handling events from the system overlay window across isolates.
class AppOverlayManager {
  static final AppOverlayManager instance = AppOverlayManager._internal();
  AppOverlayManager._internal();

  StreamSubscription? _listenerSubscription;
  void Function(String action, dynamic payload)? _onActionReceived;
  OverlayStateUpdate? _lastStateUpdate;

  /// Returns the most recent state broadcasted to the overlay
  OverlayStateUpdate? get lastStateUpdate => _lastStateUpdate;

  /// Check if the system alert window permission is granted
  Future<bool> isPermissionGranted() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await FlutterOverlayWindow.isPermissionGranted();
    } catch (e) {
      debugPrint('Error checking overlay permission: $e');
      return false;
    }
  }

  /// Request SYSTEM_ALERT_WINDOW permission
  Future<bool> requestPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final granted = await FlutterOverlayWindow.requestPermission();
      return granted ?? false;
    } catch (e) {
      debugPrint('Error requesting overlay permission: $e');
      return false;
    }
  }

  /// Show the floating system overlay window
  Future<bool> showOverlay({
    int height = 360,
    int width = WindowSize.matchParent,
    OverlayStateUpdate? initialState,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return false;

    try {
      final hasPermission = await isPermissionGranted();
      if (!hasPermission) {
        final requested = await requestPermission();
        if (!requested) return false;
      }

      final isActive = await FlutterOverlayWindow.isActive();
      if (isActive) {
        await FlutterOverlayWindow.closeOverlay();
      }

      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: "QA Mate Screen Recorder",
        overlayContent: "Screen recording active",
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.auto,
        height: height,
        width: width,
      );

      // Immediately set the size in dp so Android converts it with dpToPx
      await FlutterOverlayWindow.resizeOverlay(
        WindowSize.matchParent,
        96,
        true,
      );

      // Immediately sync state with newly spawned overlay isolate
      if (initialState != null) {
        sendUpdate(initialState);
      } else if (_lastStateUpdate != null) {
        sendUpdate(_lastStateUpdate!);
      }

      return true;
    } catch (e) {
      debugPrint('Error opening overlay window: $e');
      return false;
    }
  }

  /// Close the overlay window
  Future<void> closeOverlay() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final isActive = await FlutterOverlayWindow.isActive();
      if (isActive) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (e) {
      debugPrint('Error closing overlay window: $e');
    }
  }

  /// Resize overlay window (e.g. when menu expands/collapses)
  Future<void> resizeOverlay({
    required int width,
    required int height,
    bool enableDrag = true,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await FlutterOverlayWindow.resizeOverlay(width, height, enableDrag);
    } catch (e) {
      debugPrint('Error resizing overlay: $e');
    }
  }

  /// Broadcast a typed state update to the overlay window
  void sendUpdate(OverlayStateUpdate update) {
    if (kIsWeb || !Platform.isAndroid) return;
    _lastStateUpdate = update;
    try {
      FlutterOverlayWindow.shareData(update.toJson());
    } catch (e) {
      debugPrint('Error sending data to overlay: $e');
    }
  }

  /// Send recording state updates (elapsed time, audio muted, paused, etc.) to overlay
  void sendStateUpdate({
    required int elapsedSeconds,
    required bool isPaused,
    required bool isAudioEnabled,
    required bool isTouchesEnabled,
    String? status,
  }) {
    final update = OverlayStateUpdate(
      elapsedSeconds: elapsedSeconds,
      isPaused: isPaused,
      isAudioEnabled: isAudioEnabled,
      isTouchesEnabled: isTouchesEnabled,
      status: status ?? 'recording',
    );
    sendUpdate(update);
  }

  /// Start listening for actions triggered from the overlay window
  void startListening(void Function(String action, dynamic payload) onAction) {
    if (kIsWeb || !Platform.isAndroid) return;
    _onActionReceived = onAction;

    _listenerSubscription?.cancel();
    _listenerSubscription = FlutterOverlayWindow.overlayListener.listen((raw) {
      try {
        if (raw == null) return;
        Map<String, dynamic> data;
        if (raw is String) {
          data = jsonDecode(raw) as Map<String, dynamic>;
        } else if (raw is Map) {
          data = Map<String, dynamic>.from(raw);
        } else {
          return;
        }

        final overlayAction = OverlayAction.fromMap(data);
        if (overlayAction.action.isNotEmpty) {
          // If overlay requested state synchronization, respond immediately with cached state
          if (overlayAction.action == OverlayAction.requestSync && _lastStateUpdate != null) {
            sendUpdate(_lastStateUpdate!);
          }

          _onActionReceived?.call(overlayAction.action, overlayAction.payload);
        }
      } catch (e) {
        debugPrint('Error parsing message from overlay: $e');
      }
    });
  }

  void stopListening() {
    _listenerSubscription?.cancel();
    _listenerSubscription = null;
    _onActionReceived = null;
  }
}
