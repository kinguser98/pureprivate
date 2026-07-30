import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:private_cinema_mobile/data/cinemm_resolver.dart';
import 'package:private_cinema_mobile/data/telegram_sources.dart';
import 'package:freebuff_core/services/telegram/telegram_service.dart';
import 'package:freebuff_core/services/telegram/telegram_video_item.dart';
import 'package:freebuff_core/services/telegram/telegram_index_db.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/screens/all_movies_screen.dart';
import 'package:private_cinema_mobile/widgets/movie_image.dart';
import 'package:private_cinema_mobile/screens/video_player_screen.dart';
import 'package:private_cinema_mobile/widgets/resolving_dialog.dart';
import 'package:private_cinema_mobile/screens/webview_player_screen.dart';
import 'package:private_cinema_mobile/widgets/person_detail_sheet.dart';
import 'package:private_cinema_mobile/data/stalker_resolver.dart';
import 'package:private_cinema_mobile/data/netmirror_resolver.dart';
import 'package:private_cinema_mobile/data/stremio_addon_resolver.dart';
import 'package:private_cinema_mobile/data/sync_service.dart';
import 'package:private_cinema_mobile/data/webview_scraper_executor.dart';
import 'package:private_cinema_mobile/data/hls_preflight.dart';
import 'package:private_cinema_mobile/data/webtorrent_service.dart';
import 'package:private_cinema_mobile/widgets/seedr_countdown_dialog.dart';
import 'package:private_cinema_mobile/widgets/stream_metadata_tile.dart';

