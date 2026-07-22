import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/screens/video_player_screen.dart';
import 'package:private_cinema_mobile/screens/webview_player_screen.dart';
import 'package:private_cinema_mobile/screens/cast_controller_screen.dart';
import 'package:private_cinema_mobile/data/stalker_resolver.dart';
import 'package:private_cinema_mobile/data/netmirror_resolver.dart';
import 'package:private_cinema_mobile/data/cinemm_resolver.dart';
import 'package:private_cinema_mobile/data/api_service.dart';
import 'package:private_cinema_mobile/data/embed_resolver.dart';
import 'package:private_cinema_mobile/data/wifi_cast_service.dart';
import 'package:private_cinema_mobile/data/sync_service.dart';
import 'package:private_cinema_mobile/data/webview_scraper_executor.dart';
import 'package:private_cinema_mobile/data/stremio_addon_resolver.dart';
import 'package:private_cinema_mobile/data/hls_preflight.dart';
import 'package:private_cinema_mobile/widgets/resolving_dialog.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:io';

class SpecialSearchDialog extends StatefulWidget {
  final bool isSeriesSearch;
  const SpecialSearchDialog({super.key, this.isSeriesSearch = false});

  @override
  State<SpecialSearchDialog> createState() => _SpecialSearchDialogState();
}

