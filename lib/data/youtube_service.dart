import 'package:youtube_explode_dart/youtube_explode_dart.dart';

abstract final class YoutubeService {
  static Future<String?> getStreamUrl(String youtubeUrl) async {
    final yt = YoutubeExplode();
    try {
      final videoId = VideoId.parseVideoId(youtubeUrl);
      if (videoId == null) return null;
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      
      if (manifest.muxed.isNotEmpty) {
        // Sort muxed streams by resolution height descending (highest quality first)
        final streams = List<MuxedStreamInfo>.from(manifest.muxed)
          ..sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
        return streams.first.url.toString();
      }
    } catch (e) {
      print('Error extracting YouTube stream URL: $e');
    } finally {
      yt.close();
    }
    return null;
  }
}
