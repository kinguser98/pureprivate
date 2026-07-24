import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class EpgProgram {
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime stopTime;

  EpgProgram({
    required this.title,
    required this.description,
    required this.startTime,
    required this.stopTime,
  });
}

class EpgService {
  // Cache of all future programs: channelId/normalizedName -> list of EpgPrograms
  static final Map<String, List<EpgProgram>> _channelPrograms = {};
  // Cached channel logos extracted from EPG: channelId -> logo URL
  static final Map<String, String> _channelLogos = {};
  // Cached channel display names: channelId -> display name (e.g., "Surya TV HD")
  static final Map<String, String> _channelDisplayNames = {};
  static bool _isLoaded = false;
  static bool _isLoading = false;

  static bool get isLoaded => _isLoaded;
  static bool get isLoading => _isLoading;
  static Map<String, String> get channelDisplayNames => _channelDisplayNames;

  /// Fetches EPG files, decompresses using GZip, and parses active programs.
  /// Caches current and future programs to keep memory footprint light.
  static Future<void> loadEpg([List<String>? customUrls]) async {
    if (_isLoading) return;
    _isLoading = true;
    _channelPrograms.clear();
    _channelLogos.clear();
    _channelDisplayNames.clear();

    final urls = (customUrls != null && customUrls.where((u) => u.trim().isNotEmpty).isNotEmpty)
        ? customUrls.where((u) => u.trim().isNotEmpty).toList()
        : [
            'https://avkb.short.gy/jioepg.xml.gz',
            'https://avkb.short.gy/tsepg.xml.gz',
          ];

    final now = DateTime.now();

    for (final url in urls) {
      try {
        debugPrint('EPGService: Fetching $url...');
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
        if (res.statusCode == 200) {
          debugPrint('EPGService: Decompressing gzip...');
          final decompressedBytes = gzip.decode(res.bodyBytes);
          final xmlContent = utf8.decode(decompressedBytes);
          
          debugPrint('EPGService: Parsing xml content (Length: ${xmlContent.length} chars)...');
          _parseActivePrograms(xmlContent, now);
        }
      } catch (e) {
        debugPrint('EPGService: Error loading EPG from $url: $e');
      }
    }

    // Sort all channel program lists by startTime
    _channelPrograms.forEach((key, list) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    });

