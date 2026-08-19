import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/data/api_service.dart';
import 'package:private_cinema_mobile/data/sync_service.dart';
import 'package:private_cinema_mobile/screens/video_player_screen.dart';
import 'package:private_cinema_mobile/screens/webview_player_screen.dart';
import 'package:private_cinema_mobile/data/stalker_resolver.dart';
import 'package:private_cinema_mobile/widgets/seedr_countdown_dialog.dart';

class AppColors {
  static const primaryDark = Color(0xFF0F172A);
  static const cardDark = Color(0xFF1E293B);
  static const accent = Color(0xFFE11D48);
  static const accentBright = Color(0xFFF43F5E);
  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xFF94A3B8);
}

class SpecialSearchDialog extends StatefulWidget {
  final Map<String, dynamic>? initialMovie;
  const SpecialSearchDialog({super.key, this.initialMovie});

  @override
  State<SpecialSearchDialog> createState() => _SpecialSearchDialogState();
}

enum StreamSourceType {
  stravo,
  torrentio,
  stremioAddon,
  nuveoAddon,
  cinemm,
  stalker,
  castle,
  telegram,
}

class _SpecialSearchDialogState extends State<SpecialSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  bool _isSearchingTMDB = false;
  List<Map<String, dynamic>> _tmdbResults = [];
  Map<String, dynamic>? _selectedMovie;

  bool _isSeriesSearch = false;
  int _selectedSeason = 1;
  int _selectedEpisode = 1;
  int _totalSeasons = 1;
  int _episodesInSeason = 1;
  bool _loadingSeasonData = false;

  bool _resolvingStreams = false;
  
  List<StreamSource> stravoStreams = [];
  List<StreamSource> torrentioStreams = [];
  List<StreamSource> stremioAddonStreams = [];
  List<StreamSource> cinemmStreams = [];
  List<StreamSource> stalkerStreams = [];

  StreamSourceType? _activeGroupType;

  bool _showCinemm = true;
  bool _showStalker = true;
  bool _showStravo = true;
  bool _showTorrent = true;
  bool _showStremioAddon = true;

  Map<String, String> _customStremioAddons = {};
  List<String> _sourceOrderList = [];

  @override
  void initState() {
    super.initState();
    _loadSourceVisibilities();
    if (widget.initialMovie != null) {
      _selectMovie(widget.initialMovie!);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSourceVisibilities() async {
    final prefs = await SharedPreferences.getInstance();
    final cloud = await SyncService.fetchAppSettings();
    if (mounted) {
      setState(() {
        _showCinemm = cloud.containsKey('source_show_cinemm') ? cloud['source_show_cinemm'] == 'true' : (prefs.getBool('source_show_cinemm') ?? true);
        _showStalker = cloud.containsKey('source_show_stalker') ? cloud['source_show_stalker'] == 'true' : (prefs.getBool('source_show_stalker') ?? true);
        _showStravo = cloud.containsKey('source_show_stravo') ? cloud['source_show_stravo'] == 'true' : (prefs.getBool('source_show_stravo') ?? true);
        _showTorrent = cloud.containsKey('source_show_torrent') ? cloud['source_show_torrent'] == 'true' : (prefs.getBool('source_show_torrent') ?? true);
        _showStremioAddon = (cloud.containsKey('source_show_stremioAddon') ? cloud['source_show_stremioAddon'] == 'true' : (prefs.getBool('source_show_stremioAddon') ?? true)) && (cloud['stremio_addons_enabled'] ?? 'true') == 'true';
      });
    }

    if (cloud.containsKey('global_stremio_addons')) {
      try {
        final list = json.decode(cloud['global_stremio_addons']!);
        if (list is List) {
          final Map<String, String> map = {};
          for (final item in list) {
            if (item is Map && item['enabled'] == true && item['url'] != null) {
              map[item['name']?.toString() ?? Uri.parse(item['url']).host] = item['url'].toString();
            } else if (item is String) {
              map[Uri.parse(item).host] = item;
            }
          }
          if (mounted) setState(() => _customStremioAddons = map);
        }
      } catch (_) {}
    }

    if (cloud.containsKey('source_order')) {
      try {
        final list = json.decode(cloud['source_order']!);
        if (list is List) {
          final order = list.map((e) => e.toString()).toList();
          if (mounted) setState(() => _sourceOrderList = order);
        }
      } catch (_) {}
    }
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _tmdbResults.clear();
        _isSearchingTMDB = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _searchTMDB(query.trim());
    });
  }

  Future<void> _searchTMDB(String query) async {
    setState(() {
      _isSearchingTMDB = true;
    });

    try {
      final apiKey = '8baba8ab6b8bbe247645bcae7df63d0d';
      final multiUrl = Uri.parse('https://api.themoviedb.org/3/search/multi?api_key=$apiKey&query=${Uri.encodeComponent(query)}&include_adult=false');
      
      final res = await http.get(multiUrl).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final results = (data['results'] as List? ?? [])
            .where((item) => item['media_type'] == 'movie' || item['media_type'] == 'tv')
            .map((item) => Map<String, dynamic>.from(item))
            .toList();

        if (mounted) {
          setState(() {
            _tmdbResults = results;
            _isSearchingTMDB = false;
          });
        }
      } else {
        if (mounted) setState(() => _isSearchingTMDB = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isSearchingTMDB = false);
    }
  }

  void _selectMovie(Map<String, dynamic> movie) {
    final mediaType = movie['media_type'] ?? (movie['first_air_date'] != null ? 'tv' : 'movie');
    setState(() {
      _selectedMovie = movie;
      _isSeriesSearch = mediaType == 'tv';
      _selectedSeason = 1;
      _selectedEpisode = 1;
      _activeGroupType = null;
      _clearAllStreams();
    });

    if (_isSeriesSearch) {
      _fetchSeriesDetails(movie['id'].toString());
    } else {
      _startAutoSearch();
    }
  }

  void _clearAllStreams() {
    stravoStreams.clear();
    torrentioStreams.clear();
    stremioAddonStreams.clear();
    cinemmStreams.clear();
    stalkerStreams.clear();
  }

  Future<void> _fetchSeriesDetails(String tmdbId) async {
    setState(() => _loadingSeasonData = true);
    try {
      final apiKey = '8baba8ab6b8bbe247645bcae7df63d0d';
      final url = Uri.parse('https://api.themoviedb.org/3/tv/$tmdbId?api_key=$apiKey');
      final res = await http.get(url).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final numberOfSeasons = data['number_of_seasons'] ?? 1;

        if (mounted) {
          setState(() {
            _totalSeasons = numberOfSeasons;
            _selectedSeason = 1;
          });
        }
        await _fetchSeasonDetails(tmdbId, 1);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSeasonData = false);
      _startAutoSearch();
    }
  }

  Future<void> _fetchSeasonDetails(String tmdbId, int seasonNum) async {
    setState(() => _loadingSeasonData = true);
    try {
      final apiKey = '8baba8ab6b8bbe247645bcae7df63d0d';
      final url = Uri.parse('https://api.themoviedb.org/3/tv/$tmdbId/season/$seasonNum?api_key=$apiKey');
      final res = await http.get(url).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final episodes = data['episodes'] as List? ?? [];
        if (mounted) {
          setState(() {
            _episodesInSeason = episodes.isNotEmpty ? episodes.length : 1;
            _selectedEpisode = 1;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSeasonData = false);
    }
  }

  Future<void> _startAutoSearch() async {
    if (_selectedMovie == null) return;

    setState(() {
      _resolvingStreams = true;
      _activeGroupType = null;
      _clearAllStreams();
    });

    final tmdbId = _selectedMovie!['id'].toString();
    final title = _selectedMovie!['title'] ?? _selectedMovie!['name'] ?? '';
    final mediaType = _isSeriesSearch ? 'tv' : 'movie';
    final season = _isSeriesSearch ? _selectedSeason : null;
    final episode = _isSeriesSearch ? _selectedEpisode : null;

    try {
      String? imdbId;
      try {
        final apiKey = '8baba8ab6b8bbe247645bcae7df63d0d';
        final extUrl = Uri.parse('https://api.themoviedb.org/3/$mediaType/$tmdbId/external_ids?api_key=$apiKey');
        final extRes = await http.get(extUrl).timeout(const Duration(seconds: 5));
        if (extRes.statusCode == 200) {
          final extData = json.decode(extRes.body);
          imdbId = extData['imdb_id']?.toString();
        }
      } catch (_) {}

      final List<Future<void>> tasks = [];

      if (imdbId != null && imdbId.isNotEmpty) {
        if (_showStravo) {
          tasks.add(_resolveStravo(imdbId, season: season, episode: episode));
        }
        if (_showTorrent) {
          tasks.add(_resolveTorrentio(imdbId, title, season: season, episode: episode));
        }
        if (_showStremioAddon) {
          tasks.add(_resolveStremioAddons(imdbId, season: season, episode: episode));
        }
      } else {
        if (_showStremioAddon) {
          tasks.add(_resolveStremioAddons('tmdb:$tmdbId', season: season, episode: episode));
        }
      }

      String queryTitle = title;
      if (_isSeriesSearch && season != null && episode != null) {
        queryTitle = "$title S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}";
      }

      if (_showStalker) {
        tasks.add(_resolveStalkerVodDatabase(queryTitle));
      }

      if (_showCinemm && !_isSeriesSearch) {
        final year = _selectedMovie?['release_date']?.toString().split('-').first ?? '';
        tasks.add(_resolveCinemm(title, year));
      }

      await Future.wait(tasks);
    } catch (e) {
      debugPrint('Auto search failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _resolvingStreams = false;
        });
      }
    }
  }

  Future<void> _resolveStravo(String imdbId, {int? season, int? episode}) async {
    try {
      final String endpoint = (season != null && episode != null)
          ? 'https://stravo-clfk.onrender.com/default/stream/series/$imdbId:$season:$episode.json'
          : 'https://stravo-clfk.onrender.com/default/stream/movie/$imdbId.json';

      final res = await http.get(Uri.parse(endpoint)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final streams = data['streams'] as List? ?? [];

        final List<StreamSource> parsed = [];
        for (final s in streams) {
          final url = s['url']?.toString() ?? '';
          final titleStr = s['title']?.toString() ?? s['name']?.toString() ?? 'Stravo Direct Stream';
          if (url.isNotEmpty) {
            parsed.add(StreamSource(name: titleStr, url: url));
          }
        }
        if (mounted) setState(() => stravoStreams = parsed);
      }
    } catch (_) {}
  }

  Future<void> _resolveTorrentio(String imdbId, String title, {int? season, int? episode}) async {
    try {
      final String endpoint = (season != null && episode != null)
          ? 'https://torrentio.strem.fun/stream/series/$imdbId:$season:$episode.json'
          : 'https://torrentio.strem.fun/stream/movie/$imdbId.json';

      final res = await http.get(Uri.parse(endpoint)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final streams = data['streams'] as List? ?? [];

        final List<StreamSource> parsed = [];
        for (final s in streams) {
          final titleStr = s['title']?.toString() ?? '';
          final magnetUrl = s['url']?.toString() ?? (s['infoHash'] != null ? 'magnet:?xt=urn:btih:${s['infoHash']}' : '');
          if (magnetUrl.isNotEmpty) {
            parsed.add(StreamSource(name: titleStr.isNotEmpty ? titleStr : 'Torrentio Magnet', url: magnetUrl));
          }
        }
        if (mounted) setState(() => torrentioStreams = parsed);
      }
    } catch (_) {}
  }

  Future<void> _resolveStremioAddons(String mediaId, {int? season, int? episode}) async {
    try {
      final List<StreamSource> allAddonStreams = [];
      final typeStr = (season != null && episode != null) ? 'series' : 'movie';
      final idParam = (season != null && episode != null) ? '$mediaId:$season:$episode' : mediaId;

      final defaultAddons = {
        'Torrentio': 'https://torrentio.strem.fun',
        'KnightCrawler': 'https://knightcrawler.elfhosted.com',
        'CyberFlix': 'https://cyberflix.elfhosted.com',
      };

      final activeAddons = Map<String, String>.from(defaultAddons);
      activeAddons.addAll(_customStremioAddons);

      final List<Future<void>> futures = [];
      for (final entry in activeAddons.entries) {
        futures.add(() async {
          try {
            var baseUrl = entry.value.trim();
            if (baseUrl.endsWith('/manifest.json')) {
              baseUrl = baseUrl.replaceAll('/manifest.json', '');
            }
            final url = '$baseUrl/stream/$typeStr/$idParam.json';
            final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
            if (res.statusCode == 200) {
              final data = json.decode(res.body);
              final streams = data['streams'] as List? ?? [];
              for (final s in streams) {
                final nameStr = s['name']?.toString() ?? entry.key;
                final titleStr = s['title']?.toString() ?? '';
                final streamUrl = s['url']?.toString() ?? (s['infoHash'] != null ? 'magnet:?xt=urn:btih:${s['infoHash']}' : '');
                
                if (streamUrl.isNotEmpty) {
                  allAddonStreams.add(StreamSource(
                    name: '[$nameStr] ${titleStr.isNotEmpty ? titleStr : 'Stream'}',
                    url: streamUrl,
                  ));
                }
              }
            }
          } catch (_) {}
        }());
      }

      await Future.wait(futures);
      if (mounted) setState(() => stremioAddonStreams = allAddonStreams);
    } catch (_) {}
  }

  Future<void> _resolveStalkerVodDatabase(String queryTitle) async {
    try {
      final results = await StalkerResolver.searchVod(queryTitle);
      final List<StreamSource> parsed = [];

      for (final res in results) {
        final title = res['title'] ?? 'Stalker VOD';
        final cmd = res['cmd'] ?? '';
        final portalUrl = res['portalUrl'] ?? '';
        final mac = res['mac'] ?? '';

        if (cmd.isNotEmpty && portalUrl.isNotEmpty && mac.isNotEmpty) {
          parsed.add(StreamSource(
            name: 'Stalker: $title',
            url: 'stalker://$portalUrl?mac=$mac&cmd=${Uri.encodeComponent(cmd)}',
          ));
        }
      }
      if (mounted) setState(() => stalkerStreams = parsed);
    } catch (_) {}
  }

  Future<void> _resolveCinemm(String title, String year) async {
    try {
      final res = await http.get(Uri.parse('https://cinemm.net/search?q=${Uri.encodeComponent(title)}')).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final html = res.body;
        final match = RegExp(r'href="([^"]*movie\/[^"]*)"').firstMatch(html);
        if (match != null) {
          final moviePath = match.group(1)!;
          final targetUrl = moviePath.startsWith('http') ? moviePath : 'https://cinemm.net$moviePath';
          if (mounted) {
            setState(() {
              cinemmStreams = [StreamSource(name: 'CineMM Web Player', url: targetUrl)];
            });
          }
        }
      }
    } catch (_) {}
  }

  void _playStream(StreamSource stream, String movieTitle, String? posterPath) {
    Navigator.of(context).pop();

    if (stream.url.startsWith('magnet:')) {
      showDialog(
        context: context,
        builder: (ctx) => SeedrCountdownDialog(
          magnetUrl: stream.url,
          movieTitle: movieTitle,
        ),
      );
      return;
    }

    if (stream.url.startsWith('stalker://')) {
      final uri = Uri.parse(stream.url);
      final portalUrl = uri.host;
      final mac = uri.queryParameters['mac'] ?? '';
      final cmd = uri.queryParameters['cmd'] ?? '';

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: '',
            title: stream.name,
            movie: Movie(
              id: 'stalker_${DateTime.now().millisecondsSinceEpoch}',
              title: stream.name,
              genre: 'Stalker IPTV',
              rating: 8.0,
              posterUrl: posterPath ?? '',
              videoSource: stream.url,
            ),
          ),
        ),
      );
      return;
    }

    if (stream.url.contains('cinemm.net') || stream.url.contains('embed')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WebViewPlayerScreen(
            embedUrl: stream.url,
            title: stream.name,
            backdropUrl: posterPath,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: stream.url,
          title: stream.name,
          movie: Movie(
            id: 'search_${DateTime.now().millisecondsSinceEpoch}',
            title: movieTitle,
            genre: 'Special Search',
            rating: 8.5,
            posterUrl: posterPath ?? '',
            videoSource: stream.url,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posterPath = _selectedMovie != null ? 'https://image.tmdb.org/t/p/w500${_selectedMovie!['poster_path'] ?? ''}' : null;
    final movieTitle = _selectedMovie != null ? (_selectedMovie!['title'] ?? _selectedMovie!['name'] ?? 'Selected Title') : '';

    final defaultOrder = ['stravo', 'torrent', 'stremioAddon', 'cinemm', 'stalker'];
    final Map<String, int> priorityMap = {};
    for (int i = 0; i < _sourceOrderList.length; i++) {
      priorityMap[_sourceOrderList[i]] = i;
    }
    int pos(String key) {
      if (priorityMap.containsKey(key)) return priorityMap[key]! + 1;
      final idx = defaultOrder.indexOf(key);
      return idx != -1 ? idx + 1 : 99;
    }

    final enabledKeys = priorityMap.keys.toList();
    if (enabledKeys.isEmpty) enabledKeys.addAll(defaultOrder);

    return Dialog(
      backgroundColor: AppColors.primaryDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        maxHeight: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.saved_search_rounded, color: AppColors.accentBright, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mega Multi-Source Search', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      Text('Search TMDB & stream directly across servers', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Type movie or series title...',
                hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.accentBright),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.cardDark,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),

            if (_isSearchingTMDB)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: AppColors.accentBright))),

            if (_selectedMovie == null && _tmdbResults.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _tmdbResults.length,
                  itemBuilder: (context, idx) {
                    final item = _tmdbResults[idx];
                    final title = item['title'] ?? item['name'] ?? 'Untitled';
                    final mediaType = item['media_type'] ?? 'movie';
                    final date = item['release_date'] ?? item['first_air_date'] ?? '';
                    final year = date.toString().split('-').first;
                    final poster = item['poster_path'] != null ? 'https://image.tmdb.org/t/p/w185${item['poster_path']}' : null;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        leading: poster != null
                            ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(poster, width: 40, fit: BoxFit.cover))
                            : const Icon(Icons.movie_rounded, color: Colors.white38),
                        title: Text(title, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text('${mediaType.toUpperCase()} ${year.isNotEmpty ? '• $year' : ''}', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11)),
                        onTap: () => _selectMovie(item),
                      ),
                    );
                  },
                ),
              ),

            if (_selectedMovie != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    if (posterPath != null)
                      ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(posterPath, width: 50, height: 70, fit: BoxFit.cover)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(movieTitle, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(_isSeriesSearch ? 'TV Series' : 'Movie', style: GoogleFonts.outfit(color: AppColors.accentBright, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selectedMovie = null),
                      child: Text('CHANGE', style: GoogleFonts.outfit(color: AppColors.accentBright, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (_isSeriesSearch) ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _selectedSeason,
                        dropdownColor: AppColors.cardDark,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Season',
                          labelStyle: GoogleFonts.outfit(color: AppColors.textSecondary),
                          filled: true,
                          fillColor: AppColors.cardDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        items: List.generate(_totalSeasons, (i) => i + 1)
                            .map((s) => DropdownMenuItem(value: s, child: Text('Season $s')))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedSeason = val);
                            _fetchSeasonDetails(_selectedMovie!['id'].toString(), val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _selectedEpisode,
                        dropdownColor: AppColors.cardDark,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Episode',
                          labelStyle: GoogleFonts.outfit(color: AppColors.textSecondary),
                          filled: true,
                          fillColor: AppColors.cardDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        items: List.generate(_episodesInSeason, (i) => i + 1)
                            .map((e) => DropdownMenuItem(value: e, child: Text('Episode $e')))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedEpisode = val);
                            _startAutoSearch();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              Expanded(
                child: _buildStreamResultsList(movieTitle, posterPath),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStreamResultsList(String movieTitle, String? posterPath) {
    if (_resolvingStreams) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.accentBright),
            SizedBox(height: 16),
            Text('Scraping stream providers...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_activeGroupType != null) {
      return _buildSubStreamList(_activeGroupType!, movieTitle, posterPath);
    }

    final defaultOrder = ['stravo', 'torrent', 'stremioAddon', 'cinemm', 'stalker'];
    final Map<String, int> priorityMap = {};
    for (int i = 0; i < _sourceOrderList.length; i++) {
      priorityMap[_sourceOrderList[i]] = i;
    }
    int pos(String key) {
      if (priorityMap.containsKey(key)) return priorityMap[key]! + 1;
      final idx = defaultOrder.indexOf(key);
      return idx != -1 ? idx + 1 : 99;
    }

    final enabledKeys = priorityMap.keys.toList();
    if (enabledKeys.isEmpty) enabledKeys.addAll(defaultOrder);

    final Map<String, Widget> sourceWidgets = {};

    if (_showStravo && stravoStreams.isNotEmpty && enabledKeys.contains('stravo')) {
      sourceWidgets['stravo'] = _buildServerGroupCard(
        title: '${pos('stravo')}. Stravo Server',
        subtitle: '${stravoStreams.length} direct links available',
        icon: Icons.flash_on_rounded,
        accentColor: Colors.amberAccent,
        onTap: () => setState(() => _activeGroupType = StreamSourceType.stravo),
      );
    }

    if (_showTorrent && torrentioStreams.isNotEmpty && enabledKeys.contains('torrent')) {
      sourceWidgets['torrent'] = _buildServerGroupCard(
        title: '${pos('torrent')}. Torrentio Magnet Server',
        subtitle: '${torrentioStreams.length} magnet links available',
        icon: Icons.downloading_rounded,
        accentColor: Colors.purpleAccent,
        onTap: () => setState(() => _activeGroupType = StreamSourceType.torrentio),
      );
    }

    if (_showStremioAddon && stremioAddonStreams.isNotEmpty && enabledKeys.contains('stremioAddon')) {
      sourceWidgets['stremioAddon'] = _buildServerGroupCard(
        title: '${pos('stremioAddon')}. Stremio Addons Server',
        subtitle: '${stremioAddonStreams.length} streams from custom addons',
        icon: Icons.extension_rounded,
        accentColor: Colors.indigoAccent,
        onTap: () => setState(() => _activeGroupType = StreamSourceType.stremioAddon),
      );
    }

    if (_showStalker && stalkerStreams.isNotEmpty && enabledKeys.contains('stalker')) {
      sourceWidgets['stalker'] = _buildServerGroupCard(
        title: '${pos('stalker')}. Stalker VOD Server',
        subtitle: '${stalkerStreams.length} IPTV VOD streams available',
        icon: Icons.live_tv_rounded,
        accentColor: Colors.redAccent,
        onTap: () => setState(() => _activeGroupType = StreamSourceType.stalker),
      );
    }

    if (_showCinemm && cinemmStreams.isNotEmpty && enabledKeys.contains('cinemm')) {
      sourceWidgets['cinemm'] = _buildServerGroupCard(
        title: '${pos('cinemm')}. CineMM Web Player',
        subtitle: '1 embed web player stream available',
        icon: Icons.web_rounded,
        accentColor: Colors.blueAccent,
        onTap: () => _playStream(cinemmStreams.first, movieTitle, posterPath),
      );
    }

    final sortedKeys = sourceWidgets.keys.toList()
      ..sort((a, b) => pos(a).compareTo(pos(b)));

    if (sortedKeys.isEmpty) {
      return Center(
        child: Text('No stream links found for this title.', style: GoogleFonts.outfit(color: Colors.white54)),
      );
    }

    return ListView(
      children: sortedKeys.map((k) => sourceWidgets[k]!).toList(),
    );
  }

  Widget _buildSubStreamList(StreamSourceType type, String movieTitle, String? posterPath) {
    List<StreamSource> targetList = [];
    String titleStr = '';

    switch (type) {
      case StreamSourceType.stravo:
        targetList = stravoStreams;
        titleStr = 'Stravo Streams';
        break;
      case StreamSourceType.torrentio:
        targetList = torrentioStreams;
        titleStr = 'Torrentio Magnet Streams';
        break;
      case StreamSourceType.stremioAddon:
        targetList = stremioAddonStreams;
        titleStr = 'Stremio Addons';
        break;
      case StreamSourceType.stalker:
        targetList = stalkerStreams;
        titleStr = 'Stalker IPTV VOD';
        break;
      default:
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => setState(() => _activeGroupType = null),
            ),
            Text(titleStr, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: targetList.length,
            itemBuilder: (context, idx) {
              final src = targetList[idx];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  title: Text(src.name, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(src.url, style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.play_circle_fill_rounded, color: AppColors.accentBright),
                  onTap: () => _playStream(src, movieTitle, posterPath),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildServerGroupCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.3)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: accentColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: accentColor, size: 22),
        ),
        title: Text(title, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }
}
