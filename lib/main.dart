import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'providers/history_provider.dart';
import 'providers/recording_provider.dart';
import 'providers/upload_provider.dart';
import 'screens/home_screen.dart';
import 'services/history_repository.dart';
import 'services/screen_recorder_service.dart';
import 'services/thumbnail_service.dart';
import 'services/upload_service.dart';
import 'theme/app_theme.dart';
import 'widgets/overlay_bubble_menu.dart';

/// Entry point for the floating system overlay window outside the app
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayBubbleMenuApp());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set dark system status bar for edge-to-edge dark theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF090D16),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Attempt to load .env file if available
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {
    // If .env is missing or not packaged, continue gracefully
  }

  // Initialize service dependencies
  final historyRepository = RecordingHistoryRepository();
  final screenRecorderService = AdaptiveScreenRecorderService();
  
  // Resolve Worker endpoint from .env, falling back to --dart-define or Mock
  final workerEndpoint = dotenv.env['WORKER_ENDPOINT'] ??
      const String.fromEnvironment('WORKER_ENDPOINT');
  final UploadService uploadService = workerEndpoint.isNotEmpty
      ? PresignedUploadService(workerEndpoint: workerEndpoint)
      : MockUploadService();

  final thumbnailService = AppThumbnailService();

  runApp(
    MultiProvider(
      providers: [
        // Services
        Provider<ScreenRecorderService>.value(value: screenRecorderService),
        Provider<UploadService>.value(value: uploadService),
        Provider<ThumbnailService>.value(value: thumbnailService),
        Provider<RecordingHistoryRepository>.value(value: historyRepository),

        // State Providers
        ChangeNotifierProvider<RecordingProvider>(
          create: (_) => RecordingProvider(
            recorderService: screenRecorderService,
            historyRepository: historyRepository,
            thumbnailService: thumbnailService,
          ),
        ),
        ChangeNotifierProvider<UploadProvider>(
          create: (_) => UploadProvider(
            uploadService: uploadService,
            historyRepository: historyRepository,
          ),
        ),
        ChangeNotifierProvider<HistoryProvider>(
          create: (_) => HistoryProvider(
            repository: historyRepository,
          ),
        ),
      ],
      child: const QaMateApp(),
    ),
  );
}

class QaMateApp extends StatelessWidget {
  const QaMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QA Mate',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}
