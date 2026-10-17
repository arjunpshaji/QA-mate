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

void main() {
  testWidgets('Reel App loads HomeScreen smoke test and navigates tabs', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final historyRepo = RecordingHistoryRepository();
    final recorderService = SimulatedScreenRecorderService();
    final uploadService = MockUploadService();

    await tester.pumpWidget(
      MultiProvider(
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
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Reel title, storage indicator, and Record button
    expect(find.text('3.2 of 10 GB'), findsOneWidget);
    expect(find.text('Record'), findsWidgets);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Touches'), findsOneWidget);
    expect(find.text('Sound'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);

    // Verify bottom nav items
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Tap Settings tab
    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Settings elements
    expect(find.text('Resolution'), findsOneWidget);
    expect(find.text('Frame rate'), findsOneWidget);
    expect(find.text('Show touches'), findsOneWidget);
  });
}
