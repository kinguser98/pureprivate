import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:private_cinema_mobile/data/playback_tracker.dart';

class SyncService {
  static const String _apiSyncUrl = 'https://ott.redapp.space/api.php';

  /// Generates a random 6-character uppercase sync code
  static String generateSyncCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Avoid O, I, 1, 0
    final rand = math.Random();
    return List.generate(6, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Helper to get a sync value from the self-hosted API
  static Future<String?> _getSyncValue(String key) async {
    try {
      final url = '$_apiSyncUrl?action=get_sync_value&key=$key';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return res.body.trim();
      }
    } catch (e) {
      debugPrint('SyncService: Failed to get sync value for $key: $e');
    }
    return null;
  }

  /// Helper to save a sync value to the self-hosted API
  static Future<bool> _saveSyncValue(String key, String value) async {
    try {
      final url = '$_apiSyncUrl?action=save_sync_value';
      final res = await http.post(
        Uri.parse(url),
        body: {
          'key': key,
          'value': value,
        },
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('SyncService: Failed to save sync value for $key: $e');
    }
    return false;
  }

  /// Register TV device ID under a sync code
  static Future<void> registerTvSyncCode(String code) async {
    final deviceId = await PlaybackTracker.getOrCreateDeviceId();
    final success = await _saveSyncValue('code_$code', deviceId);
    if (success) {
      debugPrint('SyncService: TV registered sync code $code with deviceId $deviceId');
    } else {
      debugPrint('SyncService: Failed to register TV sync code $code');
    }
  }

  /// Pair mobile app with TV using the sync code
  static Future<bool> pairWithTv(String code) async {
    final tvDeviceId = await _getSyncValue('code_$code');
    if (tvDeviceId != null && tvDeviceId.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('paired_tv_device_id', tvDeviceId);
      debugPrint('SyncService: Mobile paired successfully with TV deviceId $tvDeviceId');
      return true;
    }
    return false;
  }

  /// Get paired TV device ID on mobile
  static Future<String?> getPairedTvDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('paired_tv_device_id');
  }

