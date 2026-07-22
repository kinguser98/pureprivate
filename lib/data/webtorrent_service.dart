import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/data/sync_service.dart';

class WebTorrentService {
  static const String _baseUrl = 'https://v2.seedr.cc/api/v0.1/p';

  static String? magnetToTorrentUrl(String magnetUrl) {
    final hashMatch = RegExp(r'btih:([a-fA-F0-9]{40})').firstMatch(magnetUrl);
    if (hashMatch == null) return null;
    return 'https://itorrents.org/torrent/${hashMatch.group(1)!.toLowerCase()}.torrent';
  }

  static bool isUnderLimit(String? magnetUrl, {int limitMb = 4096}) {
    if (magnetUrl == null) return true;
    // Parse size from magnet name or URL if available
    final sizeMatch = RegExp(r'xl=(\d+)').firstMatch(magnetUrl);
    if (sizeMatch == null) return true; // no size info, allow it
    final bytes = int.tryParse(sizeMatch.group(1)!) ?? 0;
    return bytes <= limitMb * 1024 * 1024;
  }

  /// Deletes ALL files and folders from Seedr account.
  static Future<bool> clearSeedr(Map<String, String> headers) async {
    try {
      final rootRes = await http.get(
        Uri.parse('$_baseUrl/fs/folder/0/contents'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (rootRes.statusCode != 200) return false;

      final root = json.decode(rootRes.body);
      final folders = root['folders'] as List? ?? [];
      final files = root['files'] as List? ?? [];

      // Delete all folders
      for (final folder in folders) {
        if (folder['id'] != null) {
          try {
            await http.delete(
              Uri.parse('$_baseUrl/fs/folder/${folder['id']}'),
              headers: headers,
            ).timeout(const Duration(seconds: 5));
          } catch (_) {}
        }
      }

      // Delete all files
      final fileIds = files.map((f) => f['id']).whereType<int>().toList();
      if (fileIds.isNotEmpty) {
        try {
          await http.post(
            Uri.parse('$_baseUrl/fs/batch/delete'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: json.encode({'ids': fileIds}),
          ).timeout(const Duration(seconds: 5));
        } catch (_) {}
      }

      debugPrint('Seedr: Cleared ${folders.length} folders, ${files.length} files');
      return true;
    } catch (e) {
      debugPrint('Seedr: Clear error - $e');
      return false;
    }
  }

  static Future<Set<int>> _getFolderIds(Map<String, String> headers) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/fs/folder/0/contents'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final folders = data['folders'] as List? ?? [];
        return folders.map((f) => f['id'] as int?).whereType<int>().toSet();
      }
    } catch (_) {}
    return {};
  }

  static Future<String?> _getUrlFromFolder(int folderId, Map<String, String> headers) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/fs/folder/$folderId/contents'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = json.decode(res.body);
      final files = data['files'] as List? ?? [];
      for (final f in files) {
        if (f['id'] == null) continue;
        final dlRes = await http.get(
          Uri.parse('$_baseUrl/download/file/${f['id']}/url'),
          headers: headers,
        ).timeout(const Duration(seconds: 10));
        if (dlRes.statusCode == 200) {
          final url = json.decode(dlRes.body)['url']?.toString() ?? '';
          if (url.isNotEmpty) return url;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Starts a torrent via Seedr. [onProgress] receives elapsed seconds (0..30).
  static Future<String?> startTorrent(String magnetUrl,
      {String? name, String? authToken, void Function(int elapsed)? onProgress}) async {
    final token = authToken ?? await _getToken();
    if (token == null || token.isEmpty) return null;

    final torrentUrl = magnetToTorrentUrl(magnetUrl);
    if (torrentUrl == null) return null;

    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    try {
      // 1. Clear existing Seedr files
      debugPrint('Seedr: Clearing existing files...');
      await clearSeedr(headers);

      // 2. Capture folder IDs before adding
      final beforeIds = await _getFolderIds(headers);
      debugPrint('Seedr: Folders before: ${beforeIds.length}');

      // 3. Add torrent
      final addRes = await http.post(
        Uri.parse('$_baseUrl/tasks'),
        headers: headers,
        body: json.encode({'url': torrentUrl, 'save_folder_id': 0}),
      ).timeout(const Duration(seconds: 20));

      if (addRes.statusCode == 401 || addRes.statusCode == 403) return null;
      if (addRes.statusCode != 200 && addRes.statusCode != 201) return null;
      debugPrint('Seedr: Torrent added');

      // 4. Poll with countdown (max 15 iterations x 2s = 30s)
      final startTime = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final elapsed = (DateTime.now().millisecondsSinceEpoch - startTime) ~/ 1000;
        onProgress?.call(elapsed.clamp(0, 30));

        try {
          final afterIds = await _getFolderIds(headers);
          final newIds = afterIds.difference(beforeIds);
          if (newIds.isNotEmpty) {
            for (final id in newIds) {
              final url = await _getUrlFromFolder(id, headers);
              if (url != null) return url;
            }
          } else if (afterIds.length > beforeIds.length) {
            for (final id in afterIds) {
              final url = await _getUrlFromFolder(id, headers);
              if (url != null) return url;
            }
          }
        } catch (e) {
          debugPrint('Seedr: Poll error: $e');
        }
      }

      debugPrint('Seedr: Timed out');
      return null;
    } catch (e) {
      debugPrint('Seedr: Error - $e');
      return null;
    }
  }

  static Future<String?> getToken() async {
    return await SyncService.getSeedrToken();
  }

  static Future<String?> _getToken() async {
    return await SyncService.getSeedrToken();
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('seedr_auth_token', token);
  }
}
