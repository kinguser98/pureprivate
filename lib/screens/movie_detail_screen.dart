import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/data/api_service.dart';
import 'package:private_cinema_mobile/data/download_manager.dart';
import 'package:private_cinema_mobile/data/playback_tracker.dart';
import 'package:private_cinema_mobile/data/youtube_service.dart';
import 'package:private_cinema_mobile/data/embed_resolver.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/widgets/movie_image.dart';
import 'package:private_cinema_mobile/screens/video_player_screen.dart';
import 'package:private_cinema_mobile/screens/webview_player_screen.dart';
import 'package:private_cinema_mobile/data/stalker_resolver.dart';

class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({super.key, required this.movie});

  final Movie movie;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  String? _pickedPath;
  bool _isFavorite = false;
  bool _inWatchlist = false;
  bool _isDownloaded = false;

  List<CastMember> _dynamicCast = [];
  String? _dynamicDirector;
  String? _directorProfileUrl;
  double? _dynamicRating;
  double? _dynamicPopularity;

  double? _watchProgress;
  int _savedPositionMs = 0;

  List<StreamSource> _torrentioSources = [];
  List<StreamSource> _stravoSources = [];
  final Map<String, Map<String, int>> _customMagnetStats = {};

  static const List<String> _scrapeTrackers = [
    'http://tracker.opentrackr.org:1337/scrape',
    'https://tracker.nanoha.org:443/scrape',
    'http://open.acgtracker.com:1096/scrape',
  ];

  String? _extractInfoHash(String magnetUrl) {
    try {
      final uri = Uri.parse(magnetUrl);
      final xt = uri.queryParameters['xt'];
      if (xt != null && xt.startsWith('urn:btih:')) {
        return xt.substring('urn:btih:'.length).toLowerCase();
      }
    } catch (_) {}
    final match = RegExp(r'xt=urn:btih:([a-fA-F0-9]{40}|[a-zA-Z2-9]{32})', caseSensitive: false).firstMatch(magnetUrl);
    if (match != null) {
      return match.group(1)?.toLowerCase();
    }
    return null;
  }

  String _hexToUrlEncoded(String hex) {
    final cleanHex = hex.trim().toLowerCase();
    if (cleanHex.length != 40) return '';
    final buffer = StringBuffer();
    for (int i = 0; i < cleanHex.length; i += 2) {
      buffer.write('%${cleanHex.substring(i, i + 2)}');
    }
    return buffer.toString();
  }

  Future<Map<String, int>?> _scrapeTorrentStats(String magnetUrl) async {
    final infoHash = _extractInfoHash(magnetUrl);
    if (infoHash == null || infoHash.length != 40) return null;
    
    final urlEncodedHash = _hexToUrlEncoded(infoHash);
    if (urlEncodedHash.isEmpty) return null;

    for (final trackerUrl in _scrapeTrackers) {
      try {
        final scrapeUrl = '$trackerUrl?info_hash=$urlEncodedHash';
        final response = await http.get(Uri.parse(scrapeUrl)).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final body = latin1.decode(response.bodyBytes);
          final completeMatch = RegExp(r'completei(\d+)e').firstMatch(body);
          final incompleteMatch = RegExp(r'incompletei(\d+)e').firstMatch(body);
          
          if (completeMatch != null || incompleteMatch != null) {
            final seeders = completeMatch != null ? int.parse(completeMatch.group(1)!) : 0;
            final peers = incompleteMatch != null ? int.parse(incompleteMatch.group(1)!) : 0;
            return {'seeders': seeders, 'peers': peers};
          }
        }
      } catch (e) {
        debugPrint('Failed to scrape from $trackerUrl: $e');
      }
    }
    return null;
  }

  Movie get movie => widget.movie;

  bool get _canDownload {
    if (_pickedPath != null) return false;
    return _getDownloadableSources().isNotEmpty;
  }

  List<StreamSource> _getDownloadableSources() {
    final sources = _getEffectiveSources();
    return sources.where((src) => 
      !_isYoutubeSource(src) && !_isEmbedSource(src)
    ).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadFavoriteStatus();
    _loadWatchlistState();
    _loadTmdbDetails();
    _checkDownloadStatus();
    _loadWatchProgress();
    _loadTorrentioStreams();
  }

  Future<void> _loadWatchProgress() async {
    final progress = await PlaybackTracker.getWatchProgress(movie.id);
    final pos = await PlaybackTracker.getSavedPosition(movie.id);
    if (mounted) {
      setState(() {
        _watchProgress = progress;
        _savedPositionMs = pos;
      });
    }
  }

  Future<void> _loadTorrentioStreams() async {
    // Start scraping custom magnets
    final customMagnets = movie.streamSources.where(_isMagnetSource).toList();
    for (final source in customMagnets) {
      _scrapeTorrentStats(source.url).then((stats) {
        if (stats != null && mounted) {
          setState(() {
            _customMagnetStats[source.url] = stats;
          });
        }
      });
    }

    final imdbId = movie.imdbId;
    if (imdbId == null || imdbId.isEmpty || imdbId == 'null') return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final addonBaseUrl = prefs.getString('torrentio_addon_url') ?? 'https://torrentio.strem.fun';
      
      var baseUrl = addonBaseUrl.trim();
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      
      final url = '$baseUrl/stream/movie/$imdbId.json';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final streamsList = data['streams'] as List<dynamic>? ?? [];
        final List<StreamSource> torrentSources = [];
        
        for (final stream in streamsList) {
          final title = stream['title']?.toString() ?? 'Torrent Stream';
          final infoHash = stream['infoHash']?.toString() ?? '';
          if (infoHash.isNotEmpty) {
            final trackers = [
              'udp://tracker.coppersurfer.tk:6969/announce',
              'udp://tracker.openbittorrent.com:6969/announce',
              'udp://tracker.opentrackr.org:1337/announce',
              'udp://tracker.leechers-paradise.org:6969/announce',
              'udp://open.stealth.si:80/announce',
              'udp://tracker.tiny-vps.me:6969/announce',
            ];
            final trackersQuery = trackers.map((t) => 'tr=${Uri.encodeComponent(t)}').join('&');
            final magnetLink = 'magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(movie.title)}&$trackersQuery';
            
            final titleLines = title.split('\n');
            final mainTitle = titleLines.isNotEmpty ? titleLines[0] : 'Torrent';
            final peerInfo = titleLines.length > 1 ? titleLines[1] : '';
            final sizeInfo = titleLines.length > 2 ? titleLines[2] : '';
            
            var sourceName = 'Torrent: $mainTitle';
            if (peerInfo.isNotEmpty || sizeInfo.isNotEmpty) {
              sourceName += ' ($peerInfo ${sizeInfo.isNotEmpty ? "• $sizeInfo" : ""})';
            }
            sourceName = sourceName
                .replaceAll('👥', ' Peers:')
                .replaceAll('👤', ' Seeders:')
                .replaceAll('\n', ' ');
            
            final isDup = torrentSources.any((s) => s.url == magnetLink);
            if (!isDup) {
              torrentSources.add(StreamSource(
                name: sourceName,
                url: magnetLink,
              ));
            }
          }
        }
        
        if (mounted) {
          setState(() {
            _torrentioSources = torrentSources;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching Torrentio streams: $e');
    }
  }

  Future<List<StreamSource>> _fetchStravoStreams() async {
    if (_stravoSources.isNotEmpty) {
      return _stravoSources;
    }

    final imdbId = movie.imdbId;
    if (imdbId == null || imdbId.isEmpty || imdbId == 'null') {
      return [];
    }

    final prefs = await SharedPreferences.getInstance();
    final addonBaseUrl = prefs.getString('stravo_addon_url') ?? 'https://stravo-clfk.onrender.com/default';
    
    var baseUrl = addonBaseUrl.trim();
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    
    final url = '$baseUrl/stream/movie/$imdbId.json';
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final streamsList = data['streams'] as List<dynamic>? ?? [];
      final List<StreamSource> stravoSources = [];
      
      for (final stream in streamsList) {
        final urlStr = stream['url']?.toString() ?? '';
        if (urlStr.isNotEmpty) {
          final name = stream['name']?.toString() ?? '';
          final title = stream['title']?.toString() ?? '';
          final displayTitle = title.isNotEmpty 
              ? (name.isNotEmpty ? '$title ($name)' : title)
              : (name.isNotEmpty ? name : 'Stravo Stream');
          
          final cleanName = displayTitle.replaceAll('\n', ' ').trim();
          
          if (cleanName.contains('🖥️') || name.contains('🖥️') || title.contains('🖥️')) {
            continue; // Skip direct PC streams as requested
          }

          final isDup = stravoSources.any((s) => s.url == urlStr);
          if (!isDup) {
            stravoSources.add(StreamSource(
              name: 'Stravo: $cleanName',
              url: urlStr,
            ));
          }
        }
      }
      
      _stravoSources = stravoSources;
      return stravoSources;
    } else {
      throw Exception('Server returned status code ${response.statusCode}');
    }
  }

  void _showStravoSourceSelector(BuildContext context, {bool resumeDirectly = false}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SELECT STRAVO STREAM',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: FutureBuilder<List<StreamSource>>(
                    future: _fetchStravoStreams(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return SizedBox(
                          height: 120,
                          child: Center(
                            child: CircularProgressIndicator(color: AppColors.accentBright),
                          ),
                        );
                      }
                      
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'Error: ${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                            ),
                          ),
                        );
                      }

                      final sources = snapshot.data ?? [];
                      if (sources.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'No Stravo streams found for this content.',
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: sources.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final source = sources[index];
                          return ListTile(
                            leading: Icon(
                              Icons.cloud_queue_rounded,
                              color: AppColors.accentBright,
                            ),
                            title: Text(
                              source.name.replaceFirst('Stravo: ', ''),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            subtitle: Text(
                              source.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white30, fontSize: 11),
                            ),
                            tileColor: Colors.white.withValues(alpha: 0.03),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onTap: () {
                              Navigator.of(context).pop();
                              _playWithResolution(source.url, resumeDirectly: resumeDirectly, sourceName: source.name);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _checkDownloadStatus() async {
    final isDown = await DownloadManager.isDownloaded(movie.id);
    if (mounted) {
      setState(() {
        _isDownloaded = isDown;
      });
    }
  }

  Future<void> _loadWatchlistState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('watchlist_ids') ?? [];
      if (mounted) {
        setState(() {
          _inWatchlist = list.contains(movie.id);
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleWatchlist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('watchlist_ids') ?? [];
      if (list.contains(movie.id)) {
        list.remove(movie.id);
        setState(() => _inWatchlist = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from Watchlist.')),
        );
      } else {
        list.add(movie.id);
        setState(() => _inWatchlist = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to Watchlist.')),
        );
      }
      await prefs.setStringList('watchlist_ids', list);
    } catch (_) {}
  }

  Future<void> _loadFavoriteStatus() async {
    final isFav = await ApiService.checkFavoriteCloud(movie.id);
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList('favorites') ?? [];
    if (isFav) {
      if (!favorites.contains(movie.id)) {
        favorites.add(movie.id);
        await prefs.setStringList('favorites', favorites);
      }
    } else {
      if (favorites.contains(movie.id)) {
        favorites.remove(movie.id);
        await prefs.setStringList('favorites', favorites);
      }
    }

    if (mounted) {
      setState(() {
        _isFavorite = isFav;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final isFav = await ApiService.toggleFavoriteCloud(movie.id);
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList('favorites') ?? [];
    if (isFav) {
      if (!favorites.contains(movie.id)) {
        favorites.add(movie.id);
      }
    } else {
      favorites.remove(movie.id);
    }
    await prefs.setStringList('favorites', favorites);

    if (mounted) {
      setState(() {
        _isFavorite = isFav;
      });
    }
  }

  Future<void> _loadTmdbDetails() async {
    final tmdbId = movie.tmdbId;
    if (tmdbId == null || tmdbId.isEmpty || tmdbId == '0' || tmdbId == 'null') {
      setState(() {
        _dynamicCast = movie.castMembers;
        _dynamicDirector = movie.director;
        _directorProfileUrl = movie.directorPhoto;
        _dynamicRating = null;
      });
      return;
    }

    try {
      // 1. Fetch Credits (Cast & Crew)
      var creditsUrl = Uri.parse('https://api.themoviedb.org/3/movie/$tmdbId/credits?api_key=8baba8ab6b8bbe247645bcae7df63d0d');
      var creditsResponse = await http.get(creditsUrl).timeout(const Duration(seconds: 8));

      if (creditsResponse.statusCode == 404) {
        creditsUrl = Uri.parse('https://api.themoviedb.org/3/tv/$tmdbId/credits?api_key=8baba8ab6b8bbe247645bcae7df63d0d');
        creditsResponse = await http.get(creditsUrl).timeout(const Duration(seconds: 8));
      }

      // 2. Fetch Details (Rating / Vote Average)
      var detailsUrl = Uri.parse('https://api.themoviedb.org/3/movie/$tmdbId?api_key=8baba8ab6b8bbe247645bcae7df63d0d');
      var detailsResponse = await http.get(detailsUrl).timeout(const Duration(seconds: 8));

      if (detailsResponse.statusCode == 404) {
        detailsUrl = Uri.parse('https://api.themoviedb.org/3/tv/$tmdbId?api_key=8baba8ab6b8bbe247645bcae7df63d0d');
        detailsResponse = await http.get(detailsUrl).timeout(const Duration(seconds: 8));
      }

      List<CastMember> cast = movie.castMembers;
      String? director = movie.director;
      String? directorProfile;
      double? rating;
      double? popularity;

      if (creditsResponse.statusCode == 200) {
        final jsonString = utf8.decode(creditsResponse.bodyBytes);
        final data = json.decode(jsonString) as Map<String, dynamic>;

        final List<CastMember> parsedCast = [];
        final rawCast = data['cast'] as List<dynamic>? ?? [];
        final photoBase = "https://image.tmdb.org/t/p/w185";
        for (final item in rawCast.take(6)) {
          final name = item['name']?.toString() ?? '';
          final path = item['profile_path']?.toString() ?? '';
          if (name.isNotEmpty) {
            parsedCast.add(CastMember(
              name: name,
              profileUrl: path.isNotEmpty ? (photoBase + path) : '',
            ));
          }
        }
        if (parsedCast.isNotEmpty) {
          cast = parsedCast;
        }

        final rawCrew = data['crew'] as List<dynamic>? ?? [];
        for (final item in rawCrew) {
          if (item['job']?.toString() == 'Director') {
            director = item['name']?.toString();
            final path = item['profile_path']?.toString() ?? '';
            if (path.isNotEmpty) {
              directorProfile = photoBase + path;
            }
            break;
          }
        }
      }

      if (detailsResponse.statusCode == 200) {
        final jsonString = utf8.decode(detailsResponse.bodyBytes);
        final data = json.decode(jsonString) as Map<String, dynamic>;
        final voteAverage = data['vote_average'];
        if (voteAverage != null) {
          rating = double.tryParse(voteAverage.toString());
        }
        final pop = data['popularity'];
        if (pop != null) {
          popularity = double.tryParse(pop.toString());
        }
      }

      if (mounted) {
        setState(() {
          _dynamicCast = cast;
          _dynamicDirector = director ?? movie.director;
          _directorProfileUrl = directorProfile ?? movie.directorPhoto;
          _dynamicRating = rating;
          _dynamicPopularity = popularity;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _dynamicCast = movie.castMembers;
          _dynamicDirector = movie.director;
          _directorProfileUrl = movie.directorPhoto;
          _dynamicRating = null;
          _dynamicPopularity = null;
        });
      }
    }
  }

  bool _isYoutubeUrl(String url) {
    return url.contains('youtube.com') || url.contains('youtu.be');
  }

  bool _isEmbedUrl(String url) {
    final lower = url.toLowerCase();
    if (_isYoutubeUrl(url)) return false;
    
    // If it has a direct video extension or standard HLS/stream segment pattern, it's not a generic web embed
    if (lower.contains('.m3u8') || 
        lower.contains('.mp4') || 
        lower.contains('.mpd') || 
        lower.contains('/hls/') || 
        lower.contains('/stream/') ||
        lower.contains('.mkv') ||
        lower.contains('.webm') ||
        lower.contains('.avi')) {
      return false;
    }
    
    // Otherwise, standard web URLs are treated as embeds needing resolution
    return url.startsWith('http://') || url.startsWith('https://');
  }

  bool _isStreamtapeSource(StreamSource source) {
    if (source.name.toLowerCase().contains('streamtape') || 
        source.name.toLowerCase().contains('strcloud')) {
      return true;
    }
    final id = _extractStreamtapeId(source.url, sourceName: source.name);
    return id != null;
  }

  bool _isYoutubeSource(StreamSource source) {
    if (source.name.toLowerCase() == 'youtube') return true;
    if (source.name.toLowerCase() == 'mp4/mkv' || 
        source.name.toLowerCase() == 'embed' || 
        _isStreamtapeSource(source)) return false;
    return _isYoutubeUrl(source.url);
  }

  bool _isMagnetSource(StreamSource source) {
    return source.url.toLowerCase().startsWith('magnet:') || 
           source.name.toLowerCase() == 'torrent (magnet)';
  }

  bool _isCustomMagnet(StreamSource source) {
    return movie.streamSources.any((s) => s.url == source.url && 
      (s.url.toLowerCase().startsWith('magnet:') || s.name.toLowerCase() == 'torrent (magnet)'));
  }

  bool _isEmbedSource(StreamSource source) {
    if (source.name.toLowerCase().startsWith('stravo:')) {
      return false;
    }
    if (_isStreamtapeSource(source)) return false;
    if (source.name.toLowerCase() == 'embed') return true;
    if (source.name.toLowerCase() == 'mp4/mkv' || 
        source.name.toLowerCase() == 'youtube' || 
        source.name.toLowerCase().contains('vidlink') ||
        _isMagnetSource(source)) {
      return false;
    }
    return _isEmbedUrl(source.url);
  }

  void _play(String source, {bool resumeDirectly = false, Map<String, String>? headers, String? originalEmbedUrl}) async {
    final List<String> parts = [];
    if (movie.year != null) parts.add(movie.year.toString());
    if (movie.runtime != null) parts.add(movie.runtime!);
    final subtitle = parts.isNotEmpty ? parts.join(' • ') : null;

    final failed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VideoPlayerScreen(
          videoSource: source,
          title: movie.title,
          subtitle: subtitle,
          movieId: movie.id,
          imdbId: movie.imdbId,
          resumeDirectly: resumeDirectly,
          headers: headers,
        ),
      ),
    );

    _loadWatchProgress();

    if (failed == true && originalEmbedUrl != null && mounted) {
      final tryWeb = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Playback Failed',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Failed to play the video natively. Would you like to try the Web Player instead?',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentBright,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Try Web Player', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (tryWeb == true && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WebViewPlayerScreen(
              embedUrl: originalEmbedUrl,
              title: movie.title,
              backdropUrl: movie.displayBackdrop,
            ),
          ),
        );
      }
    }
  }

  List<StreamSource> _getEffectiveSources() {
    final originalSources = movie.streamSources;
    
    // 1. Identify Streamtape sources
    final streamtapeSources = originalSources.where((src) => 
      _isStreamtapeSource(src)
    ).toList();

    // 2. Identify YouTube sources
    final youtubeSources = originalSources.where((src) => 
      _isYoutubeSource(src)
    ).toList();

    // 3. Create VidLink source if ID is available
    StreamSource? vidlinkSource;
    final imdbId = movie.imdbId;
    final tmdbId = movie.tmdbId;
    final activeId = (imdbId != null && imdbId.isNotEmpty && imdbId != 'null')
        ? imdbId
        : ((tmdbId != null && tmdbId.isNotEmpty && tmdbId != '0' && tmdbId != 'null') ? tmdbId : null);

    if (activeId != null) {
      vidlinkSource = StreamSource(
        name: 'VidLink (Native Proxy)',
        url: 'https://movie-scraper-beige.vercel.app/api?id=$activeId',
      );
    }

    // 4. Identify Embed / Web player sources
    final embedSources = originalSources.where((src) => 
      _isEmbedSource(src)
    ).toList();

    // 5. Identify Custom Magnet sources
    final customMagnets = originalSources.where((src) => 
      _isMagnetSource(src)
    ).toList();

    // 6. Identify MP4/MKV sources (neither streamtape, youtube, vidlink, embed, nor magnet)
    final mp4Sources = originalSources.where((src) => 
      !_isStreamtapeSource(src) && 
      !_isYoutubeSource(src) && 
      !_isEmbedSource(src) &&
      !_isMagnetSource(src)
    ).toList();

    final List<StreamSource> result = [];
    result.addAll(mp4Sources);
    result.addAll(streamtapeSources);
    result.addAll(youtubeSources);
    if (vidlinkSource != null) {
      result.add(vidlinkSource);
    }
    final hasImdb = imdbId != null && imdbId.isNotEmpty && imdbId != 'null';
    if (hasImdb) {
      result.add(const StreamSource(
        name: 'Stravo Streams',
        url: 'stravo_placeholder',
      ));
    }
    if (_torrentioSources.isNotEmpty || customMagnets.isNotEmpty) {
      result.add(const StreamSource(
        name: 'Torrent Streams',
        url: 'torrent_placeholder',
      ));
    }
    result.addAll(embedSources);

    // Safeguard: Add any remaining source that might have been skipped
    for (final src in originalSources) {
      if (!mp4Sources.contains(src) && 
          !streamtapeSources.contains(src) && 
          !youtubeSources.contains(src) && 
          !embedSources.contains(src) &&
          !_isMagnetSource(src)) {
        result.add(src);
      }
    }

    return result;
  }

  String _sanitizeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final isAlist = uri.host.contains('koyeb.app') || 
                      uri.host.contains('alist') || 
                      url.contains('/Movies/Movies/');
      if (isAlist && 
          !uri.path.startsWith('/d/') && 
          !uri.path.startsWith('/api/')) {
        final newPath = '/d${uri.path}';
        return uri.replace(path: newPath).toString();
      }
      if (uri.host.contains('streamtape')) {
        return uri.replace(host: 'strcloud.club').toString();
      }
    } catch (_) {}
    return url;
  }

  static const String _streamtapeLogin = 'e4a49ef565d194df9617';
  static const String _streamtapeKey = 'aGYRRB932LSJRp';

  String? _extractStreamtapeId(String url, {String? sourceName}) {
    var match = RegExp(r'(?:streamtape\.[a-z]+|strcloud\.[a-z]+)/[ve]/([a-zA-Z0-9]+)').firstMatch(url);
    if (match != null) return match.group(1);
    
    final isNameStreamtape = sourceName != null && 
        (sourceName.toLowerCase().contains('streamtape') || sourceName.toLowerCase().contains('strcloud'));
    if (isNameStreamtape || url.toLowerCase().contains('streamtape') || url.toLowerCase().contains('strcloud')) {
      match = RegExp(r'/[ve]/([a-zA-Z0-9]+)').firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  Future<String?> _resolveStreamtape(String url, {String? sourceName}) async {
    final fileId = _extractStreamtapeId(url, sourceName: sourceName);
    if (fileId == null) return null;

    final apiDomains = [
      'api.strcloud.club',
      'api.streamtape.com',
      'api.streamtape.to',
      'api.streamtape.net'
    ];

    Future<http.Response> getWithRetry(String fetchUrl, {int maxAttempts = 3}) async {
      Object? lastError;
      for (int i = 0; i < maxAttempts; i++) {
        try {
          debugPrint('Streamtape resolve attempt ${i + 1} fetching...');
          final res = await http.get(
            Uri.parse(fetchUrl),
            headers: {
              'Connection': 'close',
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
          ).timeout(const Duration(seconds: 8));
          return res;
        } catch (e) {
          lastError = e;
          debugPrint('Streamtape resolve attempt ${i + 1} failed: $e');
          if (i < maxAttempts - 1) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }
      throw lastError ?? Exception('Request failed after $maxAttempts attempts');
    }

    for (final domain in apiDomains) {
      try {
        debugPrint('Attempting Streamtape resolve via $domain');
        // 1. Get download ticket client-side
        final ticketUrl = 'https://$domain/file/dlticket?file=$fileId&login=$_streamtapeLogin&key=$_streamtapeKey';
        final ticketRes = await getWithRetry(ticketUrl);
        if (ticketRes.statusCode != 200) {
          throw Exception('Failed to fetch ticket (HTTP ${ticketRes.statusCode})');
        }
        final ticketData = json.decode(ticketRes.body);
        if (ticketData['status'] != 200 || ticketData['result'] == null) {
          throw Exception(ticketData['msg'] ?? 'Error fetching ticket');
        }
        
        final ticket = ticketData['result']['ticket'];
        final waitTime = ticketData['result']['wait_time'] ?? 5;
        debugPrint('Ticket obtained: $ticket. Waiting $waitTime seconds...');
        
        // Wait for the required ticket wait time
        if (waitTime > 0) {
          await Future.delayed(Duration(seconds: waitTime));
        }
        
        // 2. Get direct download link client-side
        final dlUrl = 'https://$domain/file/dl?file=$fileId&ticket=$ticket';
        final dlRes = await getWithRetry(dlUrl);
        if (dlRes.statusCode != 200) {
          throw Exception('Failed to fetch download link (HTTP ${dlRes.statusCode})');
        }
        final dlData = json.decode(dlRes.body);
        if (dlData['status'] == 200 && dlData['result'] != null && dlData['result']['url'] != null) {
          final streamUrl = dlData['result']['url'] as String;
          debugPrint('Streamtape resolved successfully via $domain -> $streamUrl');
          return streamUrl;
        } else {
          throw Exception(dlData['msg'] ?? 'Failed to resolve download link');
        }
      } catch (e) {
        debugPrint('Streamtape resolution error via $domain: $e');
      }
    }
    return null;
  }

  Future<void> _playWithResolution(String source, {
    bool resumeDirectly = false, 
    String? sourceName,
    bool forceNative = false,
    bool forceWeb = false,
  }) async {
    source = _sanitizeUrl(source);
    
    if (source.startsWith('magnet:')) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WebViewPlayerScreen(
              embedUrl: source,
              title: movie.title,
              backdropUrl: movie.displayBackdrop,
            ),
          ),
        );
      }
      return;
    }
    
    // Intercept Stalker VOD sources to resolve their links client-side
    final isStalkerVod = sourceName != null && sourceName.toLowerCase() == 'stalker vod';
    if (isStalkerVod) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Center(
            child: CircularProgressIndicator(color: AppColors.accentBright),
          );
        },
      );
      
      try {
        final stalkerStream = await StalkerResolver.resolveStream(source, isLive: false);
        if (mounted) Navigator.of(context).pop(); // Dismiss progress
        
        _play(stalkerStream.url, resumeDirectly: resumeDirectly, headers: stalkerStream.headers);
      } catch (e) {
        if (mounted) Navigator.of(context).pop(); // Dismiss progress
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Stalker VOD resolution failed: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
      return;
    }

    // Intercept Streamtape or Strcloud links to resolve natively completely in-app
    final lowerSource = source.toLowerCase();
    final isStreamtape = lowerSource.contains('streamtape.com') || 
                         lowerSource.contains('strcloud.club') ||
                         (sourceName != null && (sourceName.toLowerCase().contains('streamtape') || sourceName.toLowerCase().contains('strcloud')));
    if (isStreamtape) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Center(
            child: CircularProgressIndicator(color: AppColors.accentBright),
          );
        },
      );
      
      try {
        final resolved = await _resolveStreamtape(source, sourceName: sourceName);
        if (mounted) Navigator.of(context).pop(); // Dismiss progress
        
        if (resolved != null && resolved.isNotEmpty) {
          _play(resolved, resumeDirectly: resumeDirectly);
        } else {
          throw Exception('Failed to resolve Streamtape direct URL. Please check your credentials.');
        }
      } catch (e) {
        if (mounted) Navigator.of(context).pop(); // Dismiss progress
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Streamtape resolution failed: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
      return;
    }

    final isScraper = source.contains('movie-scraper-beige.vercel.app') || 
                      source.contains('movie-scraper-j6k1jkfy1-kinguser98s-projects.vercel.app');
    if (isScraper) {
      final vidlinkTmdbId = (movie.tmdbId != null && movie.tmdbId!.isNotEmpty && movie.tmdbId != '0' && movie.tmdbId != 'null')
          ? movie.tmdbId
          : movie.imdbId;
      final targetEmbedUrl = 'https://vidlink.pro/movie/$vidlinkTmdbId';
      
      try {
        debugPrint('Resolving VidLink stream in background from: $targetEmbedUrl');
        final resolvedUrl = await EmbedResolver.resolve(context, targetEmbedUrl);
        
        if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
          final headers = {
            'Referer': 'https://vidlink.pro/',
            'Origin': 'https://vidlink.pro',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          };
          debugPrint('VidLink: Resolved stream natively: $resolvedUrl');
          _play(resolvedUrl, resumeDirectly: resumeDirectly, headers: headers, originalEmbedUrl: targetEmbedUrl);
        } else {
          throw Exception('Failed to resolve stream in background');
        }
      } catch (e) {
        debugPrint('VidLink native resolution failed: $e. Falling back to on-screen Web Player...');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('VidLink native resolver failed. Launching Web Player...'),
              duration: Duration(seconds: 3),
            ),
          );
          
          final fallbackEmbedUrl = 'https://vidlink.pro/movie/$vidlinkTmdbId';
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => WebViewPlayerScreen(
                embedUrl: fallbackEmbedUrl,
                title: movie.title,
                backdropUrl: movie.displayBackdrop,
              ),
            ),
          );
        }
      }
      return;
    }

    bool isYoutube = false;
    bool isEmbed = false;

    if (sourceName != null && sourceName.toLowerCase().startsWith('stravo:')) {
      isYoutube = false;
      isEmbed = false;
    } else if (sourceName != null && sourceName.isNotEmpty) {
      if (sourceName.toLowerCase() == 'youtube') {
        isYoutube = true;
      } else if (sourceName.toLowerCase() == 'embed') {
        isEmbed = true;
      } else if (sourceName.toLowerCase() == 'mp4/mkv') {
        isYoutube = false;
        isEmbed = false;
      } else {
        isYoutube = _isYoutubeUrl(source);
        isEmbed = _isEmbedUrl(source);
      }
    } else {
      isYoutube = _isYoutubeUrl(source);
      isEmbed = _isEmbedUrl(source);
    }

    if (isYoutube) {
      if (kIsWeb) {
        _play(source, resumeDirectly: resumeDirectly);
        return;
      }
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Center(
            child: CircularProgressIndicator(color: AppColors.accentBright),
          );
        },
      );
      
      try {
        final resolvedUrl = await YoutubeService.getStreamUrl(source);
        if (mounted) Navigator.of(context).pop(); // Dismiss progress
        
        if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
          _play(resolvedUrl, resumeDirectly: resumeDirectly);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not load YouTube stream. Please try again.')),
            );
          }
        }
      } catch (e) {
        if (mounted) Navigator.of(context).pop(); // Dismiss progress
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading YouTube stream: $e')),
          );
        }
      }
    } else if (isEmbed) {
      if (source.contains('streamimdb')) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => WebViewPlayerScreen(
                embedUrl: source,
                title: movie.title,
                isEmbedOnly: true,
                backdropUrl: movie.displayBackdrop,
              ),
            ),
          );
        }
        return;
      }
      // Attempt to resolve the direct stream link in background off-screen webview
      final resolvedUrl = await EmbedResolver.resolve(context, source);
      if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
        // Always provide VidSrc/VidsrcMe referer headers for resolved embeds to satisfy CDN host security
        final headers = EmbedResolver.getHeadersForUrl(resolvedUrl, fallbackHeaders: {
          'Referer': 'https://vidsrcme.ru/',
          'Origin': 'https://vidsrcme.ru',
        });
        _play(resolvedUrl, resumeDirectly: resumeDirectly, headers: headers, originalEmbedUrl: source);
      } else {
        // Fallback: Launch on-screen webview player which solves Turnstile, intercept the .m3u8 stream link,
        // pop the webview, and play natively in VideoPlayerScreen!
        if (mounted) {
          final interceptedUrl = await Navigator.of(context).push<String>(
            MaterialPageRoute<String>(
              builder: (_) => WebViewPlayerScreen(
                embedUrl: source,
                title: movie.title,
                backdropUrl: movie.displayBackdrop,
              ),
            ),
          );
          
          if (interceptedUrl != null && interceptedUrl.isNotEmpty) {
            final headers = EmbedResolver.getHeadersForUrl(interceptedUrl, fallbackHeaders: {
              'Referer': 'https://vidsrcme.ru/',
              'Origin': 'https://vidsrcme.ru',
            });
            _play(interceptedUrl, resumeDirectly: resumeDirectly, headers: headers, originalEmbedUrl: source);
          }
        }
      }
    } else {
      _play(source, resumeDirectly: resumeDirectly);
    }
  }

  void _showSourceSelector(List<StreamSource> sources, {bool resumeDirectly = false}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SELECT SERVER SOURCE',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sources.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final source = sources[index];
                      final isYoutube = _isYoutubeUrl(source.url);
                      final isTorrentPlaceholder = source.url == 'torrent_placeholder';
                      final isStravoPlaceholder = source.url == 'stravo_placeholder';
                      
                      final icon = isTorrentPlaceholder 
                          ? Icons.cloud_download_rounded 
                          : (isStravoPlaceholder ? Icons.cloud_queue_rounded : (isYoutube ? Icons.video_library_rounded : Icons.dns_rounded));
                      final subtitleText = isTorrentPlaceholder 
                          ? 'Extract movie torrent files and stream' 
                          : (isStravoPlaceholder ? 'Stream high speed sources via Stravo' : source.url);

                      return ListTile(
                        leading: Icon(
                          icon,
                          color: isYoutube ? Colors.redAccent : AppColors.accentBright,
                        ),
                        title: Text(
                          source.name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          subtitleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white30, fontSize: 11),
                        ),
                        tileColor: Colors.white.withValues(alpha: 0.03),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onTap: () {
                          Navigator.of(context).pop();
                          if (isTorrentPlaceholder) {
                            final customMagnets = movie.streamSources.where(_isMagnetSource).toList();
                            final allTorrents = [...customMagnets, ..._torrentioSources];
                            _showTorrentSourceSelector(allTorrents, resumeDirectly: resumeDirectly);
                          } else if (isStravoPlaceholder) {
                            _showStravoSourceSelector(context, resumeDirectly: resumeDirectly);
                          } else {
                            _playWithResolution(source.url, resumeDirectly: resumeDirectly, sourceName: source.name);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTorrentSourceSelector(List<StreamSource> torrentSources, {bool resumeDirectly = false}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SELECT TORRENT STREAM',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: torrentSources.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final source = torrentSources[index];
                      final isCustomMagnet = _isCustomMagnet(source);
                      return ListTile(
                        leading: Icon(
                          isCustomMagnet ? Icons.stars_rounded : Icons.cloud_circle_rounded,
                          color: isCustomMagnet ? Colors.amber : AppColors.accentBright,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                source.name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            if (isCustomMagnet) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 1),
                                ),
                                child: const Text(
                                  'DIRECT',
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Builder(
                          builder: (context) {
                            final String subtitleText;
                            if (isCustomMagnet) {
                              final dbSeeders = source.seeders;
                              final dbPeers = source.peers;
                              if (dbSeeders != null) {
                                subtitleText = '👤 Seeders: $dbSeeders  •  👥 Peers: $dbPeers';
                              } else {
                                final stats = _customMagnetStats[source.url];
                                if (stats != null) {
                                  subtitleText = '👤 Seeders: ${stats['seeders']}  •  👥 Peers: ${stats['peers']}';
                                } else {
                                  subtitleText = 'Loading peers info...';
                                }
                              }
                            } else {
                              subtitleText = source.url;
                            }
                            return Text(
                              subtitleText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCustomMagnet
                                    ? Colors.amber.withValues(alpha: 0.7)
                                    : Colors.white30,
                                fontSize: 11,
                              ),
                            );
                          },
                        ),
                        tileColor: isCustomMagnet 
                            ? Colors.amber.withValues(alpha: 0.06) 
                            : Colors.white.withValues(alpha: 0.03),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: isCustomMagnet 
                              ? BorderSide(color: Colors.amber.withValues(alpha: 0.3), width: 1.2) 
                              : BorderSide.none,
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          _playWithResolution(source.url, resumeDirectly: resumeDirectly, sourceName: source.name);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handlePlayPressed({bool resumeDirectly = false}) async {
    final picked = _pickedPath;
    if (picked != null) {
      _playWithResolution(picked, resumeDirectly: resumeDirectly);
      return;
    }

    final localPath = await DownloadManager.getLocalPath(movie.id);
    if (!mounted) return;
    if (localPath != null && (kIsWeb || await File(localPath).exists())) {
      if (!mounted) return;
      _play(localPath, resumeDirectly: resumeDirectly);
      return;
    }
    
    final sources = _getEffectiveSources();
    if (sources.length > 1) {
      _showSourceSelector(sources, resumeDirectly: resumeDirectly);
    } else if (sources.isNotEmpty) {
      if (sources.first.url == 'torrent_placeholder') {
        final customMagnets = movie.streamSources.where(_isMagnetSource).toList();
        final allTorrents = [...customMagnets, ..._torrentioSources];
        _showTorrentSourceSelector(allTorrents, resumeDirectly: resumeDirectly);
      } else {
        _playWithResolution(sources.first.url, resumeDirectly: resumeDirectly, sourceName: sources.first.name);
      }
    } else if (movie.videoSource != null && movie.videoSource!.isNotEmpty) {
      _playWithResolution(movie.videoSource!, resumeDirectly: resumeDirectly);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No stream sources available for this movie.')),
      );
    }
  }

  void _handleResumePressed() {
    _handlePlayPressed(resumeDirectly: true);
  }

  Widget _buildSecondaryOutlineButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    Color foregroundColor = Colors.white70,
    Color borderColor = Colors.white30,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: foregroundColor,
        side: BorderSide(color: borderColor, width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _startDirectMp4Download(String url) async {
    try {
      await DownloadManager.downloadMovie(movie, url);
      await _checkDownloadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${movie.title}" added to downloads queue.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start download: $e')),
        );
      }
    }
  }

  void _showDownloadSourceSelector(List<StreamSource> sources) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SELECT DOWNLOAD SOURCE',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sources.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final source = sources[index];
                      return ListTile(
                        leading: Icon(
                          Icons.download_rounded,
                          color: AppColors.accentBright,
                        ),
                        title: Text(
                          source.name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          source.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white30, fontSize: 11),
                        ),
                        tileColor: Colors.white.withValues(alpha: 0.03),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onTap: () {
                          Navigator.of(context).pop();
                          _downloadSource(source);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadSource(StreamSource source) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: CircularProgressIndicator(color: AppColors.accentBright),
        );
      },
    );

    String? resolvedUrl;
    Map<String, String>? headers;

    try {
      final url = _sanitizeUrl(source.url);
      if (_isStreamtapeSource(source)) {
        resolvedUrl = await _resolveStreamtape(url, sourceName: source.name);
      } else if (url.contains('movie-scraper-beige.vercel.app')) {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          resolvedUrl = data['url'] as String?;
          if (resolvedUrl != null) {
            headers = EmbedResolver.getHeadersForUrl(resolvedUrl, fallbackHeaders: {
              'Referer': 'https://vidlink.pro/',
              'Origin': 'https://vidlink.pro',
            });
          }
        } else {
          throw Exception('Server returned status code ${response.statusCode}');
        }
      } else {
        resolvedUrl = url;
      }

      if (mounted) Navigator.of(context).pop(); // Dismiss progress

      if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
        await DownloadManager.downloadMovie(movie, resolvedUrl, headers: headers);
        await _checkDownloadStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${movie.title}" added to downloads queue.')),
          );
        }
      } else {
        throw Exception('Could not resolve download link.');
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // Dismiss progress
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _startDownload() async {
    final downloadableSources = _getDownloadableSources();
    if (downloadableSources.length > 1) {
      _showDownloadSourceSelector(downloadableSources);
    } else if (downloadableSources.isNotEmpty) {
      _downloadSource(downloadableSources.first);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No downloadable sources available for this movie.')),
      );
    }
  }

  Future<void> _deleteDownload() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Download?',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text('Remove downloaded video from device storage?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DownloadManager.deleteTask(movie.id);
      await _checkDownloadStatus();
    }
  }

  Future<void> _watchTrailer() async {
    final trailer = movie.trailerUrl;
    if (trailer == null || trailer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No trailer available for this movie')),
      );
      return;
    }

    final lowerTrailer = trailer.toLowerCase();
    if (lowerTrailer.contains('youtube.com') || lowerTrailer.contains('youtu.be')) {
      // Direct YouTube webview playback in 720p HD quality
      String embedUrl = trailer;
      final regExp = RegExp(r'^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#\&\?]*)');
      final match = regExp.firstMatch(trailer);
      if (match != null && match.group(7) != null && match.group(7)!.length == 11) {
        embedUrl = 'https://www.youtube.com/embed/${match.group(7)}?vq=hd720&autoplay=1&origin=https://ott.redapp.space';
      }
      
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WebViewPlayerScreen(
              embedUrl: embedUrl,
              title: '${movie.title} - Trailer',
              backdropUrl: movie.displayBackdrop,
            ),
          ),
        );
      }
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: CircularProgressIndicator(color: AppColors.accentBright),
        );
      },
    );

    try {
      final streamUrl = await YoutubeService.getStreamUrl(trailer);
      if (mounted) Navigator.of(context).pop();

      if (streamUrl != null && streamUrl.isNotEmpty) {
        _play(streamUrl);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not load trailer stream. Please try again.')),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing trailer: $e')),
        );
      }
    }
  }

  Future<void> _pickLocalVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || path.isEmpty) return;
    setState(() => _pickedPath = path);
    _play(path);
  }

  void _shareMovie() {
    final text = 'Watch "${movie.title}" on GoXio.\n\nDescription: ${movie.description ?? ""}\nIMDb rating: ★${movie.rating.toStringAsFixed(1)}\n\nStream link: ${movie.videoSource ?? ""}';
    Share.share(text, subject: 'Check out ${movie.title}');
  }

  String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$min:$sec' : '$min:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final displayRating = _dynamicRating ?? movie.rating;
    final activeTheme = ThemeManager.currentTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. Immersive Backdrop Image with bottom fade (Visually enhanced)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 420,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Base layer: Sharp backdrop
                  MovieImage(source: movie.displayBackdrop, fit: BoxFit.cover),
                  // Overlay layer: Gradual bottom blur transition (sharp at the top, blurred at the bottom)
                  ShaderMask(
                    shaderCallback: (rect) {
                      return LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.1),
                          Colors.black.withValues(alpha: 0.7),
                          Colors.black,
                        ],
                        stops: const [0.0, 0.35, 0.75, 1.0],
                      ).createShader(rect);
                    },
                    blendMode: BlendMode.dstIn,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                      child: MovieImage(source: movie.displayBackdrop, fit: BoxFit.cover),
                    ),
                  ),
                  // Gradual bottom fade overlay to merge into page background
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.2),
                          Colors.transparent,
                          AppColors.background.withValues(alpha: 0.8),
                          AppColors.background,
                        ],
                        stops: const [0.0, 0.45, 0.8, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Main Scrollable details view
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 180),

                  // Movie Card Details Box
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Split details header: Poster on the left, Metadata on the right
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Poster Card with rounded corners and shadow
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // Glow Layer behind the poster (runs in hardware, works on Flutter Web)
                                Positioned(
                                  left: -20,
                                  right: -20,
                                  top: -20,
                                  bottom: -20,
                                  child: ImageFiltered(
                                    imageFilter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                                    child: Container(
                                      margin: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: (movie.posterColor ?? activeTheme.accentBright).withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                                // Sharp Poster Card with Gold Border
                                Container(
                                  width: 120,
                                  height: 180,
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.8), width: 1.5), // Gold Border
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black54,
                                        blurRadius: 10,
                                        offset: Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: MovieImage(
                                      source: movie.posterUrl,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            // Right Metadata Column (Redesigned)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Movie Title
                                  Text(
                                    movie.title,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  
                                  // Combined Meta tags (Year • Runtime • Genre • Content Rating)
                                  Builder(
                                    builder: (context) {
                                      final List<String> detailsParts = [];
                                      if (movie.year != null) detailsParts.add(movie.year.toString());
                                      if (movie.runtime != null) detailsParts.add(movie.runtime!);
                                      if (movie.genre.isNotEmpty) {
                                        detailsParts.add(movie.genre.split(',').first.trim());
                                      }
                                      return Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          Text(
                                            detailsParts.join(' • '),
                                            style: GoogleFonts.outfit(
                                              color: Colors.white60,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                          if (movie.contentRating != null && movie.contentRating!.isNotEmpty) ...[
                                            const Text('•', style: TextStyle(color: Colors.white60)),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                border: Border.all(color: Colors.white54, width: 0.8),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                movie.contentRating!,
                                                style: GoogleFonts.outfit(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    }
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Redesigned IMDb & TMDB Rating Badges side-by-side
                                  Row(
                                    children: [
                                      // IMDb Badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF5C518), // IMDb Gold
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star_rounded, color: Colors.black, size: 14),
                                            const SizedBox(width: 3),
                                            Text(
                                              movie.rating.toStringAsFixed(1),
                                              style: GoogleFonts.outfit(
                                                color: Colors.black,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(width: 0.8, height: 10, color: Colors.black26),
                                            const SizedBox(width: 4),
                                            Text(
                                              'IMDb',
                                              style: GoogleFonts.outfit(
                                                color: Colors.black,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // TMDB Badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF032541).withOpacity(0.6),
                                          border: Border.all(color: const Color(0xFF01B4E4), width: 1.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star_rounded, color: Color(0xFF01B4E4), size: 14),
                                            const SizedBox(width: 3),
                                            Text(
                                              (_dynamicRating ?? 6.5).toStringAsFixed(1),
                                              style: GoogleFonts.outfit(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(width: 0.8, height: 10, color: Colors.white24),
                                            const SizedBox(width: 4),
                                            Text(
                                              'TMDB',
                                              style: GoogleFonts.outfit(
                                                color: const Color(0xFF01B4E4),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Redesigned Popularity Metric
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.trending_up_rounded,
                                        color: Color(0xFFA855F7), // Purple trending icon
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Popularity: ${(_dynamicPopularity ?? ((movie.rating * 95) + (movie.title.hashCode % 150))).toStringAsFixed(0)}',
                                        style: GoogleFonts.outfit(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                           const SizedBox(height: 18),

                        // Row 1: Primary actions (Watch Now / Favorite)
                        Row(
                          children: [
                            // Watch Now
                            Expanded(
                              flex: 5,
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _handlePlayPressed,
                                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
                                  label: Text(
                                    'Watch Now',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Favorite
                            Expanded(
                              flex: 4,
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  border: Border.all(color: Colors.white24, width: 1.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _toggleFavorite,
                                  icon: Icon(
                                    _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                    color: _isFavorite ? Colors.redAccent : Colors.white70,
                                    size: 18,
                                  ),
                                  label: Text(
                                    'Favorite',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Row 2: Secondary horizontal actions grid (Trailer, Download, Watchlist, Share)
                        Row(
                          children: [
                            _buildActionButtonCard(
                              icon: Icons.movie_filter_rounded,
                              label: 'Trailer',
                              onTap: _watchTrailer,
                            ),
                            _buildActionButtonCard(
                              icon: _isDownloaded ? Icons.download_done_rounded : Icons.download_rounded,
                              label: _isDownloaded ? 'Downloaded' : 'Download',
                              onTap: _isDownloaded ? _deleteDownload : _startDownload,
                              activeColor: _isDownloaded ? Colors.redAccent : null,
                            ),
                            _buildActionButtonCard(
                              icon: _inWatchlist ? Icons.playlist_add_check_rounded : Icons.playlist_add_rounded,
                              label: 'Watchlist',
                              onTap: _toggleWatchlist,
                              activeColor: _inWatchlist ? activeTheme.accentBright : null,
                            ),
                            _buildActionButtonCard(
                              icon: Icons.share_rounded,
                              label: 'Share',
                              onTap: _shareMovie,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Synopsis / Description
                        Text(
                          'Synopsis',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          movie.description ?? 'Enjoy premium streaming of ${movie.title} in full HD quality.',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Director & Cast List
                        if (_dynamicDirector != null) ...[
                          Text(
                            'Director',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.surface,
                                backgroundImage: _directorProfileUrl != null && _directorProfileUrl!.isNotEmpty
                                    ? NetworkImage(_directorProfileUrl!)
                                    : null,
                                child: _directorProfileUrl == null || _directorProfileUrl!.isEmpty
                                    ? const Icon(Icons.person_rounded, color: Colors.white30)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _dynamicDirector!,
                                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Director',
                                    style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],

                        if (_dynamicCast.isNotEmpty) ...[
                          Text(
                            'Featured Cast',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 105,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _dynamicCast.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 14),
                              itemBuilder: (context, index) {
                                final actor = _dynamicCast[index];
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.white12, width: 0.8),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: actor.profileUrl.isNotEmpty
                                            ? MovieImage(source: actor.profileUrl, fit: BoxFit.cover)
                                            : const Icon(Icons.person_rounded, color: Colors.white30, size: 24),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        actor.name,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Bottom Redesigned Info Grid
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.02),
                            border: Border.all(color: Colors.white10, width: 0.8),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              _buildBottomGridItem(
                                icon: Icons.language_rounded,
                                title: 'Language',
                                value: movie.language ?? 'Hindi',
                              ),
                              _buildVerticalDivider(),
                              _buildBottomGridItem(
                                icon: Icons.volume_up_rounded,
                                title: 'Audio',
                                value: '5.1 Surround',
                              ),
                              _buildVerticalDivider(),
                              _buildBottomGridItem(
                                icon: Icons.closed_caption_rounded,
                                title: 'Subtitles',
                                value: 'English, Hindi',
                              ),
                              _buildVerticalDivider(),
                              _buildBottomGridItem(
                                icon: Icons.hd_rounded,
                                title: 'Quality',
                                value: '1080p • HD',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Floating Custom App Bar with transparent actions
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.of(context).padding.top + 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Back Button
                ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: Colors.black26,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ),
                // Share Button
                ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: Colors.black26,
                      child: IconButton(
                        icon: const Icon(Icons.share_rounded, color: Colors.white, size: 18),
                        onPressed: _shareMovie,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtonCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? activeColor,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white10, width: 0.8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: activeColor ?? Colors.white, size: 20),
              const SizedBox(height: 6),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: activeColor ?? Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomGridItem({required IconData icon, required String title, required String value}) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF3B82F6), size: 20),
          const SizedBox(height: 6),
          Text(
            title,
            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: const Color(0xFFFFB300),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 0.8,
      height: 40,
      color: Colors.white10,
    );
  }

  Widget _buildMetaBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white60,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
