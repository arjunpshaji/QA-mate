import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/recording_item.dart';
import '../providers/history_provider.dart';
import '../providers/upload_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/upload_progress_view.dart';
import '../widgets/video_preview_player.dart';
import '../widgets/video_trim_liner.dart';
import 'share_screen.dart';

class PreviewScreen extends StatefulWidget {
  final RecordingItem recording;

  const PreviewScreen({super.key, required this.recording});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final GlobalKey<VideoPreviewPlayerState> _playerKey =
      GlobalKey<VideoPreviewPlayerState>();

  bool _isUploadingModalVisible = false;
  late Duration _totalDuration;
  late Duration _trimStart;
  late Duration _trimEnd;
  Duration _currentPosition = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _totalDuration = widget.recording.duration > Duration.zero
        ? widget.recording.duration
        : const Duration(seconds: 42);
    _trimStart = widget.recording.trimStart ?? Duration.zero;
    _trimEnd = widget.recording.trimEnd ?? _totalDuration;
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _startUploadAndShare() async {
    final uploadProvider = context.read<UploadProvider>();
    setState(() {
      _isUploadingModalVisible = true;
    });

    final itemToUpload = widget.recording.copyWith(
      trimStart: _trimStart,
      trimEnd: _trimEnd,
      duration: _trimEnd > _trimStart ? (_trimEnd - _trimStart) : _totalDuration,
    );

    final success = await uploadProvider.uploadRecording(itemToUpload);
    if (!mounted) return;

    if (success) {
      setState(() {
        _isUploadingModalVisible = false;
      });

      context.read<HistoryProvider>().loadHistory();

      final updatedRecording = itemToUpload.copyWith(
        shareUrl: uploadProvider.shareUrl,
        uploadId: uploadProvider.uploadId,
        expiresAt: uploadProvider.expiresAt,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ShareScreen(recording: updatedRecording),
        ),
      );
    }
  }

  void _saveAsNew() async {
    final historyProv = context.read<HistoryProvider>();
    final keepingDuration = _trimEnd - _trimStart;
    final newRecording = widget.recording.copyWith(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: 'Trimmed_${widget.recording.fileName}',
      createdAt: DateTime.now(),
      trimStart: _trimStart,
      trimEnd: _trimEnd,
      duration: keepingDuration,
    );
    await historyProv.repository.saveRecording(newRecording);
    await historyProv.loadHistory();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Saved as new recording!'),
          backgroundColor: AppTheme.surfaceContainerHigh,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    }
  }

  void _replaceOriginal() async {
    final historyProv = context.read<HistoryProvider>();
    final keepingDuration = _trimEnd - _trimStart;
    final updatedRecording = widget.recording.copyWith(
      trimStart: _trimStart,
      trimEnd: _trimEnd,
      duration: keepingDuration,
    );
    await historyProv.updateRecording(updatedRecording);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Original recording updated!'),
          backgroundColor: AppTheme.surfaceContainerHigh,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keepingDuration = (_trimEnd - _trimStart).isNegative
        ? Duration.zero
        : (_trimEnd - _trimStart);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Column(
          children: [
            Text(
              widget.recording.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_formatDuration(_totalDuration)}, ${widget.recording.formattedFileSize}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white, size: 22),
            tooltip: 'Share recording',
            onPressed: () {
              if (widget.recording.isUploaded) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShareScreen(recording: widget.recording),
                  ),
                );
              } else {
                _startUploadAndShare();
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Video Viewport Card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      color: const Color(0xFF161C2C),
                      child: VideoPreviewPlayer(
                        key: _playerKey,
                        filePath: widget.recording.filePath,
                        fallbackDuration: _totalDuration,
                        formattedSize: widget.recording.formattedFileSize,
                        trimStart: _trimStart,
                        trimEnd: _trimEnd,
                        compact: true,
                        showScrubber: false,
                        showMetaBar: false,
                        onDurationReady: (dur) {
                          if (!mounted) return;
                          setState(() {
                            _totalDuration = dur;
                            if (_trimEnd > dur) _trimEnd = dur;
                          });
                        },
                        onPositionChanged: (pos) {
                          if (!mounted) return;
                          setState(() => _currentPosition = pos);
                        },
                        onPlayingChanged: (playing) {
                          if (!mounted) return;
                          setState(() => _isPlaying = playing);
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Playback control row (-5s, Play/Pause, +5s)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _formatDuration(_currentPosition),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        TextButton(
                          onPressed: () {
                            final target = _currentPosition - const Duration(seconds: 5);
                            _playerKey.currentState?.seekTo(
                              target.isNegative ? Duration.zero : target,
                            );
                          },
                          child: const Text(
                            '-5 s',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Large Circular Play Button
                        GestureDetector(
                          onTap: () {
                            _playerKey.currentState?.togglePlayPause();
                          },
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: const Color(0xFF0F121C),
                              size: 26,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        TextButton(
                          onPressed: () {
                            final target = _currentPosition + const Duration(seconds: 5);
                            _playerKey.currentState?.seekTo(
                              target > _totalDuration ? _totalDuration : target,
                            );
                          },
                          child: const Text(
                            '+5 s',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          _formatDuration(_totalDuration),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Trim Section Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Trim',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_formatDuration(_trimStart)} to ${_formatDuration(_trimEnd)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Interactive VideoTrimLiner Scrubber
                  VideoTrimLiner(
                    totalDuration: _totalDuration,
                    trimStart: _trimStart,
                    trimEnd: _trimEnd,
                    isPlaying: _isPlaying,
                    currentPosition: _currentPosition,
                    onPlayPause: () => _playerKey.currentState?.togglePlayPause(),
                    onSeek: (target) => _playerKey.currentState?.seekTo(target),
                    onTrimStartChanged: (start) => setState(() => _trimStart = start),
                    onTrimEndChanged: (end) => setState(() => _trimEnd = end),
                    onReset: () {
                      setState(() {
                        _trimStart = Duration.zero;
                        _trimEnd = _totalDuration;
                      });
                      _playerKey.currentState?.seekTo(Duration.zero);
                    },
                  ),

                  const SizedBox(height: 10),

                  // Sub-readout: 0:00, Keeping X s, Total
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '0:00',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                        const SizedBox(width: 32),
                        Text(
                          'Keeping ${keepingDuration.inSeconds} s',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 32),
                        Text(
                          _formatDuration(_totalDuration),
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Action Buttons: Save as new & Replace original
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6E7CF0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _saveAsNew,
                    child: const Text(
                      'Save as new',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AppTheme.border),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _replaceOriginal,
                    child: const Text(
                      'Replace original',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),

            // Modal upload progress overlay
            if (_isUploadingModalVisible)
              Consumer<UploadProvider>(
                builder: (context, uploadProv, _) {
                  return Container(
                    color: Colors.black.withValues(alpha: 0.8),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: UploadProgressView(
                          uploadProvider: uploadProv,
                          onRetry: () => _startUploadAndShare(),
                          onCancel: () {
                            uploadProv.cancel();
                            setState(() {
                              _isUploadingModalVisible = false;
                            });
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
