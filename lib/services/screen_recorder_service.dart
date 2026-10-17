import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

enum RecorderPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  unknown,
}

abstract class ScreenRecorderService {
  Future<bool> isSupported();
  Future<RecorderPermissionStatus> checkPermissions();
  Future<RecorderPermissionStatus> requestPermissions();
  Future<bool> openSettings();
  Future<bool> startRecording({required String outputPath, bool showTouches = false});
  Future<String?> stopRecording();
  Future<void> cancelRecording();
  Future<bool> pauseRecording();
  Future<bool> resumeRecording();
  Future<bool> bringAppToForeground();

  Future<bool> getShowTouches();
  Future<bool> setShowTouches(bool enabled);
  Future<bool> canWriteSettings();
  Future<bool> openWriteSettings();
  Future<bool> openDeveloperSettings();
}

class PlatformScreenRecorderService implements ScreenRecorderService {
  static const MethodChannel _channel =
      MethodChannel('com.example.qa_mate/screen_recorder');

  String? _activeOutputPath;
  bool _isRecording = false;

  @override
  Future<bool> isSupported() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      final bool? supported = await _channel.invokeMethod<bool>('isSupported');
      return supported ?? false;
    } catch (e) {
      debugPrint('Error checking isSupported: $e');
      return false;
    }
  }

  @override
  Future<RecorderPermissionStatus> checkPermissions() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return RecorderPermissionStatus.granted;
    }

    try {
      // Check microphone permission
      final micStatus = await Permission.microphone.status;
      if (micStatus.isPermanentlyDenied) {
        return RecorderPermissionStatus.permanentlyDenied;
      }
      if (micStatus.isDenied) {
        return RecorderPermissionStatus.denied;
      }

      // Check notification permission for Android 13+ foreground service
      if (Platform.isAndroid) {
        final notifStatus = await Permission.notification.status;
        if (notifStatus.isPermanentlyDenied) {
          return RecorderPermissionStatus.permanentlyDenied;
        }
        if (notifStatus.isDenied) {
          return RecorderPermissionStatus.denied;
        }
      }

      return RecorderPermissionStatus.granted;
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      return RecorderPermissionStatus.unknown;
    }
  }

  @override
  Future<RecorderPermissionStatus> requestPermissions() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return RecorderPermissionStatus.granted;
    }

    try {
      final Map<Permission, PermissionStatus> statuses = await [
        Permission.microphone,
        if (Platform.isAndroid) Permission.notification,
      ].request();

      final micStatus = statuses[Permission.microphone];
      final notifStatus = statuses[Permission.notification];

      if (micStatus?.isPermanentlyDenied == true ||
          notifStatus?.isPermanentlyDenied == true) {
        return RecorderPermissionStatus.permanentlyDenied;
      }

      if (micStatus?.isGranted == true &&
          (notifStatus == null || notifStatus.isGranted)) {
        return RecorderPermissionStatus.granted;
      }

      return RecorderPermissionStatus.denied;
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      return RecorderPermissionStatus.unknown;
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final res = await _channel.invokeMethod<bool>('openSettings');
        if (res == true) return true;
      }
      return await openAppSettings();
    } catch (e) {
      debugPrint('Error opening settings: $e');
      return await openAppSettings();
    }
  }

  @override
  Future<bool> startRecording({required String outputPath, bool showTouches = false}) async {
    try {
      _activeOutputPath = outputPath;
      final bool? success = await _channel.invokeMethod<bool>(
        'startRecording',
        {
          'outputPath': outputPath,
          'showTouches': showTouches,
        },
      );
      _isRecording = success == true;
      return _isRecording;
    } on PlatformException catch (e) {
      debugPrint('PlatformException starting recording: ${e.code} - ${e.message}');
      _isRecording = false;
      _activeOutputPath = null;
      rethrow;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      _isRecording = false;
      _activeOutputPath = null;
      return false;
    }
  }

  @override
  Future<String?> stopRecording() async {
    try {
      final String? path = await _channel.invokeMethod<String>('stopRecording');
      _isRecording = false;
      final resultPath = path ?? _activeOutputPath;
      _activeOutputPath = null;
      return resultPath;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _isRecording = false;
      final fallback = _activeOutputPath;
      _activeOutputPath = null;
      return fallback;
    }
  }

  @override
  Future<void> cancelRecording() async {
    try {
      final path = await stopRecording();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('Error cancelling recording: $e');
    }
  }

  @override
  Future<bool> pauseRecording() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return true;
    try {
      final bool? res = await _channel.invokeMethod<bool>('pauseRecording');
      return res ?? false;
    } catch (e) {
      debugPrint('Error pausing recording: $e');
      return false;
    }
  }

  @override
  Future<bool> resumeRecording() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return true;
    try {
      final bool? res = await _channel.invokeMethod<bool>('resumeRecording');
      return res ?? false;
    } catch (e) {
      debugPrint('Error resuming recording: $e');
      return false;
    }
  }

  @override
  Future<bool> bringAppToForeground() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? res = await _channel.invokeMethod<bool>('bringAppToForeground');
      return res ?? false;
    } catch (e) {
      debugPrint('Error bringing app to foreground: $e');
      return false;
    }
  }

  @override
  Future<bool> getShowTouches() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return false;
    try {
      final bool? res = await _channel.invokeMethod<bool>('getShowTouches');
      return res ?? false;
    } catch (e) {
      debugPrint('Error getting show_touches: $e');
      return false;
    }
  }

  @override
  Future<bool> setShowTouches(bool enabled) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return false;
    try {
      final bool? res = await _channel.invokeMethod<bool>(
        'setShowTouches',
        {'enabled': enabled},
      );
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('PlatformException setting show_touches: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error setting show_touches: $e');
      return false;
    }
  }

  @override
  Future<bool> canWriteSettings() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? res = await _channel.invokeMethod<bool>('canWriteSettings');
      return res ?? false;
    } catch (e) {
      debugPrint('Error checking canWriteSettings: $e');
      return false;
    }
  }

  @override
  Future<bool> openWriteSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? res = await _channel.invokeMethod<bool>('openWriteSettings');
      return res ?? false;
    } catch (e) {
      debugPrint('Error opening write settings: $e');
      return false;
    }
  }

  @override
  Future<bool> openDeveloperSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? res = await _channel.invokeMethod<bool>('openDeveloperSettings');
      return res ?? false;
    } catch (e) {
      debugPrint('Error opening developer settings: $e');
      return false;
    }
  }
}

