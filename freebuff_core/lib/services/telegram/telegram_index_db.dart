import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'telegram_video_item.dart';

/// Lightweight on-device cache of Telegram Saved-Messages video metadata,
/// plus device-aware TG credentials.
///
/// Indexing strategy:
/// - On every successful login / refresh we pull a window of the most recent N
///   Saved-Messages entries that contain video files, and persist them here.
/// - [TelegramService.search] then matches a movie title/year against the
///   cached captions/file names with a small fuzzy score.
class TelegramIndexDb {
  static const String _kIndexKey = 'tg_saved_index_v1';
  static const String _kSession = 'tg_session_blob_v1';
  static const String _kUser = 'tg_user_phone_v1';
  static const String _kApiId = 'tg_api_id_override_v1';
  static const String _kApiHash = 'tg_api_hash_override_v1';
  static const int _maxCachedItems = 400;

  /// Shared singleton — callers should always go through this.
  static final TelegramIndexDb instance = TelegramIndexDb._ctor();
  TelegramIndexDb._ctor();

  final List<TelegramVideoItem> _items = [];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kIndexKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is List) {
        for (final entry in decoded) {
          if (entry is Map) {
            _items.add(_fromJson(Map<String, dynamic>.from(entry)));
          }
        }
      }
    } catch (e) {
      debugPrint('TelegramIndexDb: failed to load cache: $e');
    }
  }

  Future<List<TelegramVideoItem>> all() async {
    await _ensureLoaded();
    return List.unmodifiable(_items);
  }

  Future<void> replaceAll(List<TelegramVideoItem> items) async {
    await _ensureLoaded();
    _items
      ..clear()
      ..addAll(items.length > _maxCachedItems
          ? items.sublist(items.length - _maxCachedItems)
          : items);
    await _persist();
  }

  Future<void> upsert(TelegramVideoItem item) async {
    await _ensureLoaded();
    final idx = _items.indexWhere((e) => e.localId == item.localId);
    if (idx >= 0) {
      _items[idx] = item;
    } else {
      _items.add(item);
    }
    if (_items.length > _maxCachedItems) {
      _items.removeRange(0, _items.length - _maxCachedItems);
    }
    await _persist();
  }

  Future<void> clearIndex() async {
    _items.clear();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded =
        json.encode(_items.map((e) => _toJson(e)).toList(growable: false));
    await prefs.setString(_kIndexKey, encoded);
  }

  static Map<String, dynamic> _toJson(TelegramVideoItem e) => {
        'localId': e.localId,
        'messageId': e.messageId,
        'chatId': e.chatId,
        'fileName': e.fileName,
        'caption': e.caption,
        'sizeBytes': e.sizeBytes,
        'durationSeconds': e.durationSeconds,
        'date': e.date.toIso8601String(),
        'thumbnailUrl': e.thumbnailUrl,
        'directUrl': e.directUrl,
        'source': e.source,
      };

  static TelegramVideoItem _fromJson(Map<String, dynamic> j) =>
      TelegramVideoItem(
        localId: (j['localId'] ?? '').toString(),
        messageId: (j['messageId'] is int)
            ? j['messageId'] as int
            : int.tryParse(j['messageId']?.toString() ?? '0') ?? 0,
        chatId: (j['chatId'] is int)
            ? j['chatId'] as int
            : int.tryParse(j['chatId']?.toString() ?? '0') ?? 0,
        fileName: j['fileName']?.toString(),
        caption: j['caption']?.toString(),
        sizeBytes: (j['sizeBytes'] is int)
            ? j['sizeBytes'] as int
            : int.tryParse(j['sizeBytes']?.toString() ?? ''),
        durationSeconds: (j['durationSeconds'] is int)
            ? j['durationSeconds'] as int
            : int.tryParse(j['durationSeconds']?.toString() ?? ''),
        date:
            DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
        thumbnailUrl: j['thumbnailUrl']?.toString(),
        directUrl: j['directUrl']?.toString(),
        source: j['source']?.toString() ?? 'telegram',
      );

  // ---- session storage ---------------------------------------------------

  static Future<void> saveSession(Map<String, dynamic> session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSession, json.encode(session));
  }

  static Future<Map<String, dynamic>?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSession);
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = json.decode(raw);
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (_) {}
    return null;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSession);
    await prefs.remove(_kUser);
  }

  static Future<void> saveUserPhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUser, phone);
  }

  static Future<String?> loadUserPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUser);
  }

  static Future<void> saveApiIdOverride(int? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kApiId);
    } else {
      await prefs.setInt(_kApiId, id);
    }
  }

  static Future<void> saveApiHashOverride(String? hash) async {
    final prefs = await SharedPreferences.getInstance();
    if (hash == null || hash.isEmpty) {
      await prefs.remove(_kApiHash);
    } else {
      await prefs.setString(_kApiHash, hash);
    }
  }

  static Future<int?> loadApiIdOverride() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kApiId);
  }

  static Future<String?> loadApiHashOverride() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kApiHash);
  }

  static Future<void> saveCurrentDcId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tg_current_dc_id', id);
  }

  static Future<int?> loadCurrentDcId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('tg_current_dc_id');
  }

  static TelegramVideoItem fromMap(Map<String, dynamic> j) => _fromJson(j);
  static Map<String, dynamic> toMap(TelegramVideoItem e) => _toJson(e);
}
