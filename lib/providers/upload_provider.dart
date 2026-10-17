import 'package:flutter/foundation.dart';
import '../models/recording_item.dart';
import '../services/history_repository.dart';
import '../services/upload_service.dart';

enum UploadStatus {
  idle,
  uploading,
  success,
  error,
}

class UploadProvider extends ChangeNotifier {
  final UploadService uploadService;
  final RecordingHistoryRepository historyRepository;

  UploadProvider({
    required this.uploadService,
    required this.historyRepository,
  });

  UploadStatus _status = UploadStatus.idle;
  UploadStatus get status => _status;
  bool get isUploading => _status == UploadStatus.uploading;
  bool get isSuccess => _status == UploadStatus.success;
  bool get isError => _status == UploadStatus.error;

  double _progress = 0.0;
  double get progress => _progress;
  int get progressPercent => (_progress * 100).toInt();

  String _currentStage = 'Preparing upload...';
  String get currentStage => _currentStage;

  String? _shareUrl;
  String? get shareUrl => _shareUrl;

  String? _uploadId;
  String? get uploadId => _uploadId;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _expiresAt;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isServerDown = false;
  bool get isServerDown => _isServerDown;

  int? _serverStatusCode;
  int? get serverStatusCode => _serverStatusCode;

  RecordingItem? _activeItem;
  RecordingItem? get activeItem => _activeItem;

  Future<bool> checkServerHealth() async {
    return await uploadService.checkServerHealth();
  }

  Future<bool> uploadRecording(RecordingItem item) async {
    _activeItem = item;
    _status = UploadStatus.uploading;
    _progress = 0.0;
    _currentStage = 'Requesting pre-signed upload authorization...';
    _errorMessage = null;
    _shareUrl = null;
    _uploadId = null;
    _isServerDown = false;
    _serverStatusCode = null;
    notifyListeners();

    try {
      final result = await uploadService.uploadRecording(
        videoPath: item.filePath,
        thumbnailPath: item.thumbnailPath,
        trimStart: item.trimStart,
        trimEnd: item.trimEnd,
        onProgress: (p, stage) {
          _progress = p;
          _currentStage = stage;
          notifyListeners();
        },
      );

      if (result.isSuccess && result.playerUrl != null) {
        _status = UploadStatus.success;
        _shareUrl = result.playerUrl;
        _uploadId = result.uploadId;
        _expiresAt = result.expiresAt ?? DateTime.now().add(const Duration(days: 30));
        _progress = 1.0;
        _currentStage = 'Streaming player page ready!';
        _isServerDown = false;
        _serverStatusCode = null;

        // Update item with playerUrl, uploadId, and expiry in history
        final updated = item.copyWith(
          shareUrl: _shareUrl,
          uploadId: _uploadId,
          expiresAt: _expiresAt,
        );
        await historyRepository.saveRecording(updated);

        notifyListeners();
        return true;
      } else {
        _status = UploadStatus.error;
        _isServerDown = result.isServerDown;
        _serverStatusCode = result.statusCode;
        _errorMessage = result.errorMessage ??
            'Upload failed. Check your network connection and try again.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = UploadStatus.error;
      _isServerDown = true;
      _serverStatusCode = 500;
      _errorMessage = 'An unexpected error occurred during upload: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> retry() async {
    if (_activeItem != null) {
      return await uploadRecording(_activeItem!);
    }
    return false;
  }

  void cancel() {
    uploadService.cancelUpload();
    _status = UploadStatus.idle;
    _progress = 0.0;
    _currentStage = 'Cancelled';
    notifyListeners();
  }

  void reset() {
    _status = UploadStatus.idle;
    _progress = 0.0;
    _currentStage = 'Preparing upload...';
    _shareUrl = null;
    _uploadId = null;
    _expiresAt = null;
    _errorMessage = null;
    _activeItem = null;
    notifyListeners();
  }
}