    _isLoaded = true;
    _isLoading = false;
    debugPrint('EPGService: Finished loading EPG. Cached ${_channelPrograms.length} channel guides.');
  }

  static void _parseActivePrograms(String xml, DateTime now) {
    // EPG date format: "20260704100000 +0530" or "20260704100000"
    DateTime? parseEpgTime(String? timeStr) {
      if (timeStr == null || timeStr.length < 14) return null;
      try {
        final year = int.parse(timeStr.substring(0, 4));
        final month = int.parse(timeStr.substring(4, 6));
        final day = int.parse(timeStr.substring(6, 8));
        final hour = int.parse(timeStr.substring(8, 10));
        final minute = int.parse(timeStr.substring(10, 12));
        final second = int.parse(timeStr.substring(12, 14));
        
        // Handle timezone offset if present (e.g. "+0530")
        var dt = DateTime.utc(year, month, day, hour, minute, second);
        if (timeStr.contains('+') || timeStr.contains('-')) {
          final parts = timeStr.split(' ');
          if (parts.length > 1) {
            final offsetStr = parts[1];
            if (offsetStr.length == 5) {
              final sign = offsetStr[0] == '+' ? 1 : -1;
              final offsetHours = int.parse(offsetStr.substring(1, 3));
              final offsetMins = int.parse(offsetStr.substring(3, 5));
              final totalOffsetMins = (offsetHours * 60 + offsetMins) * sign;
              
              // Convert to local time offset
              final utcTime = dt.subtract(Duration(minutes: totalOffsetMins));
              dt = utcTime.toLocal();
            }
          }
        } else {
          // If no offset is specified, treat as UTC and convert to local time
          dt = dt.toLocal();
        }
        return dt;
      } catch (e) {
        return null;
      }
    }

    // 1. Extract channel logo icons and display names from <channel> tags
    final channelExp = RegExp(
      r'<channel\s+id="([^"]+)"[^>]*>([\s\S]*?)<\/channel>',
      caseSensitive: false,
    );
    final iconExp = RegExp(r'<icon\s+src="([^"]+)"', caseSensitive: false);
    final displayNameExp = RegExp(r'<display-name[^>]*>([^<]+)<\/display-name>', caseSensitive: false);

    final Map<String, String> channelNames = {};

    for (final match in channelExp.allMatches(xml)) {
      final channelId = match.group(1);
      final content = match.group(2);
      if (channelId != null && content != null) {
        final nameMatch = displayNameExp.firstMatch(content);
        if (nameMatch != null) {
          final dName = nameMatch.group(1)?.trim();
          if (dName != null && dName.isNotEmpty) {
            channelNames[channelId] = dName;
            _channelDisplayNames[channelId] = dName;
            
            // Store logo by channel ID and by normalized channel name
            final iconMatch = iconExp.firstMatch(content);
            if (iconMatch != null) {
              final iconUrl = iconMatch.group(1);
              if (iconUrl != null && iconUrl.isNotEmpty) {
                _channelLogos[channelId] = iconUrl;
                _channelLogos[dName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')] = iconUrl;
              }
            }
          }
        }
      }
    }

    // 2. Extract programme tags using RegExp.
    final exp = RegExp(
      r'<programme\s+start="([^"]+)"\s+stop="([^"]+)"\s+channel="([^"]+)"[^>]*>([\s\S]*?)<\/programme>',
      caseSensitive: false,
    );

    final titleExp = RegExp(r'<title[^>]*>([^<]+)<\/title>', caseSensitive: false);
    final descExp = RegExp(r'<desc[^>]*>([^<]+)<\/desc>', caseSensitive: false);

    for (final match in exp.allMatches(xml)) {
      final startStr = match.group(1);
      final stopStr = match.group(2);
      final channelId = match.group(3);
      final content = match.group(4);

      if (startStr == null || stopStr == null || channelId == null || content == null) continue;

      final start = parseEpgTime(startStr);
      final stop = parseEpgTime(stopStr);

      if (start == null || stop == null) continue;

      // Cache any future programmes (which stop after the current time)
      if (stop.isAfter(now)) {
        final titleMatch = titleExp.firstMatch(content);
        final descMatch = descExp.firstMatch(content);

        final title = titleMatch?.group(1)?.trim() ?? 'No title';
        final desc = descMatch?.group(1)?.trim() ?? 'No description available';

        final prog = EpgProgram(
          title: title,
          description: desc,
          startTime: start,
          stopTime: stop,
        );

        // Store by EPG channel ID
        _channelPrograms.putIfAbsent(channelId, () => []).add(prog);

        // Also store by normalized display name for fuzzy text matches
        final displayName = channelNames[channelId];
        if (displayName != null) {
          final normalized = _normalize(displayName);
          _channelPrograms.putIfAbsent(normalized, () => []).add(prog);
        }
      }
    }
  }

  static String _normalize(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String _cleanChannelName(String s) {
    return s.toLowerCase()
        .replaceAll('hd', '')
        .replaceAll('sd', '')
        .replaceAll('fhd', '')
        .replaceAll('uhd', '')
        .replaceAll('4k', '')
        .replaceAll(' +1', '')
        .replaceAll('+1', '')
        .replaceAll('in', '')
        .replaceAll('temp', '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
  }

  /// Get current program info for a channel by ID or Channel Name
  static EpgProgram? getCurrentProgram(String? channelId, String? channelName) {
    final list = _getProgramList(channelId, channelName);
    if (list == null || list.isEmpty) return null;
    final now = DateTime.now();
    for (final p in list) {
      if (now.isAfter(p.startTime) && now.isBefore(p.stopTime)) {
        return p;
      }
    }
    // Fallback: if none is currently active, check if there's one starting in the next 15 mins
    for (final p in list) {
      if (now.isBefore(p.startTime) && p.startTime.difference(now).inMinutes <= 15) {
        return p;
      }
    }
    return null;
  }

  /// Get next program info for a channel by ID or Channel Name
  static EpgProgram? getNextProgram(String? channelId, String? channelName) {
    final list = _getProgramList(channelId, channelName);
    if (list == null || list.isEmpty) return null;
    final now = DateTime.now();
    
    // Find index of current program
    int currentIdx = -1;
    for (int i = 0; i < list.length; i++) {
      final p = list[i];
      if (now.isAfter(p.startTime) && now.isBefore(p.stopTime)) {
        currentIdx = i;
        break;
      }
    }
    
    if (currentIdx != -1 && currentIdx + 1 < list.length) {
      return list[currentIdx + 1];
    }
    
    // If no active program found, find the first program that starts in the future
    for (final p in list) {
      if (p.startTime.isAfter(now)) {
        return p;
      }
    }
    return null;
  }

  /// Get all upcoming programs starting after the current program
  static List<EpgProgram> getUpcomingPrograms(String? channelId, String? channelName) {
    final list = _getProgramList(channelId, channelName);
    if (list == null || list.isEmpty) return [];
    final now = DateTime.now();
    
    // Filter programs where stopTime is after now
    return list.where((p) => p.stopTime.isAfter(now)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  static List<EpgProgram>? _getProgramList(String? channelId, String? channelName) {
    if (channelId != null) {
      if (_channelPrograms.containsKey(channelId)) return _channelPrograms[channelId];
      if (_channelPrograms.containsKey('ts$channelId')) return _channelPrograms['ts$channelId'];
    }
    if (channelName != null) {
      final normalized = _normalize(channelName);
      if (_channelPrograms.containsKey(normalized)) return _channelPrograms[normalized];
      
      // Try exact clean match
      final cleanName = _cleanChannelName(channelName);
      if (_channelPrograms.containsKey(cleanName)) return _channelPrograms[cleanName];
      
      // Fuzzy prefix/contains matching
      for (final key in _channelPrograms.keys) {
        if (key.length > 3 && (normalized.contains(key) || key.contains(normalized))) {
          return _channelPrograms[key];
        }
      }
    }
    return null;
  }

  /// Get channel logo extracted from EPG by channel ID or Name
  static String? getChannelLogo(String? channelId, String? channelName) {
    if (channelId != null) {
      if (_channelLogos.containsKey(channelId)) return _channelLogos[channelId];
      if (_channelLogos.containsKey('ts$channelId')) return _channelLogos['ts$channelId'];
    }
    
    if (channelName != null) {
      final normalized = _normalize(channelName);
      if (_channelLogos.containsKey(normalized)) return _channelLogos[normalized];
      
      // Try with HD/SD stripped version
      final cleanName = _cleanChannelName(channelName);
      if (_channelLogos.containsKey(cleanName)) return _channelLogos[cleanName];
      
      // Loop for exact matches of clean names
      for (final entry in _channelLogos.entries) {
        final keyClean = _cleanChannelName(entry.key);
        if (keyClean == cleanName && cleanName.length > 2) {
          return entry.value;
        }
      }
    }
    return null;
  }

  /// Returns list of all unique channel IDs loaded in EPG
  static List<String> get availableEpgChannelIds => _channelPrograms.keys.toList();
}
