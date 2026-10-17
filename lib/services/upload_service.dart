import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

class UploadResult {
  final bool isSuccess;
  final String? playerUrl;
  final String? uploadId;
  final String? thumbnailUrl;
  final DateTime? expiresAt;
  final String? errorMessage;
  final bool isServerDown;
  final int? statusCode;

  const UploadResult.success({
    required this.playerUrl,
    required this.uploadId,
    required this.expiresAt,
    this.thumbnailUrl,
  })  : isSuccess = true,
        isServerDown = false,
        statusCode = 200,
        errorMessage = null;

  const UploadResult.failure({
    required this.errorMessage,
    this.isServerDown = false,
    this.statusCode,
  })  : isSuccess = false,
        playerUrl = null,
        uploadId = null,
        thumbnailUrl = null,
        expiresAt = null;
}

abstract class UploadService {
  Future<UploadResult> uploadRecording({
    required String videoPath,
    required String? thumbnailPath,
    Duration? trimStart,
    Duration? trimEnd,
    void Function(double progress, String stage)? onProgress,
  });

  void cancelUpload();

  Future<bool> checkServerHealth();
}

/// Production implementation connecting to Cloudflare Worker or backend endpoint.
class PresignedUploadService implements UploadService {
  final String workerEndpoint;
  bool _isCancelled = false;

  PresignedUploadService({required this.workerEndpoint});

  @override
  Future<UploadResult> uploadRecording({
    required String videoPath,
    required String? thumbnailPath,
    Duration? trimStart,
    Duration? trimEnd,
    void Function(double progress, String stage)? onProgress,
  }) async {
    _isCancelled = false;

    try {
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        return const UploadResult.failure(errorMessage: 'Video file not found.');
      }
      final videoSize = await videoFile.length();

      int thumbSize = 0;
      if (thumbnailPath != null) {
        final thumbFile = File(thumbnailPath);
        if (await thumbFile.exists()) {
          thumbSize = await thumbFile.length();
        }
      }

      // Step 1: Request pre-signed URLs from backend Worker
      onProgress?.call(0.1, 'Requesting upload authorization...');
      final signedUrlResp = await http.post(
        Uri.parse(workerEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'video': {
            'contentType': 'video/mp4',
            'fileSize': videoSize,
            'trimStartMs': trimStart?.inMilliseconds ?? 0,
            'trimEndMs': trimEnd?.inMilliseconds,
          },
          'thumbnail': {
            'contentType': 'image/jpeg',
            'fileSize': thumbSize,
          },
        }),
      );

      if (_isCancelled) {
        return const UploadResult.failure(errorMessage: 'Upload was cancelled.');
      }

      if (signedUrlResp.statusCode != 200 && signedUrlResp.statusCode != 201) {
        final code = signedUrlResp.statusCode;
        final bool isServerIssue = code == 402 || code == 429 || code >= 500;
        String message;
        if (code == 402) {
          message = 'Cloud storage billing limit reached or subscription paused. Your video is safe locally.';
        } else if (code == 429) {
          message = 'Cloud storage request quota exceeded. Please try again later.';
        } else if (code == 503 || code == 502 || code == 504) {
          message = 'Cloud storage server is temporarily paused or undergoing maintenance (HTTP $code).';
        } else {
          message = 'Failed to obtain upload authorization ($code): ${signedUrlResp.body}';
        }

        return UploadResult.failure(
          errorMessage: message,
          isServerDown: isServerIssue,
          statusCode: code,
        );
      }

      final data = json.decode(signedUrlResp.body) as Map<String, dynamic>;
      final String videoUploadUrl = data['videoUploadUrl'] as String;
      final String? thumbUploadUrl = data['thumbnailUploadUrl'] as String?;
      final String playerUrl = data['playerUrl'] as String;
      final String uploadId = data['uploadId'] as String;
      final DateTime expiresAt = data['expiresAt'] != null
          ? DateTime.parse(data['expiresAt'] as String)
          : DateTime.now().add(const Duration(days: 30));

      // Step 2: HTTP PUT video binary to signed URL
      onProgress?.call(0.2, 'Uploading video to secure storage...');
      final videoBytes = await videoFile.readAsBytes();
      final videoPutResp = await http.put(
        Uri.parse(videoUploadUrl),
        headers: {
          'Content-Type': 'video/mp4',
          'Content-Length': videoBytes.length.toString(),
        },
        body: videoBytes,
      );

      if (_isCancelled) {
        return const UploadResult.failure(errorMessage: 'Upload was cancelled.');
      }

      if (videoPutResp.statusCode < 200 || videoPutResp.statusCode >= 300) {
        final code = videoPutResp.statusCode;
        final isServerIssue = code == 402 || code == 429 || code >= 500;
        return UploadResult.failure(
          errorMessage: isServerIssue
              ? 'Cloud storage rejected payload ($code). Server may be paused or at billing quota.'
              : 'Video PUT upload failed ($code).',
          isServerDown: isServerIssue,
          statusCode: code,
        );
      }
      onProgress?.call(0.8, 'Video uploaded successfully.');

