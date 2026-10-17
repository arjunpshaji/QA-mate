import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/recording_item.dart';
import '../models/overlay_event.dart';
import '../services/app_overlay_manager.dart';
import '../services/history_repository.dart';
import '../services/screen_recorder_service.dart';
import '../services/thumbnail_service.dart';

enum RecordingStatus {
  idle,
  preparing,
  recording,
  paused,
  finishing,
  error,
}

class RecordingProvider extends ChangeNotifier {
  final ScreenRecorderService recorderService;
  final RecordingHistoryRepository historyRepository;
  final ThumbnailService thumbnailService;

  RecordingProvider({
    required this.recorderService,
    required this.historyRepository,
    ThumbnailService? thumbnailService,
  }) : thumbnailService = thumbnailService ?? AppThumbnailService() {
    _init();
  }

  RecordingStatus _status = RecordingStatus.idle;
  RecordingStatus get status => _status;
  bool get isRecording => _status == RecordingStatus.recording;
  bool get isPaused => _status == RecordingStatus.paused;
  bool get isIdle => _status == RecordingStatus.idle;

  RecorderPermissionStatus _permissionStatus = RecorderPermissionStatus.unknown;
  RecorderPermissionStatus get permissionStatus => _permissionStatus;
  bool get hasPermission =>
      _permissionStatus == RecorderPermissionStatus.granted;

  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;

  static const Duration maxDuration = Duration(minutes: 5);
  static const Duration warningThreshold = Duration(minutes: 4);
  static const Duration criticalThreshold = Duration(minutes: 4, seconds: 30);

  bool get isNearLimit => _elapsed >= warningThreshold;
  bool get isCriticalLimit => _elapsed >= criticalThreshold;
  Duration get remainingTime => maxDuration - _elapsed;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isAudioEnabled = true;
  bool get isAudioEnabled => _isAudioEnabled;

  bool _deviceSoundEnabled = false;
  bool get deviceSoundEnabled => _deviceSoundEnabled;

  bool _isShowTouchesEnabled = false;
  bool get isShowTouchesEnabled => _isShowTouchesEnabled;

  String _resolution = '1080p';
  String get resolution => _resolution;

  int _frameRate = 60;
  int get frameRate => _frameRate;

  int _bitrateMbps = 12;
  int get bitrateMbps => _bitrateMbps;

  int _countdownSeconds = 3;
  int get countdownSeconds => _countdownSeconds;

  bool _canWriteSettings = true;
  bool get canWriteSettings => _canWriteSettings;

  /// Notifies when a recording was completed (especially from the floating overlay)
  final ValueNotifier<RecordingItem?> lastCompletedRecording = ValueNotifier(null);

  void setResolution(String res) {
    _resolution = res;
    notifyListeners();
  }

  void setFrameRate(int fps) {
    _frameRate = fps;
    notifyListeners();
  }

  void setBitrate(int bitrate) {
    _bitrateMbps = bitrate;
    notifyListeners();
  }

  void setCountdownSeconds(int seconds) {
    _countdownSeconds = seconds;
    notifyListeners();
  }

  void toggleDeviceSound(bool enabled) {
    _deviceSoundEnabled = enabled;
    notifyListeners();
  }

  RecordingItem? _currentRecording;
  RecordingItem? get currentRecording => _currentRecording;

  Timer? _tickerTimer;
  DateTime? _recordingStartTime;

  Future<void> _init() async {
    await checkPermissions();
    await _initShowTouches();
  }

  Future<void> _initShowTouches() async {
    try {
      _canWriteSettings = await recorderService.canWriteSettings();
      final systemVal = await recorderService.getShowTouches();
      _isShowTouchesEnabled = systemVal;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing show touches: $e');
    }
  }

  void _syncOverlayState({String? status}) {
    AppOverlayManager.instance.sendStateUpdate(
      elapsedSeconds: _elapsed.inSeconds,
      isPaused: _status == RecordingStatus.paused,
      isAudioEnabled: _isAudioEnabled,
      isTouchesEnabled: _isShowTouchesEnabled,
      status: status ?? _status.name,
    );
  }

  void toggleAudio(bool enabled) {
    _isAudioEnabled = enabled;
    notifyListeners();
    _syncOverlayState();
  }

  Future<void> togglePause() async {
    if (_status == RecordingStatus.recording) {
      _status = RecordingStatus.paused;
      _tickerTimer?.cancel();
      try {
        await recorderService.pauseRecording();
      } catch (e) {
        debugPrint('Error pausing recorder: $e');
      }
      notifyListeners();
      _syncOverlayState(status: 'paused');
    } else if (_status == RecordingStatus.paused) {
      _status = RecordingStatus.recording;
      _recordingStartTime = DateTime.now().subtract(_elapsed);
      _startTimer();
      try {
        await recorderService.resumeRecording();
      } catch (e) {
        debugPrint('Error resuming recorder: $e');
      }
      notifyListeners();
      _syncOverlayState(status: 'recording');
    }
  }

