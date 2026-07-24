import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ImageSearchResult {
  final String imageUrl;
  final String thumbnailUrl;
  final String source;

  ImageSearchResult({
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.source,
  });
}

class ImageSearchService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.5',
    },
  ));

  /// Search Web Images (Google)
  static Future<List<ImageSearchResult>> searchGoogleImages(String movieTitle, {bool isPoster = true}) async {
    final query = isPoster ? '$movieTitle movie poster HD' : '$movieTitle movie backdrop wallpaper HD';
    final results = await _searchDuckDuckGo(query, 'Google');
    if (results.isNotEmpty) return results;
    return _searchBing(query, 'Google');
  }

  /// Search Pinterest Images
  static Future<List<ImageSearchResult>> searchPinterestImages(String movieTitle, {bool isPoster = true}) async {
    final query = isPoster ? '$movieTitle movie poster pinterest HD' : '$movieTitle movie backdrop wallpaper pinterest HD';
    final results = await _searchDuckDuckGo(query, 'Pinterest');
    final filtered = results.where((item) {
      final url = item.imageUrl.toLowerCase();
      return !url.contains('favicon') && !url.contains('profile_images') && !url.contains('logo') && !url.contains('avatar_') && !url.contains('user_');
    }).toList();
    
    if (filtered.isNotEmpty) return filtered;
    return _searchBing(query, 'Pinterest');
  }

  static Future<List<ImageSearchResult>> _searchDuckDuckGo(String query, String sourceName) async {
    final List<ImageSearchResult> list = [];
    try {
      final tokenRes = await _dio.get(
        'https://html.duckduckgo.com/html/',
        queryParameters: {'q': query},
      );
      final body = tokenRes.data.toString();

      String? vqd;
      final vqdMatch1 = RegExp(r'name="vqd"\s+value="([^"]+)"').firstMatch(body);
      if (vqdMatch1 != null) {
        vqd = vqdMatch1.group(1);
      } else {
        final vqdMatch2 = RegExp(r'vqd=([\d-]+)').firstMatch(body);
        if (vqdMatch2 != null) vqd = vqdMatch2.group(1);
      }

      if (vqd != null && vqd.isNotEmpty) {
        final imgRes = await _dio.get(
          'https://duckduckgo.com/i.js',
          queryParameters: {
            'l': 'us-en',
            'o': 'json',
            'q': query,
            'vqd': vqd,
            'f': ',,,',
            'p': '1',
          },
          options: Options(
            headers: {
              'Referer': 'https://duckduckgo.com/',
              'Accept': 'application/json, text/javascript, */*; q=0.01',
            },
          ),
        );

        dynamic data = imgRes.data;
        if (data is String) {
          try { data = jsonDecode(data); } catch (_) {}
        }

        if (data is Map && data['results'] != null) {
          final results = data['results'] as List;
          for (final r in results) {
            final img = r['image']?.toString();
            final thumb = r['thumbnail']?.toString() ?? img;
            if (img != null && img.startsWith('http')) {
              list.add(ImageSearchResult(imageUrl: img, thumbnailUrl: thumb!, source: sourceName));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('ImageSearchService DuckDuckGo error ($sourceName): $e');
    }
    return list;
  }

  static Future<List<ImageSearchResult>> _searchBing(String query, String sourceName) async {
    final List<ImageSearchResult> list = [];
    try {
      final res = await _dio.get(
        'https://www.bing.com/images/search',
        queryParameters: {'q': query, 'form': 'HDRSC2'},
      );
      final html = res.data.toString();
      final matches = RegExp(r'murl&quot;:&quot;(https?://[^&]+)&quot;').allMatches(html);
      final thumbMatches = RegExp(r'turl&quot;:&quot;(https?://[^&]+)&quot;').allMatches(html);
      
      final thumbs = thumbMatches.map((m) => m.group(1)!).toList();
      int i = 0;
      for (final m in matches) {
        final imgUrl = m.group(1);
        if (imgUrl != null && imgUrl.startsWith('http')) {
          final thumbUrl = (i < thumbs.length) ? thumbs[i] : imgUrl;
          list.add(ImageSearchResult(imageUrl: imgUrl, thumbnailUrl: thumbUrl, source: sourceName));
          i++;
        }
      }
    } catch (e) {
      debugPrint('ImageSearchService Bing error ($sourceName): $e');
    }
    return list;
  }
}