/// Simulated Screen Recorder Service:
/// Fallback implementation useful for desktop/emulator/web environments or
/// testing the UI without requiring actual physical screen capture authorization.
class SimulatedScreenRecorderService implements ScreenRecorderService {
  String? _activeOutputPath;
  bool _isSimulating = false;
  bool _simulatedShowTouches = false;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<RecorderPermissionStatus> checkPermissions() async =>
      RecorderPermissionStatus.granted;

  @override
  Future<RecorderPermissionStatus> requestPermissions() async =>
      RecorderPermissionStatus.granted;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<bool> startRecording({required String outputPath, bool showTouches = false}) async {
    _activeOutputPath = outputPath;
    _isSimulating = true;
    if (showTouches) {
      _simulatedShowTouches = true;
    }
    return true;
  }

  @override
  Future<String?> stopRecording() async {
    if (!_isSimulating) return _activeOutputPath;
    _isSimulating = false;

    if (_activeOutputPath != null) {
      final destFile = File(_activeOutputPath!);
      if (!await destFile.exists()) {
        await destFile.parent.create(recursive: true);

        // Try to find a real sample MP4 bundled alongside the app binary so the
        // preview player can actually initialise and play it.
        final samplePaths = <String>[
          // Android / iOS: app bundle working dir
          '${Directory.current.path}/test_out.mp4',
          // Resolved relative to the executable for desktop
          '${File(Platform.resolvedExecutable).parent.path}/test_out.mp4',
        ];

        bool copied = false;
        for (final src in samplePaths) {
          final srcFile = File(src);
          if (await srcFile.exists() && await srcFile.length() > 1024) {
            await srcFile.copy(destFile.path);
            copied = true;
            debugPrint('[SimulatedRecorder] copied sample video from $src');
            break;
          }
        }

        if (!copied) {
          // Last resort: write a minimal ftyp-only stub.
          // VideoPreviewPlayer will detect this and show the animated fallback
          // view instantly (size < 1 KB check) rather than waiting 12 s for
          // the ExoPlayer probe to time out.
          await destFile.writeAsBytes(_minimalMp4Bytes());
          debugPrint('[SimulatedRecorder] wrote minimal stub (no sample found)');
        }
      }
    }

    final path = _activeOutputPath;
    _activeOutputPath = null;
    return path;
  }

