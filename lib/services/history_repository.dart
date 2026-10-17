import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/recording_item.dart';

class RecordingHistoryRepository {
  static const String _storageKey = 'qa_mate_recordings_history';

  Future<List<RecordingItem>> getRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString(_storageKey);
      if (jsonStr == null || jsonStr.isEmpty) {
        return [];
      }

      final List<dynamic> list = json.decode(jsonStr) as List<dynamic>;
      return list
          .map((item) => RecordingItem.fromMap(item as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('Error loading recordings history: $e');
      return [];
    }
  }

  Future<void> saveRecording(RecordingItem item) async {
    try {
      final recordings = await getRecordings();
      // Replace if exists, or prepend
      final index = recordings.indexWhere((r) => r.id == item.id);
      if (index >= 0) {
        recordings[index] = item;
      } else {
        recordings.insert(0, item);
      }
      await _persistList(recordings);
    } catch (e) {
      debugPrint('Error saving recording item: $e');
    }
  }

  Future<void> deleteRecording(String id) async {
    try {
      final recordings = await getRecordings();
      recordings.removeWhere((r) => r.id == id);
      await _persistList(recordings);
    } catch (e) {
      debugPrint('Error deleting recording item: $e');
    }
  }

  Future<void> updateShareUrl(
    String id,
    String shareUrl,
    DateTime expiresAt,
  ) async {
    try {
      final recordings = await getRecordings();
      final index = recordings.indexWhere((r) => r.id == id);
      if (index >= 0) {
        recordings[index] = recordings[index].copyWith(
          shareUrl: shareUrl,
          expiresAt: expiresAt,
        );
        await _persistList(recordings);
      }
    } catch (e) {
      debugPrint('Error updating share url: $e');
    }
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<void> _persistList(List<RecordingItem> list) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(list.map((r) => r.toMap()).toList());
    await prefs.setString(_storageKey, jsonStr);
  }
}
