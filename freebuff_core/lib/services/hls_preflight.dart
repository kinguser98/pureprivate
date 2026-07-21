import 'package:dio/dio.dart';

class HlsPreflightResult {
  final List<String> audioLanguages;
  final List<String> qualities;
  final String rawPlaylist;

  HlsPreflightResult({required this.audioLanguages, required this.qualities, required this.rawPlaylist});
}

class HlsPreflightService {
  final Dio _dio;
  HlsPreflightService(this._dio);

  Future<HlsPreflightResult?> run(String url) async {
    try {
      final response = await _dio.get<String>(url, options: Options(responseType: ResponseType.plain));
      final text = response.data ?? '';
      if (!text.startsWith('#EXTM3U')) return null;
      final audioLines = text.split('\n').where((l) => l.startsWith('#EXT-X-MEDIA:TYPE=AUDIO')).toList();
      final audioLangs = audioLines.map((l) => RegExp(r'NAME="([^"]+)"').firstMatch(l)?.group(1)).whereType<String>().toList();
      final qualities = <String>{};
      for (final line in text.split('\n')) {
        if (line.startsWith('#EXT-X-STREAM-INF')) {
          final m = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line);
          if (m != null) {
            final q = '${int.parse(m.group(1)!)}p';
            qualities.add(q);
          }
        }
      }
      return HlsPreflightResult(audioLanguages: audioLangs, qualities: qualities.toList()..sort((a, b) => int.parse(b.replaceAll('p', '')) - int.parse(a.replaceAll('p', ''))), rawPlaylist: text);
    } catch (_) {
      return null;
    }
  }
}
