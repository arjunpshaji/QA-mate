import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';

class VideoPreviewPlayer extends StatefulWidget {
  final String filePath;
  final Duration fallbackDuration;
  final String formattedSize;
  final Duration? trimStart;
  final Duration? trimEnd;
  final bool compact;
  final bool showScrubber;
  final bool showMetaBar;
  final ValueChanged<Duration>? onDurationReady;
  final ValueChanged<Duration>? onPositionChanged;
  final ValueChanged<bool>? onPlayingChanged;

  const VideoPreviewPlayer({
    super.key,
    required this.filePath,
    required this.fallbackDuration,
    required this.formattedSize,
    this.trimStart,
    this.trimEnd,
    this.compact = false,
    this.showScrubber = true,
    this.showMetaBar = true,
    this.onDurationReady,
    this.onPositionChanged,
    this.onPlayingChanged,
  });

  @override
  State<VideoPreviewPlayer> createState() => VideoPreviewPlayerState();
}

class VideoPreviewPlayerState extends State<VideoPreviewPlayer>
    with SingleTickerProviderStateMixin {
  // --- Native video controller ---
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isLoading = true;

  // --- Overlay / controls visibility ---
  bool _showControls = true;
  Timer? _hideControlsTimer;

  // --- Seeking guard ---
  bool _isSeeking = false;

  // --- Simulated playback (when file isn't a valid video / desktop) ---
  Timer? _simulatedTimer;
  Duration _simulatedPosition = Duration.zero;
  bool _simulatedIsPlaying = false;

  // --- Control-icon animation ---
  late AnimationController _playIconAnim;

  // ── public getters for parent ────────────────────────────────────────────
  bool get isPlaying =>
      _isInitialized ? (_controller?.value.isPlaying ?? false) : _simulatedIsPlaying;

  Duration get currentPosition =>
      _isInitialized ? (_controller?.value.position ?? Duration.zero) : _simulatedPosition;

  Duration get totalDuration {
    if (_isInitialized && _controller != null) {
      final d = _controller!.value.duration;
      if (d > Duration.zero) return d;
    }
    return widget.fallbackDuration > Duration.zero
        ? widget.fallbackDuration
        : const Duration(seconds: 10);
  }

  // ── lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _playIconAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _initPlayer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _simulatedTimer?.cancel();
    _playIconAnim.dispose();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  // ── player init ──────────────────────────────────────────────────────────
  Future<void> _initPlayer() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    VideoPlayerController? controller;
    try {
      final file = File(widget.filePath);
      final exists = await file.exists();
      final size = exists ? await file.length() : 0;

      debugPrint('[VideoPreviewPlayer] file=$file exists=$exists size=$size');

      // Files under 1 KB cannot be a real video (just a stub/ftyp-only MP4).
      // Skip the expensive ExoPlayer probe and go straight to the simulated
      // fallback so the UI is never stuck on a spinner.
      if (!exists || size < 1024) {
        debugPrint('[VideoPreviewPlayer] file missing/too small ($size bytes) → fallback');
        _onError();
        return;
      }

      // Wait for the file size to stabilize (moov atom fully flushed).
      // MediaRecorder writes the moov atom synchronously on stop(), but the
      // OS kernel buffer may not have hit the disk yet. Poll for up to 2 s.
      var prevSize = size;
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final newSize = await file.length();
        if (newSize == prevSize && newSize > 0) break; // stable
        prevSize = newSize;
        debugPrint('[VideoPreviewPlayer] waiting for file flush… size=$newSize');
      }
      debugPrint('[VideoPreviewPlayer] file stable at ${await file.length()} bytes');

      controller = VideoPlayerController.file(file);

      // initialize() can hang forever on ExoPlayer for invalid/incomplete media.
      // Timeout ensures we always fall through to the simulated player.
      await controller.initialize().timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          throw TimeoutException('VideoPlayer.initialize timed out after 12s');
        },
      );

      if (!mounted) {
        controller.dispose();
        return;
      }

      // Log the full controller state so we can see if there's a hidden error
      final val = controller.value;
      debugPrint(
        '[VideoPreviewPlayer] init done — '
        'duration=${val.duration} '
        'aspectRatio=${val.aspectRatio} '
        'hasError=${val.hasError} '
        'errorDescription=${val.errorDescription}',
      );

      // If the controller reports an error after initialisation (e.g. empty
      // moov atom), bail out to the simulated player instead of a black screen.
      if (val.hasError) {
        controller.dispose();
        if (mounted) _onError();
        return;
      }

      // CRITICAL for Android: seek to frame 0 immediately after init.
      // Without this the video surface stays black until the first play().
      await controller.seekTo(Duration.zero);
      await controller.setVolume(1.0);

      final dur = val.duration;
      if (dur > Duration.zero) {
        widget.onDurationReady?.call(dur);
      }

      controller.addListener(_onControllerUpdate);

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitialized = true;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[VideoPreviewPlayer] init failed ($e) → simulated fallback');
      controller?.dispose();
      if (mounted) _onError();
    }
  }


  void _onError() {
    final fallback = widget.fallbackDuration > Duration.zero
        ? widget.fallbackDuration
        : const Duration(seconds: 10);
    widget.onDurationReady?.call(fallback);
    setState(() {
      _hasError = true;
      _isLoading = false;
      // Start at the beginning of the simulated range (but paused).
      // The user taps the play button to start.
      _simulatedPosition = widget.trimStart ?? Duration.zero;
    });
  }

  void _onControllerUpdate() {
    if (!mounted || _controller == null || _isSeeking) return;

    final pos = _controller!.value.position;
    final maxDur = _controller!.value.duration;
    final playing = _controller!.value.isPlaying;

    // Notify parent
    widget.onPositionChanged?.call(pos);
    widget.onPlayingChanged?.call(playing);

    // Compute effective trim bounds
    final start = _safeDuration(widget.trimStart ?? Duration.zero, Duration.zero, maxDur);
    final end = _safeDuration(
      widget.trimEnd ?? maxDur,
      start + const Duration(milliseconds: 150),
      maxDur,
    );

    // Loop within trim range
    if (playing && end > start && pos >= end) {
      _isSeeking = true;
      _controller!.seekTo(start).then((_) {
        if (mounted && _controller != null) {
          _isSeeking = false;
          _controller!.play();
        }
      });
    }

    if (mounted) setState(() {});
  }

  // ── public API ───────────────────────────────────────────────────────────
  Future<void> seekTo(Duration target) async {
    if (_isInitialized && _controller != null) {
      _isSeeking = true;
      await _controller!.seekTo(target);
      _isSeeking = false;
      widget.onPositionChanged?.call(target);
      if (mounted) setState(() {});
    } else {
      setState(() => _simulatedPosition = target);
      widget.onPositionChanged?.call(target);
    }
  }

  Future<void> togglePlayPause() async {
    _resetControlsTimer();

    if (_isInitialized && _controller != null) {
      if (_controller!.value.isPlaying) {
        await _controller!.pause();
        widget.onPlayingChanged?.call(false);
        _playIconAnim.reverse();
      } else {
        // Make sure we start inside the trim window
        final maxDur = _controller!.value.duration;
        final start = _safeDuration(widget.trimStart ?? Duration.zero, Duration.zero, maxDur);
        final end = _safeDuration(
          widget.trimEnd ?? maxDur,
          start + const Duration(milliseconds: 150),
          maxDur,
        );
        final pos = _controller!.value.position;
        if (pos >= end || pos < start) {
          _isSeeking = true;
          await _controller!.seekTo(start);
          _isSeeking = false;
        }
        await _controller!.play();
        widget.onPlayingChanged?.call(true);
        _playIconAnim.forward();
      }
      if (mounted) setState(() {});
    } else {
      // Simulated fallback
      _toggleSimulated();
    }
  }

  // ── controls overlay auto-hide ───────────────────────────────────────────
  void _onVideoTap() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _resetControlsTimer();
  }

  void _resetControlsTimer() {
    _hideControlsTimer?.cancel();
    if (!mounted) return;
    setState(() => _showControls = true);
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && isPlaying) setState(() => _showControls = false);
    });
  }

  // ── simulated playback ───────────────────────────────────────────────────
  void _toggleSimulated() {
    if (_simulatedIsPlaying) {
      _simulatedTimer?.cancel();
      setState(() => _simulatedIsPlaying = false);
      widget.onPlayingChanged?.call(false);
      _playIconAnim.reverse();
    } else {
      final maxDur = totalDuration;
      final start = _safeDuration(widget.trimStart ?? Duration.zero, Duration.zero, maxDur);
      final end = _safeDuration(
        widget.trimEnd ?? maxDur,
        start + const Duration(milliseconds: 150),
        maxDur,
      );
      if (_simulatedPosition >= end || _simulatedPosition < start) {
        _simulatedPosition = start;
      }
      setState(() => _simulatedIsPlaying = true);
      widget.onPlayingChanged?.call(true);
      _playIconAnim.forward();
      _simulatedTimer?.cancel();
      _simulatedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted) return;
        final next = _simulatedPosition.inMilliseconds + 100;
        setState(() {
          _simulatedPosition = next >= end.inMilliseconds
              ? start
              : Duration(milliseconds: next);
        });
        widget.onPositionChanged?.call(_simulatedPosition);
      });
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────
  Duration _safeDuration(Duration val, Duration min, Duration max) {
    if (max <= min) return min;
    if (val < min) return min;
    if (val > max) return max;
    return val;
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final playing = isPlaying;
    final pos = currentPosition;
    final dur = totalDuration;
    final maxMs = dur.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final curMs = pos.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Video viewport ───────────────────────────────────────────────
          AspectRatio(
            aspectRatio: widget.compact ? 16 / 9 : 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                // ── Content: native video OR fallback ───────────────────
                if (_isLoading)
                  _buildLoadingView()
                else if (_isInitialized && _controller != null)
                  _buildNativeVideo()
                else
                  _buildFallbackView(playing),

                // ── Controls overlay (always tappable) ──────────────────
                if (!_isLoading)
                  _buildControlsOverlay(playing),
              ],
            ),
          ),

          // ── Scrubber ─────────────────────────────────────────────────────
          if (widget.showScrubber)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: [
                  Text(_fmt(pos),
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: AppTheme.primary,
                        inactiveTrackColor: AppTheme.border,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: curMs,
                        min: 0.0,
                        max: maxMs,
                        onChanged: (v) => seekTo(Duration(milliseconds: v.toInt())),
                      ),
                    ),
                  ),
                  Text(_fmt(dur),
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),

          // ── Meta chips ───────────────────────────────────────────────────
          if (!widget.compact && widget.showMetaBar) _buildMetaBar(dur),
        ],
      ),
    );
  }

  // ── sub-builders ─────────────────────────────────────────────────────────

  Widget _buildLoadingView() {
    return Container(
      color: const Color(0xFF0F172A),
      child: const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppTheme.primary,
        ),
      ),
    );
  }

  Widget _buildNativeVideo() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onVideoTap,
      child: Container(
        color: Colors.black, // explicit black bg so the texture has a surface
        child: Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio > 0
                ? _controller!.value.aspectRatio
                : 16 / 9,
            child: VideoPlayer(_controller!),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackView(bool playing) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onVideoTap,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A2438), Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: playing
                      ? AppTheme.cyanAccent.withValues(alpha: 0.15)
                      : AppTheme.primary.withValues(alpha: 0.12),
                  border: Border.all(
                    color: playing
                        ? AppTheme.cyanAccent
                        : AppTheme.primary.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  playing
                      ? Icons.graphic_eq_rounded
                      : (_hasError ? Icons.video_file_outlined : Icons.videocam_rounded),
                  color: playing ? AppTheme.cyanAccent : AppTheme.primaryLight,
                  size: 36,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                playing
                    ? 'Previewing trim...'
                    : (_hasError ? 'Screen recording captured' : 'Tap play to preview'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: playing ? AppTheme.cyanAccent : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.filePath.split(Platform.pathSeparator).last,
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay(bool playing) {
    return AnimatedOpacity(
      opacity: _showControls || !playing ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: togglePlayPause,
        child: Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.65),
              border: Border.all(
                color: playing ? AppTheme.cyanAccent : Colors.white38,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 16,
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(playing),
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaBar(Duration dur) {
    final trimmedDur =
        (widget.trimEnd != null && widget.trimStart != null && widget.trimEnd! > widget.trimStart!)
            ? widget.trimEnd! - widget.trimStart!
            : dur;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _chip(Icons.timer_outlined, 'Trimmed Length', _fmt(trimmedDur)),
          Container(height: 24, width: 1, color: AppTheme.border),
          _chip(Icons.data_usage_rounded, 'File Size', widget.formattedSize),
          Container(height: 24, width: 1, color: AppTheme.border),
          _chip(Icons.video_file_outlined, 'Format', 'MP4 / H.264'),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppTheme.textMuted),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
      ],
    );
  }
}
