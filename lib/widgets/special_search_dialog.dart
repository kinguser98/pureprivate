import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/screens/video_player_screen.dart';
import 'package:private_cinema_mobile/screens/webview_player_screen.dart';
import 'package:private_cinema_mobile/data/stalker_resolver.dart';
import 'package:private_cinema_mobile/data/netmirror_resolver.dart';
import 'package:private_cinema_mobile/data/api_service.dart';
import 'package:private_cinema_mobile/data/embed_resolver.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:io';

class SpecialSearchDialog extends StatefulWidget {
  const SpecialSearchDialog({super.key});

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
    });

    try {
      const apiKey = '3a73619bbb8fc6d47742d1b5b2b707b5';
      final targetUrl = 'https://api.themoviedb.org/3/search/movie?api_key=$apiKey&query=${Uri.encodeComponent(query)}';
      final proxyUrl = 'https://movie-scraper-beige.vercel.app/api?url=${Uri.encodeComponent(targetUrl)}';
      
      debugPrint('TMDB Search via Proxy: $proxyUrl');
      final response = await http.get(Uri.parse(proxyUrl)).timeout(const Duration(seconds: 10));
      
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
          SnackBar(content: Text('Search failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _onMovieSelected(dynamic movieData) async {
    setState(() {
      _selectedMovie = movieData;
      _loadingDetails = true;
      _imdbId = null;
      _resolvedSources = [];
      _resolvingStreams = false;
      _activeGroupType = null;
    });

    final tmdbId = movieData['id']?.toString();
    if (tmdbId == null) {
      setState(() => _loadingDetails = false);
      return;
    }

    try {
      const apiKey = '3a73619bbb8fc6d47742d1b5b2b707b5';
      final targetUrl = 'https://api.themoviedb.org/3/movie/$tmdbId?api_key=$apiKey';
      final proxyUrl = 'https://movie-scraper-beige.vercel.app/api?url=${Uri.encodeComponent(targetUrl)}';
      
      debugPrint('TMDB Details via Proxy: $proxyUrl');
      final detailsResponse = await http.get(Uri.parse(proxyUrl)).timeout(const Duration(seconds: 10));

      if (detailsResponse.statusCode == 200) {
        final details = json.decode(detailsResponse.body);
        final rawImdb = details['imdb_id']?.toString() ?? '';
        
        if (mounted) {
          setState(() {
            _imdbId = rawImdb.isNotEmpty && rawImdb != 'null' ? rawImdb : null;
            _loadingDetails = false;
          });
          // Resolve streams now
          _resolveMovieStreams(tmdbId, _imdbId, movieData['title']?.toString() ?? 'Movie');
        }
      } else {
        throw Exception('Failed to fetch details');
      }
    } catch (e) {
      debugPrint('Failed fetching movie external IDs: $e');
      if (mounted) {
        setState(() => _loadingDetails = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed loading movie details.'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _resolveMovieStreams(String tmdbId, String? imdbId, String title) async {
    setState(() {
      _resolvingStreams = true;
      _resolvedSources = [];
    });

    final List<Future<void>> tasks = [];

    // 1. Resolve VidLink (requires TMDB or IMDB ID)
    final activeId = (imdbId != null && imdbId.isNotEmpty) ? imdbId : tmdbId;
    tasks.add(_resolveVidLink(activeId));

    if (imdbId != null && imdbId.isNotEmpty) {
      // 2. Resolve Stravo (requires IMDB ID)
      tasks.add(_resolveStravo(imdbId));

      // 3. Resolve Torrentio (requires IMDB ID)
      tasks.add(_resolveTorrentio(imdbId, title));
    }

    // 4. Resolve Stalker Synced VOD Database (requires movie title)
    tasks.add(_resolveStalkerVodDatabase(title));

    // 5. Resolve NetMirror API Scraper (requires movie title)
    tasks.add(_resolveNetmirror(title));

    await Future.wait(tasks);

    if (mounted) {
      setState(() {
        _resolvingStreams = false;
      });
    }
  }

  Future<void> _resolveTamilBlastersClientSide(String title, String year) async {
    HeadlessInAppWebView? headlessWebView;
    InAppWebViewController? headlessController;
    Function(InAppWebViewController, WebUri?)? currentOnLoadStop;

    try {
      debugPrint('TamilBlasters ClientScraper: Resolving client-side via HeadlessWebView for $title ($year)...');
      
      // 1. Fetch active domains dynamically to handle domain hopping
      final domainsRes = await http.get(Uri.parse('https://raw.githubusercontent.com/phisher98/TVVVV/refs/heads/main/domains.json')).timeout(const Duration(seconds: 5));
      if (domainsRes.statusCode != 200) return;
      
      final domainsJson = json.decode(domainsRes.body);
      final mainUrl = domainsJson['tamilblasters']?.toString() ?? 'https://www.1tamilblasters.republican';
      
      // 2. Load search page in background
      final searchUrl = '$mainUrl/?s=${Uri.encodeComponent(title)}';
      debugPrint('TamilBlasters ClientScraper: Loading search page in background: $searchUrl');
      
      var pageLoadCompleter = Completer<void>();
      currentOnLoadStop = (controller, url) {
        if (!pageLoadCompleter.isCompleted) {
          pageLoadCompleter.complete();
        }
      };

      headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(searchUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true,
        ),
        onWebViewCreated: (controller) {
          headlessController = controller;
        },
        onLoadStop: (controller, url) {
          if (currentOnLoadStop != null) {
            currentOnLoadStop!(controller, url);
          }
        },
      );

      await headlessWebView.run();

      await pageLoadCompleter.future.timeout(const Duration(seconds: 12)).catchError((e) {
        debugPrint('TamilBlasters ClientScraper: Search page loading timed out');
      });

      if (headlessController == null) {
        return;
      }
      
      final searchHtml = await headlessController!.evaluateJavascript(source: "document.documentElement.outerHTML") as String? ?? '';
      
      // regex matches: <h2 ...> <a href="..."> TITLE </a> </h2>
      final searchRegex = RegExp(
        r'<h2[^>]*>\s*<a\s+[^>]*href="([^"]+)"[^>]*>([^<]+)</a>\s*</h2>',
        caseSensitive: false,
        multiLine: true,
      );
      final matches = searchRegex.allMatches(searchHtml).toList();
      
      final List<Map<String, String>> matchedPages = [];
      final cleanedSearchTitle = title.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
      
      for (final match in matches) {
        final href = match.group(1);
        final name = match.group(2) ?? '';
        final nameLower = name.toLowerCase();
        final cleanedName = nameLower.replaceAll(RegExp(r'[^\w\s]'), '').trim();
        
        if (href != null && (nameLower.contains(cleanedSearchTitle) || cleanedName.contains(cleanedSearchTitle))) {
          if (year.isEmpty || nameLower.contains(year)) {
            matchedPages.add({
              'url': href,
              'title': name,
            });
          }
        }
      }
      
      // Fallback if no matching page found but matches are not empty
      if (matchedPages.isEmpty && matches.isNotEmpty) {
        final fallbackHref = matches.first.group(1);
        final fallbackTitle = matches.first.group(2) ?? 'TamilBlasters';
        if (fallbackHref != null) {
          matchedPages.add({
            'url': fallbackHref,
            'title': fallbackTitle,
          });
        }
      }
      
      if (matchedPages.isEmpty) {
        debugPrint('TamilBlasters ClientScraper: No matched search page found.');
        return;
      }
      
      final List<StreamSourceInfo> localSources = [];
      
      // Scrape up to 4 top matched pages
      for (final page in matchedPages.take(4)) {
        final pageUrl = page['url']!;
        final pageTitle = page['title']!;
        
        debugPrint('TamilBlasters ClientScraper: Loading detail page: $pageUrl');
        var detailLoadCompleter = Completer<void>();
        currentOnLoadStop = (controller, url) {
          if (!detailLoadCompleter.isCompleted) {
            detailLoadCompleter.complete();
          }
        };

        await headlessController!.loadUrl(
          urlRequest: URLRequest(
            url: WebUri(pageUrl),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
          ),
        );
        
        await detailLoadCompleter.future.timeout(const Duration(seconds: 12)).catchError((e) {
          debugPrint('TamilBlasters ClientScraper: Detail page loading timed out');
        });
        
        final detailHtml = await headlessController!.evaluateJavascript(source: "document.documentElement.outerHTML") as String? ?? '';
        
        final iframeRegex = RegExp(r'<iframe\s+[^>]*src="([^"]+)"', caseSensitive: false);
        final iframeMatches = iframeRegex.allMatches(detailHtml);
        
        final List<String> pageEmbeds = [];
        for (final match in iframeMatches) {
          var src = match.group(1);
          if (src != null) {
            if (src.startsWith('//')) {
              src = 'https:$src';
            }
            if (!src.contains('youtube') && 
                !src.contains('facebook') && 
                !src.contains('twitter') && 
                !src.contains('instagram') && 
                !pageEmbeds.contains(src)) {
              pageEmbeds.add(src);
            }
          }
        }
        
        debugPrint('TamilBlasters ClientScraper: Found ${pageEmbeds.length} embeds on page: $pageTitle');
        
        // Format page title to remove tags, domain names, file sizes, and trailing codecs
        String displayTitle = pageTitle;
        displayTitle = displayTitle
            .replaceAll(RegExp(r'\(TamilBlasters\)', caseSensitive: false), '')
            .replaceAll(RegExp(r'www\.1TamilBlasters\.\w+', caseSensitive: false), '')
            .replaceAll(RegExp(r'\[\s*1\s*tamilblasters\s*\]', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s+-\s+x264.*$', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s+-\s+700MB.*$', caseSensitive: false), '')
            .trim();
            
        for (var url in pageEmbeds) {
          String hostName = 'Embed';
          final urlLower = url.toLowerCase();
          if (urlLower.contains('hgcloud') || urlLower.contains('hglink') || urlLower.contains('cavanhabg')) {
            hostName = 'HG Cloud';
            // Do not swap domains to dead cavanhabg.com anymore. 
            // Keep original domains like hglink.to which resolve properly on device connection.
          } else if (urlLower.contains('streamtape')) {
            hostName = 'Streamtape';
          } else if (urlLower.contains('filemoon')) {
            hostName = 'Filemoon';
          } else if (urlLower.contains('vidplay')) {
            hostName = 'Vidplay';
          } else if (urlLower.contains('vidhide') || urlLower.contains('tryzendm')) {
            hostName = 'VidHide';
          } else if (urlLower.contains('lulu') || urlLower.contains('lulustream') || urlLower.contains('lulupwr')) {
            hostName = 'LuluStream';
          }
          
          final serverName = '$hostName - $displayTitle';
          
          final isDup = _resolvedSources.any((s) => s.url == url) || localSources.any((s) => s.url == url);
          if (!isDup) {
            localSources.add(StreamSourceInfo(
              name: serverName,
              url: url,
              type: StreamSourceType.tamilblasters,
            ));
          }
        }
      }
      
      if (mounted && localSources.isNotEmpty) {
        setState(() {
          _resolvedSources.addAll(localSources);
        });
      }
    } catch (e) {
      debugPrint('TamilBlasters ClientScraper error: $e');
    } finally {
      await headlessWebView?.dispose();
    }
  }



  Future<void> _resolveVidLink(String activeId) async {
    try {
      final url = 'https://movie-scraper-beige.vercel.app/api?id=$activeId';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rawUrl = data['url'] as String?;
        if (rawUrl != null && rawUrl.isNotEmpty) {
          if (mounted) {
            setState(() {
              _resolvedSources.add(StreamSourceInfo(
                name: 'VidLink (Native Proxy)',
                url: rawUrl,
                type: StreamSourceType.vidlink,
              ));
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
      final url = '${ApiService.apiUrl}?action=get_stalker_vod_movies&search=${Uri.encodeComponent(title)}';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final movies = data['movies'] as List<dynamic>? ?? [];
        final List<StreamSourceInfo> sources = [];
        
        for (final item in movies) {
          final portalId = int.tryParse(item['portal_id']?.toString() ?? '') ?? 1;
          final cmd = item['cmd']?.toString() ?? '';
          final name = item['name']?.toString() ?? 'Stalker VOD';
          
          if (cmd.isNotEmpty) {
            // As requested, focus on Portal 2 VODs only (Airtel)
            if (portalId == 2) {
              final isDup = _resolvedSources.any((s) => s.url == 'stalker://$portalId$cmd') || sources.any((s) => s.url == 'stalker://$portalId$cmd');
              if (!isDup) {
                sources.add(StreamSourceInfo(
                  name: 'Stalker: $name',
                  url: 'stalker://$portalId$cmd',
                  type: StreamSourceType.stalker,
                ));
              }
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

  Future<void> _resolveStravo(String imdbId) async {
    try {
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
            
            if (cleanName.contains('🖥️') || name.contains('🖥️') || title.contains('🖥️')) {
              continue; // Skip direct PC streams as requested
            }

            final isDup = _resolvedSources.any((s) => s.url == urlStr) || sources.any((s) => s.url == urlStr);
            if (!isDup) {
              sources.add(StreamSourceInfo(
                name: 'Stravo: $cleanName',
                url: urlStr,
                type: StreamSourceType.stravo,
              ));
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

  Future<void> _resolveTorrentio(String imdbId, String title) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final addonBaseUrl = prefs.getString('torrentio_addon_url') ?? 'https://torrentio.strem.fun';
      var baseUrl = addonBaseUrl.trim();
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      final url = '$baseUrl/providers=yts,eztv,rarbg,1337x,torrent9,kickasstorrents|limit=5/stream/movie/$imdbId.json';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

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
            final mainTitle = titleLines.isNotEmpty ? titleLines[0] : 'Direct Stream';
            final peerInfo = titleLines.length > 1 ? titleLines[1] : '';
            final sizeInfo = titleLines.length > 2 ? titleLines[2] : '';
            
            var sourceName = '$streamName: $mainTitle';
            if (peerInfo.isNotEmpty || sizeInfo.isNotEmpty) {
              sourceName += ' ($peerInfo ${sizeInfo.isNotEmpty ? "• $sizeInfo" : ""})';
            }
            sourceName = sourceName.replaceAll('\n', ' ').trim();
            
            // Extract custom request headers if defined by the addon
            final Map<String, String> headers = {};
            if (stream['behaviorHints']?['requestHeaders'] is Map) {
              (stream['behaviorHints']['requestHeaders'] as Map).forEach((k, v) {
                headers[k.toString()] = v.toString();
              });
            }
            
            var finalUrl = directUrl;
            if (headers.isNotEmpty) {
              finalUrl = Uri.parse(directUrl).replace(queryParameters: {
                ...Uri.parse(directUrl).queryParameters,
                'headers': jsonEncode(headers),
              }).toString();
            }
            
            final isDup = _resolvedSources.any((s) => s.url == finalUrl) || sources.any((s) => s.url == finalUrl);
            if (!isDup) {
              sources.add(StreamSourceInfo(
                name: sourceName,
                url: finalUrl,
                type: StreamSourceType.torrent,
              ));
            }
          } else if (infoHash.isNotEmpty) {
            final trackers = [
              'udp://tracker.coppersurfer.tk:6969/announce',
              'udp://tracker.openbittorrent.com:6969/announce',
              'udp://tracker.opentrackr.org:1337/announce',
              'udp://tracker.leechers-paradise.org:6969/announce',
              'udp://open.stealth.si:80/announce',
            ];
            final trackersQuery = trackers.map((t) => 'tr=${Uri.encodeComponent(t)}').join('&');
            final magnetLink = 'magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(title)}&$trackersQuery';

            final titleLines = streamTitle.split('\n');
            final mainTitle = titleLines.isNotEmpty ? titleLines[0] : 'Torrent';
            final peerInfo = titleLines.length > 1 ? titleLines[1] : '';
            final sizeInfo = titleLines.length > 2 ? titleLines[2] : '';

            var sourceName = mainTitle;
            if (peerInfo.isNotEmpty || sizeInfo.isNotEmpty) {
              sourceName += ' ($peerInfo ${sizeInfo.isNotEmpty ? "• $sizeInfo" : ""})';
            }
            sourceName = sourceName
                .replaceAll('👥', ' Peers:')
                .replaceAll('👤', ' Seeders:')
                .replaceAll('\n', ' ')
                .trim();

            final isDup = _resolvedSources.any((s) => s.url == magnetLink) || sources.any((s) => s.url == magnetLink);
            if (!isDup) {
              sources.add(StreamSourceInfo(
                name: 'Torrent: $sourceName',
                url: magnetLink,
                type: StreamSourceType.torrent,
              ));
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

  void _playStream(StreamSourceInfo source, String movieTitle, String? posterPath) async {
    if (source.type == StreamSourceType.netmirror) {
      // 1. Show pre-flight loading indicator
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.tealAccent),
        ),
      );

      try {
        final uri = Uri.parse(source.url);
        
        // Extract headers from URL parameters to fetch the playlist
        final Map<String, String> headers = {};
        if (uri.queryParameters.containsKey('headers')) {
          final jsonHeaders = jsonDecode(uri.queryParameters['headers']!);
          if (jsonHeaders is Map) {
            jsonHeaders.forEach((k, v) {
              headers[k.toString()] = v.toString();
            });
          }
        }

        // Fetch master playlist
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 8);
        final req = await client.getUrl(uri);
        headers.forEach((k, v) {
          req.headers.set(k, v);
        });
        final res = await req.close();
        
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          client.close();

          // Parse audio tracks: #EXT-X-MEDIA:TYPE=AUDIO,...,NAME="LanguageName",...
          final audioLines = body.split('\n').where((line) => line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO')).toList();
          final List<String> audioLanguages = [];
          
          for (final line in audioLines) {
            final nameMatch = RegExp(r'NAME="([^"]+)"').firstMatch(line);
            if (nameMatch != null) {
              final langName = nameMatch.group(1)!;
              if (!audioLanguages.contains(langName)) {
                audioLanguages.add(langName);
              }
            }
          }

          if (mounted) {
            Navigator.of(context).pop(); // Dismiss loader
          }

          String? selectedLanguage;
          if (audioLanguages.length > 1) {
            // Show selection dialog
            selectedLanguage = await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (context) {
                return AlertDialog(
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: Text(
                    'Select Audio Language',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  content: Container(
                    width: double.maxFinite,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: audioLanguages.length,
                      itemBuilder: (context, index) {
                        final lang = audioLanguages[index];
                        return ListTile(
                          title: Text(lang, style: const TextStyle(color: Colors.white)),
                          leading: const Icon(Icons.audiotrack_rounded, color: Colors.tealAccent),
                          onTap: () => Navigator.of(context).pop(lang),
                        );
                      },
                    ),
                  ),
                );
              },
            );
          }

          // Open player with selected language
          if (mounted) {
            var finalUrl = source.url;
            if (selectedLanguage != null && selectedLanguage.isNotEmpty) {
              // Encode selected_audio into query parameters so proxy can rewrite HLS playlist
              final sourceUri = Uri.parse(source.url);
              finalUrl = sourceUri.replace(queryParameters: {
                ...sourceUri.queryParameters,
                'selected_audio': selectedLanguage
              }).toString();
            }

            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => VideoPlayerScreen(
                  videoSource: finalUrl,
                  title: movieTitle,
                  subtitle: 'NetMirror Server',
                  movieId: 'special_search_${_selectedMovie['id']}',
                  resumeDirectly: false,
                  headers: headers,
                ),
              ),
            );
          }
        } else {
          client.close();
          throw Exception('HLS Master playlist returned status ${res.statusCode}');
        }
      } catch (e) {
        // Fallback: If pre-flight check fails or times out, launch the stream directly
        debugPrint('Netmirror pre-flight check failed: $e. Launching stream directly.');
        if (mounted) {
          Navigator.of(context).pop(); // Dismiss loader if still open
          
          final uri = Uri.parse(source.url);
          final Map<String, String> headers = {};
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
                subtitle: 'NetMirror Server',
                movieId: 'special_search_${_selectedMovie['id']}',
                resumeDirectly: false,
                headers: headers,
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
        final resolved = await StalkerResolver.resolveStream(cmd, portalId, isLive: false);
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
            SnackBar(content: Text('Failed to resolve Stalker stream: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } else if (source.url.startsWith('magnet:')) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WebViewPlayerScreen(
            embedUrl: source.url,
            title: movieTitle,
            backdropUrl: posterPath != null ? 'https://image.tmdb.org/t/p/w780$posterPath' : null,
          ),
        ),
      );
    } else {
      final isWebEmbed = source.url.contains('vidsrc') ||
                         source.url.contains('embed') ||
                         source.url.contains('player') ||
                         source.url.contains('vidlink.pro') ||
                         source.url.contains('woof.video') ||
                         source.url.contains('streamtape') ||
                         source.url.contains('dood') ||
                         source.url.contains('mixdrop') ||
                         source.url.contains('hgcloud') ||
                         source.url.contains('/e/');

      if (isWebEmbed) {
        try {
          final resolvedUrl = await EmbedResolver.resolve(context, source.url);
          if (mounted) {
            if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
              final headers = EmbedResolver.getHeadersForUrl(resolvedUrl);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VideoPlayerScreen(
                    videoSource: resolvedUrl,
                    title: movieTitle,
                    subtitle: 'Resolved Stream',
                    movieId: 'special_search_${_selectedMovie['id']}',
                    resumeDirectly: false,
                    headers: headers,
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to resolve direct streaming link.'), backgroundColor: Colors.redAccent),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error resolving stream: $e'), backgroundColor: Colors.redAccent),
            );
          }
        }
      } else {
        // It is already a direct stream (Stravo, Stalker resolved url, etc.)
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoPlayerScreen(
              videoSource: source.url,
              title: movieTitle,
              subtitle: 'Direct Online Source',
              movieId: 'special_search_${_selectedMovie['id']}',
              resumeDirectly: false,
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
                constraints: const BoxConstraints(maxWidth: 480, maxHeight: 650),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
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
                              ? _buildMovieDetailsView() 
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
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
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
            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
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
        // Search Input
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                hintText: 'Search movies live online...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.5)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
        ),

        // Results / Loading state
        Expanded(
          child: _searching
              ? Center(child: CircularProgressIndicator(color: AppColors.accentBright))
              : _searchResults.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final item = _searchResults[index];
                        final title = item['title']?.toString() ?? 'Unknown Title';
                        final rawYear = item['release_date']?.toString().split('-').first ?? '';
                        final year = rawYear.isNotEmpty ? rawYear : 'N/A';
                        final lang = item['original_language']?.toString().toUpperCase() ?? 'EN';
                        final posterPath = item['poster_path']?.toString();
                        
                        return Card(
                          color: Colors.white.withValues(alpha: 0.03),
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                                            errorBuilder: (_, __, ___) => _buildFallbackPoster(),
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
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.white12,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                year,
                                                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: AppColors.accentBright.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                lang,
                                                style: TextStyle(color: AppColors.accentBright, fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded, color: Colors.white38),
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
      child: const Icon(Icons.movie_filter_rounded, color: Colors.white30, size: 20),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.travel_explore_rounded, size: 48, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            _searchController.text.isNotEmpty ? 'No movie found.' : 'Search beyond your library',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildMovieDetailsView() {
    final title = _selectedMovie['title']?.toString() ?? 'Movie Title';
    final posterPath = _selectedMovie['poster_path']?.toString();
    final rawYear = _selectedMovie['release_date']?.toString().split('-').first ?? '';
    final year = rawYear.isNotEmpty ? rawYear : 'N/A';
    final lang = _selectedMovie['original_language']?.toString().toUpperCase() ?? 'EN';

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
                          child: const Icon(Icons.movie_rounded, color: Colors.white30, size: 32),
                        ),
                      )
                    : Container(
                        width: 80,
                        height: 120,
                        color: Colors.white12,
                        child: const Icon(Icons.movie_rounded, color: Colors.white30, size: 32),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            year,
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accentBright.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            lang,
                            style: TextStyle(color: AppColors.accentBright, fontSize: 12, fontWeight: FontWeight.bold),
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
            _activeGroupType == null ? 'SELECT STREAM SERVER' : '${_activeGroupType!.name.toUpperCase()} SERVER LINKS',
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
            child: _loadingDetails || (_resolvingStreams && _resolvedSources.isEmpty)
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: AppColors.accentBright),
                        const SizedBox(height: 14),
                        Text(
                          _loadingDetails ? 'Retrieving metadata...' : 'Resolving sources from Stremio & VidLink...',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
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
                  if (_activeGroupType != null) {
                    _activeGroupType = null;
                  } else {
                    _selectedMovie = null;
                  }
                });
              },
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: Text(_activeGroupType != null ? 'BACK TO SERVERS' : 'BACK TO SEARCH'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamSelectionContent(String movieTitle, String? posterPath) {
    final stravoStreams = _resolvedSources.where((s) => s.type == StreamSourceType.stravo).toList();
    final vidlinkStreams = _resolvedSources.where((s) => s.type == StreamSourceType.vidlink).toList();
    final torrentStreams = _resolvedSources.where((s) => s.type == StreamSourceType.torrent).toList();
    final stalkerStreams = _resolvedSources.where((s) => s.type == StreamSourceType.stalker).toList();
    final netmirrorStreams = _resolvedSources.where((s) => s.type == StreamSourceType.netmirror).toList();

    if (_activeGroupType == null) {
      // 1. Server groups main list
      return ListView(
        children: [
          // Stravo Server Group
          _buildServerGroupCard(
            title: '1. Stravo Server',
            subtitle: _resolvingStreams && stravoStreams.isEmpty 
                ? 'Searching streams...' 
                : '${stravoStreams.length} links available',
            icon: Icons.rocket_launch_rounded,
            accentColor: Colors.cyan,
            onTap: stravoStreams.isEmpty 
                ? null 
                : () => setState(() => _activeGroupType = StreamSourceType.stravo),
          ),
          
          // VidLink Server Group
          _buildServerGroupCard(
            title: '2. Vidlink Server',
            subtitle: _resolvingStreams && vidlinkStreams.isEmpty 
                ? 'Resolving stream...' 
                : (vidlinkStreams.isNotEmpty ? '1 native link available' : 'Not available for this title'),
            icon: Icons.play_arrow_rounded,
            accentColor: AppColors.accentBright,
            onTap: vidlinkStreams.isEmpty 
                ? null 
                : () => _playStream(vidlinkStreams.first, movieTitle, posterPath),
          ),

          // Torrent Server Group
          _buildServerGroupCard(
            title: '3. Torrent Server',
            subtitle: _resolvingStreams && torrentStreams.isEmpty 
                ? 'Scraping torrents...' 
                : '${torrentStreams.length} links available',
            icon: Icons.cloud_circle_rounded,
            accentColor: Colors.amber,
            onTap: torrentStreams.isEmpty 
                ? null 
                : () => setState(() => _activeGroupType = StreamSourceType.torrent),
          ),

          // Stalker Server Group (Portal 2 VODs)
          _buildServerGroupCard(
            title: '4. Stalker VOD Server (Portal 2)',
            subtitle: _resolvingStreams && stalkerStreams.isEmpty 
                ? 'Searching local library...' 
                : (stalkerStreams.isNotEmpty ? '${stalkerStreams.length} links available' : 'Not available'),
            icon: Icons.movie_filter_rounded,
            accentColor: Colors.purpleAccent,
            onTap: stalkerStreams.isEmpty 
                ? null 
                : () => setState(() => _activeGroupType = StreamSourceType.stalker),
          ),

          // NetMirror Server Group
          _buildServerGroupCard(
            title: '5. NetMirror Server (NF/PV/HS)',
            subtitle: _resolvingStreams && netmirrorStreams.isEmpty 
                ? 'Searching NetMirror...' 
                : (netmirrorStreams.isNotEmpty ? '${netmirrorStreams.length} links available' : 'Not available'),
            icon: Icons.language_rounded,
            accentColor: Colors.tealAccent,
            onTap: netmirrorStreams.isEmpty 
                ? null 
                : () => setState(() => _activeGroupType = StreamSourceType.netmirror),
          ),

        ],
      );
    } else {
      // 2. Expanded group sub-links list
      final activeList = _activeGroupType == StreamSourceType.stravo 
          ? stravoStreams 
          : (_activeGroupType == StreamSourceType.torrent 
              ? torrentStreams 
              : (_activeGroupType == StreamSourceType.stalker 
                  ? stalkerStreams 
                  : netmirrorStreams));
      final accentColor = _activeGroupType == StreamSourceType.stravo 
          ? Colors.cyan 
          : (_activeGroupType == StreamSourceType.torrent 
              ? Colors.amber 
              : (_activeGroupType == StreamSourceType.stalker 
                  ? Colors.purpleAccent 
                  : Colors.tealAccent));
      final iconData = _activeGroupType == StreamSourceType.stravo 
          ? Icons.rocket_launch_rounded 
          : (_activeGroupType == StreamSourceType.torrent 
              ? Icons.cloud_circle_rounded 
              : (_activeGroupType == StreamSourceType.stalker 
                  ? Icons.movie_filter_rounded 
                  : Icons.language_rounded));

      if (activeList.isEmpty) {
        return Center(
          child: Text(
            'No links found in this server.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 14),
          ),
        );
      }

      return ListView.builder(
        itemCount: activeList.length,
        itemBuilder: (context, index) {
          final source = activeList[index];
          return Card(
            color: Colors.white.withValues(alpha: 0.04),
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: accentColor.withValues(alpha: 0.15),
                child: Icon(iconData, color: accentColor, size: 20),
              ),
              title: Text(
                source.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
              ),
              trailing: Icon(Icons.play_arrow_rounded, color: Colors.white.withValues(alpha: 0.4)),
              onTap: () => _playStream(source, movieTitle, posterPath),
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
          backgroundColor: accentColor.withValues(alpha: disabled ? 0.05 : 0.15),
          child: Icon(icon, color: accentColor.withValues(alpha: disabled ? 0.4 : 1.0), size: 22),
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

enum StreamSourceType { vidlink, stravo, torrent, stalker, tamilblasters, netmirror }

class StreamSourceInfo {
  final String name;
  final String url;
  final StreamSourceType type;

  StreamSourceInfo({
    required this.name,
    required this.url,
    required this.type,
  });
}
