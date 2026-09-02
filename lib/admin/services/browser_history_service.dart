import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/browser_bookmark_model.dart';

class BrowserHistoryService {
  static const String _bookmarksKey = 'goxio_browser_bookmarks_v1';
  static const String _historyKey = 'goxio_browser_history_v1';

  // --- Bookmarks ---

  static Future<List<BrowserBookmark>> getBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_bookmarksKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => BrowserBookmark.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('getBookmarks error: $e');
      return [];
    }
  }

  static Future<bool> isBookmarked(String url) async {
    final bookmarks = await getBookmarks();
    return bookmarks.any((b) => b.url == url);
  }

  static Future<void> toggleBookmark({required String title, required String url, String? faviconUrl}) async {
    final bookmarks = await getBookmarks();
    final index = bookmarks.indexWhere((b) => b.url == url);
    if (index >= 0) {
      bookmarks.removeAt(index);
    } else {
      bookmarks.insert(
        0,
        BrowserBookmark(
          id: 'bm_${DateTime.now().millisecondsSinceEpoch}',
          title: title.isNotEmpty ? title : url,
          url: url,
          faviconUrl: faviconUrl,
          createdAt: DateTime.now(),
        ),
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bookmarksKey, jsonEncode(bookmarks.map((e) => e.toJson()).toList()));
  }

  static Future<void> removeBookmark(String id) async {
    final bookmarks = await getBookmarks();
    bookmarks.removeWhere((b) => b.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bookmarksKey, jsonEncode(bookmarks.map((e) => e.toJson()).toList()));
  }

  // --- History ---

  static Future<List<BrowserHistoryItem>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => BrowserHistoryItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('getHistory error: $e');
      return [];
    }
  }

  static Future<void> addHistoryItem({required String title, required String url}) async {
    if (url.isEmpty || url.startsWith('about:')) return;
    try {
      final history = await getHistory();
      // Remove recent duplicate if visited within the last minute
      history.removeWhere((h) => h.url == url);
      history.insert(
        0,
        BrowserHistoryItem(
          id: 'hist_${DateTime.now().millisecondsSinceEpoch}',
          title: title.isNotEmpty ? title : url,
          url: url,
          visitedAt: DateTime.now(),
        ),
      );
      // Limit to 200 items
      if (history.length > 200) {
        history.removeRange(200, history.length);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_historyKey, jsonEncode(history.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('addHistoryItem error: $e');
    }
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  static Future<void> removeHistoryItem(String id) async {
    final history = await getHistory();
    history.removeWhere((h) => h.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, jsonEncode(history.map((e) => e.toJson()).toList()));
  }
}
