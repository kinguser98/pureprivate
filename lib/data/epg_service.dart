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

class EpgSourceDef {
  final String id;
  final String name;
  final String url;
  const EpgSourceDef({required this.id, required this.name, required this.url});
}

class EpgService {
  static const List<EpgSourceDef> defaultSources = [
    EpgSourceDef(
      id: 'aio',
      name: 'AIO (All-in-One)',
      url: 'https://avkb.short.gy/epg.xml.gz',
    ),
    EpgSourceDef(
      id: 'jio',
      name: 'JioTV',
      url: 'https://avkb.short.gy/jioepg.xml.gz',
    ),
    EpgSourceDef(
      id: 'tataplay',
      name: 'Tata Play',
      url: 'https://avkb.short.gy/tsepg.xml.gz',
    ),
    EpgSourceDef(
      id: 'epgshare',
      name: 'EPGShare India',
      url: 'https://epgshare01.online/epgshare01/epg_ripper_IN1.xml.gz',
    ),
  ];

  // Cache of all future programs: channelId/normalizedName -> list of EpgPrograms
  static final Map<String, List<EpgProgram>> _channelPrograms = {};
  // Cached channel logos extracted from EPG: channelId -> logo URL
  static final Map<String, String> _channelLogos = {};
  // Cached channel display names: channelId -> display name (e.g., "Asianet Movies HD")
  static final Map<String, String> _channelDisplayNames = {};
  // Cached channel source names: channelId -> Set of source names (e.g. {"AIO (All-in-One)", "JioTV"})
  static final Map<String, Set<String>> _channelSourceNames = {};
  // Genuine channel IDs in loaded order
  static final List<String> _allChannelIds = [];

  static bool _isLoaded = false;
  static bool _isLoading = false;

  static bool get isLoaded => _isLoaded;
  static bool get isLoading => _isLoading;
  static Map<String, String> get channelDisplayNames => _channelDisplayNames;
  static Map<String, Set<String>> get channelSourceNames => _channelSourceNames;

  static List<String> get availableSources => [
    'ALL',
    'AIO (All-in-One)',
    'JioTV',
    'Tata Play',
    'EPGShare India',
  ];

  static final Map<String, String> _aliases = {
    'flowerstv': 'flowertv',
    'suryatv': 'sunsurya',
    'suryamovies': 'sunsuryamovies',
    'suryamusic': 'sunsuryamusic',
    'suryacomedy': 'sunsuryacomedy',
    'mazhavil': 'mazhavilmanorama',
  };

  /// Fetches EPG files, decompresses using GZip, and parses active programs.
  /// Caches current and future programs to keep memory footprint light.
  static Future<void> loadEpg([List<String>? customUrls]) async {
    if (_isLoading) return;
    _isLoading = true;
    _channelPrograms.clear();
    _channelLogos.clear();
    _channelDisplayNames.clear();
    _channelSourceNames.clear();
    _allChannelIds.clear();

    final List<EpgSourceDef> sourcesToLoad;
    if (customUrls != null && customUrls.where((u) => u.trim().isNotEmpty).isNotEmpty) {
      sourcesToLoad = customUrls.where((u) => u.trim().isNotEmpty).map((url) {
        final match = defaultSources.cast<EpgSourceDef?>().firstWhere(
          (s) => s?.url == url,
          orElse: () => null,
        );
        return match ?? EpgSourceDef(id: url, name: _deriveSourceName(url), url: url);
      }).toList();
    } else {
      sourcesToLoad = defaultSources;
    }

    final now = DateTime.now();

    for (final src in sourcesToLoad) {
      try {
        debugPrint('EPGService: Fetching ${src.name} (${src.url})...');
        final res = await http.get(Uri.parse(src.url)).timeout(const Duration(seconds: 30));
        if (res.statusCode == 200) {
          debugPrint('EPGService: Decompressing gzip from ${src.name}...');
          final decompressedBytes = gzip.decode(res.bodyBytes);
          final xmlContent = utf8.decode(decompressedBytes);

          debugPrint('EPGService: Parsing xml content for ${src.name} (Length: ${xmlContent.length} chars)...');
          _parseActivePrograms(xmlContent, now, src.name);
        }
      } catch (e) {
        debugPrint('EPGService: Error loading EPG from ${src.url}: $e');
      }
    }

    // Sort all channel program lists by startTime
    _channelPrograms.forEach((key, list) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    });