  /// Builds a ~24-byte minimal MP4: just an ftyp box.
  static List<int> _minimalMp4Bytes() {
    return [
      0x00, 0x00, 0x00, 0x18, // box size = 24
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x6D, 0x70, 0x34, 0x32, // major brand 'mp42'
      0x00, 0x00, 0x00, 0x00, // minor version
      0x6D, 0x70, 0x34, 0x32, // compatible brand 'mp42'
      0x69, 0x73, 0x6F, 0x6D, // compatible brand 'isom'
    ];
  }

  @override
  Future<void> cancelRecording() async {
    _isSimulating = false;
    if (_activeOutputPath != null) {
      final file = File(_activeOutputPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _activeOutputPath = null;
  }

  @override
  Future<bool> pauseRecording() async => true;

  @override
  Future<bool> resumeRecording() async => true;

  @override
  Future<bool> bringAppToForeground() async => true;

  @override
  Future<bool> getShowTouches() async => _simulatedShowTouches;

  @override
  Future<bool> setShowTouches(bool enabled) async {
    _simulatedShowTouches = enabled;
    return true;
  }

  @override
  Future<bool> canWriteSettings() async => true;

  @override
  Future<bool> openWriteSettings() async => true;

  @override
  Future<bool> openDeveloperSettings() async => true;
}

/// Composite service that intelligently switches between Platform and Simulated
class AdaptiveScreenRecorderService implements ScreenRecorderService {
  final PlatformScreenRecorderService _platformService =
      PlatformScreenRecorderService();
  final SimulatedScreenRecorderService _simulatedService =
      SimulatedScreenRecorderService();

  bool _forceSimulation = false;
  bool get isUsingSimulation =>
      _forceSimulation ||
      kIsWeb ||
      (!Platform.isAndroid && !Platform.isIOS);

  void setForceSimulation(bool enable) {
    _forceSimulation = enable;
  }

  ScreenRecorderService get _activeService {
    if (isUsingSimulation) return _simulatedService;
    return _platformService;
  }

  @override
  Future<bool> isSupported() => _activeService.isSupported();

  @override
  Future<RecorderPermissionStatus> checkPermissions() =>
      _activeService.checkPermissions();

  @override
  Future<RecorderPermissionStatus> requestPermissions() =>
      _activeService.requestPermissions();

  @override
  Future<bool> openSettings() => _activeService.openSettings();

  @override
  Future<bool> startRecording({required String outputPath, bool showTouches = false}) =>
      _activeService.startRecording(outputPath: outputPath, showTouches: showTouches);

  @override
  Future<String?> stopRecording() => _activeService.stopRecording();

  @override
  Future<void> cancelRecording() => _activeService.cancelRecording();

  @override
  Future<bool> pauseRecording() => _activeService.pauseRecording();

  @override
  Future<bool> resumeRecording() => _activeService.resumeRecording();

  @override
  Future<bool> bringAppToForeground() => _activeService.bringAppToForeground();

  @override
  Future<bool> getShowTouches() => _activeService.getShowTouches();

  @override
  Future<bool> setShowTouches(bool enabled) =>
      _activeService.setShowTouches(enabled);

  @override
  Future<bool> canWriteSettings() => _activeService.canWriteSettings();

  @override
  Future<bool> openWriteSettings() => _activeService.openWriteSettings();

  @override
  Future<bool> openDeveloperSettings() =>
      _activeService.openDeveloperSettings();
}