class _SpecialSearchDialogState extends State<SpecialSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  bool _searching = false;
  List<dynamic> _searchResults = [];

  // Detail selection state
  dynamic _selectedMovie;
  bool _loadingDetails = false;
  String? _imdbId;

  // Stream resolution states
  bool _resolvingStreams = false;
  List<StreamSourceInfo> _resolvedSources = [];
  StreamSourceType? _activeGroupType; // server grouping selection
  String? _selectedAddonSubGroup;
  int _maxSourceSizeMb = 0;
  List<String> _sourceOrder = [];

  // Series state and dynamic episode loaders
  bool _isSeriesSearch = false;
  bool _selectingEpisode = false;
  List<dynamic> _seasons = [];
  List<dynamic> _episodes = [];
  int _selectedSeasonNumber = 1;
  bool _loadingSeasons = false;
  bool _loadingEpisodes = false;
  dynamic _selectedEpisodeData;

  // Source visibility flags
  bool _showVidlink = true;
  bool _showNetmirror = true;
  bool _showStravo = true;
  bool _showStalker = true;
  bool _showCinemm = true;
  bool _showCastle = true;
  bool _showTorrent = true;
  bool _showStremioAddon = true;
  bool _showFilmu = true;
  String? _selectedStremioResolution;
  List<String> _blockedAddonGroups = [];

  Future<void> _loadSourceVisibilitySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final cloud = await SyncService.fetchAppSettings();
    if (mounted) {
      setState(() {
        _sourceOrder = ['vidlink','netmirror','cinemm','stalker','stravo','castle','torrent','stremioAddon','filmu'];
        _showVidlink = cloud.containsKey('source_show_vidlink') ? cloud['source_show_vidlink'] == 'true' : (prefs.getBool('source_show_vidlink') ?? true);
        _showNetmirror = cloud.containsKey('source_show_netmirror') ? cloud['source_show_netmirror'] == 'true' : (prefs.getBool('source_show_netmirror') ?? true);
        _showStravo = cloud.containsKey('source_show_stravo') ? cloud['source_show_stravo'] == 'true' : (prefs.getBool('source_show_stravo') ?? true);
        _showStalker = cloud.containsKey('source_show_stalker') ? cloud['source_show_stalker'] == 'true' : (prefs.getBool('source_show_stalker') ?? true);
        _showCinemm = cloud.containsKey('source_show_cinemm') ? cloud['source_show_cinemm'] == 'true' : (prefs.getBool('source_show_cinemm') ?? true);
        _showCastle = cloud.containsKey('source_show_castle') ? cloud['source_show_castle'] == 'true' : (prefs.getBool('source_show_castle') ?? true);
        _showTorrent = cloud.containsKey('source_show_torrent') ? cloud['source_show_torrent'] == 'true' : (prefs.getBool('source_show_torrent') ?? true);
        _showStremioAddon = cloud.containsKey('source_show_stremioAddon') ? cloud['source_show_stremioAddon'] == 'true' : (prefs.getBool('source_show_stremioAddon') ?? true);
        _maxSourceSizeMb = int.tryParse(cloud['max_source_size_mb'] ?? '') ?? (prefs.getInt('max_source_size_mb') ?? 0);
        
        final blockedRaw = cloud['blocked_addon_groups'] ?? '';
        _blockedAddonGroups = blockedRaw
            .split(RegExp(r'[,\n]'))
            .map((s) => s.trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toList();
      });
    }
    // Load source order from cloud
    final order = await SyncService.fetchSourceOrder();
    if (order.isNotEmpty && mounted) {
      final List<String> mergedOrder = List<String>.from(order);
      if (!mergedOrder.contains('filmu')) mergedOrder.add('filmu');
      setState(() => _sourceOrder = mergedOrder);
    }
  }

  @override
  void initState() {
    super.initState();
    _isSeriesSearch = widget.isSeriesSearch;
    _loadSourceVisibilitySettings();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performLiveSearch(query.trim());
    });
  }

  Future<void> _performLiveSearch(String query) async {
    setState(() {
      _searching = true;
      _selectedMovie = null;
      _activeGroupType = null;
      _selectedAddonSubGroup = null;
      _selectingEpisode = false;
    });

    try {
      const apiKey = '3a73619bbb8fc6d47742d1b5b2b707b5';
      final path = _isSeriesSearch ? 'search/tv' : 'search/movie';
      final targetUrl =
          'https://api.themoviedb.org/3/$path?api_key=$apiKey&query=${Uri.encodeComponent(query)}';
      final proxyUrl =
          'https://movie-scraper-beige.vercel.app/api?url=${Uri.encodeComponent(targetUrl)}';

      debugPrint('TMDB Search via Proxy: $proxyUrl');
      final response = await http
          .get(Uri.parse(proxyUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List<dynamic>? ?? [];
        if (mounted) {
          setState(() {
            _searchResults = results;
            _searching = false;
          });
        }
      } else {
        throw Exception('TMDB error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Live Search failed: $e');
      if (mounted) {
        setState(() {
          _searching = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _fetchSeasons(String tmdbId) async {
    if (!mounted) return;
    setState(() {
      _loadingSeasons = true;
      _seasons = [];
      _episodes = [];
      _imdbId = null;
    });

    const apiKey = '3a73619bbb8fc6d47742d1b5b2b707b5';
    try {
      final url = 'https://api.themoviedb.org/3/tv/$tmdbId?api_key=$apiKey';
      final proxyUrl = 'https://movie-scraper-beige.vercel.app/api?url=${Uri.encodeComponent(url)}';
      final res = await http.get(Uri.parse(proxyUrl)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final details = json.decode(res.body);
        final rawSeasons = details['seasons'] as List<dynamic>? ?? [];
        final validSeasons = rawSeasons.where((s) {
          final num = s['season_number'] as int? ?? -1;
          final count = s['episode_count'] as int? ?? 0;
          return num > 0 && count > 0;
        }).toList();

        if (mounted) {
          setState(() {
            _seasons = validSeasons;
            if (_seasons.isNotEmpty) {
              _selectedSeasonNumber = _seasons.first['season_number'] as int? ?? 1;
            }
          });
        }
      }

      final extUrl = 'https://api.themoviedb.org/3/tv/$tmdbId/external_ids?api_key=$apiKey';
      final extProxy = 'https://movie-scraper-beige.vercel.app/api?url=${Uri.encodeComponent(extUrl)}';
      final extRes = await http.get(Uri.parse(extProxy)).timeout(const Duration(seconds: 8));
      if (extRes.statusCode == 200) {
        final extData = json.decode(extRes.body);
        final rawImdb = extData['imdb_id']?.toString() ?? '';
        if (mounted) {
          setState(() {
            _imdbId = rawImdb.isNotEmpty && rawImdb != 'null' ? rawImdb : null;
          });
        }
      }

      if (_seasons.isNotEmpty) {
        await _fetchEpisodesForSeason(tmdbId, _selectedSeasonNumber);
      }
    } catch (e) {
      debugPrint('Failed to load seasons: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingSeasons = false;
        });
      }
    }
  }

  Future<void> _fetchEpisodesForSeason(String tmdbId, int seasonNumber) async {
    if (!mounted) return;
    setState(() {
      _loadingEpisodes = true;
      _episodes = [];
    });

    const apiKey = '3a73619bbb8fc6d47742d1b5b2b707b5';
    try {
      final url = 'https://api.themoviedb.org/3/tv/$tmdbId/season/$seasonNumber?api_key=$apiKey';
      final proxyUrl = 'https://movie-scraper-beige.vercel.app/api?url=${Uri.encodeComponent(url)}';
      final res = await http.get(Uri.parse(proxyUrl)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final details = json.decode(res.body);
        final list = details['episodes'] as List<dynamic>? ?? [];
        if (mounted) {
          setState(() {
            _episodes = list;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to load episodes: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingEpisodes = false;
        });
      }
    }
  }

  Future<void> _onMovieSelected(dynamic movieData) async {
    final tmdbId = movieData['id']?.toString();
    if (tmdbId == null) return;

    if (_isSeriesSearch) {
      setState(() {
        _selectedMovie = movieData;
        _selectingEpisode = true;
      });
      _fetchSeasons(tmdbId);
    } else {
      setState(() {
        _selectedMovie = movieData;
        _loadingDetails = true;
        _imdbId = null;
        _resolvedSources = [];
        _resolvingStreams = false;
        _activeGroupType = null;
        _selectedAddonSubGroup = null;
        _selectingEpisode = false;
      });

      try {
        const apiKey = '3a73619bbb8fc6d47742d1b5b2b707b5';
        final detailsPath = 'movie/$tmdbId';
        final targetUrl = 'https://api.themoviedb.org/3/$detailsPath?api_key=$apiKey';
        final proxyUrl = 'https://movie-scraper-beige.vercel.app/api?url=${Uri.encodeComponent(targetUrl)}';

        final detailsResponse = await http
            .get(Uri.parse(proxyUrl))
            .timeout(const Duration(seconds: 10));

        String? resolvedImdb;
        if (detailsResponse.statusCode == 200) {
          final details = json.decode(detailsResponse.body);
          final rawImdb = details['imdb_id']?.toString() ?? '';
          resolvedImdb = rawImdb.isNotEmpty && rawImdb != 'null' ? rawImdb : null;
        }

        if (resolvedImdb == null) {
          try {
            final extUrl = 'https://api.themoviedb.org/3/movie/$tmdbId/external_ids?api_key=$apiKey';
            final extProxy = 'https://movie-scraper-beige.vercel.app/api?url=${Uri.encodeComponent(extUrl)}';
            final extRes = await http.get(Uri.parse(extProxy)).timeout(const Duration(seconds: 8));
            if (extRes.statusCode == 200) {
              final extData = json.decode(extRes.body);
              final rawExt = extData['imdb_id']?.toString() ?? '';
              if (rawExt.isNotEmpty && rawExt != 'null') {
                resolvedImdb = rawExt;
              }
            }
          } catch (_) {}
        }

        if (mounted) {
          setState(() {
            _imdbId = resolvedImdb;
            _loadingDetails = false;
          });
          _resolveMovieStreams(
            tmdbId,
            _imdbId,
            movieData['title']?.toString() ?? 'Movie',
          );
        }
      } catch (e) {
        debugPrint('Failed fetching movie external IDs: $e');
        if (mounted) {
          setState(() => _loadingDetails = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed loading details.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _resolveMovieStreams(
    String tmdbId,
    String? imdbId,
    String title, {
    int? season,
    int? episode,
  }) async {
    setState(() {
      _resolvingStreams = true;
      _resolvedSources = [];
    });

    try {
      final List<Future<void>> tasks = [];

      // 1. Resolve VidLink
      if (_showVidlink) {
        final activeId = (imdbId != null && imdbId.isNotEmpty) ? imdbId : tmdbId;
        tasks.add(_resolveVidLink(activeId, season: season, episode: episode));
      }

      if (imdbId != null && imdbId.isNotEmpty) {
        // 2. Resolve Stravo
        if (_showStravo) {
          tasks.add(_resolveStravo(imdbId, season: season, episode: episode));
        }
        // 3. Resolve Torrentio
        if (_showTorrent) {
          tasks.add(_resolveTorrentio(imdbId, title, season: season, episode: episode));
        }
        // Resolve synced custom Stremio addons
        if (_showStremioAddon) {
          tasks.add(_resolveStremioAddons(imdbId, season: season, episode: episode));
        }
      } else {
        // Penguplay fallback: call Stremio addons with TMDB ID when IMDB is unavailable
        if (_showStremioAddon) {
          tasks.add(_resolveStremioAddons('tmdb:$tmdbId', season: season, episode: episode));
        }
      }

      // For netmirror query title, append SXXEXX if series
      String queryTitle = title;
      if (_isSeriesSearch && season != null && episode != null) {
        queryTitle = "$title S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}";
      }

      // 4. Resolve Stalker
      if (_showStalker) {
        tasks.add(_resolveStalkerVodDatabase(queryTitle));
      }

      // 5. Resolve NetMirror
      if (_showNetmirror) {
        tasks.add(_resolveNetmirror(queryTitle));
      }

      // 6. Resolve CineMM - movies only
      if (_showCinemm && !_isSeriesSearch) {
        final year =
            _selectedMovie?['release_date']?.toString().split('-').first ?? '';
        tasks.add(_resolveCinemm(title, year));
      }

      // 7. Resolve Castle - movies only
      if (_showCastle && !_isSeriesSearch && tmdbId != null && tmdbId.isNotEmpty) {
        tasks.add(_resolveExtraScraper('castle', tmdbId));
      }

      // Resolve Nuveo Addons
      tasks.add(_resolveNuveoAddons(tmdbId, season: season, episode: episode));

      // Resolve FilmU API Scraper
      tasks.add(_resolveFilmuScraper(tmdbId, title, season: season, episode: episode));

      // 8. Add VidSrc.to Auto-Resolving Stream (requires TMDB ID)
      if (tmdbId != null && tmdbId.isNotEmpty) {
        final vidsrcUrl = _isSeriesSearch && season != null && episode != null
            ? 'https://vidsrc.to/embed/tv/$tmdbId/$season/$episode'
            : 'https://vidsrc.to/embed/movie/$tmdbId';
        _resolvedSources.add(
          StreamSourceInfo(
            name: 'VidSrc.to Server (Direct Native Play)',
            url: vidsrcUrl,
            type: StreamSourceType.vidsrc,
          ),
        );
      }

      // No Superembed and FilmU
      await Future.wait(tasks);
    } catch (e) {
      debugPrint('Error during _resolveMovieStreams: $e');
    } finally {
      if (mounted) {
        setState(() {
          _resolvingStreams = false;
        });
      }
    }
  }



  Future<void> _resolveVidLink(String activeId, {int? season, int? episode}) async {
    try {
      String url = 'https://movie-scraper-beige.vercel.app/api?id=$activeId';
      if (season != null && episode != null) {
        url += '&s=$season&e=$episode';
      }
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rawUrl = data['url'] as String?;
        if (rawUrl != null && rawUrl.isNotEmpty) {
          if (mounted) {
            setState(() {
              _resolvedSources.add(
                StreamSourceInfo(
                  name: 'VidLink (Native Proxy)',
                  url: rawUrl,
                  type: StreamSourceType.vidlink,
                ),
              );
            });
          }
        }
      }
    } catch (e) {
      debugPrint('VidLink stream resolution failed: $e');
    }
  }

  Future<void> _resolveStalkerVodDatabase(String title) async {
    try {
      final url =
          '${ApiService.apiUrl}?action=get_stalker_vod_movies&search=${Uri.encodeComponent(title)}';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        var movies = data['movies'] as List<dynamic>? ?? [];

        if (movies.isEmpty && title.isNotEmpty) {
          try {
            const fallbackUrl = '${ApiService.apiUrl}?action=get_stalker_vod_movies&category=General&page=1';
            final fallRes = await http.get(Uri.parse(fallbackUrl)).timeout(const Duration(seconds: 8));
            if (fallRes.statusCode == 200) {
              final fallData = json.decode(utf8.decode(fallRes.bodyBytes));
              final fallMovies = fallData['movies'] as List<dynamic>? ?? [];
              if (fallMovies.isNotEmpty) {
                movies = fallMovies;
              }
            }
          } catch (_) {}
        }

        final List<StreamSourceInfo> sources = [];

        for (final item in movies) {
          final rawPortalId = item['portal_id'];
          final portalId = rawPortalId != null 
              ? (int.tryParse(rawPortalId.toString()) ?? 1) 
              : 1;
          final cmd = item['cmd']?.toString() ?? '';
          final name = item['name']?.toString() ?? 'Stalker VOD';
          final rawPortalName = item['portal_name']?.toString() ?? '';
          final portalName = rawPortalName.isNotEmpty ? rawPortalName : (rawPortalId != null ? 'Portal $portalId' : 'Stalker');

          if (cmd.isNotEmpty) {
            final isDup =
                _resolvedSources.any(
                  (s) => s.url == 'stalker://$portalId$cmd',
                ) ||
                sources.any((s) => s.url == 'stalker://$portalId$cmd');
            if (!isDup) {
              sources.add(
                StreamSourceInfo(
                  name: '$portalName - $name',
                  url: 'stalker://$portalId$cmd',
                  type: StreamSourceType.stalker,
                ),
              );
            }
          }
        }
        if (mounted && sources.isNotEmpty) {
          setState(() {
            _resolvedSources.addAll(sources);
          });
        }
      }
    } catch (e) {
      debugPrint('Stalker VOD database search failed: $e');
    }
  }

  Future<void> _resolveNetmirror(String title) async {
    try {
      debugPrint('NetMirror Scraper: Resolving streams for $title...');
      final streams = await NetmirrorResolver.resolveStreams(title);
      if (mounted && streams.isNotEmpty) {
        setState(() {
          _resolvedSources.addAll(streams);
        });
      }
    } catch (e) {
      debugPrint('NetMirror resolution failed: $e');
    }
  }

  Future<void> _resolveCinemm(String title, String year) async {
    try {
      debugPrint('CineMM Scraper: Resolving streams for $title...');
      final streams = await CinemmResolver.resolveStreams(
        title: title,
        year: year.isNotEmpty ? year : null,
      );
      if (mounted && streams.isNotEmpty) {
        setState(() {
          _resolvedSources.addAll(streams);
        });
      }
    } catch (e) {
      debugPrint('CineMM resolution failed: $e');
    }
  }

  Future<void> _resolveExtraScraper(String providerName, String tmdbId) async {
    try {
      debugPrint(
        'WebViewScraperExecutor: Resolving streams for $providerName (TMDB: $tmdbId)...',
      );
      final streams = await WebViewScraperExecutor.runScraper(
        providerName,
        tmdbId,
        'movie',
      );
      if (mounted && streams.isNotEmpty) {
        setState(() {
          _resolvedSources.addAll(streams);
        });
      }
    } catch (e) {
      debugPrint('WebViewScraperExecutor: $providerName failed: $e');
    }
  }

  Future<void> _resolveStravo(String imdbId, {int? season, int? episode}) async {
    try {
      final addonBaseUrl = await SyncService.getStravoUrl();
      var baseUrl = addonBaseUrl.trim();
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      final url = (season != null && episode != null)
          ? '$baseUrl/stream/series/$imdbId:$season:$episode.json'
          : '$baseUrl/stream/movie/$imdbId.json';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json, text/plain, */*',
          'Origin': 'https://app.strem.io',
          'Referer': 'https://app.strem.io/',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final streamsList = data['streams'] as List<dynamic>? ?? [];
        final List<StreamSourceInfo> sources = [];

        for (final stream in streamsList) {
          final urlStr = stream['url']?.toString() ?? '';
          if (urlStr.isNotEmpty) {
            final name = stream['name']?.toString() ?? '';
            final title = stream['title']?.toString() ?? '';
            final displayTitle = title.isNotEmpty
                ? (name.isNotEmpty ? '$title ($name)' : title)
                : (name.isNotEmpty ? name : 'Stravo Stream');

            final cleanName = displayTitle.replaceAll('\n', ' ').trim();

            Map<String, String>? headers;
            if (stream['behaviorHints'] is Map &&
                stream['behaviorHints']['proxyHeaders'] is Map &&
                stream['behaviorHints']['proxyHeaders']['request'] is Map) {
              final reqHeaders = stream['behaviorHints']['proxyHeaders']['request'] as Map;
              headers = reqHeaders.map((k, v) => MapEntry(k.toString(), v.toString()));
            }
            if (headers == null) {
              headers = {
                'Referer': 'https://lok-lok.cc/',
                'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',
              };
            }

            final isDup =
                _resolvedSources.any((s) => s.url == urlStr) ||
                sources.any((s) => s.url == urlStr);
            if (!isDup) {
              sources.add(
                StreamSourceInfo(
                  name: 'Stravo: $cleanName',
                  url: urlStr,
                  type: StreamSourceType.stravo,
                  headers: headers,
                ),
              );
            }
          }
        }
        if (mounted) {
          setState(() {
            _resolvedSources.addAll(sources);
          });
        }
      }
    } catch (e) {
      debugPrint('Stravo streams resolution failed: $e');
    }
  }

  Future<void> _resolveTorrentio(String imdbId, String title, {int? season, int? episode}) async {
    try {
      final addonBaseUrl = await SyncService.getTorrentioUrl();
      var baseUrl = addonBaseUrl.trim();
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      final url = (season != null && episode != null)
          ? '$baseUrl/providers=yts,eztv,rarbg,1337x,torrent9,kickasstorrents|limit=5/stream/series/$imdbId:$season:$episode.json'
          : '$baseUrl/providers=yts,eztv,rarbg,1337x,torrent9,kickasstorrents|limit=5/stream/movie/$imdbId.json';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final streamsList = data['streams'] as List<dynamic>? ?? [];
        final List<StreamSourceInfo> sources = [];

        for (final stream in streamsList) {
          final infoHash = stream['infoHash']?.toString() ?? '';
          final directUrl = stream['url']?.toString() ?? '';
          final streamTitle = stream['title']?.toString() ?? 'Stream';
          final streamName = stream['name']?.toString() ?? 'Stremio';

          if (directUrl.isNotEmpty) {
            final titleLines = streamTitle.split('\n');
            final mainTitle = titleLines.isNotEmpty
                ? titleLines[0]
                : 'Direct Stream';
            final peerInfo = titleLines.length > 1 ? titleLines[1] : '';
            final sizeInfo = titleLines.length > 2 ? titleLines[2] : '';

            var sourceName = '$streamName: $mainTitle';
            if (peerInfo.isNotEmpty || sizeInfo.isNotEmpty) {
              sourceName +=
                  ' ($peerInfo ${sizeInfo.isNotEmpty ? "• $sizeInfo" : ""})';
            }
            sourceName = sourceName.replaceAll('\n', ' ').trim();

            // Extract custom request headers if defined by the addon
            final Map<String, String> headers = {};
            if (stream['behaviorHints']?['requestHeaders'] is Map) {
              (stream['behaviorHints']['requestHeaders'] as Map).forEach((
                k,
                v,
              ) {
                headers[k.toString()] = v.toString();
              });
            }

            var finalUrl = directUrl;
            if (headers.isNotEmpty) {
              finalUrl = Uri.parse(directUrl)
                  .replace(
                    queryParameters: {
                      ...Uri.parse(directUrl).queryParameters,
                      'headers': jsonEncode(headers),
                    },
                  )
                  .toString();
            }

            final isDup =
                _resolvedSources.any((s) => s.url == finalUrl) ||
                sources.any((s) => s.url == finalUrl);
            if (!isDup) {
              sources.add(
                StreamSourceInfo(
                  name: sourceName,
                  url: finalUrl,
                  type: StreamSourceType.torrent,
                ),
              );
            }
          } else if (infoHash.isNotEmpty) {
            final trackers = [
              'udp://tracker.coppersurfer.tk:6969/announce',
              'udp://tracker.openbittorrent.com:6969/announce',
              'udp://tracker.opentrackr.org:1337/announce',
              'udp://tracker.leechers-paradise.org:6969/announce',
              'udp://open.stealth.si:80/announce',
            ];
            final trackersQuery = trackers
                .map((t) => 'tr=${Uri.encodeComponent(t)}')
                .join('&');
            final magnetLink =
                'magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(title)}&$trackersQuery';

            final titleLines = streamTitle.split('\n');
            final mainTitle = titleLines.isNotEmpty ? titleLines[0] : 'Torrent';
            final peerInfo = titleLines.length > 1 ? titleLines[1] : '';
            final sizeInfo = titleLines.length > 2 ? titleLines[2] : '';

            var sourceName = mainTitle;
            if (peerInfo.isNotEmpty || sizeInfo.isNotEmpty) {
              sourceName +=
                  ' ($peerInfo ${sizeInfo.isNotEmpty ? "• $sizeInfo" : ""})';
            }
            sourceName = sourceName
                .replaceAll('👥', ' Peers:')
                .replaceAll('👤', ' Seeders:')
                .replaceAll('\n', ' ')
                .trim();

            final isDup =
                _resolvedSources.any((s) => s.url == magnetLink) ||
                sources.any((s) => s.url == magnetLink);
            if (!isDup) {
              sources.add(
                StreamSourceInfo(
                  name: 'Torrent: $sourceName',
                  url: magnetLink,
                  type: StreamSourceType.torrent,
                ),
              );
            }
          }
        }
        if (mounted) {
          setState(() {
            _resolvedSources.addAll(sources);
          });
        }
      }
    } catch (e) {
      debugPrint('Torrentio streams resolution failed: $e');
    }
  }

  Future<void> _resolveStremioAddons(String imdbId, {int? season, int? episode}) async {
    try {
      final List<String> addonUrls = await SyncService.fetchMergedStremioAddons();
      if (addonUrls.isEmpty) return;

      final List<StreamSourceInfo> sources = [];
      final List<Future<List<StremioStream>>> tasks = [];
      final typeStr = _isSeriesSearch ? 'series' : 'movie';
      
      for (final addonUrl in addonUrls) {
        tasks.add(StremioAddonResolver.fetchStreams(
          manifestUrl: addonUrl,
          type: typeStr,
          imdbId: imdbId,
          season: season,
          episode: episode,
        ));
      }

      final results = await Future.wait(tasks);
      for (final list in results) {
        for (final item in list) {
          final addonName = (item.addonName ?? '').trim().toLowerCase();
          if (_blockedAddonGroups.any((b) => addonName == b || addonName.contains(b))) {
            continue;
          }
          final isDup = _resolvedSources.any((s) => s.url == item.url) ||
                        sources.any((s) => s.url == item.url);
          if (!isDup) {
            sources.add(StreamSourceInfo(
              name: '${item.name} (${item.title})',
              url: item.url,
              type: StreamSourceType.stremioAddon,
              headers: item.headers,
              addonName: item.addonName,
              originalTitle: item.title,
              quality: item.quality,
              languages: item.languages,
              size: item.size,
            ));
          }
        }
      }

      if (mounted && sources.isNotEmpty) {
        setState(() {
          _resolvedSources.addAll(sources);
        });
      }
    } catch (e) {
      debugPrint('Error resolving Stremio Addons: $e');
    }
  }

  Future<void> _resolveNuveoAddons(
    String tmdbId, {
    int? season,
    int? episode,
  }) async {
    try {
      final List<Map<String, dynamic>> addons = await SyncService.fetchMergedNuveoAddons();
      if (addons.isEmpty) return;

      final List<StreamSourceInfo> sources = [];
      final List<Future<List<StreamSourceInfo>>> tasks = [];
      final mediaType = _isSeriesSearch ? 'series' : 'movie';

      for (final addon in addons) {
        final scrapers = addon['scrapers'] as List<dynamic>? ?? [];
        for (final scraper in scrapers) {
          final isEnabled = scraper['enabled'] == true;
          if (!isEnabled) continue;

          final scraperId = scraper['id']?.toString() ?? '';
          final scraperName = scraper['name']?.toString() ?? 'Scraper';
          final filename = scraper['filename']?.toString() ?? '';
          if (filename.isEmpty) continue;

          final manifestUrl = addon['url']?.toString() ?? '';
          if (manifestUrl.isEmpty) continue;

          String scriptUrl = '';
          try {
            final manifestUri = Uri.parse(manifestUrl);
            scriptUrl = manifestUri.resolve(filename).toString();
          } catch (e) {
            debugPrint('Failed to resolve scraper script URL: $e');
            continue;
          }

          tasks.add(WebViewScraperExecutor.runDynamicScraper(
            scraperId: scraperId,
            scraperName: scraperName,
            scriptUrl: scriptUrl,
            tmdbId: tmdbId,
            mediaType: mediaType,
            season: season,
            episode: episode,
          ));
        }
      }

      final results = await Future.wait(tasks);
      for (final list in results) {
        for (final item in list) {
          final addonName = (item.addonName ?? item.name ?? '').toString().trim().toLowerCase();
          if (_blockedAddonGroups.any((b) => addonName == b || addonName.contains(b))) {
            continue;
          }
          final isDup = _resolvedSources.any((s) => s.url == item.url) ||
                        sources.any((s) => s.url == item.url);
          if (!isDup) {
            sources.add(item);
          }
        }
      }

      if (mounted && sources.isNotEmpty) {
        setState(() {
          _resolvedSources.addAll(sources);
        });
      }
    } catch (e) {
      debugPrint('Error resolving Nuveo Addons: $e');
    }
  }

  Future<void> _resolveFilmuScraper(
    String tmdbId,
    String title, {
    int? season,
    int? episode,
  }) async {
    try {
      final mediaType = _isSeriesSearch ? 'tv' : 'movie';
      final year = _selectedMovie?['release_date']?.toString().split('-').first ?? '';
      
      final queryParams = {
        'apikey': 'filmu_moviebox_key_v1',
        if (title.isNotEmpty) 'title': title,
        if (_isSeriesSearch && season != null) 'season': season.toString(),
        if (_isSeriesSearch && episode != null) 'episode': episode.toString(),
        'tmdbId': tmdbId,
        if (year.isNotEmpty) 'year': year,
      };

      final uri = Uri.https('rive.filmu.in', '/scrape/rivestream/$mediaType/$tmdbId', queryParams);
      debugPrint('[FilmU API] Scraper Request: $uri');

      final client = HttpClient();
      client.userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
      
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      final response = await request.close().timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final Map<String, dynamic> data = jsonDecode(body);
        final List<dynamic>? sources = data['sources'];
        
        if (sources != null) {
          final List<StreamSourceInfo> tempSources = [];
          for (final src in sources) {
            final name = src['name'] ?? 'FilmU Server';
            final url = src['workerProxyUrl'] ?? src['url'];
            final quality = src['quality'] ?? '1080p';
            final Map<String, dynamic>? headersMap = src['headers'];
            
            final String lowerName = name.toString().toLowerCase();
            if (lowerName.contains('primevid') ||
                lowerName.contains('hindicast') ||
                lowerName.contains('vietsub') ||
                lowerName.contains('thuyet')) {
              continue;
            }

            if (url != null && url.toString().isNotEmpty) {
              final Map<String, String> resolvedHeaders = {};
              if (headersMap != null) {
                headersMap.forEach((key, val) {
                  resolvedHeaders[key] = val.toString();
                });
              }
              // Force referer if missing
              if (!resolvedHeaders.containsKey('Referer')) {
                resolvedHeaders['Referer'] = 'https://www.rivestream.app/';
              }

              tempSources.add(
                StreamSourceInfo(
                  name: name.toString(),
                  url: url.toString(),
                  type: StreamSourceType.filmu,
                  headers: resolvedHeaders,
                  quality: quality.toString(),
                ),
              );
            }
          }
          if (mounted && tempSources.isNotEmpty) {
            setState(() {
              _resolvedSources.addAll(tempSources);
            });
          }
        }
      }
      client.close();
    } catch (e) {
      debugPrint('[FilmU API] Scraper Error: $e');
    }
  }

  void _playStream(
    StreamSourceInfo source,
    String movieTitle,
    String? posterPath,
  ) async {
    final isScraperSource =
        source.type == StreamSourceType.netmirror ||
        source.type == StreamSourceType.castle ||
        source.type == StreamSourceType.stremioAddon ||
        source.type == StreamSourceType.nuveoAddon;

    if (source.type == StreamSourceType.filmu) {
      final Map<String, String> headers = {};
      if (source.headers != null) {
        headers.addAll(source.headers!);
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VideoPlayerScreen(
            videoSource: source.url,
            title: movieTitle,
            subtitle: 'FilmU Premium Server',
            movieId: 'special_search_${_selectedMovie['id']}',
            resumeDirectly: false,
            headers: headers.isNotEmpty ? headers : null,
          ),
        ),
      );
      return;
    }

    if (source.type == StreamSourceType.cinemm) {
      final Map<String, String> headers = {};
      if (source.headers != null) {
        headers.addAll(source.headers!);
      }
      final uri = Uri.parse(source.url);
      if (uri.queryParameters.containsKey('headers')) {
        try {
          final jsonHeaders = jsonDecode(uri.queryParameters['headers']!);
          if (jsonHeaders is Map) {
            jsonHeaders.forEach((k, v) {
              headers[k.toString()] = v.toString();
            });
          }
        } catch (_) {}
      }

      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VideoPlayerScreen(
            videoSource: source.url,
            title: movieTitle,
            subtitle: 'CineMM Server',
            movieId: 'special_search_${_selectedMovie['id']}',
            resumeDirectly: false,
            headers: headers.isNotEmpty ? headers : null,
          ),
        ),
      );
      return;
    }

    if (isScraperSource) {
      final serverSubtitle = (source.type == StreamSourceType.stremioAddon || source.type == StreamSourceType.nuveoAddon)
          ? (source.addonName ?? 'Addon')
          : '${source.name.split(':')[0]} Server';

      // 1. Show pre-flight loading indicator
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => ResolvingProgressDialog(
          title: movieTitle,
          subtitle: 'Performing pre-flight stream checks...',
        ),
      );

      try {
        final Map<String, String> headers = {};
        if (source.headers != null) {
          headers.addAll(source.headers!);
        }
        final uri = Uri.parse(source.url);

        // Extract headers from URL parameters to fetch the playlist
        if (uri.queryParameters.containsKey('headers')) {
          final jsonHeaders = jsonDecode(uri.queryParameters['headers']!);
          if (jsonHeaders is Map) {
            jsonHeaders.forEach((k, v) {
              headers[k.toString()] = v.toString();
            });
          }
        }

        // Fetch first chunk to determine if HLS
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 8);
        final req = await client.getUrl(uri);
        headers.forEach((k, v) {
          req.headers.set(k, v);
        });
        final res = await req.close();

        bool isHls = false;
        String body = '';

        if (res.statusCode == 200) {
          // Read first chunk (up to 512 bytes)
          final List<int> firstBytes = [];
          await for (final chunk in res) {
            firstBytes.addAll(chunk);
            if (firstBytes.length >= 512) {
              break;
            }
          }
          client.close(force: true); // close connection immediately

          final checkStr = utf8.decode(firstBytes, allowMalformed: true);
          if (checkStr.startsWith('#EXTM3U')) {
            isHls = true;
            // Fetch full HLS master playlist
            final playlistClient = HttpClient();
            playlistClient.connectionTimeout = const Duration(seconds: 8);
            final pReq = await playlistClient.getUrl(uri);
            headers.forEach((k, v) {
              pReq.headers.set(k, v);
            });
            final pRes = await pReq.close();
            if (pRes.statusCode == 200) {
              body = await pRes.transform(utf8.decoder).join();
            }
            playlistClient.close();
          }
        } else {
          client.close(force: true);
        }

        if (mounted) {
          Navigator.of(context).pop(); // Dismiss loader
        }

        List<String> audioLanguages = [];
        List<String> videoQualities = [];

        if (isHls && body.isNotEmpty) {
          // Parse audio tracks: #EXT-X-MEDIA:TYPE=AUDIO,...,NAME="LanguageName",...
          final audioLines = body
              .split('\n')
              .where((line) => line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO'))
              .toList();

          for (final line in audioLines) {
            final nameMatch = RegExp(r'NAME="([^"]+)"').firstMatch(line);
            if (nameMatch != null) {
              final langName = nameMatch.group(1)!;
              if (!audioLanguages.contains(langName)) {
                audioLanguages.add(langName);
              }
            }
          }

          // Parse video qualities: #EXT-X-STREAM-INF...
          final lines = body.split('\n');
          for (final line in lines) {
            if (line.startsWith('#EXT-X-STREAM-INF')) {
              final resolutionMatch = RegExp(r'RESOLUTION=(\d+x\d+)').firstMatch(line);
              if (resolutionMatch != null) {
                final height = resolutionMatch.group(1)!.split('x')[1];
                final q = '${height}p';
                if (!videoQualities.contains(q)) {
                  videoQualities.add(q);
                }
              } else {
                final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
                if (bandwidthMatch != null) {
                  final bw = int.tryParse(bandwidthMatch.group(1)!) ?? 0;
                  String q = '360p';
                  if (bw > 3000000)
                    q = '1080p';
                  else if (bw > 1500000)
                    q = '720p';
                  else if (bw > 800000)
                    q = '480p';
                  if (!videoQualities.contains(q)) {
                    videoQualities.add(q);
                  }
                }
              }
            }
          }
        }

        if (audioLanguages.isEmpty && source.languages != null && source.languages!.length > 1) {
          audioLanguages = List<String>.from(source.languages!);
        }

        String? selectedLanguage;
        if (audioLanguages.length > 1) {
          if (mounted) {
            selectedLanguage = await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (context) {
                return AlertDialog(
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Text(
                    'Select Audio Language',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: Container(
                    width: double.maxFinite,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: audioLanguages.length,
                      itemBuilder: (context, index) {
                        final lang = audioLanguages[index];
                        return ListTile(
                          title: Text(
                            lang,
                            style: const TextStyle(color: Colors.white),
                          ),
                          leading: const Icon(
                            Icons.audiotrack_rounded,
                            color: Colors.tealAccent,
                          ),
                          onTap: () => Navigator.of(context).pop(lang),
                        );
                      },
                    ),
                  ),
                );
              },
            );
          }
        }

        String? selectedQuality;
        if (videoQualities.isNotEmpty) {
          videoQualities.sort((a, b) {
            final valA = int.tryParse(a.replaceAll('p', '')) ?? 0;
            final valB = int.tryParse(b.replaceAll('p', '')) ?? 0;
            return valB.compareTo(valA);
          });

          if (mounted) {
            selectedQuality = await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (context) {
                return AlertDialog(
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Text(
                    'Select Video Quality',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: Container(
                    width: double.maxFinite,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: videoQualities.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return ListTile(
                            title: const Text(
                              'Auto / Best Quality',
                              style: TextStyle(color: Colors.white),
                            ),
                            leading: const Icon(
                              Icons.settings_backup_restore_rounded,
                              color: Colors.tealAccent,
                            ),
                            onTap: () => Navigator.of(context).pop('Auto'),
                          );
                        }
                        final q = videoQualities[index - 1];
                        return ListTile(
                          title: Text(
                            q,
                            style: const TextStyle(color: Colors.white),
                          ),
                          leading: const Icon(
                            Icons.video_settings_rounded,
                            color: Colors.tealAccent,
                          ),
                          onTap: () => Navigator.of(context).pop(q),
                        );
                      },
                    ),
                  ),
                );
              },
            );
          }
        }

        // Open player with selected language and quality
        if (mounted) {
          var finalUrl = source.url;
          final Map<String, String> queryParams = {};
          if (selectedLanguage != null && selectedLanguage.isNotEmpty) {
            queryParams['selected_audio'] = selectedLanguage;
          }
          if (selectedQuality != null &&
              selectedQuality.isNotEmpty &&
              selectedQuality != 'Auto') {
            queryParams['selected_quality'] = selectedQuality;
          }

          if (queryParams.isNotEmpty) {
            final sourceUri = Uri.parse(source.url);
            finalUrl = sourceUri
                .replace(
                  queryParameters: {
                    ...sourceUri.queryParameters,
                    ...queryParams,
                  },
                )
                .toString();
          }

          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => VideoPlayerScreen(
                videoSource: finalUrl,
                title: movieTitle,
                subtitle: serverSubtitle,
                movieId: 'special_search_${_selectedMovie['id']}',
                resumeDirectly: false,
                headers: headers.isNotEmpty ? headers : null,
                sourceName: source.name,
              ),
            ),
          );
        }
      } catch (e) {
        // Fallback: If pre-flight check fails or times out, launch the stream directly
        debugPrint(
          'Scraper pre-flight check failed: $e. Launching stream directly.',
        );
        if (mounted) {
          Navigator.of(context).pop(); // Dismiss loader if still open

          final Map<String, String> headers = {};
          if (source.headers != null) {
            headers.addAll(source.headers!);
          }
          final uri = Uri.parse(source.url);
          if (uri.queryParameters.containsKey('headers')) {
            final jsonHeaders = jsonDecode(uri.queryParameters['headers']!);
            if (jsonHeaders is Map) {
              jsonHeaders.forEach((k, v) {
                headers[k.toString()] = v.toString();
              });
            }
          }

          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => VideoPlayerScreen(
                videoSource: source.url,
                title: movieTitle,
                subtitle: serverSubtitle,
                movieId: 'special_search_${_selectedMovie['id']}',
                resumeDirectly: false,
                headers: headers.isNotEmpty ? headers : null,
                sourceName: source.name,
              ),
            ),
          );
        }
      }
      return;
    }

    if (source.url.startsWith('stalker://')) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.pinkAccent),
        ),
      );
      try {
        final uri = Uri.parse(source.url);
        final portalId = int.parse(uri.host);
        final cmd = uri.path;
        final resolved = await StalkerResolver.resolveStream(
          cmd,
          portalId,
          isLive: false,
        );
        if (mounted) {
          Navigator.of(context).pop(); // Dismiss loading
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => VideoPlayerScreen(
                videoSource: resolved.url,
                title: movieTitle,
                subtitle: 'Stalker Portal',
                movieId: 'special_search_${_selectedMovie['id']}',
                resumeDirectly: false,
                headers: resolved.headers,
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop(); // Dismiss loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to resolve Stalker stream: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } else if (source.url.startsWith('magnet:')) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WebViewPlayerScreen(
            embedUrl: source.url,
            title: movieTitle,
            backdropUrl: posterPath != null
                ? 'https://image.tmdb.org/t/p/w780$posterPath'
                : null,
          ),
        ),
      );
    } else {
      final isWebEmbed =
          source.url.contains('vidsrc') ||
          source.url.contains('embed') ||
          source.url.contains('player') ||
          source.url.contains('vidlink.pro') ||
          source.url.contains('woof.video') ||
          source.url.contains('streamtape') ||
          source.url.contains('dood') ||
          source.url.contains('mixdrop') ||
          source.url.contains('hgcloud') ||
          source.url.contains('/e/');

      if (isWebEmbed ||
          source.type == StreamSourceType.vidsrc) {
        try {
          final resolvedUrl = await EmbedResolver.resolve(context, source.url);
          if (mounted) {
            if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
              final headers = EmbedResolver.getHeadersForUrl(resolvedUrl);
              _handleStreamPlay(
                resolvedUrl,
                headers,
                movieTitle,
                posterPath,
              );
            } else {
              // Fallback to webview player directly
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WebViewPlayerScreen(
                    embedUrl: source.url,
                    title: movieTitle,
                    backdropUrl: posterPath != null
                        ? 'https://image.tmdb.org/t/p/w780$posterPath'
                        : null,
                  ),
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error resolving stream: $e'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
      } else {
        // It is already a direct stream (Stravo, Stalker resolved url, etc.)
        _handleStreamPlay(
          source.url,
          source.headers,
          movieTitle,
          posterPath,
        );
      }
    }
  }

  Future<void> _handleStreamPlay(String streamUrl, Map<String, String>? headers, String movieTitle, String? posterPath) async {
    final prefs = await SharedPreferences.getInstance();

    final hlsResult = await runHlsPreflight(
      context: context,
      url: streamUrl,
      movieTitle: movieTitle,
      headers: headers,
    );
    final finalUrl = hlsResult?.url ?? streamUrl;

    final tvDeviceId = prefs.getString('paired_tv_device_id');

    if (tvDeviceId == null) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoPlayerScreen(
              videoSource: finalUrl,
              title: movieTitle,
              subtitle: 'Resolved Stream',
              movieId: 'special_search_${_selectedMovie?['id']}',
              resumeDirectly: false,
              headers: headers,
            ),
          ),
        );
      }
      return;
    }

    final playMode = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.play_circle_fill_rounded, color: AppColors.accentBright),
              const SizedBox(width: 10),
              Text(
                'Select Playback Target',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: const Text(
            'Where would you like to stream this movie?',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('local'),
              child: const Text('Play Locally', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentBright,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).pop('cast'),
              child: const Text('Cast to TV App', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (playMode == 'local') {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoPlayerScreen(
              videoSource: streamUrl,
              title: movieTitle,
              subtitle: 'Resolved Stream',
              movieId: 'special_search_${_selectedMovie?['id']}',
              resumeDirectly: false,
              headers: headers,
            ),
          ),
        );
      }
    } else if (playMode == 'cast') {
      final proxyUrl = await WifiCastService.startProxyServer(streamUrl, headers: headers);
      if (proxyUrl == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to start Wi-Fi casting server.')),
          );
        }
        return;
      }

      final url = 'https://kvdb.io/SgA62xKx8YnQoV2Uv9QJ6t/req_$tvDeviceId';
      try {
        List<dynamic> requests = [];
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
          try {
            requests = json.decode(res.body);
          } catch (_) {}
        }

        final newReq = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'title': movieTitle,
          'downloadUrl': proxyUrl,
          'posterUrl': posterPath != null ? 'https://image.tmdb.org/t/p/w185$posterPath' : '',
          'playImmediately': true,
          'timestamp': DateTime.now().toIso8601String(),
        };
        requests.add(newReq);

        await http.post(
          Uri.parse(url),
          body: json.encode(requests),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('Failed sending instant cast request to TV: $e');
      }

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CastControllerScreen(
              title: movieTitle,
              proxyUrl: proxyUrl,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(
                  maxWidth: 480,
                  maxHeight: 650,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentBright.withValues(alpha: 0.25),
                      blurRadius: 40,
                      spreadRadius: -10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Column(
                    children: [
                      // Header bar
                      _buildHeader(),
                      // Body content
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _selectedMovie != null
                              ? (_isSeriesSearch && _selectingEpisode
                                  ? _buildEpisodeSelectionView()
                                  : _buildMovieDetailsView())
                              : _buildSearchView(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.accentBright, size: 20),
              const SizedBox(width: 8),
              Text(
                'LIVE CINEMA FINDER',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white70,
              size: 22,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(
              hoverColor: Colors.white10,
              highlightColor: Colors.white10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchView() {
    return Column(
      key: const ValueKey('search_view'),
      children: [
        // Movies/Series Toggle Row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (_isSeriesSearch) {
                        setState(() {
                          _isSeriesSearch = false;
                          _searchResults = [];
                        });
                        if (_searchController.text.isNotEmpty) {
                          _performLiveSearch(_searchController.text);
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        gradient: !_isSeriesSearch
                            ? LinearGradient(colors: [AppColors.accent, AppColors.accentBright])
                            : null,
                        color: _isSeriesSearch ? Colors.transparent : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'MOVIES',
                          style: GoogleFonts.outfit(
                            color: !_isSeriesSearch ? Colors.black : Colors.white60,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (!_isSeriesSearch) {
                        setState(() {
                          _isSeriesSearch = true;
                          _searchResults = [];
                        });
                        if (_searchController.text.isNotEmpty) {
                          _performLiveSearch(_searchController.text);
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        gradient: _isSeriesSearch
                            ? LinearGradient(colors: [AppColors.accent, AppColors.accentBright])
                            : null,
                        color: !_isSeriesSearch ? Colors.transparent : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'TV SERIES',
                          style: GoogleFonts.outfit(
                            color: _isSeriesSearch ? Colors.black : Colors.white60,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Search Input
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              cursorColor: AppColors.accentBright,
              decoration: InputDecoration(
                hintText: _isSeriesSearch ? 'Search TV series live online...' : 'Search movies live online...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.38),
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear_rounded,
                          color: Colors.white54,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),

        // Results / Loading state
        Expanded(
          child: _searching
              ? Center(
                  child: CircularProgressIndicator(
                    color: AppColors.accentBright,
                  ),
                )
              : _searchResults.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final item = _searchResults[index];
                    final title = (item['title'] ?? item['name'])?.toString() ?? 'Unknown Title';
                    final rawYear =
                        (item['release_date'] ?? item['first_air_date'])?.toString().split('-').first ?? '';
                    final year = rawYear.isNotEmpty ? rawYear : 'N/A';
                    final lang =
                        item['original_language']?.toString().toUpperCase() ??
                        'EN';
                    final posterPath = item['poster_path']?.toString();

                    return Card(
                      color: Colors.white.withValues(alpha: 0.03),
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _onMovieSelected(item),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              // Poster image
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: posterPath != null
                                    ? Image.network(
                                        'https://image.tmdb.org/t/p/w92$posterPath',
                                        width: 48,
                                        height: 70,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _buildFallbackPoster(),
                                      )
                                    : _buildFallbackPoster(),
                              ),
                              const SizedBox(width: 14),
                              // Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white12,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            year,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.accentBright
                                                .withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            lang,
                                            style: TextStyle(
                                              color: AppColors.accentBright,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.white38,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFallbackPoster() {
    return Container(
      width: 48,
      height: 70,
      color: Colors.white12,
      child: const Icon(
        Icons.movie_filter_rounded,
        color: Colors.white30,
        size: 20,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.travel_explore_rounded,
            size: 48,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),
          Text(
            _searchController.text.isNotEmpty
                ? 'No movie found.'
                : 'Search beyond your library',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeSelectionView() {
    final title = (_selectedMovie['name'] ?? _selectedMovie['title'])?.toString() ?? 'TV Series';
    final posterPath = _selectedMovie['poster_path']?.toString();
    final tmdbId = _selectedMovie['id']?.toString() ?? '';

    return Padding(
      key: const ValueKey('episode_selection_view'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          // Show metadata overview
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: posterPath != null
                      ? Image.network(
                          'https://image.tmdb.org/t/p/w92$posterPath',
                          width: 54,
                          height: 78,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildFallbackPoster(),
                        )
                      : _buildFallbackPoster(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Select Season and Episode',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Horizontal Seasons selector row
          if (_seasons.isNotEmpty)
            Container(
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _seasons.length,
                itemBuilder: (context, idx) {
                  final s = _seasons[idx];
                  final sNum = s['season_number'] as int? ?? -1;
                  final isSelected = _selectedSeasonNumber == sNum;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedSeasonNumber = sNum;
                      });
                      _fetchEpisodesForSeason(tmdbId, sNum);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? LinearGradient(colors: [AppColors.accent, AppColors.accentBright])
                            : null,
                        color: isSelected ? null : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.06),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Season $sNum',
                          style: GoogleFonts.outfit(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),

          // Vertical Episodes List
          Expanded(
            child: _loadingSeasons || _loadingEpisodes
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : _episodes.isEmpty
                    ? Center(
                        child: Text(
                          'No episodes found.',
                          style: TextStyle(color: Colors.white.withOpacity(0.38)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _episodes.length,
                        itemBuilder: (context, idx) {
                          final ep = _episodes[idx];
                          final epNum = ep['episode_number'] as int? ?? -1;
                          final epName = ep['name']?.toString() ?? 'Episode $epNum';
                          final epOverview = ep['overview']?.toString() ?? '';

                          return Card(
                            color: Colors.white.withOpacity(0.03),
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Colors.white.withOpacity(0.04)),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              title: Text(
                                'Episode $epNum: $epName',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                              subtitle: epOverview.isNotEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        epOverview,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.38),
                                          fontSize: 11,
                                        ),
                                      ),
                                    )
                                  : null,
                              trailing: const Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white30,
                                size: 24,
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedEpisodeData = ep;
                                  _selectingEpisode = false;
                                  _loadingDetails = false;
                                  _resolvedSources = [];
                                  _resolvingStreams = false;
                                  _activeGroupType = null;
                                  _selectedAddonSubGroup = null;
                                });
                                // Resolve streams now!
                                _resolveMovieStreams(
                                  tmdbId,
                                  _imdbId,
                                  title,
                                  season: _selectedSeasonNumber,
                                  episode: epNum,
                                );
                              },
                            ),
                          );
                        },
                      ),
          ),

          const SizedBox(height: 10),
          // Back Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedMovie = null;
                  });
                },
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('BACK TO SEARCH'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovieDetailsView() {
    final title = (_selectedMovie['title'] ?? _selectedMovie['name'])?.toString() ?? 'Media Title';
    final posterPath = _selectedMovie['poster_path']?.toString();
    final rawYear =
        (_selectedMovie['release_date'] ?? _selectedMovie['first_air_date'])?.toString().split('-').first ?? '';
    final year = rawYear.isNotEmpty ? rawYear : 'N/A';
    final lang =
        _selectedMovie['original_language']?.toString().toUpperCase() ?? 'EN';

    return Padding(
      key: const ValueKey('details_view'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Movie summary block
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: posterPath != null
                    ? Image.network(
                        'https://image.tmdb.org/t/p/w185$posterPath',
                        width: 80,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 80,
                          height: 120,
                          color: Colors.white12,
                          child: const Icon(
                            Icons.movie_rounded,
                            color: Colors.white30,
                            size: 32,
                          ),
                        ),
                      )
                    : Container(
                        width: 80,
                        height: 120,
                        color: Colors.white12,
                        child: const Icon(
                          Icons.movie_rounded,
                          color: Colors.white30,
                          size: 32,
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isSeriesSearch && _selectedEpisodeData != null)
                      Text(
                        'S$_selectedSeasonNumber E${_selectedEpisodeData['episode_number']}: ${_selectedEpisodeData['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: AppColors.accentBright,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            year,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentBright.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            lang,
                            style: TextStyle(
                              color: AppColors.accentBright,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Text(
            _selectedAddonSubGroup != null
                ? _selectedAddonSubGroup!.toUpperCase()
                : (_activeGroupType == null
                    ? 'SELECT STREAM SERVER'
                    : 'SERVER LINKS'),
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),

          // Streams List / Loader
          Expanded(
            child:
                _loadingDetails
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: AppColors.accentBright,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Retrieving metadata...',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : _buildStreamSelectionContent(title, posterPath),
          ),

          const SizedBox(height: 10),
          // Back Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  if (_selectedAddonSubGroup != null) {
                    _selectedAddonSubGroup = null;
                  } else if (_activeGroupType != null) {
                    _activeGroupType = null;
                  } else {
                    if (_isSeriesSearch) {
                      _selectingEpisode = true;
                    } else {
                      _selectedMovie = null;
                    }
                  }
                });
              },
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: Text(
                _selectedAddonSubGroup != null
                    ? 'BACK TO ADDONS'
                    : (_activeGroupType != null
                        ? 'BACK TO SERVERS'
                        : (_isSeriesSearch ? 'BACK TO EPISODES' : 'BACK TO SEARCH')),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _getOttLogo(String name, {double size = 24}) {
    final lower = name.toLowerCase();
    String? domain;
    Widget fallback;

    if (lower.contains('netflix') || lower.contains('(nf)')) {
      domain = 'netflix.com';
      fallback = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: const Center(
          child: Text('N', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
        ),
      );
    } else if (lower.contains('prime') || lower.contains('(pv)')) {
      domain = 'primevideo.com';
      fallback = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.blue.withOpacity(0.3)),
        ),
        child: const Center(
          child: Text('PV', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 9)),
        ),
      );
    } else if (lower.contains('hotstar') || lower.contains('disney') || lower.contains('(hs)')) {
      domain = 'hotstar.com';
      fallback = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.teal.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.teal.withOpacity(0.3)),
        ),
        child: const Center(
          child: Text('D+', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 9)),
        ),
      );
    } else {
      return Icon(Icons.language_rounded, color: AppColors.accentBright, size: size);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        'https://logo.clearbit.com/$domain',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return fallback;
        },
      ),
    );
  }

  List<StreamSourceInfo> _applySizeFilter(List<StreamSourceInfo> sources) {
    final maxMb = _maxSourceSizeMb;
    if (maxMb <= 0) return sources;
    return sources.where((s) {
      if (s.size == null || s.size!.isEmpty) return true;
      final sizeMb = parseSizeToMb(s.size);
      return sizeMb == 0 || sizeMb <= maxMb;
    }).toList();
  }

  Widget _buildStreamSelectionContent(String movieTitle, String? posterPath) {
    final filteredSources = _applySizeFilter(_resolvedSources);
    final Set<String> enabledKeys = _sourceOrder.toSet();
    final Map<String, int> orderPos = {};
    for (int i = 0; i < _sourceOrder.length; i++) {
      orderPos[_sourceOrder[i]] = i + 1;
    }
    int pos(String key) => orderPos[key] ?? 99;
    final stravoStreams = filteredSources
        .where((s) => s.type == StreamSourceType.stravo)
        .toList();
    final vidlinkStreams = filteredSources
        .where((s) => s.type == StreamSourceType.vidlink)
        .toList();
    final torrentStreams = filteredSources
        .where((s) => s.type == StreamSourceType.torrent)
        .toList();
    final stalkerStreams = filteredSources
        .where((s) => s.type == StreamSourceType.stalker)
        .toList();
    final netmirrorStreams = filteredSources
        .where((s) => s.type == StreamSourceType.netmirror)
        .toList();
    final dvdplayStreams = filteredSources
        .where((s) => s.type == StreamSourceType.dvdplay)
        .toList();
    final mallumvStreams = filteredSources
        .where((s) => s.type == StreamSourceType.mallumv)
        .toList();
    final vidnestStreams = filteredSources
        .where((s) => s.type == StreamSourceType.vidnest)
        .toList();
    final hdhub4uStreams = filteredSources
        .where((s) => s.type == StreamSourceType.hdhub4u)
        .toList();
    final castleStreams = filteredSources
        .where((s) => s.type == StreamSourceType.castle)
        .toList();
    final cinemmStreams = filteredSources
        .where((s) => s.type == StreamSourceType.cinemm)
        .toList();
    final stremioStreams = filteredSources
        .where((s) => s.type == StreamSourceType.stremioAddon)
        .toList();
    final nuveoStreams = filteredSources
        .where((s) => s.type == StreamSourceType.nuveoAddon)
        .toList();
    final filmuStreams = filteredSources
        .where((s) => s.type == StreamSourceType.filmu)
        .toList();

    if (_activeGroupType == null) {
      final Map<String, Widget> sourceWidgets = {};

      // VidLink
      if (_showVidlink && (_resolvingStreams || vidlinkStreams.isNotEmpty) && enabledKeys.contains('vidlink')) {
        sourceWidgets['vidlink'] = _buildServerGroupCard(
          title: '${pos('vidlink')}. Vidlink Server',
          subtitle: _resolvingStreams && vidlinkStreams.isEmpty
              ? 'Resolving stream...'
              : (vidlinkStreams.isNotEmpty
                    ? '1 native link available'
                    : 'Not available for this title'),
          icon: Icons.play_arrow_rounded,
          accentColor: AppColors.accentBright,
          onTap: vidlinkStreams.isEmpty
              ? null
              : () =>
                    _playStream(vidlinkStreams.first, movieTitle, posterPath),
        );
      }

      // NetMirror
      if (_showNetmirror && (_resolvingStreams || netmirrorStreams.isNotEmpty) && enabledKeys.contains('netmirror')) {
        sourceWidgets['netmirror'] = _buildServerGroupCard(
          title: '${pos('netmirror')}. NetMirror Server',
          subtitle: _resolvingStreams && netmirrorStreams.isEmpty
              ? 'Searching NetMirror...'
              : (netmirrorStreams.isNotEmpty
                    ? '${netmirrorStreams.length} links available'
                    : 'Not available'),
          icon: Icons.language_rounded,
          accentColor: Colors.tealAccent,
          onTap: netmirrorStreams.isEmpty
              ? null
              : () => setState(
                  () => _activeGroupType = StreamSourceType.netmirror,
                ),
        );
      }

      // Stravo
      if (_showStravo && (_resolvingStreams || stravoStreams.isNotEmpty) && enabledKeys.contains('stravo')) {
        sourceWidgets['stravo'] = _buildServerGroupCard(
          title: '${pos('stravo')}. Stravo Server',
          subtitle: _resolvingStreams && stravoStreams.isEmpty
              ? 'Searching streams...'
              : '${stravoStreams.length} links available',
          icon: Icons.rocket_launch_rounded,
          accentColor: Colors.cyan,
          onTap: stravoStreams.isEmpty
              ? null
              : () => setState(
                  () => _activeGroupType = StreamSourceType.stravo,
                ),
        );
      }

      // Stalker
      if (_showStalker && (_resolvingStreams || stalkerStreams.isNotEmpty) && enabledKeys.contains('stalker')) {
        sourceWidgets['stalker'] = _buildServerGroupCard(
          title: '${pos('stalker')}. Stalker VOD Server',
          subtitle: _resolvingStreams && stalkerStreams.isEmpty
              ? 'Searching local library...'
              : (stalkerStreams.isNotEmpty
                    ? '${stalkerStreams.length} links available'
                    : 'Not available'),
          icon: Icons.movie_filter_rounded,
          accentColor: Colors.purpleAccent,
          onTap: stalkerStreams.isEmpty
              ? null
              : () => setState(
                  () => _activeGroupType = StreamSourceType.stalker,
                ),
        );
      }

      // CineMM
      if (_showCinemm && (_resolvingStreams || cinemmStreams.isNotEmpty) && enabledKeys.contains('cinemm')) {
        sourceWidgets['cinemm'] = _buildServerGroupCard(
          title: '${pos('cinemm')}. CineMM Server',
          subtitle: _resolvingStreams && cinemmStreams.isEmpty
              ? 'Searching CineMM...'
              : (cinemmStreams.isNotEmpty
                    ? '${cinemmStreams.length} links available'
                    : 'Not available'),
          icon: Icons.local_movies_rounded,
          accentColor: Colors.lightBlueAccent,
          onTap: cinemmStreams.isEmpty
              ? null
              : () => setState(
                  () => _activeGroupType = StreamSourceType.cinemm,
                ),
        );
      }

      // Castle (movies only)
      if (_showCastle && !widget.isSeriesSearch && (_resolvingStreams || castleStreams.isNotEmpty) && enabledKeys.contains('castle')) {
        sourceWidgets['castle'] = _buildServerGroupCard(
          title: '${pos('castle')}. Castle TV Server',
          subtitle: _resolvingStreams && castleStreams.isEmpty
              ? 'Searching Castle...'
              : (castleStreams.isNotEmpty
                    ? '${castleStreams.length} links available'
                    : 'Not available'),
          icon: Icons.castle_rounded,
          accentColor: Colors.amberAccent,
          onTap: castleStreams.isEmpty
              ? null
              : () => setState(
                  () => _activeGroupType = StreamSourceType.castle,
                ),
        );
      }

      // Torrent
      if (_showTorrent && (_resolvingStreams || torrentStreams.isNotEmpty) && enabledKeys.contains('torrent')) {
        sourceWidgets['torrent'] = _buildServerGroupCard(
          title: '${pos('torrent')}. Torrent Server',
          subtitle: _resolvingStreams && torrentStreams.isNotEmpty
              ? 'Scraping torrents...'
              : '${torrentStreams.length} links available',
          icon: Icons.cloud_circle_rounded,
          accentColor: Colors.amber,
          onTap: torrentStreams.isEmpty
              ? null
              : () => setState(
                  () => _activeGroupType = StreamSourceType.torrent,
                ),
        );
      }

      // Stremio Addons
      if (_showStremioAddon && (_resolvingStreams || stremioStreams.isNotEmpty) && enabledKeys.contains('stremioAddon')) {
        sourceWidgets['stremioAddon'] = _buildServerGroupCard(
          title: '${pos('stremioAddon')}. Stremio Addons',
          subtitle: _resolvingStreams && stremioStreams.isEmpty
              ? 'Searching addons...'
              : '${stremioStreams.length} links available',
          icon: Icons.extension_rounded,
          accentColor: Colors.pinkAccent,
          onTap: stremioStreams.isEmpty
              ? null
              : () => setState(() {
                  _activeGroupType = StreamSourceType.stremioAddon;
                  _selectedStremioResolution = null;
                }),
        );
      }

      // Nuveo Addons
      if ((_resolvingStreams || nuveoStreams.isNotEmpty) && enabledKeys.contains('stremioAddon')) {
        sourceWidgets['nuveoAddon'] = _buildServerGroupCard(
          title: '${pos('stremioAddon')}. Nuveo Addons',
          subtitle: _resolvingStreams && nuveoStreams.isEmpty
              ? 'Searching scrapers...'
              : '${nuveoStreams.length} links available',
          icon: Icons.settings_input_component_rounded,
          accentColor: Colors.pinkAccent,
          onTap: nuveoStreams.isEmpty
              ? null
              : () => setState(() {
                  _activeGroupType = StreamSourceType.nuveoAddon;
                  _selectedStremioResolution = null;
                }),
        );
      }

      // FilmU Card
      if (_showFilmu && (_resolvingStreams || filmuStreams.isNotEmpty) && enabledKeys.contains('filmu')) {
        sourceWidgets['filmu'] = _buildServerGroupCard(
          title: '${pos('filmu')}. FilmU Premium Server',
          subtitle: _resolvingStreams && filmuStreams.isEmpty
              ? 'Searching FilmU...'
              : '${filmuStreams.length} servers available',
          icon: Icons.hd_rounded,
          accentColor: Colors.orangeAccent,
          onTap: filmuStreams.isEmpty
              ? null
              : () => setState(() {
                    _activeGroupType = StreamSourceType.filmu;
                  }),
        );
      }



      final List<Widget> groupCards = [];
      for (final key in _sourceOrder) {
        if (key == 'stremioAddon') {
          if (sourceWidgets.containsKey('stremioAddon') && enabledKeys.contains('stremioAddon')) {
            groupCards.add(sourceWidgets['stremioAddon']!);
          }
          if (sourceWidgets.containsKey('nuveoAddon') && enabledKeys.contains('stremioAddon')) {
            groupCards.add(sourceWidgets['nuveoAddon']!);
          }
        } else {
          if (sourceWidgets.containsKey(key) && enabledKeys.contains(key)) {
            groupCards.add(sourceWidgets[key]!);
          }
      }
    }

      if (groupCards.isEmpty && !_resolvingStreams) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sentiment_dissatisfied_rounded, color: Colors.white38, size: 48),
                const SizedBox(height: 12),
                Text(
                  'No streams found.',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Try searching for another query or check your active addon URLs in Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      }

      return ListView(
        children: groupCards,
      );
    } else {
      // 2. Expanded group sub-links list
      final List<StreamSourceInfo> activeList;
      final Color accentColor;
      final IconData iconData;

      if (_activeGroupType == StreamSourceType.stravo) {
        activeList = stravoStreams;
        accentColor = Colors.cyan;
        iconData = Icons.rocket_launch_rounded;
      } else if (_activeGroupType == StreamSourceType.torrent) {
        activeList = torrentStreams;
        accentColor = Colors.amber;
        iconData = Icons.cloud_circle_rounded;
      } else if (_activeGroupType == StreamSourceType.stalker) {
        activeList = stalkerStreams;
        accentColor = Colors.purpleAccent;
        iconData = Icons.movie_filter_rounded;
      } else if (_activeGroupType == StreamSourceType.netmirror) {
        activeList = netmirrorStreams;
        accentColor = Colors.tealAccent;
        iconData = Icons.language_rounded;
      } else if (_activeGroupType == StreamSourceType.dvdplay) {
        activeList = dvdplayStreams;
        accentColor = Colors.deepOrangeAccent;
        iconData = Icons.disc_full_rounded;
      } else if (_activeGroupType == StreamSourceType.mallumv) {
        activeList = mallumvStreams;
        accentColor = Colors.pinkAccent;
        iconData = Icons.music_video_rounded;
      } else if (_activeGroupType == StreamSourceType.vidnest) {
        activeList = vidnestStreams;
        accentColor = Colors.indigoAccent;
        iconData = Icons.video_library_rounded;
      } else if (_activeGroupType == StreamSourceType.hdhub4u) {
        activeList = hdhub4uStreams;
        accentColor = Colors.lightGreenAccent;
        iconData = Icons.hd_rounded;
      } else if (_activeGroupType == StreamSourceType.cinemm) {
        activeList = cinemmStreams;
        accentColor = Colors.lightBlueAccent;
        iconData = Icons.local_movies_rounded;
      } else if (_activeGroupType == StreamSourceType.stremioAddon) {
        activeList = stremioStreams;
        accentColor = Colors.pinkAccent;
        iconData = Icons.extension_rounded;
      } else if (_activeGroupType == StreamSourceType.nuveoAddon) {
        activeList = nuveoStreams;
        accentColor = Colors.pinkAccent;
        iconData = Icons.settings_input_component_rounded;
      } else if (_activeGroupType == StreamSourceType.filmu) {
        activeList = filmuStreams;
        accentColor = Colors.orangeAccent;
        iconData = Icons.hd_rounded;
      } else {
        activeList = castleStreams;
        accentColor = Colors.amberAccent;
        iconData = Icons.castle_rounded;
      }

      if (activeList.isEmpty && _activeGroupType != StreamSourceType.stremioAddon && _activeGroupType != StreamSourceType.nuveoAddon) {
        return Center(
          child: Text(
            'No links found in this server.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 14,
            ),
          ),
        );
      }
 
       // Remove resolution categories and list addon streams directly together
            if (_activeGroupType == StreamSourceType.stremioAddon || _activeGroupType == StreamSourceType.nuveoAddon) {
              final isNuv = _activeGroupType == StreamSourceType.nuveoAddon;
              final addonList = _resolvedSources
                  .where((s) => s.type == (_activeGroupType))
                  .toList();
 
              if (_selectedAddonSubGroup == null) {
                // Sub-group cards view
                final Map<String, List<StreamSourceInfo>> grouped = {};
                for (final s in addonList) {
                  final key = s.addonName ?? 'Unknown Source';
                  grouped.putIfAbsent(key, () => []).add(s);
                }
 
                if (grouped.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isNuv ? Icons.settings_input_component_rounded : Icons.extension_rounded,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _resolvingStreams ? 'Resolving addon streams...' : 'No links found in this server',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }
 
                final entries = grouped.entries.toList();
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    Padding(
                       padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${isNuv ? "Nuveo" : "Stremio"} Addons \u2022 ${entries.length} source${entries.length != 1 ? "s" : ""}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final entry in entries)
                      Card(
                        color: Colors.white.withValues(alpha: 0.04),
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() => _selectedAddonSubGroup = entry.key),
                          onLongPress: () {
                            Clipboard.setData(ClipboardData(text: entry.key));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied Category: ${entry.key}'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(
                                  isNuv ? Icons.settings_input_component_rounded : Icons.extension_rounded,
                                  color: Colors.pinkAccent,
                                  size: 28,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.key,
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${entry.value.length} link${entry.value.length != 1 ? "s" : ""} available',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.45),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              } else {
                // Filtered view for selected sub-group
                final filtered = addonList
                    .where((s) => (s.addonName ?? 'Unknown Source') == _selectedAddonSubGroup)
                    .toList();
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${filtered.length} link${filtered.length != 1 ? "s" : ""} from ${_selectedAddonSubGroup}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final s in filtered)
                      Card(
                        color: Colors.white.withValues(alpha: 0.04),
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Icon(
                            isNuv ? Icons.settings_input_component_rounded : Icons.extension_rounded,
                            color: Colors.pinkAccent,
                          ),
                          title: Text(
                            (s.quality?.isNotEmpty ?? false) ? s.quality! : 'Stream',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            (s.languages?.isNotEmpty ?? false) ? s.languages!.join(', ') : 'Unknown',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white30,
                          ),
                          onTap: () => _playStream(s, movieTitle, posterPath),
                          onLongPress: () {
                            Clipboard.setData(ClipboardData(text: s.url));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied Link: ${s.url}'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              }
            }

      return ListView.builder(
        itemCount: activeList.length,
        itemBuilder: (context, index) {
          final source = activeList[index];
          return Card(
            color: Colors.white.withValues(alpha: 0.04),
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: _activeGroupType == StreamSourceType.netmirror
                  ? CircleAvatar(
                      backgroundColor: Colors.transparent,
                      child: _getOttLogo(source.name, size: 28),
                    )
                  : CircleAvatar(
                      backgroundColor: accentColor.withValues(alpha: 0.15),
                      child: Icon(iconData, color: accentColor, size: 20),
                    ),
              title: Text(
                (source.quality != null && source.quality!.isNotEmpty)
                    ? '${source.name} (${source.quality})'
                    : source.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white.withValues(alpha: 0.4),
              ),
              onTap: () => _playStream(source, movieTitle, posterPath),
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: source.url));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied Link: ${source.url}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          );
        },
      );
    }
  }

  Widget _buildServerGroupCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    VoidCallback? onTap,
  }) {
    final bool disabled = onTap == null;
    return Card(
      color: Colors.white.withValues(alpha: disabled ? 0.015 : 0.04),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        enabled: !disabled,
        leading: CircleAvatar(
          backgroundColor: accentColor.withValues(
            alpha: disabled ? 0.05 : 0.15,
          ),
          child: Icon(
            icon,
            color: accentColor.withValues(alpha: disabled ? 0.4 : 1.0),
            size: 22,
          ),
        ),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            color: disabled ? Colors.white30 : Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: disabled ? Colors.white24 : Colors.white54,
            fontSize: 12.5,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: disabled ? Colors.white12 : Colors.white54,
        ),
      ),
    );
  }
}

enum StreamSourceType {
  vidlink,
  stravo,
  torrent,
  stalker,
  netmirror,
  dvdplay,
  mallumv,
  vidnest,
  hdhub4u,
  castle,
  cinemm,
  vidsrc,
  stremioAddon,
  nuveoAddon,
  filmu,
}

class StreamSourceInfo {
  final String name;
  final String url;
  final StreamSourceType type;
  final Map<String, String>? headers;

  // Custom fields for Stremio addon streams
  final String? addonName;
  final String? originalTitle;
  final String? quality;
  final List<String>? languages;
  final String? size;

  StreamSourceInfo({
    required this.name,
    required this.url,
    required this.type,
    this.headers,
    this.addonName,
    this.originalTitle,
    this.quality,
    this.languages,
    this.size,
  });
}