  Future<bool> toggleShowTouches(bool enabled) async {
    _canWriteSettings = await recorderService.canWriteSettings();
    final systemVal = await recorderService.getShowTouches();

    if (enabled) {
      if (systemVal) {
        _isShowTouchesEnabled = true;
        notifyListeners();
        _syncOverlayState();
        return true;
      }

      if (_canWriteSettings) {
        try {
          final ok = await recorderService.setShowTouches(true);
          _isShowTouchesEnabled = ok;
          notifyListeners();
          _syncOverlayState();
          return ok;
        } catch (e) {
          debugPrint('Error enabling show touches: $e');
          _isShowTouchesEnabled = false;
          notifyListeners();
          _syncOverlayState();
          return false;
        }
      } else {
        // Permission or developer options needed
        _isShowTouchesEnabled = false;
        notifyListeners();
        _syncOverlayState();
        return false;
      }
    } else {
      if (_canWriteSettings) {
        try {
          await recorderService.setShowTouches(false);
        } catch (e) {
          debugPrint('Error disabling show touches: $e');
        }
      }
      _isShowTouchesEnabled = false;
      notifyListeners();
      _syncOverlayState();
      return true;
    }
  }

  Future<bool> openWriteSettings() async {
    final res = await recorderService.openWriteSettings();
    await refreshShowTouches();
    return res;
  }

  Future<bool> openDeveloperSettings() async {
    return await recorderService.openDeveloperSettings();
  }

  Future<void> refreshShowTouches() async {
    try {
      _canWriteSettings = await recorderService.canWriteSettings();
      final systemVal = await recorderService.getShowTouches();
      _isShowTouchesEnabled = systemVal;
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing show touches: $e');
    }
  }

  Future<void> checkPermissions() async {
    try {
      _permissionStatus = await recorderService.checkPermissions();
      notifyListeners();
    } catch (e) {
      debugPrint('Error checking permissions: $e');
    }
  }

