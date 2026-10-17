import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qa_mate/models/recording_item.dart';
import 'package:qa_mate/services/history_repository.dart';
import 'package:qa_mate/services/screen_recorder_service.dart';
import 'package:qa_mate/services/upload_service.dart';
import 'package:qa_mate/providers/recording_provider.dart';
import 'package:qa_mate/providers/upload_provider.dart';
import 'package:provider/provider.dart';
import 'package:qa_mate/widgets/touch_visualizer.dart';
import 'package:qa_mate/widgets/video_trim_liner.dart';
import 'package:qa_mate/widgets/recording_indicator.dart';
import 'package:qa_mate/widgets/overlay_bubble_menu.dart';
import 'package:qa_mate/screens/preview_screen.dart';
import 'package:qa_mate/providers/history_provider.dart';
import 'package:qa_mate/models/overlay_event.dart';
import 'package:qa_mate/widgets/recording_control_pill.dart';
import 'package:qa_mate/widgets/video_preview_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RecordingItem Model Tests', () {
    test('formats duration, trimming, and file size correctly', () {
      final item = RecordingItem(
        id: '123',
        filePath: '/mock/path/video.mp4',
        fileName: 'video.mp4',
        createdAt: DateTime.now(),
        duration: const Duration(minutes: 2, seconds: 45),
        fileSizeBytes: 1024 * 1024 * 5, // 5 MB
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        thumbnailPath: '/mock/path/thumb.jpg',
        trimStart: const Duration(seconds: 15),
        trimEnd: const Duration(seconds: 75),
      );

      expect(item.formattedDuration, '01:00');
      expect(item.formattedFullDuration, '02:45');
      expect(item.formattedFileSize, '5.0 MB');
      expect(item.isTrimmed, isTrue);
      expect(item.isExpired, isFalse);
      expect(item.formattedExpiryCountdown, contains('day'));
      expect(item.thumbnailPath, '/mock/path/thumb.jpg');
    });

    test('serializes and deserializes to JSON properly with player url and trim range', () {
      final now = DateTime.now();
      final item = RecordingItem(
        id: 'rec_999',
        filePath: '/storage/rec_999.mp4',
        fileName: 'rec_999.mp4',
        createdAt: now,
        duration: const Duration(seconds: 75),
        fileSizeBytes: 2048,
        shareUrl: 'https://share.qamate.io/r/rec_999',
        uploadId: 'upload_xyz',
        thumbnailPath: '/storage/thumb_999.jpg',
        trimStart: const Duration(seconds: 5),
        trimEnd: const Duration(seconds: 60),
        expiresAt: now.add(const Duration(days: 30)),
      );

      final jsonMap = item.toMap();
      final reconstructed = RecordingItem.fromMap(jsonMap);

      expect(reconstructed.id, item.id);
      expect(reconstructed.filePath, item.filePath);
      expect(reconstructed.duration.inSeconds, 75);
      expect(reconstructed.shareUrl, 'https://share.qamate.io/r/rec_999');
      expect(reconstructed.uploadId, 'upload_xyz');
      expect(reconstructed.thumbnailPath, '/storage/thumb_999.jpg');
      expect(reconstructed.trimStart?.inSeconds, 5);
      expect(reconstructed.trimEnd?.inSeconds, 60);
      expect(reconstructed.isUploaded, isTrue);
    });
  });

  group('MockUploadService Tests', () {
    test('executes signed URL and streaming PUT stages, returns player URL', () async {
      final uploadService = MockUploadService();
      final stages = <String>[];
      final progressList = <double>[];

      final result = await uploadService.uploadRecording(
        videoPath: '/mock/sample.mp4',
        thumbnailPath: '/mock/thumb.jpg',
        trimStart: const Duration(seconds: 2),
        trimEnd: const Duration(seconds: 20),
        onProgress: (p, stage) {
          progressList.add(p);
          stages.add(stage);
        },
      );

      expect(result.isSuccess, isTrue);
      expect(result.playerUrl, isNotNull);
      // User requirement: streaming player-page URL (e.g. https://your-domain.com/r/{uploadId})
      expect(result.playerUrl, startsWith('https://share.qamate.io/r/'));
      expect(result.uploadId, isNotNull);
      expect(stages.isNotEmpty, isTrue);
      expect(stages.first, contains('pre-signed'));
      expect(progressList.last, 1.0);
    });

    test('handles failure and allows subsequent retry to succeed', () async {
      final uploadService = MockUploadService();
      uploadService.setSimulateFailure(true);

      final resultFail = await uploadService.uploadRecording(
        videoPath: '/mock/sample.mp4',
        thumbnailPath: null,
      );
      expect(resultFail.isSuccess, isFalse);
      expect(resultFail.errorMessage, contains('Worker error'));

      // Retry should succeed as failure flag is consumed
      final resultRetry = await uploadService.uploadRecording(
        videoPath: '/mock/sample.mp4',
        thumbnailPath: null,
      );
      expect(resultRetry.isSuccess, isTrue);
      expect(resultRetry.playerUrl, startsWith('https://share.qamate.io/r/'));
    });
  });

  group('ScreenRecorderService Tests', () {
    test('SimulatedScreenRecorderService lifecycle', () async {
      final service = SimulatedScreenRecorderService();
      expect(await service.isSupported(), isTrue);

      final started = await service.startRecording(outputPath: 'test_out.mp4');
      expect(started, isTrue);

      final outputPath = await service.stopRecording();
      expect(outputPath, 'test_out.mp4');

      expect(await service.pauseRecording(), isTrue);
      expect(await service.resumeRecording(), isTrue);
      expect(await service.bringAppToForeground(), isTrue);
    });
  });

  group('UploadProvider Tests', () {
    test('manages upload states, stage messages, and player URL correctly', () async {
      final uploadService = MockUploadService();
      final historyRepo = RecordingHistoryRepository();
      final provider = UploadProvider(
        uploadService: uploadService,
        historyRepository: historyRepo,
      );

      final item = RecordingItem(
        id: 'test_item',
        filePath: 'test_file.mp4',
        fileName: 'test_file.mp4',
        createdAt: DateTime.now(),
        duration: const Duration(seconds: 30),
        fileSizeBytes: 1024,
      );

      expect(provider.status, UploadStatus.idle);

      final success = await provider.uploadRecording(item);
      expect(success, isTrue);
      expect(provider.status, UploadStatus.success);
      expect(provider.shareUrl, startsWith('https://share.qamate.io/r/'));
      expect(provider.uploadId, isNotNull);
      expect(provider.progress, 1.0);
      expect(provider.currentStage, contains('ready'));
    });
  });

  group('RecordingProvider Tests', () {
    test('toggles audio and manages initial recording status', () {
      final recorderService = SimulatedScreenRecorderService();
      final historyRepo = RecordingHistoryRepository();
      final provider = RecordingProvider(
        recorderService: recorderService,
        historyRepository: historyRepo,
      );

      expect(provider.status, RecordingStatus.idle);
      expect(provider.isRecording, isFalse);
      expect(provider.isAudioEnabled, isTrue);

      provider.toggleAudio(false);
      expect(provider.isAudioEnabled, isFalse);

      provider.toggleAudio(true);
      expect(provider.isAudioEnabled, isTrue);
    });

    test('toggles show touch and persists state', () async {
      final recorderService = SimulatedScreenRecorderService();
      final historyRepo = RecordingHistoryRepository();
      final provider = RecordingProvider(
        recorderService: recorderService,
        historyRepository: historyRepo,
      );

      expect(provider.isShowTouchesEnabled, isFalse);

      final success = await provider.toggleShowTouches(true);
      expect(success, isTrue);
      expect(provider.isShowTouchesEnabled, isTrue);
      expect(await recorderService.getShowTouches(), isTrue);

      final successOff = await provider.toggleShowTouches(false);
      expect(successOff, isTrue);
      expect(provider.isShowTouchesEnabled, isFalse);
      expect(await recorderService.getShowTouches(), isFalse);
    });

    test('toggles pause and resume with state updates', () async {
      final recorderService = SimulatedScreenRecorderService();
      final historyRepo = RecordingHistoryRepository();
      final provider = RecordingProvider(
        recorderService: recorderService,
        historyRepository: historyRepo,
      );

      await provider.checkPermissions();
      // Start recording
      await provider.startRecording();
      expect(provider.isRecording, isTrue);
      expect(provider.isPaused, isFalse);

      // Pause
      await provider.togglePause();
      expect(provider.isPaused, isTrue);
      expect(provider.status, RecordingStatus.paused);

      // Resume
      await provider.togglePause();
      expect(provider.isPaused, isFalse);
      expect(provider.isRecording, isTrue);
      expect(provider.status, RecordingStatus.recording);

      await provider.cancelRecording();
    });
  });

  group('TouchVisualizer Widget Tests', () {
    testWidgets('paints touch circles when show touch is enabled', (tester) async {
      final recorderService = SimulatedScreenRecorderService();
      final historyRepo = RecordingHistoryRepository();
      final provider = RecordingProvider(
        recorderService: recorderService,
        historyRepository: historyRepo,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<RecordingProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: TouchVisualizer(
              child: Scaffold(
                body: Center(child: Text('App Content')),
              ),
            ),
          ),
        ),
      );

      // Initially disabled
      expect(find.byKey(const ValueKey('touch_visualizer_painter')), findsNothing);

      // Enable show touch
      await provider.toggleShowTouches(true);
      await tester.pumpAndSettle();

      // Trigger pointer down
      final gesture = await tester.createGesture();
      await gesture.down(const Offset(100, 100));
      await tester.pump();

      // Verify custom painter is present during active touch
      expect(find.byKey(const ValueKey('touch_visualizer_painter')), findsOneWidget);

      // Release touch
      await gesture.up();
      await tester.pump();

      // Pointer released
      expect(find.byKey(const ValueKey('touch_visualizer_painter')), findsNothing);
    });
  });

  group('VideoTrimLiner Widget Tests', () {
    testWidgets('renders trim section, play trim button, and triggers callbacks', (tester) async {
      bool playPauseCalled = false;
      Duration? seekTarget;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoTrimLiner(
              totalDuration: const Duration(seconds: 15),
              trimStart: const Duration(seconds: 2),
              trimEnd: const Duration(seconds: 8),
              isPlaying: false,
              currentPosition: const Duration(seconds: 4),
              onPlayPause: () {
                playPauseCalled = true;
              },
              onSeek: (target) {
                seekTarget = target;
              },
              onTrimStartChanged: (_) {},
              onTrimEndChanged: (_) {},
              onReset: () {},
            ),
          ),
        ),
      );

      // Verify header and elements exist
      expect(find.text('Trim Video Range'), findsOneWidget);
      expect(find.text('Play Trim'), findsOneWidget);
      expect(find.text('Start: 00:02'), findsOneWidget);
      expect(find.text('End: 00:08'), findsOneWidget);
      expect(find.text('Playhead: 00:04'), findsOneWidget);

      // Tap Play Trim button
      await tester.tap(find.text('Play Trim'));
      await tester.pump();
      expect(playPauseCalled, isTrue);

      // Tap on the timeline track to test seeking
      await tester.tap(find.byKey(const ValueKey('trim_timeline_slider')));
      await tester.pump();
      expect(seekTarget, isNotNull);
    });
  });

  group('RecordingIndicator Widget Tests', () {
    testWidgets('renders cleanly without overflow', (tester) async {
      final recorderService = SimulatedScreenRecorderService();
      final historyRepo = RecordingHistoryRepository();
      final provider = RecordingProvider(
        recorderService: recorderService,
        historyRepository: historyRepo,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RecordingIndicator(provider: provider),
            ),
          ),
        ),
      );

      expect(find.byType(RecordingIndicator), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
    });
  });

  group('OverlayBubbleMenu Widget Tests', () {
    testWidgets('renders pill and controls without overflow', (tester) async {
      await tester.pumpWidget(
        const OverlayBubbleMenuApp(),
      );

      expect(find.byType(OverlayBubbleMenu), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      // Tap pause button
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      // Tap menu expand button
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pump();
      expect(find.text('Touches'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
    });
  });

  group('PreviewScreen Widget Tests', () {
    testWidgets('renders preview page without overflow on mobile viewport', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final historyRepo = RecordingHistoryRepository();
      final uploadService = MockUploadService();
      final historyProv = HistoryProvider(repository: historyRepo);
      final uploadProv = UploadProvider(
        uploadService: uploadService,
        historyRepository: historyRepo,
      );

      final item = RecordingItem(
        id: 'preview_test_rec',
        filePath: 'non_existent_test_video.mp4',
        fileName: 'rec_1737849182391_very_long_test_recording.mp4',
        createdAt: DateTime.now(),
        duration: const Duration(seconds: 45),
        fileSizeBytes: 1024 * 1024 * 3,
        trimStart: const Duration(seconds: 5),
        trimEnd: const Duration(seconds: 40),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: historyProv),
            ChangeNotifierProvider.value(value: uploadProv),
          ],
          child: MaterialApp(
            home: PreviewScreen(recording: item),
          ),
        ),
      );
      await tester.pump();

      // Check header and buttons
      expect(find.text('Save as new'), findsOneWidget);
      expect(find.text('Replace original'), findsOneWidget);
      expect(find.byType(VideoTrimLiner), findsOneWidget);
      expect(find.byType(VideoPreviewPlayer), findsOneWidget);
    });
  });

  group('OverlayEvent Model Tests', () {
    test('serializes and deserializes OverlayStateUpdate properly', () {
      const update = OverlayStateUpdate(
        elapsedSeconds: 42,
        isPaused: true,
        isAudioEnabled: false,
        isTouchesEnabled: true,
        status: 'paused',
      );

      final jsonStr = update.toJson();
      final decoded = OverlayStateUpdate.fromJson(jsonStr);

      expect(decoded.elapsedSeconds, 42);
      expect(decoded.isPaused, isTrue);
      expect(decoded.isAudioEnabled, isFalse);
      expect(decoded.isTouchesEnabled, isTrue);
      expect(decoded.status, 'paused');
    });

    test('serializes and deserializes OverlayAction properly', () {
      const action = OverlayAction(
        action: OverlayAction.requestSync,
        payload: {'version': 2},
      );

      final jsonStr = action.toJson();
      final decoded = OverlayAction.fromJson(jsonStr);

      expect(decoded.action, OverlayAction.requestSync);
      expect(decoded.payload['version'], 2);
    });
  });

  group('RecordingControlPill Widget Tests', () {
    testWidgets('renders pill with timer, pause, mic, discard, and stop buttons', (tester) async {
      final recorderService = SimulatedScreenRecorderService();
      final historyRepo = RecordingHistoryRepository();
      final provider = RecordingProvider(
        recorderService: recorderService,
        historyRepository: historyRepo,
      );

      bool finishCalled = false;
      bool cancelCalled = false;
      bool pauseCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RecordingControlPill(
                provider: provider,
                onFinish: () => finishCalled = true,
                onCancel: () => cancelCalled = true,
                onPauseResume: () => pauseCalled = true,
              ),
            ),
          ),
        ),
      );

      // Verify timer and buttons exist
      expect(find.byType(RecordingControlPill), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byKey(const ValueKey('pill_finish_btn')), findsOneWidget);

      // Tap pause button
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      expect(pauseCalled, isTrue);

      // Tap mic button
      expect(provider.isAudioEnabled, isTrue);
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      expect(provider.isAudioEnabled, isFalse);
      expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);

      // Tap cancel button
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(cancelCalled, isTrue);

      // Tap finish button
      await tester.tap(find.byKey(const ValueKey('pill_finish_btn')));
      await tester.pump();
      expect(finishCalled, isTrue);
    });
  });
}