  /// Send remote download request from mobile to paired TV
  static Future<bool> sendRemoteDownload({
    required String title,
    required String downloadUrl,
    required String posterUrl,
    String? tmdbId,
    String? description,
    String? genre,
    String? language,
  }) async {
    final tvDeviceId = await getPairedTvDeviceId();
    if (tvDeviceId == null) return false;

    try {
      final key = 'req_$tvDeviceId';
      
      // Get existing requests
      List<dynamic> requests = [];
      final existing = await _getSyncValue(key);
      if (existing != null && existing.isNotEmpty) {
        try {
          requests = json.decode(existing);
        } catch (_) {}
      }

      // Add new request
      final newReq = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'title': title,
        'downloadUrl': downloadUrl,
        'posterUrl': posterUrl,
        'tmdbId': tmdbId,
        'description': description ?? '',
        'genre': genre ?? 'Drama',
        'language': language ?? 'Malayalam',
        'timestamp': DateTime.now().toIso8601String(),
      };

      requests.add(newReq);

      // Post back
      final success = await _saveSyncValue(key, json.encode(requests));
      if (success) {
        debugPrint('SyncService: Remote download request sent to TV: $title');
        return true;
      }
    } catch (e) {
      debugPrint('SyncService: Failed to send remote download: $e');
    }
    return false;
  }

  /// Fetch remote download requests on TV
  static Future<List<dynamic>> fetchRemoteDownloads() async {
    try {
      final deviceId = await PlaybackTracker.getOrCreateDeviceId();
      final key = 'req_$deviceId';
      final existing = await _getSyncValue(key);
      if (existing != null && existing.isNotEmpty) {
        return json.decode(existing) as List<dynamic>;
      }
    } catch (e) {
      debugPrint('SyncService: Failed to fetch remote downloads on TV: $e');
    }
    return [];
  }

  /// Remove/Acknowledge a remote download request on TV
  static Future<void> removeRemoteDownload(String requestId) async {
    try {
      final deviceId = await PlaybackTracker.getOrCreateDeviceId();
      final key = 'req_$deviceId';
      
      // Get existing requests
      List<dynamic> requests = [];
      final existing = await _getSyncValue(key);
      if (existing != null && existing.isNotEmpty) {
        try {
          requests = json.decode(existing);
        } catch (_) {}
      }

      // Filter out this request
      requests.removeWhere((r) => r['id']?.toString() == requestId);

      // Post back
      await _saveSyncValue(key, json.encode(requests));
      debugPrint('SyncService: Remote download request $requestId removed on TV');
    } catch (e) {
      debugPrint('SyncService: Failed to remove remote download request: $e');
    }
  }

  /// Save categories order to KVDB
  static Future<void> saveCategoriesOrder(List<String> categories) async {
    try {
      final deviceId = await PlaybackTracker.getOrCreateDeviceId();
      final key = 'ord_cats_$deviceId';
      await _saveSyncValue(key, json.encode(categories));
      debugPrint('SyncService: Saved categories order to KVDB');
    } catch (e) {
      debugPrint('SyncService: Failed to save categories order: $e');
    }
  }

  /// Fetch categories order from KVDB
  static Future<List<String>?> fetchCategoriesOrder() async {
    try {
      final deviceId = await PlaybackTracker.getOrCreateDeviceId();
      final key = 'ord_cats_$deviceId';
      final existing = await _getSyncValue(key);
      if (existing != null && existing.isNotEmpty) {
        final decoded = json.decode(existing);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      }
    } catch (e) {
      debugPrint('SyncService: Failed to fetch categories order: $e');
    }
    return null;
  }

  /// Save channels order for a category to KVDB
  static Future<void> saveChannelsOrder(String category, List<String> channelIds) async {
    try {
      final deviceId = await PlaybackTracker.getOrCreateDeviceId();
      final cleanCat = Uri.encodeComponent(category);
      final key = 'ord_chans_${deviceId}_$cleanCat';
      await _saveSyncValue(key, json.encode(channelIds));
      debugPrint('SyncService: Saved channels order for $category to KVDB');
    } catch (e) {
      debugPrint('SyncService: Failed to save channels order: $e');
    }
  }

  /// Fetch channels order for a category from KVDB
  static Future<List<String>?> fetchChannelsOrder(String category) async {
    try {
      final deviceId = await PlaybackTracker.getOrCreateDeviceId();
      final cleanCat = Uri.encodeComponent(category);
      final key = 'ord_chans_${deviceId}_$cleanCat';
      final existing = await _getSyncValue(key);
      if (existing != null && existing.isNotEmpty) {
        final decoded = json.decode(existing);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      }
    } catch (e) {
      debugPrint('SyncService: Failed to fetch channels order: $e');
    }
    return null;
  }

  /// Fetch list of synced Stremio addon URLs
  static Future<List<String>> fetchStremioAddons() async {
    try {
      String? deviceId;
      final prefs = await SharedPreferences.getInstance();
      final pairedId = prefs.getString('paired_tv_device_id');
      if (pairedId != null && pairedId.isNotEmpty) {
        deviceId = pairedId;
      } else {
        deviceId = await PlaybackTracker.getOrCreateDeviceId();
      }
      
      final rawValue = await _getSyncValue('stremio_addons_$deviceId');
      if (rawValue != null && rawValue.isNotEmpty) {
        final decoded = jsonDecode(rawValue);
        if (decoded is List) {
          return decoded.map((e) {
            final str = e.toString();
            try {
              // Try to base64 decode the URL if it was stored base64 encoded
              final decodedBytes = base64.decode(str);
              return utf8.decode(decodedBytes);
            } catch (_) {
              // Fallback to original string if not base64
              return str;
            }
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('SyncService: Failed to fetch Stremio addons: $e');
    }
    return [];
  }

  /// Save list of synced Stremio addon URLs
  static Future<bool> saveStremioAddons(List<String> urls) async {
    try {
      String? deviceId;
      final prefs = await SharedPreferences.getInstance();
      final pairedId = prefs.getString('paired_tv_device_id');
      if (pairedId != null && pairedId.isNotEmpty) {
        deviceId = pairedId;
      } else {
        deviceId = await PlaybackTracker.getOrCreateDeviceId();
      }

      // Base64 encode each URL to prevent security filtering / WAF blocks on production server
      final List<String> encodedUrls = urls.map((url) {
        final bytes = utf8.encode(url);
        return base64.encode(bytes);
      }).toList();

      final value = jsonEncode(encodedUrls);
      return await _saveSyncValue('stremio_addons_$deviceId', value);
    } catch (e) {
      debugPrint('SyncService: Failed to save Stremio addons: $e');
    }
    return false;
  }

  /// Fetch list of synced Nuveo addon manifest configs
  static Future<List<Map<String, dynamic>>> fetchNuveoAddons() async {
    try {
      String? deviceId;
      final prefs = await SharedPreferences.getInstance();
      final pairedId = prefs.getString('paired_tv_device_id');
      if (pairedId != null && pairedId.isNotEmpty) {
        deviceId = pairedId;
      } else {
        deviceId = await PlaybackTracker.getOrCreateDeviceId();
      }

      final rawValue = await _getSyncValue('nuveo_addons_$deviceId');
      if (rawValue != null && rawValue.isNotEmpty) {
        final decodedBytes = base64.decode(rawValue);
        final decodedStr = utf8.decode(decodedBytes);
        final dynamic decoded = jsonDecode(decodedStr);
        if (decoded is List) {
          return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('SyncService: Failed to fetch Nuveo addons: $e');
    }
    return [];
  }

  /// Fetch global app settings from the admin panel
  static Future<Map<String, String>> fetchAppSettings() async {
    try {
      final url = '$_apiSyncUrl?action=get_app_settings';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is Map) {
          return data.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
    } catch (e) {
      debugPrint('SyncService: Failed to fetch app settings: $e');
    }
    return {};
  }

  /// Fetch global Stremio addons (merged with device-specific ones)
  static Future<List<String>> fetchGlobalStremioAddons() async {
    final settings = await fetchAppSettings();
    final raw = settings['global_stremio_addons'];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          return decoded.where((e) {
            if (e is String) return true;
            if (e is Map) {
              final enabled = e['enabled'];
              return enabled != false && enabled != 'false';
            }
            return false;
          }).map((e) {
            if (e is String) return e;
            if (e is Map) return e['url']?.toString() ?? '';
            return '';
          }).where((u) => u.isNotEmpty).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  /// Merge global + device-specific Stremio addons (deduplicated)
  static Future<List<String>> fetchMergedStremioAddons() async {
    final global = await fetchGlobalStremioAddons();
    final device = await fetchStremioAddons();
    final seen = <String>{};
    final merged = <String>[];
    for (final url in [...global, ...device]) {
      if (seen.add(url)) merged.add(url);
    }
    return merged;
  }

  /// Fetch global Nuveo addons from the admin panel
  static Future<List<Map<String, dynamic>>> fetchGlobalNuveoAddons() async {
    final settings = await fetchAppSettings();
    final raw = settings['global_nuveo_addons'];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          return decoded.where((e) {
            if (e is Map) {
              final enabled = e['enabled'];
              return enabled != false && enabled != 'false';
            }
            return true;
          }).map((e) {
            if (e is Map) return Map<String, dynamic>.from(e);
            // If it's a URL string, build a basic manifest placeholder
            return <String, dynamic>{'url': e.toString(), 'name': 'Global Nuveo', 'scrapers': <dynamic>[]};
          }).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  /// Merge global + device-specific Nuveo addons (deduplicated by URL)
  static Future<List<Map<String, dynamic>>> fetchMergedNuveoAddons() async {
    final global = await fetchGlobalNuveoAddons();
    final device = await fetchNuveoAddons();
    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];
    for (final addon in [...global, ...device]) {
      final url = addon['url']?.toString() ?? '';
      if (url.isNotEmpty && seen.add(url)) merged.add(addon);
    }
    return merged;
  }

  /// Fetch active Stalker portal IDs from global settings (returns empty list = all portals)
  static Future<List<int>> fetchActiveStalkerPortals() async {
    final settings = await fetchAppSettings();
    final raw = settings['active_stalker_portals'];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) return decoded.map((e) => int.tryParse(e.toString()) ?? 0).where((e) => e > 0).toList();
      } catch (_) {}
    }
    return [];
  }

  /// Check if a global source visibility setting is enabled (defaults to true)
  static Future<bool> getGlobalSourceVisibility(String sourceKey) async {
    final settings = await fetchAppSettings();
    final raw = settings['source_show_$sourceKey'];
    return raw == null || raw == 'true';
  }

  /// Fetch the ordered list of enabled source keys from the admin panel
  static Future<List<String>> fetchSourceOrder() async {
    final settings = await fetchAppSettings();
    final raw = settings['source_visibility'] ?? settings['source_order'];
    List<String> list = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          list = decoded.cast<String>();
        }
      } catch (_) {}
    }
    if (list.isEmpty) {
      list = ['vidlink','netmirror','cinemm','stalker','stravo','castle','torrent','stremioAddon','telegram'];
    }
    return list;
  }

  /// Fetch admin-configured Telegram api credentials. Returns nulls if the
  /// admin hasn't set them yet (or if the admin has disabled the source).
  static Future<({int? apiId, String? apiHash, bool enabled})>
      fetchTelegramConfig() async {
    final settings = await fetchAppSettings();
    final enabled =
        (settings['source_show_telegram'] ?? 'true').toString() != 'false';
    final apiIdStr = settings['telegram_api_id'];
    final apiHash = settings['telegram_api_hash'];
    return (
      apiId: apiIdStr == null || apiIdStr.isEmpty ? null : int.tryParse(apiIdStr),
      apiHash: (apiHash == null || apiHash.isEmpty) ? null : apiHash,
      enabled: enabled,
    );
  }

  /// Save list of synced Nuveo addon manifest configs
  static Future<bool> saveNuveoAddons(List<Map<String, dynamic>> addons) async {
    try {
      String? deviceId;
      final prefs = await SharedPreferences.getInstance();
      final pairedId = prefs.getString('paired_tv_device_id');
      if (pairedId != null && pairedId.isNotEmpty) {
        deviceId = pairedId;
      } else {
        deviceId = await PlaybackTracker.getOrCreateDeviceId();
      }

      final rawStr = jsonEncode(addons);
      final bytes = utf8.encode(rawStr);
      final encodedValue = base64.encode(bytes);
      return await _saveSyncValue('nuveo_addons_$deviceId', encodedValue);
    } catch (e) {
      debugPrint('SyncService: Failed to save Nuveo addons: $e');
    }
    return false;
  }

  static Future<String> getTorrentioUrl() async {
    try {
      final cloud = await fetchAppSettings();
      if (cloud.containsKey('torrentio_addon_url') && cloud['torrentio_addon_url']!.isNotEmpty) {
        return cloud['torrentio_addon_url']!;
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('torrentio_addon_url') ?? 'https://torrentio.strem.fun';
  }

  static Future<String> getStravoUrl() async {
    try {
      final cloud = await fetchAppSettings();
      if (cloud.containsKey('stravo_addon_url') && cloud['stravo_addon_url']!.isNotEmpty) {
        return cloud['stravo_addon_url']!;
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('stravo_addon_url') ?? 'https://stravo-clfk.onrender.com/default';
  }

  static Future<String> getNetmirrorDomains() async {
    try {
      final cloud = await fetchAppSettings();
      if (cloud.containsKey('netmirror_domains') && cloud['netmirror_domains']!.isNotEmpty) {
        return cloud['netmirror_domains']!;
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('netmirror_domains') ?? '';
  }

  static Future<String?> getSeedrToken() async {
    try {
      final cloud = await fetchAppSettings();
      if (cloud.containsKey('seedr_token') && cloud['seedr_token']!.isNotEmpty) {
        return cloud['seedr_token']!;
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('seedr_auth_token');
  }
}

