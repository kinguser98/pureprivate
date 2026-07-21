import 'dart:convert';
import 'package:dio/dio.dart';

class StremioStream {
  final String name;
  final String url;
  final String quality;
  final Map<String, String> headers;
  final String addonName;
  final List<String> languages;
  StremioStream({required this.name, required this.url, required this.quality, required this.headers, required this.addonName, required this.languages});
}

class StremioResolver {
  final Dio _dio;
  final List<String> addons; // manifest URLs
  StremioResolver(this._dio, this.addons);

  Future<List<StremioStream>> resolve(String imdbId, {String type = 'movie'}) async {
    if (addons.isEmpty) return [];
    final results = <StremioStream>[];
    for (final manifestUrl in addons) {
      try {
        final base = manifestUrl.replaceAll('/manifest.json', '');
        final url = '$base/stream/$type/$imdbId.json';
        final proxy = 'api_proxy.php?url=${Uri.encodeComponent(url)}';
        final resp = await _dio.get<String>(proxy, options: Options(responseType: ResponseType.json));
        final data = resp.data != null ? jsonDecode(resp.data!) : null;
        if (data == null || data['streams'] == null) continue;
        for (final s in data['streams']) {
          final streamUrl = s['url'] as String? ?? '';
          if (streamUrl.isEmpty || streamUrl.startsWith('magnet:')) continue;
          final title = s['title'] as String? ?? '';
          final quality = RegExp(r'(2160p|1080p|720p|480p|360p)', caseSensitive: false).firstMatch(title)?.group(1) ?? '';
          final langs = _extractLanguages(title);
          results.add(StremioStream(
            name: title.isNotEmpty ? title : 'Stream',
            url: streamUrl,
            quality: quality,
            headers: (s['behaviorHints']?['proxyHeaders']?['request'] as Map?)?.cast<String, String>() ?? {},
            addonName: s['addonName'] as String? ?? 'Stremio',
            languages: langs,
          ));
        }
      } catch (_) {
        // ignore individual addon failures
      }
    }
    return results;
  }

  List<String> _extractLanguages(String title) {
    const known = ['Hindi','English','Tamil','Telugu','Malayalam','Kannada','Bengali','Punjabi','Japanese','Korean','Spanish','French'];
    final upper = title.toUpperCase();
    return known.where((l) => upper.contains(l.toUpperCase())).toList();
  }
}
