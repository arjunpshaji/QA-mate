import 'dart:convert';

/// Represents a state update message sent from the main app isolate to the overlay isolate.
class OverlayStateUpdate {
  final int elapsedSeconds;
  final bool isPaused;
  final bool isAudioEnabled;
  final bool isTouchesEnabled;
  final String status;

  const OverlayStateUpdate({
    required this.elapsedSeconds,
    required this.isPaused,
    required this.isAudioEnabled,
    required this.isTouchesEnabled,
    required this.status,
  });

  Map<String, dynamic> toMap() => {
    'type': 'state_update',
    'elapsedSeconds': elapsedSeconds,
    'isPaused': isPaused,
    'isAudioEnabled': isAudioEnabled,
    'isTouchesEnabled': isTouchesEnabled,
    'status': status,
  };

  factory OverlayStateUpdate.fromMap(Map<String, dynamic> map) {
    return OverlayStateUpdate(
      elapsedSeconds: map['elapsedSeconds'] as int? ?? 0,
      isPaused: map['isPaused'] as bool? ?? false,
      isAudioEnabled: map['isAudioEnabled'] as bool? ?? true,
      isTouchesEnabled: map['isTouchesEnabled'] as bool? ?? false,
      status: map['status'] as String? ?? 'idle',
    );
  }

  String toJson() => jsonEncode(toMap());

  factory OverlayStateUpdate.fromJson(String source) =>
      OverlayStateUpdate.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  String toString() =>
      'OverlayStateUpdate(elapsed: ${elapsedSeconds}s, paused: $isPaused, mic: $isAudioEnabled, touches: $isTouchesEnabled, status: $status)';
}

/// Standardized action names and payloads sent from the overlay isolate back to the main app isolate.
class OverlayAction {
  static const String stop = 'stop';
  static const String pauseResume = 'pause_resume';
  static const String toggleMic = 'toggle_mic';
  static const String toggleTouches = 'toggle_touches';
  static const String discard = 'discard';
  static const String openApp = 'open_app';
  static const String requestSync = 'request_sync';

  final String action;
  final dynamic payload;

  const OverlayAction({
    required this.action,
    this.payload,
  });

  Map<String, dynamic> toMap() => {
    'action': action,
    'payload': payload,
  };

  factory OverlayAction.fromMap(Map<String, dynamic> map) {
    return OverlayAction(
      action: map['action'] as String? ?? '',
      payload: map['payload'],
    );
  }

  String toJson() => jsonEncode(toMap());

  factory OverlayAction.fromJson(String source) =>
      OverlayAction.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  String toString() => 'OverlayAction($action, payload: $payload)';
}
