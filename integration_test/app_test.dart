import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildApp() {
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

  group('End-to-End App Smoke Tests', () {
    testWidgets('App launches and renders HomeScreen', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Storage pill is visible
      expect(find.text('3.2 of 10 GB'), findsOneWidget);

      // Bottom nav is present
      expect(find.byKey(const ValueKey('nav_record')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_library')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_settings')), findsOneWidget);

      // Core record tab content visible
      expect(find.text('Voice'), findsOneWidget);
      expect(find.text('Touches'), findsOneWidget);
      expect(find.text('Sound'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
    });

    testWidgets('Bottom nav: navigate to Library tab', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.byKey(const ValueKey('nav_library')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Library heading visible
      expect(find.text('Library'), findsWidgets);
    });

    testWidgets('Bottom nav: navigate to Settings tab', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.byKey(const ValueKey('nav_settings')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Resolution'), findsOneWidget);
      expect(find.text('Frame rate'), findsOneWidget);
    });

    testWidgets('Bottom nav: navigate back to Record tab', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Go to settings
      await tester.tap(find.byKey(const ValueKey('nav_settings')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Navigate back to record tab
      await tester.tap(find.byKey(const ValueKey('nav_record')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Voice'), findsOneWidget);
      expect(find.byKey(const ValueKey('record_button')), findsOneWidget);
    });

    testWidgets('Settings shortcut pill navigates to Settings', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.byKey(const ValueKey('settings_shortcut_pill')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('Voice toggle card turns audio off', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Voice starts On
      expect(find.byKey(const ValueKey('toggle_voice')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('toggle_voice')));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // There should now be an "Off" badge somewhere in the toggle cards
      expect(find.text('Off'), findsWidgets);
    });

    testWidgets('Sound toggle card changes volume icon', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('toggle_sound')));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    });

    testWidgets('See all navigates to Library tab', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Library'), findsWidgets);
    });
  });
}