    _isLoaded = true;
    _isLoading = false;
    debugPrint('EPGService: Finished loading EPG. Cached ${_allChannelIds.length} channels from ${sourcesToLoad.length} sources.');
  }

  static String _deriveSourceName(String url) {
    if (url.contains('jio')) return 'JioTV';
    if (url.contains('tsepg')) return 'Tata Play';
    if (url.contains('epgshare')) return 'EPGShare India';
    if (url.contains('epg.')) return 'AIO (All-in-One)';
    final uri = Uri.tryParse(url);
    return uri?.host.isNotEmpty == true ? uri!.host : 'Custom';
  }

  static void _parseActivePrograms(String xml, DateTime now, String sourceName) {
    DateTime? parseEpgTime(String? timeStr) {
      if (timeStr == null || timeStr.length < 14) return null;
      try {
        final year = int.parse(timeStr.substring(0, 4));
        final month = int.parse(timeStr.substring(4, 6));
        final day = int.parse(timeStr.substring(6, 8));
        final hour = int.parse(timeStr.substring(8, 10));
        final minute = int.parse(timeStr.substring(10, 12));
        final second = int.parse(timeStr.substring(12, 14));

        var dt = DateTime.utc(year, month, day, hour, minute, second);
        if (timeStr.contains('+') || timeStr.contains('-')) {
          final parts = timeStr.split(' ');
          if (parts.length > 1) {
            final offsetStr = parts[1];
            if (offsetStr.length == 5) {
              final sign = offsetStr[0] == '+' ? 1 : -1;
              final offsetHours = int.parse(offsetStr.substring(1, 3));
              final offsetMins = int.parse(offsetStr.substring(3, 5));
              final totalOffsetMins = sign * (offsetHours * 60 + offsetMins);
              dt = dt.subtract(Duration(minutes: totalOffsetMins));
            }
          }
        }
        return dt.toLocal();
      } catch (_) {
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
            _channelSourceNames.putIfAbsent(channelId, () => {}).add(sourceName);
            if (!_allChannelIds.contains(channelId)) {
              _allChannelIds.add(channelId);
            }

            final iconMatch = iconExp.firstMatch(content);
            if (iconMatch != null) {
              final iconUrl = iconMatch.group(1);
              if (iconUrl != null && iconUrl.isNotEmpty) {
                _channelLogos[channelId] = iconUrl;
                _channelLogos[_normalize(dName)] = iconUrl;
                final clean = _cleanChannelName(dName);
                if (clean.isNotEmpty) {
                  _channelLogos[clean] = iconUrl;
                }
              }
            }
          }
        }
      }
    }

    // 2. Extract programme tags
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

        // Also store by normalized and cleaned display name for instant fuzzy matching
        final displayName = channelNames[channelId];
        if (displayName != null) {
          final normalized = _normalize(displayName);
          _channelPrograms.putIfAbsent(normalized, () => []).add(prog);
          final clean = _cleanChannelName(displayName);
          if (clean.isNotEmpty && clean != normalized) {
            _channelPrograms.putIfAbsent(clean, () => []).add(prog);
          }
        }
      }
    }
  }

  static String _normalize(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String _cleanChannelName(String s) {
    var str = s.toLowerCase();
    // Strip bracket expressions e.g. [MAL], (HD), [4K]
    str = str.replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), ' ');
    // Strip common IPTV category/language prefixes e.g. "MAL: ", "MALAYALAM - ", "KL: "
    str = str.replaceFirst(RegExp(r'^(mal|malayalam|kl|in|ind|south|tam|tamil|tel|telugu|kan|kannada|hin|hindi)\s*[:|\-]?\s*', caseSensitive: false), '');
    // Strip quality tokens
    str = str.replaceAll(RegExp(r'\b(fhd|uhd|hd|sd|4k|hevc|h265|h264|\+1|temp)\b', caseSensitive: false), ' ');
    return str.replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
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
    // Fallback: next 15 minutes
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

    return list.where((p) => p.stopTime.isAfter(now)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  static List<EpgProgram>? _getProgramList(String? channelId, String? channelName) {
    if (channelId != null && channelId.isNotEmpty) {
      if (_channelPrograms.containsKey(channelId)) return _channelPrograms[channelId];
      if (_channelPrograms.containsKey('ts$channelId')) return _channelPrograms['ts$channelId'];
      final cleanId = _cleanChannelName(channelId);
      if (_channelPrograms.containsKey(cleanId)) return _channelPrograms[cleanId];
    }
    if (channelName != null && channelName.isNotEmpty) {
      final normalized = _normalize(channelName);
      if (_channelPrograms.containsKey(normalized)) return _channelPrograms[normalized];

      final cleanName = _cleanChannelName(channelName);
      if (_channelPrograms.containsKey(cleanName)) return _channelPrograms[cleanName];

      // Check aliases
      final alias = _aliases[cleanName] ?? _aliases[normalized];
      if (alias != null && _channelPrograms.containsKey(alias)) {
        return _channelPrograms[alias];
      }

      // Fuzzy prefix/contains matching
      for (final entry in _channelPrograms.entries) {
        final key = entry.key;
        if (key.length > 3 && (normalized.contains(key) || key.contains(normalized) || (cleanName.length > 3 && (cleanName.contains(key) || key.contains(cleanName))))) {
          return entry.value;
        }
      }
    }
    return null;
  }

  /// Get channel logo extracted from EPG by channel ID or Name
  static String? getChannelLogo(String? channelId, String? channelName) {
    if (channelId != null && channelId.isNotEmpty) {
      if (_channelLogos.containsKey(channelId)) return _channelLogos[channelId];
      if (_channelLogos.containsKey('ts$channelId')) return _channelLogos['ts$channelId'];
      final cleanId = _cleanChannelName(channelId);
      if (_channelLogos.containsKey(cleanId)) return _channelLogos[cleanId];
    }

    if (channelName != null && channelName.isNotEmpty) {
      final normalized = _normalize(channelName);
      if (_channelLogos.containsKey(normalized)) return _channelLogos[normalized];

      final cleanName = _cleanChannelName(channelName);
      if (_channelLogos.containsKey(cleanName)) return _channelLogos[cleanName];

      final alias = _aliases[cleanName] ?? _aliases[normalized];
      if (alias != null && _channelLogos.containsKey(alias)) {
        return _channelLogos[alias];
      }

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
  static List<String> get availableEpgChannelIds => _allChannelIds.isNotEmpty ? _allChannelIds : _channelDisplayNames.keys.toList();
}
