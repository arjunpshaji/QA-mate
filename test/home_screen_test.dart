// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qa_mate/main.dart';
import 'package:qa_mate/providers/history_provider.dart';
import 'package:qa_mate/providers/recording_provider.dart';
import 'package:qa_mate/providers/upload_provider.dart';
import 'package:qa_mate/services/history_repository.dart';
import 'package:qa_mate/services/screen_recorder_service.dart';
import 'package:qa_mate/services/upload_service.dart';
import 'package:qa_mate/screens/settings_screen.dart';
import 'package:qa_mate/widgets/reel_record_button.dart';

/// Helper to build the full app with simulated services.
Widget buildTestApp() {
  final historyRepo = RecordingHistoryRepository();
  final recorderService = SimulatedScreenRecorderService();
  final uploadService = MockUploadService();

  return MultiProvider(
    providers: [
      Provider<ScreenRecorderService>.value(value: recorderService),
      Provider<UploadService>.value(value: uploadService),
      Provider<RecordingHistoryRepository>.value(value: historyRepo),
      ChangeNotifierProvider<RecordingProvider>(
        create: (_) => RecordingProvider(
          recorderService: recorderService,
          historyRepository: historyRepo,
        ),
      ),
      ChangeNotifierProvider<UploadProvider>(
        create: (_) => UploadProvider(
          uploadService: uploadService,
          historyRepository: historyRepo,
        ),
      ),
      ChangeNotifierProvider<HistoryProvider>(
        create: (_) => HistoryProvider(repository: historyRepo),
      ),
    ],
    child: const QaMateApp(),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomeScreen Layout & Navigation Tests', () {
    testWidgets('Record tab renders all core UI elements', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 500));

      // Storage pill
      expect(find.text('3.2 of 10 GB'), findsOneWidget);

      // Hero record button
      expect(find.byKey(const ValueKey('record_button')), findsOneWidget);
      expect(find.byType(ReelRecordButton), findsOneWidget);

      // Quick toggle cards
      expect(find.byKey(const ValueKey('toggle_voice')), findsOneWidget);
      expect(find.byKey(const ValueKey('toggle_touches')), findsOneWidget);
      expect(find.byKey(const ValueKey('toggle_sound')), findsOneWidget);
      expect(find.text('Voice'), findsOneWidget);
      expect(find.text('Touches'), findsOneWidget);
      expect(find.text('Sound'), findsOneWidget);

      // Recent section header
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('See all'), findsOneWidget);

      // Empty-state hint
      expect(find.text('Tap Record to make your first screen video.'), findsOneWidget);
    });

    testWidgets('Bottom nav items are all rendered with correct keys', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('nav_record')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_library')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_settings')), findsOneWidget);
    });

    testWidgets('Tapping Library nav item switches to Library tab', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('nav_library')));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // Library screen shows heading
      expect(find.text('Library'), findsWidgets);
    });

    testWidgets('Tapping Settings nav item switches to Settings tab', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('nav_settings')));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Resolution'), findsOneWidget);
      expect(find.text('Frame rate'), findsOneWidget);
      expect(find.text('Show touches'), findsOneWidget);
    });

    testWidgets('Tapping settings shortcut pill navigates to Settings tab', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('settings_shortcut_pill')));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('See all link navigates to Library tab', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      expect(find.text('Library'), findsWidgets);
    });
  });

  group('Quick Toggle Cards Tests', () {
    testWidgets('Voice toggle card changes subtitle on tap', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 300));

      // Tap the Voice card
      await tester.tap(find.byKey(const ValueKey('toggle_voice')));
      await tester.pump(const Duration(milliseconds: 300));

      // Now voice should be off
      expect(find.text('Off'), findsWidgets);
    });

    testWidgets('Sound toggle card changes icon on tap', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 300));

      // Volume off initially (defaults to false)
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('toggle_sound')));
      await tester.pump(const Duration(milliseconds: 300));

      // Volume on after tap
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    });
  });

  group('ReelRecordButton Widget Tests', () {
    testWidgets('Record button renders and tap callback fires', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReelRecordButton(
              key: const ValueKey('test_record_btn'),
              isRecording: false,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byKey(const ValueKey('test_record_btn')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('test_record_btn')));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('Record button shows recording state visually', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReelRecordButton(
              key: const ValueKey('test_record_btn_recording'),
              isRecording: true,
              onTap: () {},
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('test_record_btn_recording')), findsOneWidget);
    });
  });
}