class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({super.key, required this.movie});

  final Movie movie;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  Movie get movie => widget.movie;
  String? _pickedPath;
  bool _isFavorite = false;
  bool _inWatchlist = false;
  bool _isDownloaded = false;

  List<CastMember> _dynamicCast = [];
  String? _dynamicDirector;
  String? _directorProfileUrl;
  double? _dynamicRating;
  double? _dynamicPopularity;
  List<Map<String, dynamic>> _watchProviders = [];

  double? _watchProgress;
  int _savedPositionMs = 0;

  List<StreamSource> _torrentioSources = [];
  List<StreamSource> _stravoSources = [];
  final Map<String, Map<String, int>> _customMagnetStats = {};

  List<StreamSource> _liveVidlinkSources = [];
  List<StreamSource> _liveNetmirrorSources = [];
  List<StreamSource> _liveCinemmSources = [];
  List<StreamSource> _liveMovieboxSources = [];
  List<StreamSource> _liveStalkerSources = [];
  List<StreamSource> _liveStravoSources = [];
  List<StreamSource> _liveStremioSources = [];
  List<StreamSource> _liveNuveoSources = [];
  List<StreamSource> _liveCastleSources = [];
  List<StreamSource> _liveTelegramSources = [];

  bool _resolvingVidlink = false;
  bool _resolvingNetmirror = false;
  bool _resolvingCinemm = false;
  bool _resolvingMoviebox = false;
  bool _resolvingStalker = false;
  bool _resolvingStravo = false;
  bool _resolvingStremio = false;
  bool _resolvingNuveo = false;
  bool _resolvingCastle = false;
  bool _resolvingTorrent = false;
  bool _resolvingTelegram = false;

  bool _showVidlink = true;
  bool _showNetmirror = true;
  bool _showCinemm = true;
  bool _showMoviebox = true;
  bool _showStalker = true;
  bool _showStravo = true;
  bool _showTorrent = true;
  bool _showStremioAddon = true;
  bool _showNuveoAddon = true;
  bool _showCastle = true;
  bool _showTelegram = true;
  List<String> _blockedAddonGroups = [];
  List<String> _sourceOrder = [];
  StateSetter? _modalSetState;

  Color? _qualityBadgeColor(String quality) {
    final q = quality.toLowerCase();
    if (q.contains('2160p') || q.contains('4k') || q.contains('uhd') || q.contains('2160')) {
      return const Color(0xFF9C27B0);
    }
    if (q.contains('1080p') || q.contains('fhd') || q.contains('1080')) {
      return const Color(0xFF2196F3);
    }
    if (q.contains('720p') || q.contains('hd') || q.contains('720')) {
      return const Color(0xFF4CAF50);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadSourceVisibilities();
    _loadFavoriteStatus();
    _loadWatchlistState();
    _loadTmdbDetails();
    _checkDownloadStatus();
    _loadWatchProgress();
    _loadTorrentioStreams();
    _resolveAllLiveSources();
  }

  @override
  void setState(VoidCallback fn) {
    if (!mounted) return;
    super.setState(fn);
    if (_modalSetState != null) {
      try {
        _modalSetState!(() {});
      } catch (_) {}
    }
  }

  Future<void> _loadSourceVisibilities() async {
    final prefs = await SharedPreferences.getInstance();
    final cloud = await SyncService.fetchAppSettings();
    if (mounted) {
      setState(() {
        _showVidlink = cloud.containsKey('source_show_vidlink') ? cloud['source_show_vidlink'] == 'true' : (prefs.getBool('source_show_vidlink') ?? true);
        _showNetmirror = cloud.containsKey('source_show_netmirror') ? cloud['source_show_netmirror'] == 'true' : (prefs.getBool('source_show_netmirror') ?? true);
        _showCinemm = cloud.containsKey('source_show_cinemm') ? cloud['source_show_cinemm'] == 'true' : (prefs.getBool('source_show_cinemm') ?? true);
        _showStalker = cloud.containsKey('source_show_stalker') ? cloud['source_show_stalker'] == 'true' : (prefs.getBool('source_show_stalker') ?? true);
        _showStravo = cloud.containsKey('source_show_stravo') ? cloud['source_show_stravo'] == 'true' : (prefs.getBool('source_show_stravo') ?? true);
        _showTorrent = cloud.containsKey('source_show_torrent') ? cloud['source_show_torrent'] == 'true' : (prefs.getBool('source_show_torrent') ?? true);
        _showStremioAddon = (cloud.containsKey('source_show_stremioAddon') ? cloud['source_show_stremioAddon'] == 'true' : (prefs.getBool('source_show_stremioAddon') ?? true)) && (cloud['stremio_addons_enabled'] ?? 'true') == 'true';
        _showNuveoAddon = (cloud.containsKey('source_show_stremioAddon') ? cloud['source_show_stremioAddon'] == 'true' : (prefs.getBool('source_show_stremioAddon') ?? true)) && (cloud['nuveo_addons_enabled'] ?? 'true') == 'true';
        _showCastle = cloud.containsKey('source_show_castle') ? cloud['source_show_castle'] == 'true' : (prefs.getBool('source_show_castle') ?? true);
        _showTelegram = cloud.containsKey('source_show_telegram') ? cloud['source_show_telegram'] == 'true' : (prefs.getBool('source_show_telegram') ?? true);
        _showMoviebox = cloud.containsKey('source_show_moviebox') ? cloud['source_show_moviebox'] == 'true' : (prefs.getBool('source_show_moviebox') ?? true);
        
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
      if (!mergedOrder.contains('moviebox')) mergedOrder.add('moviebox');
      setState(() => _sourceOrder = mergedOrder);
    }
  }

  void _resolveAllLiveSources() {
    final activeId =
        (movie.imdbId != null &&
            movie.imdbId!.isNotEmpty &&
            movie.imdbId != 'null')
        ? movie.imdbId
        : ((movie.tmdbId != null &&
                  movie.tmdbId!.isNotEmpty &&
                  movie.tmdbId != '0' &&
                  movie.tmdbId != 'null')
              ? movie.tmdbId
              : null);

    if (_showVidlink && activeId != null) {
      _resolveLiveVidlink(activeId);
    }

    if (_showNetmirror) _resolveLiveNetmirror(movie.title);
    if (_showCinemm) _resolveLiveCinemm(movie.title);
    if (_showMoviebox) _resolveLiveMoviebox(movie.title);
    if (_showStalker) _resolveLiveStalker(movie.title);

    final imdbId = movie.imdbId;
    if (imdbId != null && imdbId.isNotEmpty && imdbId != 'null') {
      if (_showStravo) _resolveLiveStravo(imdbId);
      if (_showStremioAddon) _resolveLiveStremioAddons(imdbId);
    }

    if (movie.tmdbId != null && movie.tmdbId!.isNotEmpty && movie.tmdbId != '0' && movie.tmdbId != 'null') {
      _resolveLiveNuveoAddons(movie.tmdbId!);
      if (_showCastle) {
        _resolveLiveCastle(movie.tmdbId!);
      }
    }

    if (_showTelegram) {
      _resolveLiveTelegram();
    }
  }

  Future<void> _resolveLiveVidlink(String activeId) async {
    if (mounted) setState(() => _resolvingVidlink = true);
    try {
      final url = 'https://movie-scraper-beige.vercel.app/api?id=$activeId';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rawUrl = data['url'] as String?;
        if (rawUrl != null && rawUrl.isNotEmpty) {
          if (mounted) {
            setState(() {
              _liveVidlinkSources = [
                StreamSource(name: 'VidLink (Native Proxy)', url: rawUrl),
              ];
            });
          }
        }
      }
    } catch (e) {
      debugPrint('VidLink stream resolution failed: $e');
    } finally {
      if (mounted) setState(() => _resolvingVidlink = false);
    }
  }

  Future<void> _resolveLiveNetmirror(String title) async {
    if (mounted) setState(() => _resolvingNetmirror = true);
    try {
      debugPrint('NetMirror: Resolving streams for $title...');
      final streams = await NetmirrorResolver.resolveStreams(title);
      final List<StreamSource> resolved = [];
      for (final s in streams) {
        resolved.add(StreamSource(name: s.name, url: s.url));
      }
      if (mounted) {
        setState(() {
          _liveNetmirrorSources = resolved;
        });
      }
    } catch (e) {
      debugPrint('NetMirror resolution failed: $e');
    } finally {
      if (mounted) setState(() => _resolvingNetmirror = false);
    }
  }

  Future<void> _resolveLiveCinemm(String title) async {
    if (mounted) setState(() => _resolvingCinemm = true);
    try {
      debugPrint('CineMM: Resolving streams for $title...');
      final streams = await CinemmResolver.resolveStreams(
        title: title,
        year: movie.year?.toString(),
      );
      final resolved = streams
          .map((s) => StreamSource(name: s.name, url: s.url, headers: s.headers))
          .toList();
      if (mounted) {
        setState(() {
          _liveCinemmSources = resolved;
        });
      }
    } catch (e) {
      debugPrint('CineMM resolution failed: $e');
    } finally {
      if (mounted) setState(() => _resolvingCinemm = false);
    }
  }

  Future<void> _resolveLiveStalker(String title) async {
    if (mounted) setState(() => _resolvingStalker = true);
    try {
      final url =
          '${ApiService.apiUrl}?action=get_stalker_vod_movies&search=${Uri.encodeComponent(title)}';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = json.decode(responseBody);
        var movies = data['movies'] as List<dynamic>? ?? [];
        var totalItems = data['total_items'] ?? 0;

        debugPrint('StalkerResolver: API returned ${movies.length} movies (total: $totalItems) for "$title"');

        if ((movies.isEmpty || totalItems == 0) && title.isNotEmpty) {
          try {
            final allUrl = '${ApiService.apiUrl}?action=get_stalker_vod_movies&search=${Uri.encodeComponent(title.substring(0, title.length > 3 ? title.length ~/ 2 : title.length))}';
            final allRes = await http.get(Uri.parse(allUrl)).timeout(const Duration(seconds: 8));
            if (allRes.statusCode == 200) {
              final allData = json.decode(utf8.decode(allRes.bodyBytes));
              final allMovies = allData['movies'] as List<dynamic>? ?? [];
              if (allMovies.isNotEmpty) {
                debugPrint('StalkerResolver: Partial-title search returned ${allMovies.length} movies');
                movies = allMovies;
                totalItems = allData['total_items'] ?? 0;
              }
            }
          } catch (_) {}
        }

        if (movies.isEmpty) {
          // Last resort: fetch first page of any category
          try {
            const fallbackUrl = '${ApiService.apiUrl}?action=get_stalker_vod_movies&category=General&page=1';
            final fallRes = await http.get(Uri.parse(fallbackUrl)).timeout(const Duration(seconds: 8));
            if (fallRes.statusCode == 200) {
              final fallData = json.decode(utf8.decode(fallRes.bodyBytes));
              final fallMovies = fallData['movies'] as List<dynamic>? ?? [];
              if (fallMovies.isNotEmpty) {
                debugPrint('StalkerResolver: Fallback (no search) returned ${fallMovies.length} movies');
                movies = fallMovies;
              }
            }
          } catch (_) {}
        }

        final List<StreamSource> sources = [];

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
            final isDup = sources.any(
              (s) => s.url == 'stalker://$portalId$cmd',
            );
            if (!isDup) {
              sources.add(
                StreamSource(
                  name: '$portalName - $name',
                  url: 'stalker://$portalId$cmd',
                ),
              );
            }
          }
        }
        if (mounted) {
          setState(() {
            _liveStalkerSources = sources;
          });
        }
      }
    } catch (e) {
      debugPrint('Stalker VOD database search failed: $e');
    } finally {
      if (mounted) setState(() => _resolvingStalker = false);
    }
  }

  Future<void> _resolveLiveStravo(String imdbId) async {
    if (mounted) setState(() => _resolvingStravo = true);
    try {
      final addonBaseUrl = await SyncService.getStravoUrl();
      var baseUrl = addonBaseUrl.trim();
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      final url = '$baseUrl/stream/movie/$imdbId.json';
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
        final List<StreamSource> sources = [];

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

            final isDup = sources.any((s) => s.url == urlStr);
            if (!isDup) {
              sources.add(
                StreamSource(name: 'Stravo: $cleanName', url: urlStr, headers: headers),
              );
            }
          }
        }
        if (mounted) {
          setState(() {
            _liveStravoSources = sources;
          });
        }
      }
    } catch (e) {
      debugPrint('Stravo streams resolution failed: $e');
    } finally {
      if (mounted) setState(() => _resolvingStravo = false);
    }
  }

  Future<void> _resolveLiveStremioAddons(String imdbId) async {
    if (mounted) setState(() => _resolvingStremio = true);
    try {
      final addonUrls = await SyncService.fetchMergedStremioAddons();
      if (addonUrls.isEmpty) {
        debugPrint('StremioAddonResolver: No addon URLs configured (global + device empty)');
        return;
      }

      final List<Future<List<StremioStream>>> tasks = [];
      for (final url in addonUrls) {
        tasks.add(StremioAddonResolver.fetchStreams(
          manifestUrl: url,
          type: 'movie',
          imdbId: imdbId,
        ));
      }
      final results = await Future.wait(tasks);
      final List<StreamSource> sources = [];
      for (final list in results) {
        for (final item in list) {
          final addonName = (item.addonName ?? '').trim().toLowerCase();
          if (_blockedAddonGroups.any((b) => addonName == b || addonName.contains(b))) {
            continue;
          }
          final isDup = sources.any((s) => s.url == item.url);
          if (!isDup) {
            final metaParts = <String>[item.addonName ?? ''];
            if (item.quality != null && item.quality!.isNotEmpty) metaParts.add(item.quality!);
            if (item.size != null && item.size!.isNotEmpty) metaParts.add(item.size!);
            if (item.languages != null && item.languages!.isNotEmpty) metaParts.add(item.languages!.join(', '));
  sources.add(StreamSource(
    name: metaParts.join(' - '),
    url: item.url,
    headers: item.headers.isNotEmpty ? item.headers : null,
    quality: item.quality,
    qualityBadgeColor: item.quality != null && item.quality!.isNotEmpty ? _qualityBadgeColor(item.quality!) : null,
    qualityBadgeText: item.quality,
  ));
          }
        }
      }
      if (mounted) {
        setState(() {
          _liveStremioSources = sources;
        });
      }
    } catch (e) {
      debugPrint('Stremio addon resolution failed: $e');
    } finally {
      if (mounted) setState(() => _resolvingStremio = false);
    }
  }

  Future<void> _resolveLiveNuveoAddons(String tmdbId) async {
    if (mounted) setState(() => _resolvingNuveo = true);
    try {
      final addons = await SyncService.fetchMergedNuveoAddons();
      if (addons.isEmpty) return;

      final List<Future<List<dynamic>>> tasks = [];
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
            scriptUrl = Uri.parse(manifestUrl).resolve(filename).toString();
          } catch (_) {
            continue;
          }
          tasks.add(WebViewScraperExecutor.runDynamicScraper(
            scraperId: scraperId,
            scraperName: scraperName,
            scriptUrl: scriptUrl,
            tmdbId: tmdbId,
            mediaType: 'movie',
            title: widget.movie.title,
            imdbId: widget.movie.imdbId,
            releaseDate: widget.movie.year != null ? '${widget.movie.year}-01-01' : null,
          ));
        }
      }
      final results = await Future.wait(tasks);
  final List<StreamSource> sources = [];
  for (final list in results) {
    for (final item in list) {
      final addonName = (item.addonName ?? item.name ?? '').toString().trim().toLowerCase();
      if (_blockedAddonGroups.any((b) => addonName == b || addonName.contains(b))) {
        continue;
      }
      final isDup = sources.any((s) => s.url == item.url);
      if (!isDup) {
        final quality = item.quality ?? StremioParser.parseQuality(item.name ?? '', item.originalTitle ?? '');
        final badgeColor = _qualityBadgeColor(quality);
        sources.add(StreamSource(
          name: '${item.addonName ?? item.name}${quality.isNotEmpty ? ' - $quality' : ''}',
          url: item.url,
          headers: item.headers,
          quality: quality,
          qualityBadgeColor: badgeColor,
          qualityBadgeText: quality.toUpperCase(),
        ));
      }
    }
  }
      if (mounted) {
        setState(() {
          _liveNuveoSources = sources;
        });
      }
    } catch (e) {
      debugPrint('Nuveo addon resolution failed: $e');
    } finally {
      if (mounted) setState(() => _resolvingNuveo = false);
    }
  }

  Future<void> _resolveLiveCastle(String tmdbId) async {
    if (mounted) setState(() => _resolvingCastle = true);
    try {
      debugPrint('Castle: Resolving streams for TMDB: $tmdbId...');
      final streams = await WebViewScraperExecutor.runScraper(
        'castle',
        tmdbId,
        'movie',
      );
      final List<StreamSource> resolved = [];
      for (final s in streams) {
        resolved.add(StreamSource(
          name: 'Castle TV - ${s.name}${s.quality != null ? ' - ${s.quality}' : ''}',
          url: s.url,
          headers: s.headers,
        ));
      }
      if (mounted) {
        setState(() {
          _liveCastleSources = resolved;
        });
      }
    } catch (e) {
      debugPrint('Castle resolution failed: $e');
    } finally {
      if (mounted) setState(() => _resolvingCastle = false);
    }
  }

  Future<void> _resolveLiveTelegram() async {
    if (mounted) setState(() => _resolvingTelegram = true);
    try {
      if (!await TelegramService.instance.hasSession) {
        if (mounted) setState(() => _liveTelegramSources = const []);
        return;
      }
      final cfg = await SyncService.fetchTelegramConfig();
      if (!cfg.enabled) {
        if (mounted) setState(() => _liveTelegramSources = const []);
        return;
      }
      if (cfg.apiId != null && cfg.apiHash != null) {
        await TelegramService.instance
            .setCredentials(cfg.apiId, cfg.apiHash);
      }
      await TelegramService.instance.init();
      final query =
          '${movie.title}${movie.year != null ? ' ${movie.year}' : ''}';
      final hits = await TelegramService.instance.search(query);
      if (mounted) {
        setState(() {
          _liveTelegramSources =
              TelegramSources.toStreamSources(hits).cast<StreamSource>();
        });
      }
    } catch (e) {
      debugPrint('Telegram resolution failed: $e');
    } finally {
      if (mounted) setState(() => _resolvingTelegram = false);
    }
  }



  Future<Map<String, int>?> _scrapeTorrentStats(String url) async {
    try {
      final uri = Uri.parse(url);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        client.close();
        final seeders = RegExp(r'seeds?e?r?s?[:\s]+(\d+)', caseSensitive: false).firstMatch(body);
        final peers = RegExp(r'peers?[:\s]+(\d+)', caseSensitive: false).firstMatch(body);
        return {
          'seeders': int.tryParse(seeders?.group(1) ?? '') ?? 0,
          'peers': int.tryParse(peers?.group(1) ?? '') ?? 0,
        };
      }
      client.close();
    } catch (_) {}
    return null;
  }

  Future<void> _loadTorrentioStreams() async {
    // Ensure source order is loaded before checking
    if (_sourceOrder.isEmpty) {
      final order = await SyncService.fetchSourceOrder();
      if (order.isNotEmpty && mounted) setState(() => _sourceOrder = order);
    }
    if (!_showTorrent || !_sourceOrder.contains('torrent')) return;
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
      final addonBaseUrl = await SyncService.getTorrentioUrl();
      var baseUrl = addonBaseUrl.trim();
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }

      final url = '$baseUrl/stream/movie/$imdbId.json';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final streamsList = data['streams'] as List<dynamic>? ?? [];
        final List<StreamSource> torrentSources = [];

        for (final stream in streamsList) {
          final infoHash = stream['infoHash']?.toString() ?? '';
          final directUrl = stream['url']?.toString() ?? '';
          final title = stream['title']?.toString() ?? 'Stream';
          final streamName = stream['name']?.toString() ?? 'Stremio';

          if (directUrl.isNotEmpty) {
            final titleLines = title.split('\n');
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

            // Extract custom headers
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

            final isDup = torrentSources.any((s) => s.url == finalUrl);
            if (!isDup) {
              torrentSources.add(StreamSource(name: sourceName, url: finalUrl));
            }
          } else if (infoHash.isNotEmpty) {
            final trackers = [
              'udp://tracker.coppersurfer.tk:6969/announce',
              'udp://tracker.openbittorrent.com:6969/announce',
              'udp://tracker.opentrackr.org:1337/announce',
              'udp://tracker.leechers-paradise.org:6969/announce',
              'udp://open.stealth.si:80/announce',
              'udp://tracker.tiny-vps.me:6969/announce',
            ];
            final trackersQuery = trackers
                .map((t) => 'tr=${Uri.encodeComponent(t)}')
                .join('&');
            final magnetLink =
                'magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(movie.title)}&$trackersQuery';

            final titleLines = title.split('\n');
            final mainTitle = titleLines.isNotEmpty ? titleLines[0] : 'Torrent';
            final peerInfo = titleLines.length > 1 ? titleLines[1] : '';
            final sizeInfo = titleLines.length > 2 ? titleLines[2] : '';

            var sourceName = 'Torrent: $mainTitle';
            if (peerInfo.isNotEmpty || sizeInfo.isNotEmpty) {
              sourceName +=
                  ' ($peerInfo ${sizeInfo.isNotEmpty ? "• $sizeInfo" : ""})';
            }
            sourceName = sourceName
                .replaceAll('👥', ' Peers:')
                .replaceAll('👤', ' Seeders:')
                .replaceAll('\n', ' ');

            final isDup = torrentSources.any((s) => s.url == magnetLink);
            if (!isDup) {
              torrentSources.add(
                StreamSource(name: sourceName, url: magnetLink),
              );
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

    final addonBaseUrl = await SyncService.getStravoUrl();

    var baseUrl = addonBaseUrl.trim();
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    final url = '$baseUrl/stream/movie/$imdbId.json';
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

          final isDup = stravoSources.any((s) => s.url == urlStr);
          if (!isDup) {
            stravoSources.add(
              StreamSource(name: 'Stravo: $cleanName', url: urlStr, headers: headers),
            );
          }
        }
      }

      _stravoSources = stravoSources;
      return stravoSources;
    } else {
      throw Exception('Server returned status code ${response.statusCode}');
    }
  }

  void _showStravoSourceSelector(
    BuildContext context, {
    bool resumeDirectly = false,
  }) {
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
                            child: CircularProgressIndicator(
                              color: AppColors.accentBright,
                            ),
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
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 13,
                              ),
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
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              source.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white30,
                                fontSize: 11,
                              ),
                            ),
                            tileColor: Colors.white.withValues(alpha: 0.03),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              _playWithResolution(
                                source.url,
                                resumeDirectly: resumeDirectly,
                                sourceName: source.name,
                              );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Added to Watchlist.')));
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
        _watchProviders = [];
      });
      return;
    }

    try {
      // 1. Fetch Credits (Cast & Crew)
      var creditsUrl = Uri.parse(
        'https://api.themoviedb.org/3/movie/$tmdbId/credits?api_key=8baba8ab6b8bbe247645bcae7df63d0d',
      );
      var creditsResponse = await http
          .get(creditsUrl)
          .timeout(const Duration(seconds: 8));

      if (creditsResponse.statusCode == 404) {
        creditsUrl = Uri.parse(
          'https://api.themoviedb.org/3/tv/$tmdbId/credits?api_key=8baba8ab6b8bbe247645bcae7df63d0d',
        );
        creditsResponse = await http
            .get(creditsUrl)
            .timeout(const Duration(seconds: 8));
      }

      // 2. Fetch Details (Rating / Vote Average)
      var detailsUrl = Uri.parse(
        'https://api.themoviedb.org/3/movie/$tmdbId?api_key=8baba8ab6b8bbe247645bcae7df63d0d',
      );
      var detailsResponse = await http
          .get(detailsUrl)
          .timeout(const Duration(seconds: 8));

      if (detailsResponse.statusCode == 404) {
        detailsUrl = Uri.parse(
          'https://api.themoviedb.org/3/tv/$tmdbId?api_key=8baba8ab6b8bbe247645bcae7df63d0d',
        );
        detailsResponse = await http
            .get(detailsUrl)
            .timeout(const Duration(seconds: 8));
      }

      // 3. Fetch Watch Providers (Where to Watch)
      var providersUrl = Uri.parse(
        'https://api.themoviedb.org/3/movie/$tmdbId/watch/providers?api_key=8baba8ab6b8bbe247645bcae7df63d0d',
      );
      var providersResponse = await http
          .get(providersUrl)
          .timeout(const Duration(seconds: 8));

      if (providersResponse.statusCode == 404) {
        providersUrl = Uri.parse(
          'https://api.themoviedb.org/3/tv/$tmdbId/watch/providers?api_key=8baba8ab6b8bbe247645bcae7df63d0d',
        );
        providersResponse = await http
            .get(providersUrl)
            .timeout(const Duration(seconds: 8));
      }

      List<Map<String, dynamic>> flatrateProviders = [];
      if (providersResponse.statusCode == 200) {
        try {
          final pData = json.decode(utf8.decode(providersResponse.bodyBytes)) as Map<String, dynamic>;
          final pResults = pData['results'] as Map<String, dynamic>? ?? {};
          final regionalData = pResults['IN'] as Map<String, dynamic>? ?? pResults['US'] as Map<String, dynamic>?;
          if (regionalData != null) {
            final flatrateList = regionalData['flatrate'] as List<dynamic>? ?? [];
            for (final provider in flatrateList) {
              flatrateProviders.add({
                'name': provider['provider_name']?.toString() ?? '',
                'logo_path': provider['logo_path']?.toString() ?? '',
              });
            }
          }
        } catch (_) {}
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
            parsedCast.add(
              CastMember(
                name: name,
                profileUrl: path.isNotEmpty ? (photoBase + path) : '',
              ),
            );
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

      String? resolvedImdb;
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
        resolvedImdb = data['imdb_id']?.toString();
      }

      if ((resolvedImdb == null || resolvedImdb.isEmpty || resolvedImdb == 'null') && tmdbId != 'null') {
        try {
          final extUrl = Uri.parse('https://api.themoviedb.org/3/movie/$tmdbId/external_ids?api_key=8baba8ab6b8bbe247645bcae7df63d0d');
          final extRes = await http.get(extUrl).timeout(const Duration(seconds: 5));
          if (extRes.statusCode == 200) {
            final extData = json.decode(utf8.decode(extRes.bodyBytes));
            resolvedImdb = extData['imdb_id']?.toString();
          }
        } catch (_) {}
        if (resolvedImdb == null || resolvedImdb.isEmpty || resolvedImdb == 'null') {
          try {
            final extUrl = Uri.parse('https://api.themoviedb.org/3/tv/$tmdbId/external_ids?api_key=8baba8ab6b8bbe247645bcae7df63d0d');
            final extRes = await http.get(extUrl).timeout(const Duration(seconds: 5));
            if (extRes.statusCode == 200) {
              final extData = json.decode(utf8.decode(extRes.bodyBytes));
              resolvedImdb = extData['imdb_id']?.toString();
            }
          } catch (_) {}
        }
      }

      if (resolvedImdb != null && resolvedImdb.isNotEmpty && resolvedImdb != 'null') {
        final currentImdb = movie.imdbId;
        if (currentImdb == null || currentImdb.isEmpty || currentImdb == 'null') {
          _resolveLiveStravo(resolvedImdb);
        }
      }

      if (mounted) {
        setState(() {
          _dynamicCast = cast;
          _dynamicDirector = director ?? movie.director;
          _directorProfileUrl = directorProfile ?? movie.directorPhoto;
          _dynamicRating = rating;
          _dynamicPopularity = popularity;
          _watchProviders = flatrateProviders;
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
          _watchProviders = [];
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

    // Local Telegram streams are direct file resources, not web embeds
    if (lower.contains('127.0.0.1') || lower.contains('localhost') || lower.contains('/tg/')) {
      return false;
    }

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
        _isStreamtapeSource(source))
      return false;
    return _isYoutubeUrl(source.url);
  }

  bool _isMagnetSource(StreamSource source) {
    return source.url.toLowerCase().startsWith('magnet:') ||
        source.name.toLowerCase() == 'torrent (magnet)';
  }

  bool _isCustomMagnet(StreamSource source) {
    return movie.streamSources.any(
      (s) =>
          s.url == source.url &&
          (s.url.toLowerCase().startsWith('magnet:') ||
              s.name.toLowerCase() == 'torrent (magnet)'),
    );
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

  void _play(
    String source, {
    bool resumeDirectly = false,
    Map<String, String>? headers,
    String? originalEmbedUrl,
    String? sourceName,
  }) async {
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
          sourceName: sourceName,
        ),
      ),
    );

    _loadWatchProgress();

    if (failed == true && originalEmbedUrl != null && mounted) {
      final tryWeb = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Playback Failed',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Try Web Player',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
    final streamtapeSources = originalSources
        .where((src) => _isStreamtapeSource(src))
        .toList();

    // 2. Identify YouTube sources
    final youtubeSources = originalSources
        .where((src) => _isYoutubeSource(src))
        .toList();

    // 3. Create VidLink source if ID is available
    StreamSource? vidlinkSource;
    final imdbId = movie.imdbId;
    final tmdbId = movie.tmdbId;
    final activeId = (imdbId != null && imdbId.isNotEmpty && imdbId != 'null')
        ? imdbId
        : ((tmdbId != null &&
                  tmdbId.isNotEmpty &&
                  tmdbId != '0' &&
                  tmdbId != 'null')
              ? tmdbId
              : null);

    if (activeId != null) {
      vidlinkSource = StreamSource(
        name: 'VidLink (Native Proxy)',
        url: 'https://movie-scraper-beige.vercel.app/api?id=$activeId',
      );
    }

    // 4. Identify Embed / Web player sources
    final embedSources = originalSources
        .where((src) => _isEmbedSource(src))
        .toList();

    // 5. Identify Custom Magnet sources
    final customMagnets = originalSources
        .where((src) => _isMagnetSource(src))
        .toList();

    // 6. Identify MP4/MKV sources (neither streamtape, youtube, vidlink, embed, nor magnet)
    final mp4Sources = originalSources
        .where(
          (src) =>
              !_isStreamtapeSource(src) &&
              !_isYoutubeSource(src) &&
              !_isEmbedSource(src) &&
              !_isMagnetSource(src),
        )
        .toList();

    final List<StreamSource> result = [];
    result.addAll(mp4Sources);
    result.addAll(streamtapeSources);
    result.addAll(youtubeSources);
    if (vidlinkSource != null) {
      result.add(vidlinkSource);
    }
    final hasImdb = imdbId != null && imdbId.isNotEmpty && imdbId != 'null';
    if (hasImdb) {
      result.add(
        const StreamSource(name: 'Stravo Streams', url: 'stravo_placeholder'),
      );
    }
    if (_torrentioSources.isNotEmpty || customMagnets.isNotEmpty) {
      result.add(
        const StreamSource(name: 'Torrent Streams', url: 'torrent_placeholder'),
      );
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
      final isAlist =
          uri.host.contains('koyeb.app') ||
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
    var match = RegExp(
      r'(?:streamtape\.[a-z]+|strcloud\.[a-z]+)/[ve]/([a-zA-Z0-9]+)',
    ).firstMatch(url);
    if (match != null) return match.group(1);

    final isNameStreamtape =
        sourceName != null &&
        (sourceName.toLowerCase().contains('streamtape') ||
            sourceName.toLowerCase().contains('strcloud'));
    if (isNameStreamtape ||
        url.toLowerCase().contains('streamtape') ||
        url.toLowerCase().contains('strcloud')) {
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
      'api.streamtape.net',
    ];

    Future<http.Response> getWithRetry(
      String fetchUrl, {
      int maxAttempts = 3,
    }) async {
      Object? lastError;
      for (int i = 0; i < maxAttempts; i++) {
        try {
          debugPrint('Streamtape resolve attempt ${i + 1} fetching...');
          final res = await http
              .get(
                Uri.parse(fetchUrl),
                headers: {
                  'Connection': 'close',
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                },
              )
              .timeout(const Duration(seconds: 8));
          return res;
        } catch (e) {
          lastError = e;
          debugPrint('Streamtape resolve attempt ${i + 1} failed: $e');
          if (i < maxAttempts - 1) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }
      throw lastError ??
          Exception('Request failed after $maxAttempts attempts');
    }

    for (final domain in apiDomains) {
      try {
        debugPrint('Attempting Streamtape resolve via $domain');
        // 1. Get download ticket client-side
        final ticketUrl =
            'https://$domain/file/dlticket?file=$fileId&login=$_streamtapeLogin&key=$_streamtapeKey';
        final ticketRes = await getWithRetry(ticketUrl);
        if (ticketRes.statusCode != 200) {
          throw Exception(
            'Failed to fetch ticket (HTTP ${ticketRes.statusCode})',
          );
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
          throw Exception(
            'Failed to fetch download link (HTTP ${dlRes.statusCode})',
          );
        }
        final dlData = json.decode(dlRes.body);
        if (dlData['status'] == 200 &&
            dlData['result'] != null &&
            dlData['result']['url'] != null) {
          final streamUrl = dlData['result']['url'] as String;
          debugPrint(
            'Streamtape resolved successfully via $domain -> $streamUrl',
          );
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

  Future<void> _playWithResolution(
    String source, {
    bool resumeDirectly = false,
    String? sourceName,
    bool forceNative = false,
    bool forceWeb = false,
    Map<String, String>? headers,
  }) async {
    source = _sanitizeUrl(source);

    // Telegram Saved-Message file: resolve to a streamable URL first.
    if (TelegramSources.isTelegramUrl(source)) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return ResolvingProgressDialog(
            title: movie.title,
            subtitle: 'Connecting to Telegram Server...',
          );
        },
      );

      try {
        final localId = TelegramSources.extractLocalId(source);
        final items = await TelegramIndexDb.instance.all().catchError((_) => <TelegramVideoItem>[]);
        TelegramVideoItem? match;
        for (final i in items) {
          if (i.localId == localId) {
            match = i;
            break;
          }
        }
        if (match == null) {
          // Not in cache → try to refresh and re-search.
          await TelegramService.instance.loadSavedMessages();
          final items2 = await TelegramIndexDb.instance.all();
          for (final i in items2) {
            if (i.localId == localId) {
              match = i;
              break;
            }
          }
        }

        if (mounted) Navigator.of(context).pop(); // Dismiss progress dialog

        if (match == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Telegram file not found locally. Open Settings → Telegram → Sync Telegram Server.'),
              backgroundColor: Color(0xFFEF4444),
            ));
          }
          return;
        }

        final resolved = await TelegramService.instance.resolveStream(match);
        // Re-enter playback with the resolved URL.
        return _playWithResolution(
          resolved,
          resumeDirectly: resumeDirectly,
          sourceName: 'mp4/mkv',
          forceNative: true,
          forceWeb: false,
          headers: headers,
        );
      } catch (e) {
        if (mounted) Navigator.of(context).pop(); // Dismiss progress dialog
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Telegram resolve failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ));
        }
        return;
      }
    }

    if (source.startsWith('magnet:')) {
      // Show dialog IMMEDIATELY before any async
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SeedrCountdownDialog(title: movie.title),
      );
      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        final seedrToken = prefs.getString('seedr_auth_token');
        if (seedrToken != null && seedrToken.isNotEmpty && WebTorrentService.isUnderLimit(source)) {
          try {
            final downloadUrl = await WebTorrentService.startTorrent(source,
                authToken: seedrToken, name: movie.title);
            if (mounted) Navigator.of(context).pop();
            if (downloadUrl != null && mounted) {
              // Audio/quality selection handled in-player via top bar menus
              _play(downloadUrl, resumeDirectly: resumeDirectly, headers: headers);
              return;
            }
          } catch (e) {
            if (mounted) Navigator.of(context).pop();
            debugPrint('Seedr error: $e');
          }
        } else {
          if (mounted) Navigator.of(context).pop();
        }
        // Fallback to WebView
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
    final isStalkerVod =
        source.startsWith('stalker://') ||
        (sourceName != null &&
            (sourceName.toLowerCase() == 'stalker vod' ||
                sourceName.toLowerCase().contains('stalker')));
    if (isStalkerVod) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return ResolvingProgressDialog(
            title: movie.title,
            subtitle: 'Connecting to Stalker VOD Portal...',
          );
        },
      );

      final params = StalkerResolver.parseStalkerUrl(source);
      try {
        final stalkerStream = await StalkerResolver.resolveStream(
          params.cmd,
          params.portalId,
          isLive: false,
        );
        if (mounted) Navigator.of(context).pop(); // Dismiss progress

        _play(
          stalkerStream.url,
          resumeDirectly: resumeDirectly,
          headers: stalkerStream.headers,
          sourceName: 'Stalker',
        );
      } catch (e) {
        if (mounted) Navigator.of(context).pop(); // Dismiss progress
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Stalker VOD failed (Portal ${params.portalId}, cmd: ${params.cmd}): $e',
              ),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 8),
            ),
          );
        }
      }
      return;
    }

    // Intercept Streamtape or Strcloud links to resolve natively completely in-app
    final lowerSource = source.toLowerCase();
    final isStreamtape =
        lowerSource.contains('streamtape.com') ||
        lowerSource.contains('strcloud.club') ||
        (sourceName != null &&
            (sourceName.toLowerCase().contains('streamtape') ||
                sourceName.toLowerCase().contains('strcloud')));
    if (isStreamtape) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return ResolvingProgressDialog(
            title: movie.title,
            subtitle: 'Bypassing Streamtape Scrapers...',
          );
        },
      );

      try {
        final resolved = await _resolveStreamtape(
          source,
          sourceName: sourceName,
        );
        if (mounted) Navigator.of(context).pop(); // Dismiss progress

        if (resolved != null && resolved.isNotEmpty) {
          _play(
            resolved,
            resumeDirectly: resumeDirectly,
            headers: {
              'Referer': 'https://streamtape.com/',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
          );
        } else {
          throw Exception(
            'Failed to resolve Streamtape direct URL. Please check your credentials.',
          );
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

    final isScraper =
        source.contains('movie-scraper-beige.vercel.app') ||
        source.contains('movie-scraper-beige.vercel.app');
    if (isScraper) {
      final vidlinkTmdbId =
          (movie.tmdbId != null &&
              movie.tmdbId!.isNotEmpty &&
              movie.tmdbId != '0' &&
              movie.tmdbId != 'null')
          ? movie.tmdbId
          : movie.imdbId;
      final targetEmbedUrl = 'https://vidlink.pro/movie/$vidlinkTmdbId';

      try {
        debugPrint(
          'Resolving VidLink stream in background from: $targetEmbedUrl',
        );
        final resolvedUrl = await EmbedResolver.resolve(
          context,
          targetEmbedUrl,
        );

        if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
          final headers = {
            'Referer': 'https://vidlink.pro/',
            'Origin': 'https://vidlink.pro',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          };
          debugPrint('VidLink: Resolved stream natively: $resolvedUrl');
          _play(
            resolvedUrl,
            resumeDirectly: resumeDirectly,
            headers: headers,
            originalEmbedUrl: targetEmbedUrl,
          );
        } else {
          throw Exception('Failed to resolve stream in background');
        }
      } catch (e) {
        debugPrint(
          'VidLink native resolution failed: $e. Falling back to on-screen Web Player...',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'VidLink native resolver failed. Launching Web Player...',
              ),
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
              const SnackBar(
                content: Text(
                  'Could not load YouTube stream. Please try again.',
                ),
              ),
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
        final headers = EmbedResolver.getHeadersForUrl(
          resolvedUrl,
          fallbackHeaders: {
            'Referer': 'https://vidsrcme.ru/',
            'Origin': 'https://vidsrcme.ru',
          },
        );
        _play(
          resolvedUrl,
          resumeDirectly: resumeDirectly,
          headers: headers,
          originalEmbedUrl: source,
        );
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
            final headers = EmbedResolver.getHeadersForUrl(
              interceptedUrl,
              fallbackHeaders: {
                'Referer': 'https://vidsrcme.ru/',
                'Origin': 'https://vidsrcme.ru',
              },
            );
            _play(
              interceptedUrl,
              resumeDirectly: resumeDirectly,
              headers: headers,
              originalEmbedUrl: source,
            );
          }
        }
      }
    } else {
      final isLocalTelegram = source.contains('127.0.0.1') || source.contains('localhost') || source.contains('/tg/');
      final isStalkerOrDirect = (sourceName != null && sourceName.toLowerCase().contains('stalker')) || headers != null;

      String playUrl = source;
      Map<String, String>? playHeaders = headers;

      if (!isLocalTelegram && !isStalkerOrDirect) {
        // Show resolving dialog
        if (mounted) {
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => ResolvingProgressDialog(
              title: movie.title,
              subtitle: 'Resolving stream...',
            ),
          );
        }
        final result = await runHlsPreflight(
          context: context,
          url: source,
          movieTitle: movie.title,
          headers: headers,
        );
        if (mounted) Navigator.of(context).pop();
        if (result?.url != null) {
          playUrl = result!.url;
        }
      }

      final uri = Uri.tryParse(playUrl);
      final Map<String, String> finalHeaders = {};
      if (playHeaders != null) {
        finalHeaders.addAll(playHeaders);
      }
      if (uri != null && uri.queryParameters.containsKey('headers')) {
        try {
          final jsonHeaders = json.decode(uri.queryParameters['headers']!);
          if (jsonHeaders is Map) {
            jsonHeaders.forEach((k, v) {
              finalHeaders[k.toString()] = v.toString();
            });
          }
        } catch (e) {
          debugPrint('Failed to parse stream headers: $e');
        }
      }

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoPlayerScreen(
              videoSource: playUrl,
              title: movie.title,
              subtitle: sourceName ?? 'Stalker Portal',
              movieId: movie.id,
              resumeDirectly: resumeDirectly,
              headers: finalHeaders.isEmpty ? null : finalHeaders,
              sourceName: sourceName,
            ),
          ),
        );
      }
    }
  }

  void _showSourceSelector({bool resumeDirectly = false}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            _modalSetState = setModalState;

            final dbMp4Sources = movie.streamSources
                .where(
                  (src) =>
                      !_isStreamtapeSource(src) &&
                      !_isYoutubeSource(src) &&
                      !_isEmbedSource(src) &&
                      !_isMagnetSource(src),
                )
                .toList();

            final dbStreamtapeSources = movie.streamSources
                .where((src) => _isStreamtapeSource(src))
                .toList();

            final customMagnets = movie.streamSources
                .where(_isMagnetSource)
                .toList();

            // Build order lookup from admin panel settings
            final Set<String> enabledKeys = _sourceOrder.toSet();
            final Map<String, int> orderPos = {};
            for (int i = 0; i < _sourceOrder.length; i++) {
              orderPos[_sourceOrder[i]] = i + 1;
            }
            int pos(String key) => orderPos[key] ?? 99;

            final Map<String, Widget> sourceWidgets = {};

            // 2. Vidlink Server
            if ((_resolvingVidlink || _liveVidlinkSources.isNotEmpty) && enabledKeys.contains('vidlink')) {
              sourceWidgets['vidlink'] = _buildSourceTile(
                icon: Icons.play_arrow_rounded,
                title: '${pos('vidlink')}. Vidlink Server',
                subtitle: _resolvingVidlink
                    ? 'Checking live...'
                    : '1 native link available',
                disabled: _resolvingVidlink,
                onTap: () {
                  Navigator.of(context).pop();
                  _playWithResolution(
                    _liveVidlinkSources.first.url,
                    resumeDirectly: resumeDirectly,
                    sourceName: _liveVidlinkSources.first.name,
                  );
                },
              );
            }

            // 3. NetMirror Server
            if ((_resolvingNetmirror || _liveNetmirrorSources.isNotEmpty) && enabledKeys.contains('netmirror')) {
              sourceWidgets['netmirror'] = _buildSourceTile(
                icon: Icons.language_rounded,
                title: '${pos('netmirror')}. NetMirror Server',
                subtitle: _resolvingNetmirror
                    ? 'Searching NetMirror...'
                    : '${_liveNetmirrorSources.length} links available',
                disabled: _resolvingNetmirror,
                onTap: () {
                  Navigator.of(context).pop();
                  if (_liveNetmirrorSources.length == 1) {
                    _playNetmirrorStream(
                      _liveNetmirrorSources.first,
                      resumeDirectly: resumeDirectly,
                    );
                  } else {
                    _showNetmirrorSubSelector(
                      _liveNetmirrorSources,
                      resumeDirectly: resumeDirectly,
                    );
                  }
                },
              );
            }

            // 5. CineMM Server
            if ((_resolvingCinemm || _liveCinemmSources.isNotEmpty) && enabledKeys.contains('cinemm')) {
              sourceWidgets['cinemm'] = _buildSourceTile(
                icon: Icons.local_movies_rounded,
                title: '${pos('cinemm')}. CineMM Server',
                subtitle: _resolvingCinemm
                    ? 'Searching CineMM...'
                    : '${_liveCinemmSources.length} links available',
                disabled: _resolvingCinemm,
                onTap: () {
                  Navigator.of(context).pop();
                  if (_liveCinemmSources.length == 1) {
                    _playWithResolution(
                      _liveCinemmSources.first.url,
                      resumeDirectly: resumeDirectly,
                      sourceName: _liveCinemmSources.first.name,
                      headers: _liveCinemmSources.first.headers,
                    );
                  } else {
                    _showSubSourceSelector(
                      context,
                      'CINEMM STREAMS',
                      _liveCinemmSources,
                      resumeDirectly: resumeDirectly,
                    );
                  }
                },
              );
            }

            // MovieBox Server
            if ((_resolvingMoviebox || _liveMovieboxSources.isNotEmpty) && enabledKeys.contains('moviebox')) {
              sourceWidgets['moviebox'] = _buildSourceTile(
                icon: Icons.movie_filter_rounded,
                title: '${pos('moviebox')}. MovieBox Server',
                subtitle: _resolvingMoviebox
                    ? 'Searching MovieBox...'
                    : '${_liveMovieboxSources.length} links available',
                disabled: _resolvingMoviebox,
                onTap: () {
                  Navigator.of(context).pop();
                  if (_liveMovieboxSources.length == 1) {
                    _playWithResolution(
                      _liveMovieboxSources.first.url,
                      resumeDirectly: resumeDirectly,
                      sourceName: _liveMovieboxSources.first.name,
                      headers: _liveMovieboxSources.first.headers,
                    );
                  } else {
                    _showSubSourceSelector(
                      context,
                      'MOVIEBOX STREAMS',
                      _liveMovieboxSources,
                      resumeDirectly: resumeDirectly,
                    );
                  }
                },
              );
            }

            // 6. Stalker VOD Server
            if ((_resolvingStalker || _liveStalkerSources.isNotEmpty) && enabledKeys.contains('stalker')) {
              final uniquePortals = _liveStalkerSources.map((s) {
                final stripped = s.url.replaceAll('stalker://', '');
                final portalMatch = RegExp(r'^(\d+)').firstMatch(stripped);
                return portalMatch?.group(1) ?? '1';
              }).toSet();

              sourceWidgets['stalker'] = _buildSourceTile(
                icon: Icons.movie_filter_rounded,
                title: uniquePortals.length > 1
                    ? '${pos('stalker')}. Stalker VOD Servers'
                    : '${pos('stalker')}. Stalker VOD Server',
                subtitle: _resolvingStalker
                    ? 'Searching Portal...'
                    : '${_liveStalkerSources.length} links available',
                disabled: _resolvingStalker,
                onTap: () {
                  Navigator.of(context).pop();
                  if (uniquePortals.length > 1) {
                    _showStalkerGroupedSelector(
                      context,
                      _liveStalkerSources,
                      resumeDirectly: resumeDirectly,
                    );
                  } else {
                    _showSubSourceSelector(
                      context,
                      'STALKER VOD STREAMS',
                      _liveStalkerSources,
                      resumeDirectly: resumeDirectly,
                    );
                  }
                },
              );
            }

            // 7. Stravo Server
            if ((_resolvingStravo || _liveStravoSources.isNotEmpty) && enabledKeys.contains('stravo')) {
              sourceWidgets['stravo'] = _buildSourceTile(
                icon: Icons.rocket_launch_rounded,
                title: '${pos('stravo')}. Stravo Server',
                subtitle: _resolvingStravo
                    ? 'Searching streams...'
                    : '${_liveStravoSources.length} links available',
                disabled: _resolvingStravo,
                onTap: () {
                  Navigator.of(context).pop();
                  _showSubSourceSelector(
                    context,
                    'STRAVO STREAMS',
                    _liveStravoSources,
                    resumeDirectly: resumeDirectly,
                  );
                },
              );
            }

            // 8. Torrent Server
            final totalTorrents = _torrentioSources.length + customMagnets.length;
            if (totalTorrents > 0 && enabledKeys.contains('torrent')) {
              sourceWidgets['torrent'] = _buildSourceTile(
                icon: Icons.cloud_circle_rounded,
                title: '${pos('torrent')}. Torrent Server',
                subtitle: '$totalTorrents links available',
                disabled: false,
                onTap: () {
                  Navigator.of(context).pop();
                  _showTorrentSourceSelector([
                    ...customMagnets.where((s) => _isUnderLimitBySize(s)),
                    ..._torrentioSources.where((s) => _isUnderLimitBySize(s)),
                  ], resumeDirectly: resumeDirectly);
                },
              );
            }

            // 9. Stremio Addons
            if ((_resolvingStremio || _liveStremioSources.isNotEmpty) && enabledKeys.contains('stremioAddon')) {
              sourceWidgets['stremioAddon'] = _buildSourceTile(
                icon: Icons.extension_rounded,
                title: '${pos('stremioAddon')}. Stremio Addons',
                subtitle: _resolvingStremio
                    ? 'Searching...'
                    : '${_liveStremioSources.length} links available',
                disabled: _resolvingStremio,
                onTap: () {
                  Navigator.of(context).pop();
                  _showAddonGroupedSelector(
                    context,
                    'STREMIO ADDON STREAMS',
                    _liveStremioSources,
                    resumeDirectly: resumeDirectly,
                  );
                },
              );
            }

            // Nuveo Addons (uses stremioAddon key)
            if ((_resolvingNuveo || _liveNuveoSources.isNotEmpty) && enabledKeys.contains('stremioAddon')) {
              sourceWidgets['nuveoAddon'] = _buildSourceTile(
                icon: Icons.auto_awesome_rounded,
                title: '${pos('stremioAddon')}. Nuveo Addons',
                subtitle: _resolvingNuveo
                    ? 'Searching...'
                    : '${_liveNuveoSources.length} links available',
                disabled: _resolvingNuveo,
                onTap: () {
                  Navigator.of(context).pop();
                  _showAddonGroupedSelector(
                    context,
                    'NUVEO ADDON STREAMS',
                    _liveNuveoSources,
                    resumeDirectly: resumeDirectly,
                  );
                },
              );
            }
 
            // Castle Server
            if ((_resolvingCastle || _liveCastleSources.isNotEmpty) && enabledKeys.contains('castle')) {
              sourceWidgets['castle'] = _buildSourceTile(
                icon: Icons.castle_rounded,
                title: '${pos('castle')}. Castle TV Server',
                subtitle: _resolvingCastle
                    ? 'Searching Castle...'
                    : '${_liveCastleSources.length} links available',
                disabled: _resolvingCastle,
                onTap: () {
                  Navigator.of(context).pop();
                  if (_liveCastleSources.length == 1) {
                    _playWithResolution(
                      _liveCastleSources.first.url,
                      resumeDirectly: resumeDirectly,
                      sourceName: _liveCastleSources.first.name,
                      headers: _liveCastleSources.first.headers,
                    );
                  } else {
                    _showSubSourceSelector(
                      context,
                      'CASTLE TV STREAMS',
                      _liveCastleSources,
                      resumeDirectly: resumeDirectly,
                    );
                  }
                },
              );
            }

             // Telegram Server
             if ((_resolvingTelegram || _liveTelegramSources.isNotEmpty) && enabledKeys.contains('telegram')) {
               sourceWidgets['telegram'] = _buildSourceTile(
                 icon: Icons.send_rounded,
                 title: '${pos('telegram')}. Telegram Server',
                 subtitle: _resolvingTelegram
                     ? 'Searching Telegram...'
                     : (_liveTelegramSources.isEmpty
                         ? 'No files found'
                         : '${_liveTelegramSources.length} files in Telegram Server'),
                 disabled: _resolvingTelegram || _liveTelegramSources.isEmpty,
                 onTap: () {
                   Navigator.of(context).pop();
                   if (_liveTelegramSources.length == 1) {
                     final s = _liveTelegramSources.first;
                     _playWithResolution(
                       s.url,
                       resumeDirectly: resumeDirectly,
                       sourceName: s.name,
                       headers: s.headers,
                     );
                   } else {
                     _showSubSourceSelector(
                       context,
                       'TELEGRAM SERVER',
                       _liveTelegramSources,
                       resumeDirectly: resumeDirectly,
                     );
                   }
                 },
              );
            }
 

 
            final List<Widget> items = [];
 
            // 1. Direct MP4/MKV Link (always shown at top if exist)
            if (dbMp4Sources.isNotEmpty) {
              items.add(
                _buildSourceTile(
                  icon: Icons.video_file_rounded,
                  title: 'Direct MP4/MKV Link',
                  subtitle: dbMp4Sources.length == 1
                      ? dbMp4Sources.first.name
                      : '${dbMp4Sources.length} files available',
                  disabled: false,
                  onTap: () {
                    Navigator.of(context).pop();
                    if (dbMp4Sources.length == 1) {
                      _playWithResolution(
                        dbMp4Sources.first.url,
                        resumeDirectly: resumeDirectly,
                        sourceName: dbMp4Sources.first.name,
                      );
                    } else {
                      _showSubSourceSelector(
                        context,
                        'MP4/MKV DIRECT FILES',
                        dbMp4Sources,
                        resumeDirectly: resumeDirectly,
                      );
                    }
                  },
                ),
              );
            }
 
            // 4. Streamtape Server (always shown at top if exist)
            if (dbStreamtapeSources.isNotEmpty) {
              items.add(
                _buildSourceTile(
                  icon: Icons.folder_shared_rounded,
                  title: 'Streamtape Server',
                  subtitle: dbStreamtapeSources.length == 1
                      ? dbStreamtapeSources.first.name
                      : '${dbStreamtapeSources.length} files available',
                  disabled: false,
                  onTap: () {
                    Navigator.of(context).pop();
                    if (dbStreamtapeSources.length == 1) {
                      _playWithResolution(
                        dbStreamtapeSources.first.url,
                        resumeDirectly: resumeDirectly,
                        sourceName: dbStreamtapeSources.first.name,
                      );
                    } else {
                      _showSubSourceSelector(
                        context,
                        'STREAMTAPE STREAMS',
                        dbStreamtapeSources,
                        resumeDirectly: resumeDirectly,
                      );
                    }
                  },
                ),
              );
            }
 
            // Dynamically append other sources in sorted visibility order
            for (final key in _sourceOrder) {
              if (key == 'stremioAddon') {
                if (sourceWidgets.containsKey('stremioAddon') && enabledKeys.contains('stremioAddon')) {
                  items.add(sourceWidgets['stremioAddon']!);
                }
                if (sourceWidgets.containsKey('nuveoAddon') && enabledKeys.contains('stremioAddon')) {
                  items.add(sourceWidgets['nuveoAddon']!);
                }
              } else {
                if (sourceWidgets.containsKey(key) && enabledKeys.contains(key)) {
                  items.add(sourceWidgets[key]!);
                }
              }
            }
 
            if (items.isEmpty) {
              final resolvingAny = _resolvingVidlink || _resolvingNetmirror || _resolvingCinemm || _resolvingStalker || _resolvingStravo || _resolvingStremio || _resolvingNuveo || _resolvingCastle;
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (resolvingAny) ...[
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        const Text('Searching online sources...', style: TextStyle(color: Colors.white70)),
                      ] else ...[
                        const Icon(Icons.sentiment_dissatisfied_rounded, color: Colors.white38, size: 40),
                        const SizedBox(height: 12),
                        const Text('No active stream servers found.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ]
                    ],
                  ),
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
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
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => items[index],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      _modalSetState = null;
    });
  }

  Widget _buildSourceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool disabled,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: disabled ? Colors.white24 : AppColors.accentBright,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: disabled ? Colors.white30 : Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: disabled ? Colors.white24 : Colors.white54,
          fontSize: 11.5,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: disabled ? Colors.white10 : Colors.white54,
      ),
      tileColor: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: disabled ? null : onTap,
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

  void _showNetmirrorSubSelector(
    List<StreamSource> sources, {
    bool resumeDirectly = false,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'NETMIRROR STREAMS',
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
                        leading: _getOttLogo(source.name, size: 28),
                        title: Text(
                          source.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        tileColor: Colors.white.withValues(alpha: 0.03),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _playNetmirrorStream(
                            source,
                            resumeDirectly: resumeDirectly,
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

  /// Plays a NetMirror stream with full HLS pre-flight: audio language + quality selection + headers
  Future<void> _playNetmirrorStream(
    StreamSource source, {
    bool resumeDirectly = false,
  }) async {
    try {
      final uri = Uri.parse(source.url);
      final Map<String, String> headers = {};
      if (uri.queryParameters.containsKey('headers')) {
        final jsonHeaders = json.decode(uri.queryParameters['headers']!);
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
            title: movie.title,
            subtitle: 'NetMirror Server',
            movieId: movie.id,
            resumeDirectly: resumeDirectly,
            headers: headers.isNotEmpty ? headers : null,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playback failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _showSubSourceSelector(
    BuildContext context,
    String title,
    List<StreamSource> sources, {
    bool resumeDirectly = false,
  }) {
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
                  title,
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
                        return StreamMetadataTile(
                          name: source.name,
                          url: source.url,
                          headers: source.headers,
                          isSelected: false,
                          onTap: () {
                            Navigator.of(context).pop();
                            _playWithResolution(
                              source.url,
                              resumeDirectly: resumeDirectly,
                              sourceName: source.name,
                              headers: source.headers,
                            );
                          },
                          onLongPress: () {
                            Clipboard.setData(ClipboardData(text: source.url));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied Link: ${source.url}'),
                                duration: const Duration(seconds: 2),
                              ),
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

  Future<String?> _showLanguagePicker(BuildContext context) async {
    final langs = ['Hindi', 'English', 'Tamil', 'Telugu', 'Malayalam', 'Kannada', 'Bengali', 'Punjabi'];
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Select Audio', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: langs.length,
            itemBuilder: (_, i) => ListTile(
              leading: const Icon(Icons.audiotrack_rounded, color: Colors.white54),
              title: Text(langs[i], style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.of(ctx).pop(langs[i]),
            ),
          ),
        ),
      ),
    );
  }

  bool _isUnderLimitBySize(StreamSource s) {
    final name = s.name.toLowerCase();
    final match = RegExp(r'([\d.]+)\s*(gb|gib)').firstMatch(name);
    if (match == null) return true;
    final gb = double.tryParse(match.group(1)!) ?? 0;
    return gb <= 4;
  }

  void _showStalkerGroupedSelector(
    BuildContext context,
    List<StreamSource> sources, {
    bool resumeDirectly = false,
  }) {
    // Group sources by portal ID extracted from url
    final Map<String, List<StreamSource>> grouped = {};
    for (final s in sources) {
      final stripped = s.url.replaceAll('stalker://', '');
      final portalMatch = RegExp(r'^(\d+)').firstMatch(stripped);
      final portalId = portalMatch?.group(1) ?? '1';
      grouped.putIfAbsent(portalId, () => []);
      grouped[portalId]!.add(s);
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final allEntries = grouped.entries.toList();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'STALKER VOD SERVERS',
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
                    itemCount: allEntries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, groupIdx) {
                      final entry = allEntries[groupIdx];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 6),
                            child: Text(
                              'Portal ${entry.key}',
                              style: GoogleFonts.outfit(
                                color: AppColors.accentBright,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ...entry.value.map((source) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              leading: Icon(
                                Icons.play_circle_outline_rounded,
                                color: AppColors.accentBright,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      source.name.replaceAll(RegExp(r'[-_.]?[tT][gG]\b'), '').replaceAll(RegExp(r'\[[tT][gG]\]'), '').replaceAll(RegExp(r'\b[tT][gG]\b'), '').replaceAll(RegExp(r'\s+'), ' ').trim(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    source.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white30,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              tileColor: Colors.white.withValues(alpha: 0.03),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onTap: () {
                                Navigator.of(context).pop();
                                _playWithResolution(
                                  source.url,
                                  resumeDirectly: resumeDirectly,
                                  sourceName: source.name,
                                  headers: source.headers,
                                );
                              },
                            ),
                          )),
                        ],
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

  void _showAddonGroupedSelector(
    BuildContext context,
    String title,
    List<StreamSource> sources, {
    bool resumeDirectly = false,
  }) {
    // Parse metadata and build nested grouping: addon -> site -> streams
    final Map<String, Map<String, List<StreamSource>>> nested = {};
    for (final s in sources) {
      final meta = parseStreamMeta(s.name, s.url);
      final parts = s.name.contains(' - ') ? s.name.split(' - ') : [s.name];
      final addonName = meta.site.isNotEmpty ? parts.first : s.name;
      final siteName = meta.site.isNotEmpty ? meta.site : (parts.length > 1 ? parts.last : 'Stream');

      nested.putIfAbsent(addonName, () => {});
      nested[addonName]!.putIfAbsent(siteName, () => []);
      nested[addonName]![siteName]!.add(s);
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final addonEntries = nested.entries.toList();

        // If only one addon with one site → show flat source list
        bool onlyOne = addonEntries.length == 1 && addonEntries.first.value.length == 1;
        if (onlyOne) {
          final streams = addonEntries.first.value.values.first;
          if (streams.length <= 2) {
            return SafeArea(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(title, style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                const SizedBox(height: 16),
                Flexible(child: _buildFlatSourceList(streams, resumeDirectly)),
              ]),
            ));
          }
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: addonEntries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final addonEntry = addonEntries[i];
                      final siteEntries = addonEntry.value.entries.toList();
                      final totalLinks = siteEntries.fold(0, (s, e) => s + e.value.length);
                      return Container(
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
                        child: ExpansionTile(
                          shape: const Border(), collapsedShape: const Border(),
                          iconColor: AppColors.accentBright, collapsedIconColor: Colors.white38,
                          initiallyExpanded: i == 0,
                          title: Text(addonEntry.key, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text('$totalLinks links across ${siteEntries.length} source(s)', style: TextStyle(color: Colors.white38, fontSize: 11)),
                          children: siteEntries.map((siteEntry) {
                            final streams = siteEntry.value;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (siteEntries.length > 1)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                    child: Text(siteEntry.key, style: GoogleFonts.outfit(color: AppColors.accentBright, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                  ),
                                ...streams.map((s) => Padding(
                                  padding: EdgeInsets.only(left: siteEntries.length > 1 ? 8 : 0),
                                  child: StreamMetadataTile(
                                    name: s.name, url: s.url, headers: s.headers,
                                    onTap: () {
                                      Navigator.of(ctx).pop();
                                      _playWithResolution(s.url, resumeDirectly: resumeDirectly, sourceName: s.name, headers: s.headers);
                                    },
                                  ),
                                )),
                              ],
                            );
                          }).toList(),
                        ),
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

  Widget _buildFlatSourceList(List<StreamSource> sources, bool resumeDirectly) {
    return ListView.separated(
      shrinkWrap: true,
      itemCount: sources.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = sources[i];
        return StreamMetadataTile(
          name: s.name,
          url: s.url,
          headers: s.headers,
          onTap: () {
            Navigator.of(context).pop();
            _playWithResolution(s.url, resumeDirectly: resumeDirectly, sourceName: s.name, headers: s.headers);
          },
        );
      },
    );
  }

  void _showTorrentSourceSelector(
    List<StreamSource> torrentSources, {
    bool resumeDirectly = false,
  }) {
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
                      final isSeedrMagnet = source.url.startsWith('magnet:');
                      return ListTile(
                        leading: Icon(
                          isSeedrMagnet
                              ? Icons.cloud_download_rounded
                              : (isCustomMagnet
                                  ? Icons.stars_rounded
                                  : Icons.cloud_circle_rounded),
                          color: isSeedrMagnet
                              ? const Color(0xFF00E676)
                              : (isCustomMagnet
                                  ? Colors.amber
                                  : AppColors.accentBright),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                source.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
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
                                child: const Text('DIRECT', style: TextStyle(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.bold)),
                              ),
                            ],
                            if (isSeedrMagnet) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4), width: 1),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.cloud_download_rounded, size: 8, color: const Color(0xFF00E676)),
                                  const SizedBox(width: 3),
                                  const Text('SEEDR', style: TextStyle(color: Color(0xFF00E676), fontSize: 8, fontWeight: FontWeight.bold)),
                                ]),
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
                                subtitleText =
                                    '👤 Seeders: $dbSeeders  •  👥 Peers: $dbPeers';
                              } else {
                                final stats = _customMagnetStats[source.url];
                                if (stats != null) {
                                  subtitleText =
                                      '👤 Seeders: ${stats['seeders']}  •  👥 Peers: ${stats['peers']}';
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
                              ? BorderSide(
                                  color: Colors.amber.withValues(alpha: 0.3),
                                  width: 1.2,
                                )
                              : BorderSide.none,
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          _playWithResolution(
                            source.url,
                            resumeDirectly: resumeDirectly,
                            sourceName: source.name,
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

    _showSourceSelector(resumeDirectly: resumeDirectly);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }


  Future<void> _promptAndStartDownload(String downloadUrl, {Map<String, String>? headers}) async {
    try {
      await DownloadManager.downloadMovie(
        movie,
        downloadUrl,
        headers: headers,
      );
      await _checkDownloadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${movie.title}" added to downloads queue.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start download: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _downloadTelegramStream(StreamSource source) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.tealAccent)),
    );
    try {
      final localId = TelegramSources.extractLocalId(source.url);
      var items = await TelegramIndexDb.instance.all().catchError((_) => <TelegramVideoItem>[]);
      TelegramVideoItem? match;
      for (final item in items) {
        if (item.localId == localId) {
          match = item;
          break;
        }
      }
      if (match == null) {
        await TelegramService.instance.loadSavedMessages();
        final items2 = await TelegramIndexDb.instance.all();
        for (final item in items2) {
          if (item.localId == localId) {
            match = item;
            break;
          }
        }
      }

      if (mounted) Navigator.of(context).pop();

      if (match != null) {
        final resolved = await TelegramService.instance.resolveStream(match);
        await _promptAndStartDownload(resolved);
      } else {
        throw Exception('Telegram file not found in sync database.');
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Telegram download failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _startDirectMp4Download(String url) async {
    try {
      await _promptAndStartDownload(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start download: $e')));
      }
    }
  }

  void _showDownloadSourceSelector() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final dbMp4Sources = movie.streamSources.where((src) => 
          !_isStreamtapeSource(src) && 
          !_isYoutubeSource(src) && 
          !_isEmbedSource(src) &&
          !_isMagnetSource(src)
        ).toList();

        final dbStreamtapeSources = movie.streamSources.where(_isStreamtapeSource).toList();
        final totalTorrents = _torrentioSources.length + movie.streamSources.where(_isMagnetSource).length;

        // Build order lookup from admin settings
        final Set<String> enabledKeys = _sourceOrder.toSet();
        final Map<String, int> orderPos = {};
        for (int i = 0; i < _sourceOrder.length; i++) {
          orderPos[_sourceOrder[i]] = i + 1;
        }
        int pos(String key) => orderPos[key] ?? 99;

        final Map<String, Widget> downloadSourceWidgets = {};

        // 2. Vidlink Server
        if ((_resolvingVidlink || _liveVidlinkSources.isNotEmpty) && enabledKeys.contains('vidlink')) {
          downloadSourceWidgets['vidlink'] = _buildSourceTile(
            icon: Icons.play_arrow_rounded,
            title: '${pos('vidlink')}. Vidlink Server',
            subtitle: _resolvingVidlink 
                ? 'Checking live...' 
                : (_liveVidlinkSources.isNotEmpty ? '1 native link available' : 'Not available for this title'),
            disabled: _liveVidlinkSources.isEmpty,
            onTap: () {
              Navigator.of(context).pop();
              _downloadSourceUrl(_liveVidlinkSources.first.url, sourceName: _liveVidlinkSources.first.name);
            },
          );
        }

        // 3. NetMirror Server
        if ((_resolvingNetmirror || _liveNetmirrorSources.isNotEmpty) && enabledKeys.contains('netmirror')) {
          downloadSourceWidgets['netmirror'] = _buildSourceTile(
            icon: Icons.language_rounded,
            title: '${pos('netmirror')}. NetMirror Server',
            subtitle: _resolvingNetmirror 
                ? 'Searching NetMirror...' 
                : (_liveNetmirrorSources.isNotEmpty ? '${_liveNetmirrorSources.length} links available' : 'Not available'),
            disabled: _liveNetmirrorSources.isEmpty,
            onTap: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('NetMirror uses HLS (.m3u8) format, which does not support downloading. Please choose another server.'),
                  backgroundColor: Colors.orangeAccent,
                ),
              );
            },
          );
        }

        // 5. CineMM Server
        if ((_resolvingCinemm || _liveCinemmSources.isNotEmpty) && enabledKeys.contains('cinemm')) {
          downloadSourceWidgets['cinemm'] = _buildSourceTile(
            icon: Icons.local_movies_rounded,
            title: '${pos('cinemm')}. CineMM Server',
            subtitle: _resolvingCinemm
                ? 'Searching CineMM...'
                : '${_liveCinemmSources.length} links available',
            disabled: _resolvingCinemm,
            onTap: () {
              Navigator.of(context).pop();
              if (_liveCinemmSources.length == 1) {
                _downloadCinemmStream(_liveCinemmSources.first);
              } else {
                _showDownloadSubSelector('CINEMM DOWNLOADS', _liveCinemmSources, isCinemm: true);
              }
            },
          );
        }

        // 6. Stalker VOD Server
        if ((_resolvingStalker || _liveStalkerSources.isNotEmpty) && enabledKeys.contains('stalker')) {
          downloadSourceWidgets['stalker'] = _buildSourceTile(
            icon: Icons.movie_filter_rounded,
            title: '${pos('stalker')}. Stalker VOD Server',
            subtitle: _resolvingStalker
                ? 'Searching Portal...'
                : '${_liveStalkerSources.length} links available',
            disabled: _resolvingStalker,
            onTap: () {
              Navigator.of(context).pop();
              if (_liveStalkerSources.length == 1) {
                _downloadStalkerStream(_liveStalkerSources.first);
              } else {
                _showDownloadSubSelector('STALKER VOD DOWNLOADS', _liveStalkerSources, isStalker: true);
              }
            },
          );
        }

        // 7. Stravo Server
        if ((_resolvingStravo || _liveStravoSources.isNotEmpty) && enabledKeys.contains('stravo')) {
          downloadSourceWidgets['stravo'] = _buildSourceTile(
            icon: Icons.rocket_launch_rounded,
            title: '${pos('stravo')}. Stravo Server',
            subtitle: _resolvingStravo
                ? 'Searching streams...'
                : '${_liveStravoSources.length} links available',
            disabled: _resolvingStravo,
            onTap: () {
              Navigator.of(context).pop();
              if (_liveStravoSources.length == 1) {
                _downloadStravoStream(_liveStravoSources.first);
              } else {
                _showDownloadSubSelector('STRAVO DOWNLOADS', _liveStravoSources, isStravo: true);
              }
            },
          );
        }

        // 8. Torrent Server (Seedr Cloud Download)
        if (totalTorrents > 0 && enabledKeys.contains('torrent')) {
          final torrentSources = [
            ..._torrentioSources,
            ...movie.streamSources.where(_isMagnetSource),
          ];
          downloadSourceWidgets['torrent'] = _buildSourceTile(
            icon: Icons.cloud_download_rounded,
            title: '${pos('torrent')}. Torrent Server (Seedr)',
            subtitle: '$totalTorrents links available for Seedr cloud download',
            disabled: false,
            onTap: () {
              Navigator.of(context).pop();
              if (torrentSources.length == 1) {
                _downloadTorrentViaSeedr(torrentSources.first);
              } else {
                _showDownloadSubSelector('TORRENT DOWNLOADS (SEEDR)', torrentSources, isTorrentSeedr: true);
              }
            },
          );
        }

        // Castle Server
        if ((_resolvingCastle || _liveCastleSources.isNotEmpty) && enabledKeys.contains('castle')) {
          downloadSourceWidgets['castle'] = _buildSourceTile(
            icon: Icons.castle_rounded,
            title: '${pos('castle')}. Castle TV Server',
            subtitle: _resolvingCastle
                ? 'Searching Castle...'
                : '${_liveCastleSources.length} links available',
            disabled: _resolvingCastle,
            onTap: () {
              Navigator.of(context).pop();
              if (_liveCastleSources.length == 1) {
                _downloadCastleStream(_liveCastleSources.first);
              } else {
                _showDownloadSubSelector('CASTLE TV DOWNLOADS', _liveCastleSources, isCastle: true);
              }
            },
          );
        }

        // Telegram Server
        if ((_resolvingTelegram || _liveTelegramSources.isNotEmpty) && enabledKeys.contains('telegram')) {
          downloadSourceWidgets['telegram'] = _buildSourceTile(
            icon: Icons.send_rounded,
            title: '${pos('telegram')}. Telegram Server',
            subtitle: _resolvingTelegram
                ? 'Searching Telegram...'
                : (_liveTelegramSources.isEmpty
                    ? 'No files found'
                    : '${_liveTelegramSources.length} files in Telegram Server'),
            disabled: _resolvingTelegram || _liveTelegramSources.isEmpty,
            onTap: () {
              Navigator.of(context).pop();
              if (_liveTelegramSources.length == 1) {
                _downloadTelegramStream(_liveTelegramSources.first);
              } else {
                _showDownloadSubSelector('TELEGRAM DOWNLOADS', _liveTelegramSources, isTelegram: true);
              }
            },
          );
        }

        // Ordered items output list
        final List<Widget> items = [];

        // 1. Direct MP4/MKV Link (always shown at top if exist)
        if (dbMp4Sources.isNotEmpty) {
          items.add(
            _buildSourceTile(
              icon: Icons.video_file_rounded,
              title: 'Direct MP4/MKV Link',
              subtitle: dbMp4Sources.length == 1
                  ? dbMp4Sources.first.name
                  : '${dbMp4Sources.length} files available',
              disabled: false,
              onTap: () {
                Navigator.of(context).pop();
                if (dbMp4Sources.length == 1) {
                  _downloadSourceUrl(dbMp4Sources.first.url, sourceName: dbMp4Sources.first.name);
                } else {
                  _showDownloadSubSelector('MP4/MKV DIRECT DOWNLOADS', dbMp4Sources);
                }
              },
            ),
          );
        }

        // 4. Streamtape Server (always shown at top if exist)
        if (dbStreamtapeSources.isNotEmpty) {
          items.add(
            _buildSourceTile(
              icon: Icons.folder_shared_rounded,
              title: 'Streamtape Server',
              subtitle: dbStreamtapeSources.isEmpty 
                  ? 'Not available' 
                  : (dbStreamtapeSources.length == 1 ? dbStreamtapeSources.first.name : '${dbStreamtapeSources.length} files available'),
              disabled: dbStreamtapeSources.isEmpty,
              onTap: () {
                Navigator.of(context).pop();
                if (dbStreamtapeSources.length == 1) {
                  _downloadStreamtapeSource(dbStreamtapeSources.first);
                } else {
                  _showDownloadSubSelector('STREAMTAPE DOWNLOADS', dbStreamtapeSources, isStreamtape: true);
                }
              },
            ),
          );
        }

        // Dynamic sources
        for (final key in _sourceOrder) {
          if (key == 'stremioAddon') {
            if (downloadSourceWidgets.containsKey('stremioAddon') && enabledKeys.contains('stremioAddon')) {
              items.add(downloadSourceWidgets['stremioAddon']!);
            }
            if (downloadSourceWidgets.containsKey('nuveoAddon') && enabledKeys.contains('stremioAddon')) {
              items.add(downloadSourceWidgets['nuveoAddon']!);
            }
          } else {
            if (downloadSourceWidgets.containsKey(key) && enabledKeys.contains(key)) {
              items.add(downloadSourceWidgets[key]!);
            }
          }
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SELECT SERVER FOR DOWNLOAD',
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
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => items[index],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadSourceUrl(String rawUrl, {String? sourceName}) async {
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
      final url = _sanitizeUrl(rawUrl);
      String? resolvedUrl = url;
      Map<String, String>? headers;

      if (url.contains('movie-scraper-beige.vercel.app')) {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          resolvedUrl = data['url'] as String?;
          if (resolvedUrl != null) {
            headers = EmbedResolver.getHeadersForUrl(
              resolvedUrl,
              fallbackHeaders: {
                'Referer': 'https://vidlink.pro/',
                'Origin': 'https://vidlink.pro',
              },
            );
          }
        }
      }

      if (mounted) Navigator.of(context).pop();

      if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
        await _promptAndStartDownload(resolvedUrl, headers: headers);
      } else {
        throw Exception('Could not resolve download link.');
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _downloadCinemmStream(StreamSource source) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const ResolvingProgressDialog(
          title: 'Resolving CineMM...',
          subtitle: 'Extracting Direct Stream',
        );
      },
    );
    try {
      final url = _sanitizeUrl(source.url);
      if (mounted) Navigator.of(context).pop();

      if (url.isNotEmpty) {
        await _promptAndStartDownload(url);
      } else {
        throw Exception('Failed to resolve CineMM direct URL.');
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _downloadMovieboxStream(StreamSource source) async {
    try {
      final url = source.url;
      if (url.isNotEmpty) {
        await _promptAndStartDownload(url, headers: source.headers);
      } else {
        throw Exception('Failed to resolve MovieBox direct URL.');
      }
    } catch (e) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _downloadStreamtapeSource(StreamSource source) async {
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
      final url = _sanitizeUrl(source.url);
      final resolvedUrl = await _resolveStreamtape(url, sourceName: source.name);
      if (mounted) Navigator.of(context).pop();

      if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
        await _promptAndStartDownload(
          resolvedUrl,
          headers: {
            'Referer': 'https://streamtape.com/',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        );
      } else {
        throw Exception('Failed to resolve Streamtape direct URL.');
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _downloadStalkerStream(StreamSource source) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.tealAccent)),
    );
    try {
      final uri = Uri.parse(source.url);
      final portalId = int.tryParse(uri.host) ?? 1;
      final cmd = uri.path;
      final resolved = await StalkerResolver.resolveStream(cmd, portalId, isLive: false);
      if (mounted) Navigator.of(context).pop();

      await _promptAndStartDownload(resolved.url, headers: resolved.headers);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Stalker download failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _downloadStravoStream(StreamSource source) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.tealAccent)),
    );
    try {
      final uri = Uri.parse(source.url);
      final Map<String, String> headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
      };
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      if (mounted) Navigator.of(context).pop();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final streamsList = data['streams'] as List<dynamic>? ?? [];
        final List<dynamic> validStreams = streamsList.where((s) {
          final u = s['url']?.toString() ?? '';
          return u.isNotEmpty && !u.contains('t.me');
        }).toList();

        if (validStreams.isEmpty) {
          throw Exception('No downloadable video streams returned by Stravo.');
        }

        if (mounted) {
          final selectedStream = await showDialog<dynamic>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Select Download Quality', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: validStreams.length,
                  itemBuilder: (context, index) {
                    final stream = validStreams[index];
                    final title = stream['title']?.toString() ?? 'Stream ${index + 1}';
                    final name = stream['name']?.toString() ?? '';
                    return ListTile(
                      title: Text(title, style: const TextStyle(color: Colors.white)),
                      subtitle: name.isNotEmpty ? Text(name, style: const TextStyle(color: Colors.white54)) : null,
                      leading: const Icon(Icons.download_rounded, color: Colors.tealAccent),
                      onTap: () => Navigator.of(context).pop(stream),
                    );
                  },
                ),
              ),
            ),
          );

          if (selectedStream != null) {
            final dlUrl = selectedStream['url']?.toString() ?? '';
            final Map<String, String> dlHeaders = {};
            final behavior = selectedStream['behaviorHints'];
            if (behavior != null && behavior['proxyHeaders'] != null && behavior['proxyHeaders']['request'] != null) {
              final reqHeaders = behavior['proxyHeaders']['request'] as Map<String, dynamic>;
              reqHeaders.forEach((k, v) {
                dlHeaders[k] = v.toString();
              });
            }
            if (dlHeaders.isEmpty) {
              dlHeaders.addAll({
                'Referer': 'https://lok-lok.cc/',
                'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',
              });
            }

            await DownloadManager.downloadMovie(movie, dlUrl, headers: dlHeaders.isNotEmpty ? dlHeaders : null);
            await _checkDownloadStatus();
            ScaffoldMessenger.of(this.context).showSnackBar(
              SnackBar(content: Text('"${movie.title}" added to downloads queue.')),
            );
          }
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Stravo download failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _downloadCastleStream(StreamSource source) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.amberAccent)),
    );
    try {
      final url = _sanitizeUrl(source.url);
      final resolvedUrl = await EmbedResolver.resolve(context, url);
      if (mounted) Navigator.of(context).pop();

      if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
        await _promptAndStartDownload(resolvedUrl);
      } else {
        await _promptAndStartDownload(url);
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Castle download failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _downloadTorrentViaSeedr(StreamSource source) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      final seedrToken = prefs.getString('seedr_auth_token');
      if (seedrToken == null || seedrToken.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to Seedr in Settings to download torrents.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        return;
      }
      final resolvedUrl = await WebTorrentService.startTorrent(
        source.url,
        authToken: seedrToken,
        name: movie.title,
      );
      if (mounted) Navigator.of(context).pop();
      if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
        await _promptAndStartDownload(resolvedUrl);
      } else {
        throw Exception('Could not fetch Seedr direct download link.');
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Seedr torrent download failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _showDownloadSubSelector(String title, List<StreamSource> sources, {bool isStreamtape = false, bool isStalker = false, bool isStravo = false, bool isCinemm = false, bool isTelegram = false, bool isCastle = false, bool isTorrentSeedr = false, bool isMoviebox = false}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0),
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
                        leading: Icon(Icons.download_rounded, color: AppColors.accentBright),
                        title: Text(source.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        tileColor: Colors.white.withOpacity(0.03),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          if (isStreamtape) {
                            _downloadStreamtapeSource(source);
                          } else if (isStalker) {
                            _downloadStalkerStream(source);
                          } else if (isStravo) {
                            _downloadStravoStream(source);
                          } else if (isCinemm) {
                            _downloadCinemmStream(source);
                          } else if (isTelegram) {
                            _downloadTelegramStream(source);
                          } else if (isCastle) {
                            _downloadCastleStream(source);
                          } else if (isTorrentSeedr) {
                            _downloadTorrentViaSeedr(source);
                          } else {
                            _downloadSourceUrl(source.url, sourceName: source.name);
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

  Future<void> _startDownload() async {
    _showDownloadSourceSelector();
  }

  Future<void> _deleteDownload() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Download?',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text('Remove downloaded video from device storage?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
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
    if (lowerTrailer.contains('youtube.com') ||
        lowerTrailer.contains('youtu.be')) {
      // Direct YouTube webview playback in 720p HD quality
      String embedUrl = trailer;
      final regExp = RegExp(
        r'^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#\&\?]*)',
      );
      final match = regExp.firstMatch(trailer);
      if (match != null &&
          match.group(7) != null &&
          match.group(7)!.length == 11) {
        embedUrl =
            'https://www.youtube.com/embed/${match.group(7)}?vq=hd720&autoplay=1&origin=https://ott.redapp.space';
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
            const SnackBar(
              content: Text('Could not load trailer stream. Please try again.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error playing trailer: $e')));
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
    final text =
        'Watch "${movie.title}" on GoXio.\n\nDescription: ${movie.description ?? ""}\nIMDb rating: ★${movie.rating.toStringAsFixed(1)}\n\nStream link: ${movie.videoSource ?? ""}';
    Share.share(text, subject: 'Check out ${movie.title}');
  }

  void _showWatchProvidersBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF16151A),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'OTT Streaming Providers',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_watchProviders.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: Text(
                      'No OTT streaming platforms found for this region.',
                      style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                    ),
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _watchProviders.map((provider) {
                      final logoPath = provider['logo_path']?.toString() ?? '';
                      final logoUrl = 'https://image.tmdb.org/t/p/w154$logoPath';
                      final pName = provider['provider_name']?.toString() ?? movie.ottName;
                      return InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          if (pName != null && pName.isNotEmpty) {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AllMoviesScreen(initialOttProvider: pName),
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          margin: const EdgeInsets.only(right: 16),
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white10),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.network(
                            logoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.tv_rounded, color: Colors.white60, size: 24),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
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
                      child: MovieImage(
                        source: movie.displayBackdrop,
                        fit: BoxFit.cover,
                      ),
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
                                    imageFilter: ImageFilter.blur(
                                      sigmaX: 15.0,
                                      sigmaY: 15.0,
                                    ),
                                    child: Container(
                                      margin: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color:
                                            (movie.posterColor ??
                                                    activeTheme.accentBright)
                                                .withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                                // Sharp Poster Card with Gold Border
                                // Sharp Poster Card with Border
                                Container(
                                  width: 120,
                                  height: 180,
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.12),
                                      width: 0.8,
                                    ),
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
                                  const SizedBox(height: 35),
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
                                      if (movie.year != null)
                                        detailsParts.add(movie.year.toString());
                                      if (movie.runtime != null)
                                        detailsParts.add(movie.runtime!);
                                      if (movie.genre.isNotEmpty) {
                                        detailsParts.add(
                                          movie.genre.split(',').first.trim(),
                                        );
                                      }
                                      return Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
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
                                          if (movie.contentRating != null &&
                                              movie
                                                  .contentRating!
                                                  .isNotEmpty) ...[
                                            const Text(
                                              '•',
                                              style: TextStyle(
                                                color: Colors.white60,
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1.5,
                                                  ),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: Colors.white54,
                                                  width: 0.8,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
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
                                    },
                                  ),
                                  const SizedBox(height: 12),

                                  // Redesigned IMDb & TMDB Rating Badges side-by-side
                                  Row(
                                    children: [
                                      // IMDb Badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFFF5C518,
                                          ), // IMDb Gold
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.star_rounded,
                                              color: Colors.black,
                                              size: 14,
                                            ),
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
                                            Container(
                                              width: 0.8,
                                              height: 10,
                                              color: Colors.black26,
                                            ),
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
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF032541,
                                          ).withOpacity(0.6),
                                          border: Border.all(
                                            color: const Color(0xFF01B4E4),
                                            width: 1.2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.star_rounded,
                                              color: Color(0xFF01B4E4),
                                              size: 14,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              (_dynamicRating ?? 6.5)
                                                  .toStringAsFixed(1),
                                              style: GoogleFonts.outfit(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(
                                              width: 0.8,
                                              height: 10,
                                              color: Colors.white24,
                                            ),
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
                                        color: Color(
                                          0xFFA855F7,
                                        ), // Purple trending icon
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
                                ],
                              ),
                            ),
                          ],
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
                                    colors: [
                                      Color(0xFFFBBF24),
                                      Color(0xFFF59E0B),
                                    ],
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
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.black,
                                    size: 20,
                                  ),
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
                                  border: Border.all(
                                    color: Colors.white24,
                                    width: 1.2,
                                  ),
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
                                    _isFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: _isFavorite
                                        ? Colors.redAccent
                                        : Colors.white70,
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
                              icon: _isDownloaded
                                  ? Icons.download_done_rounded
                                  : Icons.download_rounded,
                              label: _isDownloaded ? 'Downloaded' : 'Download',
                              onTap: _isDownloaded
                                  ? _deleteDownload
                                  : _startDownload,
                              activeColor: _isDownloaded
                                  ? Colors.redAccent
                                  : null,
                            ),
                            _buildActionButtonCard(
                              icon: _inWatchlist
                                  ? Icons.playlist_add_check_rounded
                                  : Icons.playlist_add_rounded,
                              label: 'Watchlist',
                              onTap: _toggleWatchlist,
                              activeColor: _inWatchlist
                                  ? activeTheme.accentBright
                                  : null,
                            ),
                            if (movie.ottName != null && movie.ottName!.isNotEmpty)
                              _buildActionButtonCard(
                                logoUrl: movie.ottLogo,
                                label: movie.ottName!,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => AllMoviesScreen(initialOttProvider: movie.ottName!),
                                    ),
                                  );
                                },
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
                          movie.description ??
                              'Enjoy premium streaming of ${movie.title} in full HD quality.',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),

                        const SizedBox(height: 20),

                        const SizedBox(height: 4),

                        // Director & Cast List
                        if (_dynamicDirector != null) ...[
                          Text(
                            'Director',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            onTap: () {
                              if (_dynamicDirector != null && _dynamicDirector!.isNotEmpty) {
                                PersonDetailSheet.show(
                                  context,
                                  personName: _dynamicDirector!,
                                  photoUrl: _directorProfileUrl,
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: AppColors.surface,
                                    backgroundImage:
                                        _directorProfileUrl != null &&
                                            _directorProfileUrl!.isNotEmpty
                                        ? NetworkImage(_directorProfileUrl!)
                                        : null,
                                    child:
                                        _directorProfileUrl == null ||
                                            _directorProfileUrl!.isEmpty
                                        ? const Icon(
                                            Icons.person_rounded,
                                            color: Colors.white30,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _dynamicDirector!,
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(
                                            'Director',
                                            style: GoogleFonts.outfit(
                                              color: Colors.white38,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFA855F7), size: 10),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        if (_dynamicCast.isNotEmpty) ...[
                          Text(
                            'Featured Cast',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 105,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _dynamicCast.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 14),
                              itemBuilder: (context, index) {
                                final actor = _dynamicCast[index];
                                return InkWell(
                                  onTap: () {
                                    PersonDetailSheet.show(
                                      context,
                                      personName: actor.name,
                                      photoUrl: actor.profileUrl,
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.white12,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: actor.profileUrl.isNotEmpty
                                              ? MovieImage(
                                                  source: actor.profileUrl,
                                                  fit: BoxFit.cover,
                                                )
                                              : const Icon(
                                                  Icons.person_rounded,
                                                  color: Colors.white30,
                                                  size: 24,
                                                ),
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
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
                            border: Border.all(
                              color: Colors.white10,
                              width: 0.8,
                            ),
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
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
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
                        icon: const Icon(
                          Icons.share_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
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

  Widget _buildOttBadgesRow(String ottName, String? ottLogo) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ottLogo != null && ottLogo.isNotEmpty)
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.white10,
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.network(
              ottLogo,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.play_circle_rounded,
                color: AppColors.accentBright,
                size: 18,
              ),
            ),
          )
        else
          Icon(
            Icons.play_circle_rounded,
            color: AppColors.accentBright,
            size: 18,
          ),
        const SizedBox(width: 6),
        Text(
          ottName,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtonCard({
    IconData? icon,
    String? logoUrl,
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
              if (logoUrl != null && logoUrl.isNotEmpty)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.network(
                    logoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      icon ?? Icons.tv_rounded,
                      color: activeColor ?? Colors.white,
                      size: 20,
                    ),
                  ),
                )
              else
                Icon(
                  icon ?? Icons.tv_rounded,
                  color: activeColor ?? Colors.white,
                  size: 20,
                ),
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

  Widget _buildBottomGridItem({
    required IconData icon,
    required String title,
    required String value,
  }) {
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
    return Container(width: 0.8, height: 40, color: Colors.white10);
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
