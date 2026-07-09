import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class StremioStream {
  final String name;
  final String title;
  final String url;
  final Map<String, String> headers;
  final String addonName;
  final String originalTitle;
  final String quality;
  final List<String> languages;
  final String? size;

  StremioStream({
    required this.name,
    required this.title,
    required this.url,
    required this.headers,
    required this.addonName,
    required this.originalTitle,
    required this.quality,
    required this.languages,
    this.size,
  });
}

class StremioParser {
  static String parseQuality(String name, String title) {
    final combined = '$name\n$title'.toLowerCase();
    if (RegExp(r'\b(2160p|4k|uhd|2160)\b').hasMatch(combined)) {
      return '2160p (4K)';
    }
    if (RegExp(r'\b(1080p|fhd|1080)\b').hasMatch(combined)) {
      return '1080p';
    }
    if (RegExp(r'\b(720p|720)\b').hasMatch(combined) || RegExp(r'\bhd\b').hasMatch(combined)) {
      return '720p';
    }
    if (RegExp(r'\b(480p|sd|480|576p|576)\b').hasMatch(combined)) {
      return '480p';
    }
    return '1080p'; // Default fallback
  }

  static List<String> parseLanguages(String name, String title) {
    final combined = '$name\n$title'.toLowerCase();
    final List<String> detected = [];
    final Map<String, List<String>> langMap = {
      'Hindi': ['hindi', 'hin', 'ind'],
      'English': ['english', 'eng'],
      'Tamil': ['tamil', 'tam'],
      'Telugu': ['telugu', 'tel'],
      'Malayalam': ['malayalam', 'mal'],
      'Kannada': ['kannada', 'kan'],
      'Spanish': ['spanish', 'esp', 'spa'],
      'French': ['french', 'fre', 'fra'],
      'German': ['german', 'ger', 'deu'],
      'Italian': ['italian', 'ita'],
      'Portuguese': ['portuguese', 'por'],
      'Russian': ['russian', 'rus'],
      'Chinese': ['chinese', 'chi', 'zho'],
      'Japanese': ['japanese', 'jpn', 'jap'],
      'Korean': ['korean', 'kor'],
    };

    if (RegExp(r'\b(multi|dual|dual-audio|multi-audio|dual\s+audio|multi\s+audio)\b').hasMatch(combined)) {
      detected.add('Multi Audio');
    }

    for (final entry in langMap.entries) {
      for (final keyword in entry.value) {
        if (keyword.length <= 3) {
          final regex = RegExp('\\b$keyword\\b');
          if (regex.hasMatch(combined)) {
            detected.add(entry.key);
            break;
          }
        } else {
          if (combined.contains(keyword)) {
            detected.add(entry.key);
            break;
          }
        }
      }
    }

    if (detected.isEmpty) {
      detected.add('English');
    }
    return detected;
  }

  static String? parseSize(String title) {
    final regex = RegExp(r'\b(\d+(?:\.\d+)?\s*(?:GB|MB|GiB|MiB|gb|mb|gib|mib))\b', caseSensitive: false);
    final match = regex.firstMatch(title);
    if (match != null) {
      return match.group(1);
    }
    return null;
  }
}

class StremioAddonResolver {
  static Future<List<StremioStream>> fetchStreams({
    required String manifestUrl,
    required String type, // 'movie' or 'series'
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    // Standardize URL by removing trailing slash if any, then replacing manifest.json
    var baseUrl = manifestUrl.trim();
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    baseUrl = baseUrl.replaceAll('/manifest.json', '');
    
    final String streamId = (type == 'series' && season != null && episode != null)
        ? '$imdbId:$season:$episode'
        : imdbId;

    final url = Uri.parse('$baseUrl/stream/$type/$streamId.json');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> streamsList = data['streams'] ?? [];
        final List<StremioStream> results = [];
        
        for (final item in streamsList) {
          final streamUrl = item['url']?.toString() ?? '';
          if (streamUrl.isEmpty) continue;
          
          // Keep magnet links for P2P streaming via dart_torrent (WebTorrent).
          // Magnet URLs are kept and passed to the player which handles them.

          final headers = <String, String>{};
          final reqHeaders = item['behaviorHints']?['proxyHeaders']?['request'] as Map?;
          reqHeaders?.forEach((k, v) {
            headers[k.toString()] = v.toString();
          });

          final nameVal = item['name']?.toString() ?? 'Stremio Addon';
          final titleVal = item['title']?.toString() ?? item['description']?.toString() ?? 'Stream Link';

          final addonName = nameVal.split('\n')[0].trim();
          final quality = StremioParser.parseQuality(nameVal, titleVal);
          final languages = StremioParser.parseLanguages(nameVal, titleVal);
          final size = StremioParser.parseSize(titleVal);

          results.add(StremioStream(
            name: nameVal,
            title: titleVal,
            url: streamUrl,
            headers: headers,
            addonName: addonName,
            originalTitle: titleVal,
            quality: quality,
            languages: languages,
            size: size,
          ));
        }
        return results;
      }
    } catch (e) {
      debugPrint('StremioAddonResolver: Error fetching streams from $manifestUrl: $e');
    }
    return [];
  }
}
