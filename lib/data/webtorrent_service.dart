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

  /// Confirms that torrent file size is <= [limitMb] (default 4096 MB / 4 GB).
  static bool isUnderLimit(dynamic source, {int limitMb = 4096}) {
    String? url;
    String? name;
    if (source is String) {
      url = source;
    } else if (source != null) {
      try {
        url = (source as dynamic).url?.toString();
        name = (source as dynamic).name?.toString();
      } catch (_) {}
    }
    if (url == null && name == null) return true;

    // Check size in name first (e.g. "3.2 GB", "1.8 GiB", "4.5 GB")
    if (name != null) {
      final nameLower = name.toLowerCase();
      final gbMatch = RegExp(r'([\d.]+)\s*(gb|gib)').firstMatch(nameLower);
      if (gbMatch != null) {
        final gb = double.tryParse(gbMatch.group(1)!) ?? 0;
        return (gb * 1024) <= limitMb;
      }
      final mbMatch = RegExp(r'([\d.]+)\s*(mb|mib)').firstMatch(nameLower);
      if (mbMatch != null) {
        final mb = double.tryParse(mbMatch.group(1)!) ?? 0;
        return mb <= limitMb;
      }
    }

    // Check xl parameter in magnet url (bytes)
    if (url != null) {
      final sizeMatch = RegExp(r'xl=(\d+)').firstMatch(url);
      if (sizeMatch != null) {
        final bytes = int.tryParse(sizeMatch.group(1)!) ?? 0;
        return bytes <= (limitMb * 1024 * 1024);
      }
    }

    return true; // No explicit size metadata detected, allow attempt
  }

  /// Deletes ALL files, folders, and pending tasks from Seedr account.
  static Future<bool> clearSeedr(Map<String, String> headers) async {
    try {
      // 1. Delete all folders and files in folder 0
      final rootRes = await http.get(
        Uri.parse('$_baseUrl/fs/folder/0/contents'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (rootRes.statusCode == 200) {
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
      }

      // 2. Clear all active/pending tasks so new torrent can start cleanly
      try {
        final taskRes = await http.get(
          Uri.parse('$_baseUrl/tasks'),
          headers: headers,
        ).timeout(const Duration(seconds: 6));
        if (taskRes.statusCode == 200) {
          final tJson = json.decode(taskRes.body);
          final tasks = tJson['tasks'] as List? ?? [];
          for (final t in tasks) {
            final tid = t['id'];
            if (tid != null) {
              try {
                await http.delete(
                  Uri.parse('$_baseUrl/tasks/$tid'),
                  headers: headers,
                ).timeout(const Duration(seconds: 4));
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      debugPrint('Seedr: Cleared existing folders, files, and tasks');
      return true;
    } catch (e) {
      debugPrint('Seedr: Clear error - $e');
      return false;
    }
  }

  static Future<String?> _getUrlForFile(int fileId, Map<String, String> headers) async {
    try {
      final dlRes = await http.get(
        Uri.parse('$_baseUrl/download/file/$fileId/url'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (dlRes.statusCode == 200) {
        final data = json.decode(dlRes.body);
        final url = data['url']?.toString() ?? '';
        if (url.isNotEmpty) return url;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _scanFolderForStream(int folderId, Map<String, String> headers) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/fs/folder/$folderId/contents'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = json.decode(res.body);
      final files = data['files'] as List? ?? [];

      int? candidateFileId;
      int candidateSize = -1;

      for (final f in files) {
        if (f['id'] == null) continue;
        final fId = f['id'] as int;
        final name = (f['name']?.toString() ?? '').toLowerCase();
        final size = f['size'] is int ? f['size'] as int : 0;
        final isVideo = f['is_video'] == true;

        if (name.endsWith('.torrent')) continue; // Skip .torrent file

        final isVideoExt = name.endsWith('.mkv') ||
            name.endsWith('.mp4') ||
            name.endsWith('.avi') ||
            name.endsWith('.mov') ||
            name.endsWith('.ts');

        if (isVideo || isVideoExt || size > 30000000) {
          if (size > candidateSize) {
            candidateSize = size;
            candidateFileId = fId;
          }
        }
      }

      if (candidateFileId != null) {
        return await _getUrlForFile(candidateFileId, headers);
      }
    } catch (_) {}
    return null;
  }

  /// Starts a torrent via Seedr. [onProgress] receives elapsed seconds (0..30).
  static Future<String?> startTorrent(String magnetUrl,
      {String? name, String? authToken, void Function(int elapsed)? onProgress}) async {
    final token = authToken?.trim().isNotEmpty == true ? authToken!.trim() : await getToken();
    if (token == null || token.isEmpty) return null;

    final torrentUrl = magnetToTorrentUrl(magnetUrl) ?? magnetUrl;

    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };

    try {
      // 1. Clear existing Seedr files and tasks
      debugPrint('Seedr: Clearing existing files and tasks...');
      await clearSeedr(headers);

      // 2. Add torrent using form fields (matching native TV implementation)
      final formBody = <String, String>{
        'folder_id': '0',
      };
      if (magnetUrl.toLowerCase().startsWith('magnet:')) {
        formBody['torrent_magnet'] = magnetUrl;
      } else {
        formBody['torrent_url'] = torrentUrl;
      }

      var addRes = await http.post(
        Uri.parse('$_baseUrl/tasks'),
        headers: headers,
        body: formBody,
      ).timeout(const Duration(seconds: 20));

      if (addRes.statusCode != 200 && addRes.statusCode != 201 && addRes.statusCode != 409) {
        // Fallback to JSON payload if form body returned unexpected status
        try {
          addRes = await http.post(
            Uri.parse('$_baseUrl/tasks'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: json.encode({'url': torrentUrl, 'save_folder_id': 0}),
          ).timeout(const Duration(seconds: 15));
        } catch (_) {}
      }

      debugPrint('Seedr: Torrent task submit response code=${addRes.statusCode}');

      // 3. Poll for completed file (max 15 iterations x 2s = 30s)
      final startTime = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final elapsed = (DateTime.now().millisecondsSinceEpoch - startTime) ~/ 1000;
        onProgress?.call(elapsed.clamp(0, 30));

        try {
          final rootRes = await http.get(
            Uri.parse('$_baseUrl/fs/folder/0/contents'),
            headers: headers,
          ).timeout(const Duration(seconds: 8));

          if (rootRes.statusCode == 200) {
            final root = json.decode(rootRes.body);

            // A. Check direct video files in root folder 0
            final files = root['files'] as List? ?? [];
            for (final f in files) {
              if (f['id'] == null) continue;
              final fName = (f['name']?.toString() ?? '').toLowerCase();
              if (fName.endsWith('.torrent')) continue;
              final fId = f['id'] as int;
              final streamUrl = await _getUrlForFile(fId, headers);
              if (streamUrl != null && streamUrl.isNotEmpty) {
                debugPrint('Seedr: Resolved direct stream from root folder: $streamUrl');
                return streamUrl;
              }
            }

            // B. Check subfolders in root folder 0
            final folders = root['folders'] as List? ?? [];
            for (final folder in folders) {
              final folderId = folder['id'];
              if (folderId is int) {
                final streamUrl = await _scanFolderForStream(folderId, headers);
                if (streamUrl != null && streamUrl.isNotEmpty) {
                  debugPrint('Seedr: Resolved direct stream from subfolder $folderId: $streamUrl');
                  return streamUrl;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Seedr: Poll error: $e');
        }
      }

      debugPrint('Seedr: Stream polling timed out');
      return null;
    } catch (e) {
      debugPrint('Seedr: startTorrent error - $e');
      return null;
    }
  }

  static Future<String?> getToken() async {
    return await SyncService.getSeedrToken();
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('seedr_auth_token', token.trim());
  }
}