      // Step 3: HTTP PUT thumbnail binary if present
      if (thumbUploadUrl != null && thumbnailPath != null) {
        final thumbFile = File(thumbnailPath);
        if (await thumbFile.exists()) {
          onProgress?.call(0.85, 'Uploading thumbnail...');
          final thumbBytes = await thumbFile.readAsBytes();
          await http.put(
            Uri.parse(thumbUploadUrl),
            headers: {
              'Content-Type': 'image/jpeg',
              'Content-Length': thumbBytes.length.toString(),
            },
            body: thumbBytes,
          );
        }
      }

      onProgress?.call(1.0, 'Streaming player page ready.');
      return UploadResult.success(
        playerUrl: playerUrl,
        uploadId: uploadId,
        expiresAt: expiresAt,
      );
    } catch (e) {
      final isNetworkOrServer = e is SocketException ||
          e is http.ClientException ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('timed out');

      return UploadResult.failure(
        errorMessage: isNetworkOrServer
            ? 'Cannot reach cloud server. Server may be paused, offline, or your device is disconnected.'
            : 'Error during upload: $e',
        isServerDown: isNetworkOrServer,
        statusCode: isNetworkOrServer ? 503 : null,
      );
    }
  }

  @override
  void cancelUpload() {
    _isCancelled = true;
  }

  @override
  Future<bool> checkServerHealth() async {
    try {
      final baseUri = Uri.parse(workerEndpoint).resolve('/');
      final response = await http.get(baseUri).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

/// Mock upload service simulating pre-signed URL request, video PUT, thumbnail PUT,
/// and streaming player URL generation.
class MockUploadService implements UploadService {
  bool _isCancelled = false;
  bool _simulateFailure = false;
  bool _simulateServerDown = false;

  void setSimulateFailure(bool fail) {
    _simulateFailure = fail;
  }

  void setSimulateServerDown(bool down) {
    _simulateServerDown = down;
  }

  bool get willFail => _simulateFailure;
  bool get willSimulateServerDown => _simulateServerDown;

  @override
  Future<bool> checkServerHealth() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return !_simulateServerDown;
  }

  @override
  Future<UploadResult> uploadRecording({
    required String videoPath,
    required String? thumbnailPath,
    Duration? trimStart,
    Duration? trimEnd,
    void Function(double progress, String stage)? onProgress,
  }) async {
    _isCancelled = false;

    // Step 1: Simulate signed-URL negotiation
    onProgress?.call(0.1, 'Requesting pre-signed upload URLs...');
    await Future.delayed(const Duration(milliseconds: 300));

    if (_isCancelled) {
      return const UploadResult.failure(errorMessage: 'Upload was cancelled.');
    }

    if (_simulateServerDown) {
      return const UploadResult.failure(
        errorMessage: 'Cloud storage server is temporarily paused or at billing quota (Simulated HTTP 503).',
        isServerDown: true,
        statusCode: 503,
      );
    }

    if (_simulateFailure) {
      _simulateFailure = false; // Reset so retry works
      return const UploadResult.failure(
        errorMessage: 'Backend Worker error: Unable to generate pre-signed upload URL. Please retry.',
      );
    }

    // Step 2: Simulate streaming video PUT (progress 0.15 -> 0.8)
    for (int step = 2; step <= 8; step++) {
      if (_isCancelled) {
        return const UploadResult.failure(errorMessage: 'Upload was cancelled.');
      }
      await Future.delayed(const Duration(milliseconds: 140));
      final progress = step / 10.0;
      final pct = (progress * 100).toInt();
      onProgress?.call(progress, 'Streaming video upload ($pct%)...');
    }

    // Step 3: Simulate thumbnail PUT (progress 0.85 -> 0.95)
    onProgress?.call(0.88, 'Uploading video thumbnail...');
    await Future.delayed(const Duration(milliseconds: 250));

    onProgress?.call(0.95, 'Finalizing streaming player page...');
    await Future.delayed(const Duration(milliseconds: 250));

    if (_isCancelled) {
      return const UploadResult.failure(errorMessage: 'Upload was cancelled.');
    }

    final uploadId = _generateRandomString(10);
    // User requirement: streaming player-page URL (e.g. https://share.qamate.io/r/{uploadId})
    final playerUrl = 'https://share.qamate.io/r/$uploadId';
    final expiryDate = DateTime.now().add(const Duration(days: 30));

    onProgress?.call(1.0, 'Streaming player page ready.');
    return UploadResult.success(
      playerUrl: playerUrl,
      uploadId: uploadId,
      expiresAt: expiryDate,
      thumbnailUrl: 'https://share.qamate.io/thumbs/$uploadId.jpg',
    );
  }

  @override
  void cancelUpload() {
    _isCancelled = true;
  }

  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
      ),
    );
  }
}
