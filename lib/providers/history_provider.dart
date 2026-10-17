import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/recording_item.dart';
import '../services/history_repository.dart';

class HistoryProvider extends ChangeNotifier {
  final RecordingHistoryRepository repository;

  HistoryProvider({required this.repository}) {
    loadHistory();
  }

  List<RecordingItem> _items = [];
  List<RecordingItem> get items => _items;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> loadHistory() async {
    _isLoading = true;
    notifyListeners();
    try {
      _items = await repository.getRecordings();
    } catch (e) {
      debugPrint('Error loading history: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteItem(String id) async {
    final item = _items.firstWhere((i) => i.id == id, orElse: () => _items.first);
    try {
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    await repository.deleteRecording(id);
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  Future<void> deleteRecording(String id) => deleteItem(id);

  Future<void> updateRecording(RecordingItem item) async {
    await repository.saveRecording(item);
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      _items[index] = item;
    } else {
      _items.add(item);
    }
    notifyListeners();
  }

  Future<void> copyLink(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
              SizedBox(width: 10),
              Text('Share link copied to clipboard!'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: const Color(0xFF1E293B),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> shareNative(String url, {String? title}) async {
    try {
      // ignore: deprecated_member_use
      await Share.share(
        'Check out this screen recording: $url\n(Link expires in 30 days)',
        subject: title ?? 'QA Mate Screen Recording',
      );
    } catch (e) {
      debugPrint('Error triggering native share: $e');
    }
  }
}
