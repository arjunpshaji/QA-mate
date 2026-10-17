import 'dart:convert';
import 'dart:io';

class RecordingItem {
  final String id;
  final String filePath;
  final String fileName;
  final DateTime createdAt;
  final Duration duration;
  final int fileSizeBytes;
  final String? shareUrl;
  final DateTime? expiresAt;
  final String? thumbnailPath;
  final String? uploadId;
  final Duration? trimStart;
  final Duration? trimEnd;

  const RecordingItem({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.createdAt,
    required this.duration,
    required this.fileSizeBytes,
    this.shareUrl,
    this.expiresAt,
    this.thumbnailPath,
    this.uploadId,
    this.trimStart,
    this.trimEnd,
  });

  bool get isUploaded => shareUrl != null && shareUrl!.isNotEmpty;

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  Duration get remainingTimeToExpiry {
    if (expiresAt == null) return Duration.zero;
    final diff = expiresAt!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String get formattedExpiryCountdown {
    if (expiresAt == null) return 'Expires in 30 days';
    final remaining = remainingTimeToExpiry;
    if (remaining == Duration.zero) return 'Expired';
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;

    if (days > 0) {
      return '$days day${days > 1 ? 's' : ''}, $hours hr${hours > 1 ? 's' : ''} left';
    } else if (hours > 0) {
      return '$hours hr${hours > 1 ? 's' : ''}, $minutes min left';
    } else {
      return '$minutes min left';
    }
  }

  Duration get effectiveDuration {
    final start = trimStart ?? Duration.zero;
    final end = trimEnd ?? duration;
    final diff = end - start;
    return diff.isNegative ? duration : diff;
  }

  String get formattedDuration {
    final d = effectiveDuration;
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get formattedFullDuration {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  bool get isTrimmed =>
      (trimStart != null && trimStart! > Duration.zero) ||
      (trimEnd != null && trimEnd! < duration);

  String get formattedFileSize {
    if (fileSizeBytes < 1024) {
      return '$fileSizeBytes B';
    } else if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  bool get fileExists {
    try {
      return File(filePath).existsSync();
    } catch (_) {
      return false;
    }
  }

  bool get hasThumbnail {
    if (thumbnailPath == null) return false;
    try {
      return File(thumbnailPath!).existsSync();
    } catch (_) {
      return false;
    }
  }

  RecordingItem copyWith({
    String? id,
    String? filePath,
    String? fileName,
    DateTime? createdAt,
    Duration? duration,
    int? fileSizeBytes,
    String? shareUrl,
    DateTime? expiresAt,
    String? thumbnailPath,
    String? uploadId,
    Duration? trimStart,
    Duration? trimEnd,
  }) {
    return RecordingItem(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      createdAt: createdAt ?? this.createdAt,
      duration: duration ?? this.duration,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      shareUrl: shareUrl ?? this.shareUrl,
      expiresAt: expiresAt ?? this.expiresAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      uploadId: uploadId ?? this.uploadId,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'fileName': fileName,
      'createdAt': createdAt.toIso8601String(),
      'durationMs': duration.inMilliseconds,
      'fileSizeBytes': fileSizeBytes,
      'shareUrl': shareUrl,
      'expiresAt': expiresAt?.toIso8601String(),
      'thumbnailPath': thumbnailPath,
      'uploadId': uploadId,
      'trimStartMs': trimStart?.inMilliseconds,
      'trimEndMs': trimEnd?.inMilliseconds,
    };
  }

  factory RecordingItem.fromMap(Map<String, dynamic> map) {
    return RecordingItem(
      id: map['id'] as String,
      filePath: map['filePath'] as String,
      fileName: map['fileName'] as String? ?? 'Recording.mp4',
      createdAt: DateTime.parse(map['createdAt'] as String),
      duration: Duration(milliseconds: map['durationMs'] as int? ?? 0),
      fileSizeBytes: map['fileSizeBytes'] as int? ?? 0,
      shareUrl: map['shareUrl'] as String?,
      expiresAt: map['expiresAt'] != null
          ? DateTime.parse(map['expiresAt'] as String)
          : null,
      thumbnailPath: map['thumbnailPath'] as String?,
      uploadId: map['uploadId'] as String?,
      trimStart: map['trimStartMs'] != null
          ? Duration(milliseconds: map['trimStartMs'] as int)
          : null,
      trimEnd: map['trimEndMs'] != null
          ? Duration(milliseconds: map['trimEndMs'] as int)
          : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory RecordingItem.fromJson(String source) =>
      RecordingItem.fromMap(json.decode(source) as Map<String, dynamic>);
}