  Future<bool> requestPermissions() async {
    try {
      _permissionStatus = await recorderService.requestPermissions();
      notifyListeners();
      return _permissionStatus == RecorderPermissionStatus.granted;
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      _errorMessage = 'Could not request permissions: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> openSettings() async {
    await recorderService.openSettings();
    // Re-check after returning from settings
    await checkPermissions();
  }

  Future<bool> startRecording() async {
    _errorMessage = null;
    _status = RecordingStatus.preparing;
    notifyListeners();

    try {
      // 1. Verify permissions
      if (_permissionStatus != RecorderPermissionStatus.granted) {
        final granted = await requestPermissions();
        if (!granted) {
          _status = RecordingStatus.error;
          _errorMessage = _permissionStatus == RecorderPermissionStatus.permanentlyDenied
              ? 'Permission is permanently denied. Please enable microphone and notifications in system settings.'
              : 'Permission is required to capture audio and notify during screen recording.';
          notifyListeners();
          return false;
        }
      }

      // 2. Prepare output file path in app documents / cache directory
      final dir = await _getRecordingsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'rec_$timestamp.mp4';
      final outputPath = '${dir.path}/$fileName';

      // 3. Trigger native recorder
      final started = await recorderService.startRecording(
        outputPath: outputPath,
        showTouches: _isShowTouchesEnabled,
      );
      if (!started) {
        _status = RecordingStatus.error;
        _errorMessage = 'Failed to start native screen capture.';
        notifyListeners();
        return false;
      }

      // 4. Start elapsed timer
      _elapsed = Duration.zero;
      _recordingStartTime = DateTime.now();
      _status = RecordingStatus.recording;
      _startTimer();

      // 5. Show system overlay window outside the app
      try {
        final hasOverlayPermission = await AppOverlayManager.instance.isPermissionGranted();
        if (!hasOverlayPermission) {
          await AppOverlayManager.instance.requestPermission();
        }
        await AppOverlayManager.instance.showOverlay(
          height: 360,
          initialState: OverlayStateUpdate(
            elapsedSeconds: 0,
            isPaused: false,
            isAudioEnabled: _isAudioEnabled,
            isTouchesEnabled: _isShowTouchesEnabled,
            status: 'recording',
          ),
        );
        AppOverlayManager.instance.startListening((action, payload) async {
          switch (action) {
            case 'stop':
              final item = await stopRecording();
              await recorderService.bringAppToForeground();
              if (item != null) {
                lastCompletedRecording.value = item;
              }
              break;
            case 'pause_resume':
              await togglePause();
              break;
            case 'toggle_mic':
              toggleAudio(!_isAudioEnabled);
              break;
            case 'toggle_touches':
              await toggleShowTouches(!_isShowTouchesEnabled);
              break;
            case 'discard':
              await cancelRecording();
              await recorderService.bringAppToForeground();
              break;
            case 'open_app':
              await recorderService.bringAppToForeground();
              break;
            case 'request_sync':
              _syncOverlayState();
              break;
          }
        });
      } catch (e) {
        debugPrint('Overlay setup error: $e');
      }

      notifyListeners();
      return true;
    } catch (e) {
      _status = RecordingStatus.error;
      _errorMessage = e.toString();
      _stopTimer();
      notifyListeners();
      return false;
    }
  }

  Future<RecordingItem?> stopRecording() async {
    if (_status != RecordingStatus.recording && _status != RecordingStatus.paused) return null;

    _status = RecordingStatus.finishing;
    _stopTimer();
    AppOverlayManager.instance.stopListening();
    await AppOverlayManager.instance.closeOverlay();
    notifyListeners();

    try {
      final String? outputPath = await recorderService.stopRecording();
      final duration = _elapsed;

      if (outputPath == null) {
        _status = RecordingStatus.error;
        _errorMessage = 'Could not retrieve recording output path.';
        notifyListeners();
        return null;
      }

      final file = File(outputPath);
      int size = 0;
      if (await file.exists()) {
        size = await file.length();
      }

      String? thumbPath;
      try {
        thumbPath = await thumbnailService.generateThumbnail(outputPath);
      } catch (e) {
        debugPrint('Thumbnail generation error: $e');
      }

      final recording = RecordingItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: outputPath,
        fileName: outputPath.split(Platform.pathSeparator).last,
        createdAt: DateTime.now(),
        duration: duration,
        fileSizeBytes: size,
        thumbnailPath: thumbPath,
        trimStart: Duration.zero,
        trimEnd: duration,
      );

      _currentRecording = recording;
      await historyRepository.saveRecording(recording);

      _status = RecordingStatus.idle;
      _elapsed = Duration.zero;
      notifyListeners();
      return recording;
    } catch (e) {
      _status = RecordingStatus.error;
      _errorMessage = 'Error saving recording: $e';
      notifyListeners();
      return null;
    }
  }

  Future<void> cancelRecording() async {
    _stopTimer();
    AppOverlayManager.instance.stopListening();
    await AppOverlayManager.instance.closeOverlay();
    await recorderService.cancelRecording();
    _status = RecordingStatus.idle;
    _elapsed = Duration.zero;
    notifyListeners();
  }

  Future<void> discardCurrentRecording() async {
    if (_currentRecording != null) {
      try {
        final file = File(_currentRecording!.filePath);
        if (await file.exists()) {
          await file.delete();
        }
        await historyRepository.deleteRecording(_currentRecording!.id);
      } catch (e) {
        debugPrint('Error deleting discarded recording: $e');
      }
      _currentRecording = null;
      notifyListeners();
    }
  }

  void setCurrentRecording(RecordingItem item) {
    _currentRecording = item;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    if (_status == RecordingStatus.error) {
      _status = RecordingStatus.idle;
    }
    notifyListeners();
  }

  void _startTimer() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_recordingStartTime != null) {
        _elapsed = DateTime.now().difference(_recordingStartTime!);
      } else {
        _elapsed += const Duration(seconds: 1);
      }

      // Sync state with overlay window outside the app
      AppOverlayManager.instance.sendStateUpdate(
        elapsedSeconds: _elapsed.inSeconds,
        isPaused: _status == RecordingStatus.paused,
        isAudioEnabled: _isAudioEnabled,
        isTouchesEnabled: _isShowTouchesEnabled,
        status: _status.name,
      );

      // Enforce max 5-minute duration
      if (_elapsed >= maxDuration) {
        _elapsed = maxDuration;
        stopRecording();
      } else {
        notifyListeners();
      }
    });
  }

  void _stopTimer() {
    _tickerTimer?.cancel();
    _tickerTimer = null;
    _recordingStartTime = null;
  }

  Future<Directory> _getRecordingsDirectory() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${docsDir.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
      return recordingsDir;
    } catch (_) {
      return Directory.systemTemp.createTempSync('qa_mate_rec');
    }
  }

  @override
  void dispose() {
    _stopTimer();
    lastCompletedRecording.dispose();
    super.dispose();
  }
}
