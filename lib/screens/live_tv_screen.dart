import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/widgets/tv_focusable.dart';
import 'package:private_cinema_mobile/data/stalker_resolver.dart';
import 'package:private_cinema_mobile/data/api_service.dart';
import 'package:private_cinema_mobile/widgets/glass_panel.dart';
import 'package:private_cinema_mobile/screens/video_player_screen.dart';
import 'package:private_cinema_ios/screens/multi_view_player_screen.dart';
import 'package:private_cinema_mobile/data/epg_service.dart';
import 'package:private_cinema_mobile/data/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ViewMode { list, grid }

class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key});

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  List<dynamic> _allChannels = [];
  Map<String, List<dynamic>> _groupedChannels = {};
  List<String> _categories = [];
  String _selectedCategory = '';
  bool _isLoading = true;
  String? _errorMessage;
  bool _isSyncing = false;
  bool _isResolvingStream = false;
  bool _isChannelSelected = false;
  Map<String, dynamic>? _selectedChannel;
  ViewMode _viewMode = ViewMode.list;
  String _resolvingChannelName = '';
  Map<String, String> _logoHeaders = {};

  bool _isSearchActive = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Player? _miniPlayer;
  VideoController? _miniController;
  Map<String, dynamic>? _activeMiniChannel;
  bool _isMiniPlayerPlaying = false;
  bool _isMiniPlayerMuted = false;
  Timer? _miniEpgTimer;
  EpgProgram? _miniCurrentProgram;

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _fetchChannels();
    _loadEPGData();
    
    // Initialize mini player early so it is ready for immediate playback
    _miniPlayer = Player();
    _miniController = VideoController(_miniPlayer!);
    _miniPlayer!.stream.playing.listen((playing) {
      if (mounted) setState(() => _isMiniPlayerPlaying = playing);
    });
    _miniPlayer!.stream.volume.listen((vol) {
      if (mounted) setState(() => _isMiniPlayerMuted = vol == 0.0);
    });
  }

  void _initPrefs() async {
    _cachedPrefs = await SharedPreferences.getInstance();
  }

  @override
  void dispose() {
    _miniEpgTimer?.cancel();
    _miniPlayer?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _loadEPGData() {
    if (!EpgService.isLoaded && !EpgService.isLoading) {
      EpgService.loadEpg().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _fetchChannels() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final headers = await StalkerResolver.getLogoHeaders(1);
      final uri = Uri.parse('${ApiService.apiUrl}?action=get_live_channels');
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      
      if (response.statusCode == 200) {
        final List<dynamic> channels = json.decode(utf8.decode(response.bodyBytes));
        final Map<String, List<dynamic>> grouped = {};
        final List<String> categories = [];
        
        for (final ch in channels) {
          final cat = ch['category_name']?.toString() ?? 'General';
          if (!categories.contains(cat)) {
            categories.add(cat);
          }
          grouped.putIfAbsent(cat, () => []).add(ch);
        }

        if (mounted) {
          setState(() {
            _allChannels = channels;
            _groupedChannels = grouped;
            _categories = categories;
            _selectedCategory = categories.isNotEmpty ? categories.first : '';
            _logoHeaders = headers;
            _isLoading = false;
            _errorMessage = null;
          });

          if (_activeMiniChannel == null && _selectedCategory.isNotEmpty) {
            // Channel loaded — user will tap to play. No auto-play.
          }
        }
      } else {
        throw Exception('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error loading live TV channels: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to connect to IPTV Catalog. Please check database sync and setup.';
        });
      }
    }
  }

  Future<void> _applyLocalAndRemoteSorting() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Sort Categories locally first for instant rendering
      final localCats = prefs.getStringList('local_cats_order_1');
      if (localCats != null && localCats.isNotEmpty) {
        _categories.sort((a, b) {
          final idxA = localCats.indexOf(a);
          final idxB = localCats.indexOf(b);
          if (idxA == -1 && idxB == -1) return 0;
          if (idxA == -1) return 1;
          if (idxB == -1) return -1;
          return idxA.compareTo(idxB);
        });
      }

      // 2. Sort Channels inside categories locally
      for (final cat in _categories) {
        final localChans = prefs.getStringList('local_chans_order_1_$cat');
        if (localChans != null && localChans.isNotEmpty) {
          final list = _groupedChannels[cat];
          if (list != null) {
            list.sort((a, b) {
              final idA = (a['stalker_id'] ?? a['id']).toString();
              final idB = (b['stalker_id'] ?? b['id']).toString();
              final idxA = localChans.indexOf(idA);
              final idxB = localChans.indexOf(idB);
              if (idxA == -1 && idxB == -1) return 0;
              if (idxA == -1) return 1;
              if (idxB == -1) return -1;
              return idxA.compareTo(idxB);
            });
          }
        }
      }

      if (mounted) setState(() {
        _selectedCategory = _categories.isNotEmpty ? _categories.first : '';
      });

      // 3. Background fetch custom category order from cloud/KVDB
      final remoteCats = await SyncService.fetchCategoriesOrder();
      if (remoteCats != null && remoteCats.isNotEmpty) {
        await prefs.setStringList('local_cats_order_1', remoteCats);
        if (mounted) {
          setState(() {
            _categories.sort((a, b) {
              final idxA = remoteCats.indexOf(a);
              final idxB = remoteCats.indexOf(b);
              if (idxA == -1 && idxB == -1) return 0;
              if (idxA == -1) return 1;
              if (idxB == -1) return -1;
              return idxA.compareTo(idxB);
            });
            _selectedCategory = _categories.isNotEmpty ? _categories.first : '';
          });
        }
      }

      // 4. Background fetch channel custom order from cloud/KVDB
      for (final cat in _categories) {
        final remoteChans = await SyncService.fetchChannelsOrder(cat);
        if (remoteChans != null && remoteChans.isNotEmpty) {
          await prefs.setStringList('local_chans_order_1_$cat', remoteChans);
          if (mounted) {
            setState(() {
              final list = _groupedChannels[cat];
              if (list != null) {
                list.sort((a, b) {
                  final idA = (a['stalker_id'] ?? a['id']).toString();
                  final idB = (b['stalker_id'] ?? b['id']).toString();
                  final idxA = remoteChans.indexOf(idA);
                  final idxB = remoteChans.indexOf(idB);
                  if (idxA == -1 && idxB == -1) return 0;
                  if (idxA == -1) return 1;
                  if (idxB == -1) return -1;
                  return idxA.compareTo(idxB);
                });
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error applying custom order sorting: $e');
    }
  }

  Future<void> _onCategoryReorder(int oldIndex, int newIndex) async {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final String item = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, item);
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('local_cats_order_1', _categories);
      await SyncService.saveCategoriesOrder(_categories);
    } catch (e) {
      debugPrint('Failed to save reordered categories: $e');
    }
  }

  Future<void> _onChannelReorder(int oldIndex, int newIndex) async {
    final chans = _groupedChannels[_selectedCategory];
    if (chans == null) return;

    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final dynamic item = chans.removeAt(oldIndex);
      chans.insert(newIndex, item);
    });

    try {
      final channelIds = chans.map((c) => (c['stalker_id'] ?? c['id']).toString()).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('local_chans_order_1_$_selectedCategory', channelIds);
      await SyncService.saveChannelsOrder(_selectedCategory, channelIds);
    } catch (e) {
      debugPrint('Failed to save reordered channels: $e');
    }
  }

  Widget _buildFallbackLogo(String name) {
    final cleanName = name.trim();
    final initial = cleanName.isNotEmpty ? cleanName[0].toUpperCase() : '?';
    final code = name.hashCode.abs();
    final List<Color> gradientColors = [
      Colors.primaries[code % Colors.primaries.length],
      Colors.primaries[(code + 3) % Colors.primaries.length].withValues(alpha: 0.8),
    ];
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withValues(alpha: 0.35),
            blurRadius: 8,
            spreadRadius: 1,
          )
        ],
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _syncChannels() async {
    setState(() {
      _isSyncing = true;
    });

    List<Map<String, dynamic>> portals = [];
    try {
      portals = await StalkerResolver.getAllPortals();
    } catch (e) {
      debugPrint('Error getting portals: $e');
    }

    if (portals.isEmpty) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Stalker Portals configured. Please add one first in the admin panel.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    int? selectedPortalId;
    if (mounted) {
      setState(() => _isSyncing = false);
      selectedPortalId = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (context) => TvPortalPickerDialog(portals: portals),
      );
    }

    if (selectedPortalId == null) return;

    setState(() {
      _isSyncing = true;
    });

    try {
      final syncResult = await StalkerResolver.syncChannelsToServer(selectedPortalId);
      if (mounted) {
        setState(() => _isSyncing = false);
        if (syncResult['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync successful! Imported ${syncResult['imported']} channels.'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchChannels();
        }
      }
    } catch (e) {
      debugPrint('Sync failed: $e');
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _playChannel(Map<String, dynamic> channel) async {
    final name = channel['name']?.toString() ?? 'Live Channel';
    final cmd = channel['cmd']?.toString() ?? '';

    if (cmd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid channel link cmd.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_miniPlayer != null) {
      try {
        await _miniPlayer!.stop();
      } catch (e) {
        debugPrint('Error stopping mini player: $e');
      }
    }

    setState(() {
      _isResolvingStream = true;
      _resolvingChannelName = name;
      _selectedChannel = channel;
      _isChannelSelected = true;
      _activeMiniChannel = null;
    });

    try {
      final portalId = int.tryParse(channel['portal_id']?.toString() ?? '') ?? 1;
      final resolved = await StalkerResolver.resolveStream(cmd, portalId);
      
      if (mounted) {
        if (_miniPlayer == null) {
          _miniPlayer = Player();
          _miniController = VideoController(_miniPlayer!);
          
          _miniPlayer!.stream.playing.listen((playing) {
            if (mounted) setState(() => _isMiniPlayerPlaying = playing);
          });
          _miniPlayer!.stream.volume.listen((vol) {
            if (mounted) setState(() => _isMiniPlayerMuted = vol == 0.0);
          });
        }

        // Configure properties for live stream optimization
        if (_miniPlayer!.platform is NativePlayer) {
          final nativePlayer = _miniPlayer!.platform as NativePlayer;
          await nativePlayer.setProperty('tls-verify', 'no');
          if (!Platform.isIOS) {
            await nativePlayer.setProperty('dns-lookup-family', 'ipv4');
          }
          if (resolved.headers.isNotEmpty) {
            final headerList = <String>[];
            resolved.headers.forEach((key, value) {
              headerList.add('$key: $value');
            });
            if (headerList.isNotEmpty) {
              await nativePlayer.setProperty('http-header-fields', headerList.join(','));
            }
          }
          
          if (Platform.isAndroid) {
            await nativePlayer.setProperty('hwdec', 'mediacodec-copy');
          } else if (Platform.isIOS || Platform.isMacOS) {
            await nativePlayer.setProperty('hwdec', 'videotoolbox');
          } else {
            await nativePlayer.setProperty('hwdec', 'auto');
          }
          
          await nativePlayer.setProperty('cache', 'yes');
          await nativePlayer.setProperty('cache-on-disk', 'no');
          await nativePlayer.setProperty('demuxer-max-bytes', '104857600'); // 100MB buffer limit
          await nativePlayer.setProperty('demuxer-readahead-secs', '30');   // 30 seconds readahead
          await nativePlayer.setProperty('cache-secs', '30');               // 30 seconds cache
          await nativePlayer.setProperty('network-timeout', '30');
          await nativePlayer.setProperty('hr-seek', 'no');
          await nativePlayer.setProperty('video-sync', 'audio');
          await nativePlayer.setProperty('autosync', '10');
          await nativePlayer.setProperty('demuxer-lavf-o', 'http_persistent=0');
        }

        await _miniPlayer!.open(Media(resolved.url, httpHeaders: resolved.headers), play: true);

        final channelId = channel['stalker_id']?.toString() ?? channel['id']?.toString();
        
        setState(() {
          _isResolvingStream = false;
          _activeMiniChannel = channel;
          _miniCurrentProgram = EpgService.getCurrentProgram(channelId, name);
        });

        _miniEpgTimer?.cancel();
        _miniEpgTimer = Timer.periodic(const Duration(minutes: 1), (_) {
          if (mounted && _activeMiniChannel != null) {
            setState(() {
              _miniCurrentProgram = EpgService.getCurrentProgram(channelId, name);
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error resolving channel stream: $e');
      if (mounted) {
        setState(() => _isResolvingStream = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error resolving channel stream: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  List<String> _getFavoriteChannels() {
    final saved = _prefs.getStringList('live_tv_favorites');
    return saved ?? [];
  }

  void _saveFavoriteChannels(List<String> favs) {
    _prefs.setStringList('live_tv_favorites', favs);
  }

  void _toggleFavorite(String channelId) {
    final favs = _getFavoriteChannels();
    if (favs.contains(channelId)) {
      favs.remove(channelId);
    } else {
      favs.add(channelId);
    }
    _saveFavoriteChannels(favs);
    setState(() {});
  }

  SharedPreferences get _prefs => _cachedPrefs;
  late final SharedPreferences _cachedPrefs;

  void _showRecordingDialog(BuildContext context) {
    if (_activeMiniChannel == null) return;
    final name = _activeMiniChannel!['name']?.toString() ?? 'Channel';
    final cmd = _activeMiniChannel!['cmd']?.toString() ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Record $name', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Start recording this live channel?', style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Recording will be saved to your server. Ensure sufficient storage space.',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),)),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _startRecording(cmd, name);
            },
            child: const Text('Start Recording'),
          ),
        ],
      ),
    );
  }

  void _startRecording(String cmd, String name) async {
    try {
      final portalId = int.tryParse(_activeMiniChannel!['portal_id']?.toString() ?? '') ?? 1;
      final resolved = await StalkerResolver.resolveStream(cmd, portalId);

      // Save to local recordings list
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList('live_tv_recordings') ?? [];
      existing.add(json.encode({
        'url': resolved.url,
        'name': name,
        'channel_id': (_activeMiniChannel!['stalker_id'] ?? _activeMiniChannel!['id']).toString(),
        'recorded_at': DateTime.now().toIso8601String(),
      }));
      await prefs.setStringList('live_tv_recordings', existing);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Recording saved: $name'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ));
      }

      // Try to download actual video data in background
      _downloadRecording(resolved.url, name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Recording error: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  void _downloadRecording(String url, String name) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeName = name.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
      final filePath = '${dir.path}/recordings/${safeName}_${DateTime.now().millisecondsSinceEpoch}.ts';
      await File(filePath).create(recursive: true);

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await File(filePath).writeAsBytes(response.bodyBytes);
        debugPrint('Recording downloaded to: $filePath');
      }
    } catch (e) {
      debugPrint('Background recording download failed (stream may be HLS): $e');
    }
  }

  void _expandMiniPlayerToFullScreen() async {
    if (_activeMiniChannel == null || _miniPlayer == null) return;

    final name = _activeMiniChannel!['name']?.toString() ?? 'Live TV';
    final stalkerId = (_activeMiniChannel!['stalker_id'] ?? _activeMiniChannel!['id']).toString();
    final cmd = _activeMiniChannel!['cmd']?.toString() ?? '';
    final portalId = int.tryParse(_activeMiniChannel!['portal_id']?.toString() ?? '') ?? 1;

    await _miniPlayer!.pause();

    final headers = await StalkerResolver.getLogoHeaders(portalId);
    final streamUrl = await StalkerResolver.resolveStream(cmd, portalId).then((res) => res.url).catchError((_) => '');

    if (!mounted) return;

    final isError = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoSource: streamUrl,
          title: name,
          subtitle: 'Live TV | ${_activeMiniChannel!['category_name']}',
          movieId: stalkerId,
          imdbId: stalkerId,
          isLive: true,
          headers: headers,
        ),
      ),
    );

    if (isError != true && mounted && _miniPlayer != null) {
      await _miniPlayer!.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        color: AppColors.background,
        child: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top + 8),
            _buildTopActionBar(context),
            _buildEmbeddedPlayer(context),
            _buildEpgTimeline(context),
            _buildBreadcrumbRow(context),
            _buildSearchRow(context),
            _buildCategoriesChips(context),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: AppColors.accentBright))
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ),
                        )
                      : _buildReorderableChannelList(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActionBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Builder(builder: (ctx) {
            final isFav = _activeMiniChannel != null && _getFavoriteChannels().contains((_activeMiniChannel!['stalker_id'] ?? _activeMiniChannel!['id']).toString());
            return _buildTopActionBtn(isFav ? Icons.star_rounded : Icons.star_border_rounded, 'FAV', () {
              if (_activeMiniChannel == null) return;
              final channelId = (_activeMiniChannel!['stalker_id'] ?? _activeMiniChannel!['id']).toString();
              _toggleFavorite(channelId);
            }, iconColor: isFav ? Colors.yellow : null);
          }),
          _buildTopActionBtn(Icons.format_list_bulleted_rounded, 'EPG', () {
            if (_activeMiniChannel != null) {
              _showEpgGuideModal();
            }
          }),
        ],
      ),
    );
  }

  Widget _buildTopActionBtn(IconData icon, String label, VoidCallback onTap, {Color? iconColor}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor ?? Colors.white70, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmbeddedPlayer(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      height: 205,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: _selectedChannel != null && _miniController != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Video(
                  controller: _miniController!,
                  controls: AdaptiveVideoControls,
                ),
                if (_isResolvingStream || _activeMiniChannel == null)
                  Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AppColors.accentBright),
                          const SizedBox(height: 12),
                          Text(
                            'Connecting to $_resolvingChannelName...',
                            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.tv_rounded, color: Colors.white24, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Select a channel to start playing',
                    style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEpgTimeline(BuildContext context) {
    if (_activeMiniChannel == null) return const SizedBox.shrink();
    final name = _activeMiniChannel!['name']?.toString() ?? '';
    final channelId = (_activeMiniChannel!['stalker_id'] ?? _activeMiniChannel!['id']).toString();
    final current = _miniCurrentProgram;
    final next = EpgService.getNextProgram(channelId, name);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accentBright.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'NOW',
                  style: TextStyle(color: AppColors.accentBright, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  current != null ? current.title : 'Live Streaming',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              if (current != null)
                Text(
                  '${_formatEpgTime(current.startTime)} - ${_formatEpgTime(current.stopTime)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
            ],
          ),
          if (current != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _calculateEpgProgress(current),
                minHeight: 3,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentBright),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'NEXT',
                  style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  next != null ? next.title : 'No upcoming program',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                ),
              ),
              if (next != null)
                Text(
                  'Starts ${_formatEpgTime(next.startTime)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatEpgTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  double _calculateEpgProgress(EpgProgram prog) {
    final now = DateTime.now();
    if (now.isBefore(prog.startTime)) return 0.0;
    if (now.isAfter(prog.stopTime)) return 1.0;
    final total = prog.stopTime.difference(prog.startTime).inSeconds;
    final elapsed = now.difference(prog.startTime).inSeconds;
    return total > 0 ? elapsed / total : 0.0;
  }

  Widget _buildBreadcrumbRow(BuildContext context) {
    final chans = _groupedChannels[_selectedCategory] ?? [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'TV / ${_selectedCategory.toUpperCase()} | TV / ${chans.length} RECORDS',
            style: GoogleFonts.outfit(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const Icon(Icons.swap_vert_rounded, color: Colors.white60, size: 20),
        ],
      ),
    );
  }

  Widget _buildSearchRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search channel...',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 16),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.only(top: 2),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 14),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    _isSearchActive = val.isNotEmpty;
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: IconButton(
              icon: Icon(_viewMode == ViewMode.grid ? Icons.list_rounded : Icons.grid_view_rounded, color: Colors.white70, size: 18),
              onPressed: () => setState(() => _viewMode = _viewMode == ViewMode.grid ? ViewMode.list : ViewMode.grid),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: IconButton(
              icon: const Icon(Icons.splitscreen_rounded, color: Colors.white70, size: 18),
              onPressed: () {
                _miniPlayer?.pause();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MultiViewPlayerScreen(initialChannels: _allChannels),
                  ),
                ).then((_) => _miniPlayer?.play());
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesChips(BuildContext context) {
    if (_categories.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        onReorder: _onCategoryReorder,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = cat == _selectedCategory;

          return Padding(
            key: ValueKey(cat),
            padding: const EdgeInsets.only(right: 8.0),
            child: Center(
              child: ChoiceChip(
                label: Text(
                  cat.toUpperCase(),
                  style: GoogleFonts.outfit(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                selected: isSelected,
                selectedColor: AppColors.accent,
                backgroundColor: Colors.white.withValues(alpha: 0.03),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedCategory = cat;
                    });
                    _loadReorderedChannelsForCategory(cat);
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadReorderedChannelsForCategory(String cat) async {
    try {
      final savedChans = await SyncService.fetchChannelsOrder(cat);
      if (savedChans != null && savedChans.isNotEmpty && mounted) {
        setState(() {
          final list = _groupedChannels[cat];
          if (list != null) {
            list.sort((a, b) {
              final idA = (a['stalker_id'] ?? a['id']).toString();
              final idB = (b['stalker_id'] ?? b['id']).toString();
              final idxA = savedChans.indexOf(idA);
              final idxB = savedChans.indexOf(idB);
              if (idxA == -1 && idxB == -1) return 0;
              if (idxA == -1) return 1;
              if (idxB == -1) return -1;
              return idxA.compareTo(idxB);
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading category reordering: $e');
    }
  }

  Widget _buildChannelItem(Map<String, dynamic> ch, String channelId, String name,
      String logoUrl, bool isPlayingNow, EpgProgram? currentProg, {bool isGrid = false}) {
    final isSelected = _selectedChannel != null &&
        (_selectedChannel!['stalker_id'] ?? _selectedChannel!['id']).toString() == channelId;

    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.accent.withValues(alpha: 0.2)
            : (isPlayingNow
                ? AppColors.accent.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.03)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? AppColors.accentBright
              : (isPlayingNow
                  ? AppColors.accent.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: isGrid ? _buildGridChannelContent(ch, channelId, name, logoUrl) : _buildListChannelContent(ch, channelId, name, logoUrl, currentProg),
    );
  }

  Widget _buildGridChannelContent(Map<String, dynamic> ch, String channelId, String name, String logoUrl) {
    return InkWell(
      onTap: () => _playChannel(ch),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
              child: logoUrl.isNotEmpty
                  ? Image.network(logoUrl, headers: _logoHeaders, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _buildFallbackLogo(name))
                  : _buildFallbackLogo(name),
            ),
            const SizedBox(height: 6),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center),
            Text(channelId, style: const TextStyle(color: Colors.white38, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildListChannelContent(Map<String, dynamic> ch, String channelId, String name, String logoUrl, EpgProgram? currentProg) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      onTap: () => _playChannel(ch),
      leading: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
        child: logoUrl.isNotEmpty
            ? Image.network(logoUrl, headers: _logoHeaders, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _buildFallbackLogo(name))
            : _buildFallbackLogo(name),
      ),
      title: Text(name, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
            child: Text(channelId, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              currentProg != null ? currentProg.title : 'Live TV', maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: currentProg != null ? AppColors.accentBright.withValues(alpha: 0.8) : Colors.white38, fontSize: 11),
            ),
          ),
        ]),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: Icon(
            _getFavoriteChannels().contains(channelId)
                ? Icons.star_rounded
                : Icons.star_border_rounded,
            color: _getFavoriteChannels().contains(channelId)
                ? Colors.yellow
                : Colors.white30,
            size: 20,
          ),
          onPressed: () {
            _toggleFavorite(channelId);
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  Widget _buildReorderableChannelList(BuildContext context) {
    var chans = (_groupedChannels[_selectedCategory] ?? []).where((ch) {
      if (_searchQuery.isEmpty) return true;
      final name = ch['name']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    // Sort favorites to the top
    final favs = _getFavoriteChannels();
    if (favs.isNotEmpty) {
      chans.sort((a, b) {
        final idA = (a['stalker_id'] ?? a['id']).toString();
        final idB = (b['stalker_id'] ?? b['id']).toString();
        final fA = favs.contains(idA);
        final fB = favs.contains(idB);
        if (fA && !fB) return -1;
        if (!fA && fB) return 1;
        return 0;
      });
    }

    if (chans.isEmpty) {
      return Center(
        child: Text(
          'No channels found.',
          style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
        ),
      );
    }

    if (_viewMode == ViewMode.grid) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.85,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: chans.length,
        itemBuilder: (context, index) {
          final ch = chans[index];
          final channelId = (ch['stalker_id'] ?? ch['id']).toString();
          final name = ch['name']?.toString() ?? 'Live Stream';
          final logoUrl = (ch['logo_url']?.toString().isNotEmpty == true) ? ch['logo_url'].toString() : (EpgService.getChannelLogo(channelId, name) ?? '');
          final isPlayingNow = _activeMiniChannel != null && (_activeMiniChannel!['stalker_id'] ?? _activeMiniChannel!['id']).toString() == channelId;
          return _buildChannelItem(ch, channelId, name, logoUrl, isPlayingNow, null, isGrid: true);
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: chans.length,
      itemBuilder: (context, index) {
        final ch = chans[index];
        final channelId = (ch['stalker_id'] ?? ch['id']).toString();
        final name = ch['name']?.toString() ?? 'Live Stream';
        final logoUrl = (ch['logo_url']?.toString().isNotEmpty == true) ? ch['logo_url'].toString() : (EpgService.getChannelLogo(channelId, name) ?? '');
        final isPlayingNow = _activeMiniChannel != null && (_activeMiniChannel!['stalker_id'] ?? _activeMiniChannel!['id']).toString() == channelId;
        final currentProg = EpgService.getCurrentProgram(channelId, name);
        return Padding(
          key: ValueKey(channelId),
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildChannelItem(ch, channelId, name, logoUrl, isPlayingNow, currentProg),
        );
      },
    );
  }

  void _showEpgGuideModal() {
    if (_activeMiniChannel == null) return;
    final name = _activeMiniChannel!['name']?.toString() ?? '';
    final channelId = (_activeMiniChannel!['stalker_id'] ?? _activeMiniChannel!['id']).toString();
    final programs = EpgService.getUpcomingPrograms(channelId, name);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EPG SCHEDULE - $name',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: programs.isEmpty
                    ? const Center(
                        child: Text(
                          'No EPG data available for this channel.',
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.builder(
                        itemCount: programs.length,
                        itemBuilder: (context, index) {
                          final prog = programs[index];
                          final isNow = DateTime.now().isAfter(prog.startTime) && DateTime.now().isBefore(prog.stopTime);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isNow ? AppColors.accent.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.02),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '${_formatEpgTime(prog.startTime)} - ${_formatEpgTime(prog.stopTime)}',
                                  style: TextStyle(
                                    color: isNow ? AppColors.accentBright : Colors.white54,
                                    fontSize: 11,
                                    fontWeight: isNow ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    prog.title,
                                    style: TextStyle(
                                      color: isNow ? Colors.white : Colors.white70,
                                      fontSize: 13,
                                      fontWeight: isNow ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TvPortalPickerDialog extends StatelessWidget {
  final List<Map<String, dynamic>> portals;

  const TvPortalPickerDialog({super.key, required this.portals});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: AlertDialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: SizedBox(
          width: 500,
          height: 380,
          child: GlassPanel(
            borderRadius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SELECT STALKER PORTAL',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose the Stalker Portal you want to sync.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: portals.length,
                    itemBuilder: (context, index) {
                      final p = portals[index];
                      final portalId = int.tryParse(p['id']?.toString() ?? '') ?? 0;
                      final portalName = p['name']?.toString() ?? 'Stalker Portal';
                      final portalUrl = p['portal_url']?.toString() ?? '';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TvFocusable(
                          borderRadius: 10,
                          onPressed: () {
                            Navigator.of(context).pop(portalId);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.settings_input_hdmi, color: AppColors.accentBright),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        portalName,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        portalUrl,
                                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TvFocusable(
                      borderRadius: 8,
                      onPressed: () {
                        Navigator.of(context).pop(null);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Text(
                          'CANCEL',
                          style: GoogleFonts.outfit(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
