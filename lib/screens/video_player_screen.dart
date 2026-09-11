import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/data/playback_tracker.dart';
import 'package:private_cinema_mobile/data/dns_proxy.dart';
import 'package:private_cinema_mobile/data/api_service.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/widgets/glass_panel.dart';
import 'package:private_cinema_mobile/data/epg_service.dart';
import 'package:private_cinema_mobile/data/external_player_service.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:private_cinema_mobile/widgets/marquee_text.dart';
import '../widgets/stream_metadata_tile.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.videoSource,
    this.title,
    this.subtitle,
    this.movieId,
    this.imdbId,
    this.resumeDirectly = false,
    this.headers,
    this.isLive = false,
    this.sourceName,
    this.logoUrl,
    this.season,
    this.episode,
    this.isTvShow = false,
  });

  final String videoSource;
  final String? title;
  final String? subtitle;
  final String? movieId;
  final String? imdbId;
  final bool resumeDirectly;
  final Map<String, String>? headers;
  final bool isLive;
  final String? sourceName;
  final String? logoUrl;
  final int? season;
  final int? episode;
  final bool isTvShow;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  int _lastSavedMs = 0;

  bool _ready = false;
  bool _showControls = true;
  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _showInitialTrackSelector = false;
  AudioTrack? _selectedAudioTrack;
  VideoTrack? _selectedVideoTrack;
  bool _trackSelectorScheduled = false;
  bool _hasStartedPlaying = false;
  bool _hasError = false;
  bool _isSeeking = false;
  double? _dragValue;
  
  Timer? _clockTimer;
  String _timeString = '';
  
  // Zoom & Pan variables
  double _videoScale = 1.0;
  double _baseScale = 1.0;
  Offset _videoOffset = Offset.zero;
  Offset _baseOffset = Offset.zero;
  Offset? _dragStartPoint;
  double? _dragStartVolume;
  double? _dragStartBrightness;
  bool _isDraggingHUD = false;
  
  // Custom aspect ratio values (null = Auto, 16/9, 21/9, 4/3)
  final List<double?> _aspectRatios = [null, 16 / 9, 21 / 9, 4 / 3];
  int _aspectRatioIndex = 0;

  // Gesture HUD values
  double _brightness = 1.0; // 0.0 to 1.0 (black overlay opacity is 1.0 - _brightness)
  double _volume = 80.0; // 0.0 to 100.0
  String? _hudType; // 'brightness', 'volume', 'seek'
  int? _seekOverlayValue; // +10 or -10
  Timer? _hudTimer;

  // Lock Controls State
  bool _controlsLocked = false;

  Timer? _hideControlsTimer;
  Timer? _playerLogoTimer;
  bool _showPlayerLogoCrossFade = true;

  void _startPlayerLogoTimer() {
    if (_playerLogoTimer != null && _playerLogoTimer!.isActive) return;
    if (widget.logoUrl == null || widget.logoUrl!.isEmpty) return;
    _playerLogoTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.logoUrl != null && widget.logoUrl!.isNotEmpty) {
        setState(() => _showPlayerLogoCrossFade = !_showPlayerLogoCrossFade);
      }
    });
  }
  double _subtitleFontSize = 32.0; // Increased by 2x
  bool _isFavorite = false;
  double _playbackSpeed = 1.0;
  double _audioDelay = 0.0;
  double _subtitleDelay = 0.0;

  String? _resolvedSourceUrl;
  Map<String, String>? _resolvedSourceHeaders;
  bool _hasAttemptedFallback = false;

  EpgProgram? _currentProgram;
  EpgProgram? _nextProgram;
  List<EpgProgram> _upcomingPrograms = [];
  Timer? _epgRefreshTimer;

  Future<void> _loadSubtitleSize() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _subtitleFontSize = prefs.getDouble('subtitle_font_size') ?? 32.0;
      });
    }
  }

  Future<void> _changeSubtitleSize(double size) async {
    setState(() {
      _subtitleFontSize = size;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('subtitle_font_size', size);
  }

  Future<void> _changeAudioDelay(double delay) async {
    setState(() {
      _audioDelay = double.parse(delay.toStringAsFixed(3));
    });
    if (_player.platform is NativePlayer) {
      final nativePlayer = _player.platform as NativePlayer;
      await nativePlayer.setProperty('audio-delay', _audioDelay.toString());
      debugPrint('Set audio-delay: $_audioDelay');
    }
  }

  Future<void> _changeSubtitleDelay(double delay) async {
    setState(() {
      _subtitleDelay = double.parse(delay.toStringAsFixed(3));
    });
    if (_player.platform is NativePlayer) {
      final nativePlayer = _player.platform as NativePlayer;
      await nativePlayer.setProperty('sub-delay', _subtitleDelay.toString());
      debugPrint('Set sub-delay: $_subtitleDelay');
    }
  }

  Future<void> _loadFavoriteStatus() async {
    if (widget.movieId == null) return;
    try {
      final isFav = await ApiService.checkFavoriteCloud(widget.movieId!);
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList('favorites') ?? [];
      final localFav = favorites.contains(widget.movieId!);
      if (mounted) {
        setState(() {
          _isFavorite = isFav || localFav;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    if (widget.movieId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot favorite this media')),
      );
      return;
    }
    try {
      final isFav = await ApiService.toggleFavoriteCloud(widget.movieId!);
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList('favorites') ?? [];
      if (isFav) {
        if (!favorites.contains(widget.movieId!)) {
          favorites.add(widget.movieId!);
        }
      } else {
        favorites.remove(widget.movieId!);
      }
      await prefs.setStringList('favorites', favorites);
      if (mounted) {
        setState(() {
          _isFavorite = isFav;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isFav ? 'Added to favorites!' : 'Removed from favorites!')),
      );
    } catch (e) {
      debugPrint('Failed to toggle favorite: $e');
    }
  }

  void _changePlaybackSpeed() {
    final speeds = [1.0, 1.25, 1.5, 1.75, 2.0];
    final currentIndex = speeds.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % speeds.length;
    final nextSpeed = speeds[nextIndex];
    
    setState(() {
      _playbackSpeed = nextSpeed;
    });
    
    _player.setRate(nextSpeed);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playback speed: ${nextSpeed}x')),
    );
  }

  void _updateClock() {
    final now = DateTime.now();
    int hour = now.hour;
    final isAm = hour < 12;
    final amPm = isAm ? 'AM' : 'PM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    final h = hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    if (mounted) {
      setState(() {
        _timeString = '$h:$m $amPm';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    ProxyStats.reset(); // Reset proxy counters
    _loadSubtitleSize();
    _loadFavoriteStatus();
    
    // Force Landscape for video player
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _player = Player();
    _controller = VideoController(_player);
    _bindStreams();
    _open();
    
    _loadEPG();
    _epgRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _loadEPG());
    
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
    _startProxyStatsTimer();
    _startPlayerLogoTimer();
    _initSystemBrightnessAndVolume();
  }

  Future<void> _initSystemBrightnessAndVolume() async {
    try {
      final currentBrightness = await ScreenBrightness().application;
      if (mounted) {
        setState(() => _brightness = currentBrightness.clamp(0.05, 1.0));
      }
    } catch (_) {}
    try {
      await FlutterVolumeController.updateShowSystemUI(false);
      final currentVol = await FlutterVolumeController.getVolume();
      if (currentVol != null && mounted) {
        setState(() => _volume = (currentVol * 100.0).clamp(0.0, 100.0));
        _player.setVolume(_volume);
      }
    } catch (_) {}
  }

  bool _isStreamProxied = false;
  Timer? _proxyStatsTimer;

  void _startProxyStatsTimer() {
    _proxyStatsTimer?.cancel();
    ProxyStats.reset();

    int? maxKnownBytes;
    try {
      final meta = parseStreamMeta(
        '${widget.sourceName ?? ''} ${widget.subtitle ?? ''}',
        widget.videoSource,
      );
      if (meta.sizeInMb > 0) {
        maxKnownBytes = (meta.sizeInMb * 1024 * 1024).round();
      }
    } catch (_) {}

    _proxyStatsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      // If the stream is routed through the local proxy relay, CustomDnsProxy already
      // tracks real network socket throughput and byte transfers directly in real time.
      if (_isStreamProxied) return;

      if (_player.platform is! NativePlayer) return;
      final nativePlayer = _player.platform as NativePlayer;
      try {
        int bytes = 0;
        final res1 = await nativePlayer.getProperty('demuxer-bytes-read');
        bytes = int.tryParse(res1.toString()) ?? 0;
        if (bytes <= 0) {
          final res2 = await nativePlayer.getProperty('bytes-read');
          bytes = int.tryParse(res2.toString()) ?? 0;
        }

        // Query file-size from mpv headers if not already known from stream metadata
        if (maxKnownBytes == null || maxKnownBytes! <= 0) {
          final resSize = await nativePlayer.getProperty('file-size');
          final fs = int.tryParse(resSize.toString()) ?? 0;
          if (fs > 0) {
            maxKnownBytes = fs;
          }
        }

        // If IPC failed or gave 0, NEVER touch baseline (no phantom byte accumulation)
        if (bytes <= 0) return;

        ProxyStats.updateDirectStats(bytes, maxKnownBytes: maxKnownBytes);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    try {
      ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
    _proxyStatsTimer?.cancel();
    _hideControlsTimer?.cancel();
    _hudTimer?.cancel();
    _clockTimer?.cancel();
    _epgRefreshTimer?.cancel();
    _player.dispose();
    
    // Lock back to portrait mode when exiting player
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _bindStreams() {
    _player.stream.playing.listen((v) {
      if (mounted && _playing != v) {
        setState(() => _playing = v);
        if (v) {
          _armHideControls();
        }
      }
    });
    _player.stream.position.listen((v) {
      if (mounted) {
        final lastMs = _position.inMilliseconds;
        final currentMs = v.inMilliseconds;
        _position = v;

        if (currentMs > 0 && !_hasStartedPlaying) {
          _hasStartedPlaying = true;
          // Schedule track selector ~1s after playback actually starts (tracks are populated by then)
          if (!_trackSelectorScheduled) {
            _trackSelectorScheduled = true;
            Future.delayed(const Duration(milliseconds: 1200), () {
              if (mounted && _hasMultipleTracks) {
                setState(() => _showInitialTrackSelector = true);
              }
            });
          }
        }

        // Save progress every 5 seconds
        if (widget.movieId != null && _duration.inMilliseconds > 0 && (currentMs - _lastSavedMs).abs() > 5000) {
          _lastSavedMs = currentMs;
          PlaybackTracker.saveProgress(widget.movieId!, currentMs, _duration.inMilliseconds);
        }

        // Only rebuild UI when controls are visible or every 250ms when visible
        if (_showControls && (currentMs - lastMs).abs() >= 250) {
          setState(() {});
        }
      }
    });
    _player.stream.duration.listen((v) {
      if (mounted && _duration != v) {
        setState(() => _duration = v);
      }
    });
    _player.stream.buffering.listen((v) {
      if (mounted && _buffering != v) {
        setState(() => _buffering = v);
        if (!v && _playing) {
          _armHideControls();
        }
      }
    });
    _player.stream.volume.listen((v) {
      if (mounted && _volume != v) {
        setState(() => _volume = v);
      }
    });
    _player.stream.track.listen((_) {
      if (mounted) {
        if (_showControls) setState(() {});
        if (!_trackSelectorScheduled && _hasStartedPlaying && _hasMultipleTracks) {
          _trackSelectorScheduled = true;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) setState(() => _showInitialTrackSelector = true);
          });
        }
      }
    });
    _player.stream.error.listen((e) async {
      debugPrint('VideoPlayerScreen player error: $e');
      if (mounted) {
        final errorStr = e.toString().toLowerCase();

        // Non-fatal audio decoding errors or minor stream glitches should NEVER crash or terminate video playback
        if (errorStr.contains('audio') && (errorStr.contains('decode') || errorStr.contains('codec') || errorStr.contains('fail'))) {
          debugPrint('VideoPlayerScreen: Non-fatal audio decode notice. Continuing video playback.');
          return;
        }

        if (!_hasAttemptedFallback && 
            _resolvedSourceUrl != null &&
            (errorStr.contains('codec') || 
             errorStr.contains('decode') || 
             errorStr.contains('open') || 
             errorStr.contains('fail') || 
             errorStr.contains('format') ||
             errorStr.contains('load'))) {
          _hasAttemptedFallback = true;
          debugPrint('VideoPlayerScreen: Video codec error. Retrying with software decoding...');
          if (_player.platform is NativePlayer) {
            final nativePlayer = _player.platform as NativePlayer;
            await nativePlayer.setProperty('hwdec', 'no');
            await _player.open(
              Media(_resolvedSourceUrl!, httpHeaders: _resolvedSourceHeaders),
              play: true,
            );
            return;
          }
        }

        setState(() {
          _hasError = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playback Error: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 8),
          ),
        );
        if (!_ready && !_hasStartedPlaying) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && !_hasStartedPlaying) {
              Navigator.of(context).pop(true);
            }
          });
        }
      }
    });
  }

  Future<void> _open() async {
    try {
      final shouldExternal = await ExternalPlayerService.shouldPlayInExternalPlayer(
        url: widget.videoSource,
        sourceName: widget.sourceName ?? widget.subtitle,
      );
      if (shouldExternal) {
        if (mounted) {
          final displayName = await ExternalPlayerService.getPlayerDisplayName();
          ExternalPlayerService.showLaunchDialog(context, displayName);
        }
        final launched = await ExternalPlayerService.launch(
          url: widget.videoSource,
          title: widget.title,
          headers: widget.headers,
        );
        if (launched && mounted) {
          Navigator.of(context).pop();
          return;
        }
      }

      int seekToMs = 0;
      if (widget.movieId != null) {
        final savedMs = await PlaybackTracker.getSavedPosition(widget.movieId!);
        if (savedMs > 10000) {
          if (widget.resumeDirectly) {
            seekToMs = savedMs;
          } else {
            final resume = await _showResumeDialog(savedMs);
            if (resume == true) {
              seekToMs = savedMs;
            } else if (resume == false) {
              PlaybackTracker.saveProgress(widget.movieId!, 0, 0);
            }
          }
        }
      }

      final Map<String, String> playHeaders = {};
      final isLocalStream = widget.videoSource.contains('127.0.0.1') || 
                            widget.videoSource.contains('localhost') || 
                            widget.videoSource.contains('/f/');

      if (!isLocalStream) {
        if (widget.headers != null) {
          playHeaders.addAll(widget.headers!);
        } else if (widget.videoSource.startsWith('http')) {
          playHeaders.addAll({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            if (widget.videoSource.contains('.m3u8') || widget.videoSource.contains('/hls/'))
              'Referer': 'https://streamimdb.ru/',
          });
        }
      }
      
      // Parse inline headers from the stream URL if present
      if (!isLocalStream && widget.videoSource.startsWith('http')) {
        try {
          final uri = Uri.parse(widget.videoSource);
          if (uri.queryParameters.containsKey('headers')) {
            final jsonHeaders = jsonDecode(uri.queryParameters['headers']!);
            if (jsonHeaders is Map) {
              jsonHeaders.forEach((key, value) {
                playHeaders[key.toString()] = value.toString();
              });
            }
          }
        } catch (e) {
          debugPrint('Error parsing URL query headers: $e');
        }
      }

      if (_player.platform is NativePlayer) {
        final nativePlayer = _player.platform as NativePlayer;
        
        // Disable SSL/TLS verification to prevent Cloudflare certificate trust chain issues
        await nativePlayer.setProperty('tls-verify', 'no');
        
        if (!Platform.isIOS) {
          // Force IPv4 DNS lookups to avoid broken/blocked IPv6 routing on some carriers/ISPs
          await nativePlayer.setProperty('dns-lookup-family', 'ipv4');
        }
        
        if (isLocalStream) {
          // Exact diagnostic configuration for local/loopback Telegram streams
          await nativePlayer.setProperty('network-timeout', '60');
          await nativePlayer.setProperty('demuxer-max-bytes', '32MiB');
          await nativePlayer.setProperty('demuxer-max-back-bytes', '8MiB');
          await nativePlayer.setProperty('cache', 'yes');
        } else if (playHeaders.isNotEmpty) {
          final userAgent = playHeaders['User-Agent'] ?? playHeaders['user-agent'];
          if (userAgent != null) {
            await nativePlayer.setProperty('user-agent', userAgent);
          }
          final referrer = playHeaders['Referer'] ?? playHeaders['referer'] ?? playHeaders['Referrer'] ?? playHeaders['referrer'];
          if (referrer != null) {
            await nativePlayer.setProperty('referrer', referrer);
          }
          final headerList = <String>[];
          playHeaders.forEach((key, value) {
            final kLower = key.toLowerCase();
            if (kLower != 'user-agent' && kLower != 'referer') {
              headerList.add('$key: $value');
            }
          });
          if (headerList.isNotEmpty) {
            await nativePlayer.setProperty('http-header-fields', headerList.join(','));
          }
        }
        // Hardware decoding configuration
        if (Platform.isAndroid) {
          await nativePlayer.setProperty('hwdec', 'auto');
        } else if (Platform.isIOS || Platform.isMacOS) {
          await nativePlayer.setProperty('hwdec', 'videotoolbox');
        } else {
          await nativePlayer.setProperty('hwdec', 'auto');
        }
        
        if (widget.isLive) {
          await nativePlayer.setProperty('cache', 'yes');
          await nativePlayer.setProperty('cache-on-disk', 'no');
          await nativePlayer.setProperty('demuxer-readahead-secs', '5');
          await nativePlayer.setProperty('cache-secs', '5');
          await nativePlayer.setProperty('demuxer-max-bytes', '33554432');
          await nativePlayer.setProperty('demuxer-max-back-bytes', '8388608');
          await nativePlayer.setProperty('cache-pause-wait', '0');
          await nativePlayer.setProperty('network-timeout', '30');
          await nativePlayer.setProperty('hr-seek', 'no');
          await nativePlayer.setProperty('framedrop', 'vo');
          await nativePlayer.setProperty('autosync', '0');
          await nativePlayer.setProperty('audio-pitch-correction', 'yes');
        } else if (!isLocalStream) {
          await nativePlayer.setProperty('network-timeout', '30');
          await nativePlayer.setProperty('cache', 'yes');
          await nativePlayer.setProperty('cache-on-disk', 'no');
          await nativePlayer.setProperty('demuxer-max-bytes', '134217728'); // 128 MB RAM buffer
          await nativePlayer.setProperty('demuxer-max-back-bytes', '33554432'); // 32 MB back buffer
          await nativePlayer.setProperty('demuxer-readahead-secs', '30'); // Buffer up to 30 seconds ahead
          await nativePlayer.setProperty('cache-secs', '30');
          await nativePlayer.setProperty('cache-pause', 'yes');
          await nativePlayer.setProperty('cache-pause-wait', '2'); // Buffer at least 2s before resuming to prevent frame stutter
          await nativePlayer.setProperty('cache-pause-initial', 'yes');
          await nativePlayer.setProperty('demuxer-lavf-buffersize', '1048576');
          await nativePlayer.setProperty('stream-buffer-size', '2097152');
          await nativePlayer.setProperty('stream-live', 'no');
        }
        
        await nativePlayer.setProperty('force-seekable', 'yes');
        if (Platform.isIOS) {
          await nativePlayer.setProperty('ao', 'audiounit,');
        }
        
        // Disable HTTP persistent connections to avoid avformat_open_input()
        // "Cannot reuse HTTP connection for different host" failures with HLS CDN segments
        await nativePlayer.setProperty('demuxer-lavf-o', 'http_persistent=0');
      }

      var resolvedSource = widget.videoSource;
      bool isProxied = false;
      
      if (resolvedSource.startsWith('http')) {
        try {
          final uri = Uri.parse(resolvedSource);
          final host = uri.host;
          final lowerHost = host.toLowerCase();
          // Always proxy all http/https streams to support real-time network speed & data usage tracking
          // EXCEPT for Stalker portal and Castle TV server streams, which fail to resolve duration/VOD seek when proxied.
          bool shouldProxy = true;
          final lowerSubtitle = widget.subtitle?.toLowerCase() ?? '';
          final lowerSourceName = widget.sourceName?.toLowerCase() ?? '';
          final lowerUrl = resolvedSource.toLowerCase();
          final hasStalkerCookie = playHeaders.entries.any(
            (e) => e.key.toLowerCase() == 'cookie' && e.value.toLowerCase().contains('mac='),
          );
          if (lowerSubtitle.contains('stalker') ||
              lowerSubtitle.contains('castle') ||
              lowerSubtitle.contains('telegram') ||
              lowerSubtitle.contains('streamplay') ||
              lowerSubtitle.contains('moviebox') ||
              lowerSourceName.contains('stalker') ||
              lowerSourceName.contains('castle') ||
              lowerSourceName.contains('telegram') ||
              lowerSourceName.contains('streamplay') ||
              lowerSourceName.contains('moviebox') ||
              lowerUrl.contains('vidlink.pro') ||
              lowerUrl.contains('hlowb.com') ||
              lowerUrl.contains('castle') ||
              lowerUrl.contains('127.0.0.1') ||
              lowerUrl.contains('localhost') ||
              lowerUrl.contains('/tg/') ||
              lowerUrl.contains('/f/') ||
              hasStalkerCookie) {
            shouldProxy = false;
          }
          if (shouldProxy) {
            final dnsProxy = CustomDnsProxy();
            if (dnsProxy.port != null) {
              var cleanUri = uri;
              if (!uri.queryParameters.containsKey('local_proxy_headers') && playHeaders.isNotEmpty) {
                // Encode the playHeaders into the URL parameter so the proxy can extract it
                final newParams = Map<String, String>.from(uri.queryParameters);
                newParams['local_proxy_headers'] = jsonEncode(playHeaders);
                cleanUri = uri.replace(queryParameters: newParams);
              }
              
              final hostWithPort = cleanUri.hasPort ? '${cleanUri.host}:${cleanUri.port}' : cleanUri.host;
              resolvedSource = 'http://127.0.0.1:${dnsProxy.port}/proxy/${cleanUri.scheme}/$hostWithPort${cleanUri.path}${cleanUri.hasQuery ? "?" + cleanUri.query : ""}';
              debugPrint('VideoPlayerScreen: Rewrote source to proxy relay: $resolvedSource');
              isProxied = true;
            }
          }
        } catch (e) {
          debugPrint('VideoPlayerScreen error rewriting proxy URL: $e');
        }
      }

      _isStreamProxied = isProxied;

      // If we are NOT routing through the local proxy, we must strip the 'headers' query parameter
      // here so the player directly requests the clean URL without corrupting CDN signatures.
      if (!isProxied && resolvedSource.startsWith('http')) {
        try {
          final sourceUri = Uri.parse(resolvedSource);
          if (sourceUri.queryParameters.containsKey('headers')) {
            final cleanParams = Map<String, String>.from(sourceUri.queryParameters);
            cleanParams.remove('headers');
            if (cleanParams.isEmpty) {
              resolvedSource = sourceUri.replace(query: '').toString();
              if (resolvedSource.endsWith('?')) {
                resolvedSource = resolvedSource.substring(0, resolvedSource.length - 1);
              }
            } else {
              resolvedSource = sourceUri.replace(queryParameters: cleanParams).toString();
            }
            debugPrint('VideoPlayerScreen: Direct playback, stripped headers param: $resolvedSource');
          }
        } catch (e) {
          debugPrint('VideoPlayerScreen: Error stripping headers param: $e');
        }
      }
      _resolvedSourceUrl = resolvedSource;
      _resolvedSourceHeaders = playHeaders;
      _hasAttemptedFallback = false;
      await _player.open(Media(resolvedSource, httpHeaders: playHeaders), play: true);
      
      if (seekToMs > 0) {
        _player.stream.duration
            .firstWhere((d) => d > Duration.zero, orElse: () => Duration.zero)
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () => Duration.zero,
            )
            .catchError((_) => Duration.zero)
            .then((d) async {
          if (d > Duration.zero && mounted) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await _player.seek(Duration(milliseconds: seekToMs));
          }
        });
      }

      if (mounted) setState(() => _ready = true);
      _armHideControls();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play stream: $e')),
      );
    }
  }

  Future<bool?> _showResumeDialog(int savedMs) async {
    final Duration duration = Duration(milliseconds: savedMs);
    final String timestamp = _fmt(duration);
    
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
              borderRadius: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'RESUME PLAYBACK?',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'You left off at $timestamp. Would you like to resume?',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Resume', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Restart'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _armHideControls() {
    _hideControlsTimer?.cancel();
    if (_controlsLocked) {
      _hideControlsTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showControls = false);
      });
      return;
    }
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) {
        setState(() => _showControls = false);
      }
    });
  }

  void _keepControlsVisible() {
    _hideControlsTimer?.cancel();
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _armHideControls();
  }

  void _revealControls() {
    if (_showControls) {
      setState(() => _showControls = false);
      _hideControlsTimer?.cancel();
    } else {
      _startPlayerLogoTimer();
      setState(() => _showControls = true);
      _armHideControls();
    }
  }

  void _togglePlay() {
    _startPlayerLogoTimer();
    _player.playOrPause();
    _keepControlsVisible();
  }

  Future<void> _seekRelative(int seconds) async {
    _startPlayerLogoTimer();
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && target > _duration ? _duration : target);

    setState(() {
      _isSeeking = true;
      _buffering = true;
    });

    await _player.seek(clamped);

    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() {
        _isSeeking = false;
        _buffering = _player.state.buffering;
      });
    }

    _showHud('seek', seconds);
    _keepControlsVisible();
  }

  void _showHud(String type, [int? value]) {
    _hudTimer?.cancel();
    setState(() {
      _hudType = type;
      if (type == 'seek' && value != null) {
        _seekOverlayValue = value;
      }
    });
    _hudTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _hudType = null;
          _seekOverlayValue = null;
        });
      }
    });
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _videoScale;
    _baseOffset = _videoOffset;
    _dragStartPoint = details.localFocalPoint;
    
    if (details.pointerCount == 1) {
      _isDraggingHUD = true;
      _dragStartVolume = _volume;
      _dragStartBrightness = _brightness;
    } else {
      _isDraggingHUD = false;
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, double screenWidth) {
    if (_controlsLocked) return;

    if (details.pointerCount == 2) {
      // Pinch to Zoom
      setState(() {
        _videoScale = (_baseScale * details.scale).clamp(1.0, 4.0);
        if (_videoScale > 1.0) {
          _videoOffset = _baseOffset + details.focalPointDelta;
        } else {
          _videoOffset = Offset.zero;
        }
      });
      _keepControlsVisible();
    } else if (details.pointerCount == 1 && _isDraggingHUD && _dragStartPoint != null) {
      // Single finger drag: Swipe up/down for Volume/Brightness
      final deltaY = details.localFocalPoint.dy - _dragStartPoint!.dy;
      final startX = _dragStartPoint!.dx;
      
      if (startX < screenWidth / 2) {
        // Left side: Brightness
        setState(() {
          _hudType = 'brightness';
          if (_dragStartBrightness != null) {
            _brightness = (_dragStartBrightness! - deltaY / 150).clamp(0.05, 1.0);
          }
        });
        try {
          ScreenBrightness().setApplicationScreenBrightness(_brightness);
        } catch (_) {}
      } else {
        // Right side: Volume
        setState(() {
          _hudType = 'volume';
          if (_dragStartVolume != null) {
            _volume = (_dragStartVolume! - deltaY / 2.5).clamp(0.0, 100.0);
          }
          _player.setVolume(_volume);
        });
        try {
          FlutterVolumeController.setVolume(_volume / 100.0);
        } catch (_) {}
      }
      _armHideControls();
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _isDraggingHUD = false;
    _dragStartVolume = null;
    _dragStartBrightness = null;
    _dragStartPoint = null;
    
    _armHideControls();

    // Start timer to hide brightness/volume overlay after drag ends
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _hudType = null;
          _seekOverlayValue = null;
        });
      }
    });
  }



  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (!_ready) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accentBright),
        ),
      );
    }

    final selectedAspectRatio = _aspectRatios[_aspectRatioIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. The Video Viewport (responsive aspect scale + zoom & pan)
          Center(
            child: Transform.translate(
              offset: _videoOffset,
              child: Transform.scale(
                scale: _videoScale,
                child: AspectRatio(
                  aspectRatio: selectedAspectRatio ?? 16 / 9,
                  child: Video(
                    controller: _controller,
                    controls: NoVideoControls,
                    subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                  ),
                ),
              ),
            ),
          ),

          // 1.5. Separate Subtitle Layer (untransformed, fixed in the same area)
          IgnorePointer(
            child: SubtitleView(
              controller: _controller,
              configuration: SubtitleViewConfiguration(
                style: TextStyle(
                  fontSize: _subtitleFontSize,
                  color: Colors.white,
                  backgroundColor: Colors.black38,
                  shadows: const [
                    Shadow(
                      offset: Offset(1.0, 1.0),
                      blurRadius: 2.0,
                      color: Colors.black,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Custom Emulator-Compatible Visual Brightness Layer (Opacified Black Scrim)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: (1.0 - _brightness).clamp(0.0, 0.85)),
              ),
            ),
          ),

          // 3. Gesture Layer (vertical swipes, pinch zoom, and double tap seek)
          Positioned.fill(
            child: GestureDetector(
              onScaleStart: widget.isLive ? null : _handleScaleStart,
              onScaleUpdate: widget.isLive ? null : (details) => _handleScaleUpdate(details, screenWidth),
              onScaleEnd: widget.isLive ? null : _handleScaleEnd,
              onTap: _revealControls,
              onDoubleTapDown: widget.isLive ? null : (details) {
                if (_controlsLocked) return;
                final x = details.localPosition.dx;
                if (x < screenWidth / 2) {
                  _seekRelative(-5);
                } else {
                  _seekRelative(5);
                }
              },
              behavior: HitTestBehavior.opaque,
            ),
          ),

          // 4. Buffering Overlay (only shown when controls are hidden)
          if ((_buffering || _isSeeking) && !_showControls)
            Center(
              child: GradientCircularProgressIndicator(
                size: 80.0,
                colors: [
                  AppColors.accentBright.withValues(alpha: 0.05),
                  AppColors.accentBright,
                ],
                strokeWidth: 4.0,
              ),
            ),

          // 5. HUD indicator overlays (Brightness/Volume/Seek)
          if (_hudType != null) _buildHudOverlay(),

          // 6. UI Overlays (Control Bar controls)
          if (_showControls) _buildControlsLayout(context),
        ],
      ),
    );
  }

  List<AudioTrack> get _realAudioTracks => _player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
  List<VideoTrack> get _realVideoTracks => _player.state.tracks.video.where((t) => t.id != 'auto' && t.id != 'no').toList();
  bool get _hasMultipleTracks => _realAudioTracks.length > 1 || _realVideoTracks.length > 1;

  String _formatAudioTrackLabel(AudioTrack track, int index) {
    final title = (track.title ?? '').toLowerCase();
    final lang = (track.language ?? '').toLowerCase();
    final id = track.id.toLowerCase();
    final combined = '$title $lang $id';

    if (combined.contains('hin') || combined.contains('hindi')) return 'Hindi';
    if (combined.contains('mal') || combined.contains('malayalam')) return 'Malayalam';
    if (combined.contains('tam') || combined.contains('tamil')) return 'Tamil';
    if (combined.contains('tel') || combined.contains('telugu')) return 'Telugu';
    if (combined.contains('kan') || combined.contains('kannada')) return 'Kannada';
    if (combined.contains('eng') || combined.contains('english')) return 'English';

    if (track.title != null && track.title!.isNotEmpty && !track.title!.toLowerCase().startsWith('track')) {
      return track.title!;
    }
    if (track.language != null && track.language!.isNotEmpty) {
      return track.language!.toUpperCase();
    }

    return 'Audio Track ${index + 1}';
  }



  Widget _buildTrackTile({required String label, required bool isSelected, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected ? AppColors.accent.withOpacity(0.2) : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Icon(isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: isSelected ? AppColors.accentBright : Colors.white38, size: 20),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildHudOverlay() {
    IconData icon;
    String label;
    double progress = 0.0;

    if (_hudType == 'seek') {
      final isForward = (_seekOverlayValue ?? 0) > 0;
      icon = isForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded;
      label = isForward ? '+ 5' : '- 5';
    } else if (_hudType == 'volume') {
      icon = _volume == 0
          ? Icons.volume_mute_rounded
          : (_volume < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded);
      label = '${_volume.round()}%';
      progress = _volume / 100.0;
    } else if (_hudType == 'brightness') {
      icon = Icons.brightness_6_rounded;
      label = '${(_brightness * 100).round()}%';
      progress = _brightness;
    } else {
      return const SizedBox.shrink();
    }

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.black45,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 48),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                if (_hudType != 'seek') ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 100,
                    height: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white24,
                        color: AppColors.accentBright,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildTopBarIcon(Widget child, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBarMenuIcon(IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  Widget _buildPopupMenuS() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _showSubtitleManagerSheet,
      child: Padding(
        padding: const EdgeInsets.only(left: 10),
        child: _buildTopBarMenuIcon(Icons.subtitles_rounded),
      ),
    );
  }

  Widget _buildPopupMenuSubtitleSize() {
    return Theme(
      data: Theme.of(context).copyWith(
        cardColor: AppColors.surface,
      ),
      child: PopupMenuButton<double>(
        child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: _buildTopBarMenuIcon(Icons.format_size_rounded),
        ),
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (size) {
          _changeSubtitleSize(size);
        },
        itemBuilder: (context) {
          final sizes = {
            24.0: 'Small',
            36.0: 'Normal',
            48.0: 'Large',
            60.0: 'Extra Large',
          };
          return sizes.entries.map((entry) {
            final isCurrent = _subtitleFontSize == entry.key;
            return PopupMenuItem<double>(
              value: entry.key,
              child: Row(
                children: [
                  Icon(
                    isCurrent ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: isCurrent ? AppColors.accentBright : Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${entry.value} (${entry.key.toInt()})',
                    style: TextStyle(
                      color: isCurrent ? Colors.white : Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }).toList();
        },
      ),
    );
  }

  void _showSubtitleManagerSheet() {
    final textController = TextEditingController();
    final cleanSearchTitle = (widget.title ?? '')
        .replaceAll(RegExp(r'\s*•.*'), '')
        .replaceAll(RegExp(r'\s*\[.*?\]'), '')
        .replaceAll(RegExp(r'\s*\(.*?\)'), '')
        .trim();
    String currentMovieTitle = cleanSearchTitle.isNotEmpty ? cleanSearchTitle : (widget.title ?? 'Current Video');
    final manualSearchController = TextEditingController(text: currentMovieTitle);
    int activeTab = 0; // 0: Tracks & Sync, 1: OpenSubtitles Search, 2: Manual URL
    bool loading = false;
    bool isSearchingTmdb = false;
    List<dynamic> tmdbResults = [];
    List<dynamic> subtitleTracks = [];
    Map<String, List<dynamic>> groupedTracks = {};
    String? expandedLang;
    String errorMsg = '';
    String? currentImdbId = widget.imdbId;

    final langNames = {
      'eng': 'English',
      'mal': 'Malayalam',
      'hin': 'Hindi',
      'tam': 'Tamil',
      'tel': 'Telugu',
      'kan': 'Kannada',
      'spa': 'Spanish',
      'fre': 'French',
      'ger': 'German',
      'ita': 'Italian',
      'por': 'Portuguese',
      'rus': 'Russian',
      'ara': 'Arabic',
      'chi': 'Chinese',
      'jpn': 'Japanese',
      'kor': 'Korean',
      'ind': 'Indonesian',
      'may': 'Malay',
      'tha': 'Thai',
      'tur': 'Turkish',
      'vie': 'Vietnamese',
      'est': 'Estonian',
      'lav': 'Latvian',
      'lit': 'Lithuanian',
    };

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> fetchSubtitles() async {
              final imdb = currentImdbId;
              if (imdb == null || imdb.isEmpty || imdb == 'null') {
                setSheetState(() {
                  errorMsg = 'No IMDb ID available. Search movie title below.';
                });
                return;
              }

              setSheetState(() {
                loading = true;
                errorMsg = '';
                subtitleTracks = [];
                groupedTracks = {};
              });

              try {
                String type = 'movie';
                String finalImdb = imdb;
                if (imdb.contains(':')) {
                  type = 'series';
                }
                final url = 'https://opensubtitles-v3.strem.io/subtitles/$type/$finalImdb.json';
                debugPrint('Querying subtitles: $url');
                final response = await http.get(
                  Uri.parse(url),
                  headers: {'User-Agent': 'GoXio/1.0'},
                ).timeout(const Duration(seconds: 8));
                if (response.statusCode == 200) {
                  final data = jsonDecode(response.body);
                  final List<dynamic> subs = data['subtitles'] as List<dynamic>? ?? [];

                  final Map<String, List<dynamic>> grouped = {};
                  for (final s in subs) {
                    final lang = s['lang']?.toString() ?? 'unknown';
                    if (!grouped.containsKey(lang)) {
                      grouped[lang] = [];
                    }
                    grouped[lang]!.add(s);
                  }

                  setSheetState(() {
                    subtitleTracks = subs;
                    groupedTracks = grouped;
                    loading = false;
                  });
                } else {
                  throw Exception('HTTP error ${response.statusCode}');
                }
              } catch (e) {
                debugPrint('Failed to query OpenSubtitles: $e');
                setSheetState(() {
                  loading = false;
                  errorMsg = 'Could not retrieve subtitles from OpenSubtitles.';
                });
              }
            }

            Future<void> searchTmdb(String query) async {
              setSheetState(() {
                isSearchingTmdb = true;
                errorMsg = '';
                tmdbResults = [];
              });

              try {
                final encoded = Uri.encodeComponent(query.trim());
                final isTv = widget.isTvShow || (widget.season != null && widget.season! > 0);
                final endpoint = isTv ? 'tv' : 'movie';
                final url = 'https://api.themoviedb.org/3/search/$endpoint?api_key=8baba8ab6b8bbe247645bcae7df63d0d&query=$encoded';
                final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));

                if (res.statusCode == 200) {
                  final data = jsonDecode(res.body);
                  final results = data['results'] as List<dynamic>? ?? [];
                  setSheetState(() {
                    tmdbResults = results;
                    isSearchingTmdb = false;
                    if (results.isEmpty) {
                      errorMsg = 'No titles found on TMDB for "$query".';
                    }
                  });
                } else {
                  throw Exception('Search failed');
                }
              } catch (e) {
                setSheetState(() {
                  isSearchingTmdb = false;
                  errorMsg = 'Search failed. Try again.';
                });
              }
            }

            // Auto-trigger OpenSubtitles search on first load of Tab 1 if IMDB ID is available
            if (activeTab == 1 && currentImdbId != null && subtitleTracks.isEmpty && !loading && errorMsg.isEmpty && tmdbResults.isEmpty && !isSearchingTmdb) {
              Future.microtask(() => fetchSubtitles());
            }

            final currentTrack = _player.state.track.subtitle;
            final availableTracks = _player.state.tracks.subtitle;
            final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

            Widget tabContent;
            if (activeTab == 0) {
              tabContent = _buildTracksAndSyncTab(
                availableTracks: availableTracks,
                currentTrack: currentTrack,
                onTrackSelected: (t) {
                  _player.setSubtitleTrack(t);
                  setSheetState(() {});
                },
                onSearchOnlineTap: () {
                  setSheetState(() => activeTab = 1);
                },
                setSheetState: setSheetState,
              );
            } else if (activeTab == 1) {
              tabContent = _buildOpenSubtitlesSheetTab(
                currentTitle: currentMovieTitle,
                currentImdbId: currentImdbId,
                loading: loading,
                errorMsg: errorMsg,
                groupedTracks: groupedTracks,
                expandedLang: expandedLang,
                langNames: langNames,
                isSearchingTmdb: isSearchingTmdb,
                tmdbResults: tmdbResults,
                manualSearchController: manualSearchController,
                onRetry: fetchSubtitles,
                onSearchQuery: (q) => searchTmdb(q),
                onSelectTmdbItem: (item) async {
                  final tmdbId = item['id'];
                  final isTv = item['media_type'] == 'tv';
                  final title = item['title'] ?? item['name'] ?? 'Movie';
                  setSheetState(() => loading = true);
                  try {
                    String? imdb;
                    if (isTv) {
                      final extUrl = 'https://api.themoviedb.org/3/tv/$tmdbId/external_ids?api_key=8baba8ab6b8bbe247645bcae7df63d0d';
                      final res = await http.get(Uri.parse(extUrl)).timeout(const Duration(seconds: 8));
                      if (res.statusCode == 200) {
                        final extData = jsonDecode(res.body);
                        imdb = extData['imdb_id']?.toString();
                      }
                    } else {
                      final detailUrl = 'https://api.themoviedb.org/3/movie/$tmdbId?api_key=8baba8ab6b8bbe247645bcae7df63d0d';
                      final res = await http.get(Uri.parse(detailUrl)).timeout(const Duration(seconds: 8));
                      if (res.statusCode == 200) {
                        final detailData = jsonDecode(res.body);
                        imdb = detailData['imdb_id']?.toString();
                      }
                    }
                    if (imdb != null && imdb.isNotEmpty && imdb != 'null') {
                      currentImdbId = imdb;
                      currentMovieTitle = title;
                      manualSearchController.text = title;
                      tmdbResults = [];
                      await fetchSubtitles();
                    } else {
                      throw Exception('No IMDb ID found');
                    }
                  } catch (e) {
                    setSheetState(() {
                      loading = false;
                      errorMsg = 'Could not find subtitles for $title';
                    });
                  }
                },
                onLangTap: (lang) {
                  setSheetState(() {
                    expandedLang = expandedLang == lang ? null : lang;
                  });
                },
                onTrackSelected: (track, displayLang) {
                  final subUrl = track['url']?.toString() ?? '';
                  if (subUrl.isNotEmpty) {
                    _player.setSubtitleTrack(SubtitleTrack.uri(subUrl, title: 'OpenSubtitles: $displayLang', language: displayLang));
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text('OpenSubtitles ($displayLang) loaded successfully.'),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );
                  }
                },
              );
            } else {
              tabContent = _buildCustomUrlTab(
                controller: textController,
                onImport: () {
                  final url = textController.text.trim();
                  if (url.isNotEmpty && url.startsWith('http')) {
                    _player.setSubtitleTrack(SubtitleTrack.uri(url, title: 'Custom Subtitle', language: 'Custom'));
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('Custom subtitle loaded successfully.'),
                        backgroundColor: Color(0xFF10B981),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a valid HTTP/HTTPS URL.'),
                        backgroundColor: Color(0xFFEF4444),
                      ),
                    );
                  }
                },
              );
            }

            return Align(
              alignment: isLandscape ? Alignment.centerRight : Alignment.bottomCenter,
              child: Container(
                width: isLandscape ? 440 : double.infinity,
                height: isLandscape ? MediaQuery.of(context).size.height : MediaQuery.of(context).size.height * 0.85,
                decoration: BoxDecoration(
                  color: const Color(0xFF13151F),
                  borderRadius: isLandscape
                      ? const BorderRadius.horizontal(left: Radius.circular(20))
                      : const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  children: [
                    // Top Drag Handle & Header
                    const SizedBox(height: 8),
                    if (!isLandscape)
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.accentBright.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.subtitles_rounded, color: AppColors.accentBright, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Subtitles & Captions',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  currentTrack.id == 'no'
                                      ? 'Subtitles Off'
                                      : (currentTrack.id == 'auto'
                                          ? 'Auto-Selected'
                                          : (currentTrack.title ?? currentTrack.language ?? 'Track ${currentTrack.id}')),
                                  style: TextStyle(
                                    color: currentTrack.id == 'no' ? Colors.white38 : AppColors.accentBright,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                            onPressed: () => Navigator.of(ctx).pop(),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Modern Segmented Tab Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Row(
                          children: [
                            _buildTabButton(
                              title: 'Tracks & Sync',
                              icon: Icons.tune_rounded,
                              isActive: activeTab == 0,
                              onTap: () => setSheetState(() => activeTab = 0),
                            ),
                            _buildTabButton(
                              title: 'OpenSubtitles',
                              icon: Icons.travel_explore_rounded,
                              isActive: activeTab == 1,
                              onTap: () => setSheetState(() => activeTab = 1),
                            ),
                            _buildTabButton(
                              title: 'Custom URL',
                              icon: Icons.link_rounded,
                              isActive: activeTab == 2,
                              onTap: () => setSheetState(() => activeTab = 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Tab Content
                    Expanded(child: tabContent),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.accentBright.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? AppColors.accentBright : Colors.white54,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white54,
                  fontSize: 12.5,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTracksAndSyncTab({
    required List<SubtitleTrack> availableTracks,
    required SubtitleTrack currentTrack,
    required ValueChanged<SubtitleTrack> onTrackSelected,
    required VoidCallback onSearchOnlineTap,
    required StateSetter setSheetState,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // 1. Available Embedded Tracks
        Text(
          'EMBEDDED SUBTITLE TRACKS',
          style: GoogleFonts.outfit(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        for (final track in availableTracks) ...[
          _buildTrackRow(
            track: track,
            isSelected: track.id == currentTrack.id,
            onTap: () => onTrackSelected(track),
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 16),

        // 2. Subtitle Appearance / Font Size Selector
        Text(
          'SUBTITLE FONT SIZE',
          style: GoogleFonts.outfit(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildSizeChip(label: 'Small', size: 24.0, setSheetState: setSheetState),
            const SizedBox(width: 8),
            _buildSizeChip(label: 'Normal', size: 36.0, setSheetState: setSheetState),
            const SizedBox(width: 8),
            _buildSizeChip(label: 'Large', size: 48.0, setSheetState: setSheetState),
            const SizedBox(width: 8),
            _buildSizeChip(label: 'Extra Large', size: 60.0, setSheetState: setSheetState),
          ],
        ),
        const SizedBox(height: 18),

        // 3. Subtitle Timing Sync (Delay Adjustment)
        Text(
          'SUBTITLE TIMING SYNC',
          style: GoogleFonts.outfit(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Sync Offset:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accentBright.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_subtitleDelay >= 0 ? "+" : ""}${_subtitleDelay.toStringAsFixed(1)}s',
                      style: TextStyle(
                        color: AppColors.accentBright,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildDelayButton('-0.5s', -0.5, setSheetState),
                  const SizedBox(width: 6),
                  _buildDelayButton('-0.1s', -0.1, setSheetState),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        _changeSubtitleDelay(0.0);
                        setSheetState(() {});
                      },
                      child: const Text('Reset', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildDelayButton('+0.1s', 0.1, setSheetState),
                  const SizedBox(width: 6),
                  _buildDelayButton('+0.5s', 0.5, setSheetState),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Quick button to open OpenSubtitles tab
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentBright.withValues(alpha: 0.15),
            foregroundColor: AppColors.accentBright,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.accentBright.withValues(alpha: 0.3)),
            ),
          ),
          icon: const Icon(Icons.travel_explore_rounded, size: 18),
          label: const Text('Search Subtitles on OpenSubtitles', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
          onPressed: onSearchOnlineTap,
        ),
      ],
    );
  }

  Widget _buildTrackRow({
    required SubtitleTrack track,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    String name = track.title ?? track.language ?? 'Track ${track.id}';
    if (track.id == 'auto') name = 'Auto (Best Match)';
    if (track.id == 'no') name = 'Off (Disable Subtitles)';

    return Material(
      color: isSelected ? AppColors.accentBright.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.accentBright.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: isSelected ? AppColors.accentBright : Colors.white30,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSizeChip({
    required String label,
    required double size,
    required StateSetter setSheetState,
  }) {
    final isCurrent = _subtitleFontSize == size;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _changeSubtitleSize(size);
          setSheetState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isCurrent ? AppColors.accentBright : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isCurrent ? AppColors.accentBright : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isCurrent ? Colors.black : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDelayButton(String label, double delta, StateSetter setSheetState) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () {
          _changeSubtitleDelay(_subtitleDelay + delta);
          setSheetState(() {});
        },
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildOpenSubtitlesSheetTab({
    required String currentTitle,
    required String? currentImdbId,
    required bool loading,
    required String errorMsg,
    required Map<String, List<dynamic>> groupedTracks,
    required String? expandedLang,
    required Map<String, String> langNames,
    required bool isSearchingTmdb,
    required List<dynamic> tmdbResults,
    required TextEditingController manualSearchController,
    required VoidCallback onRetry,
    required ValueChanged<String> onSearchQuery,
    required ValueChanged<dynamic> onSelectTmdbItem,
    required ValueChanged<String> onLangTap,
    required void Function(dynamic track, String displayLang) onTrackSelected,
  }) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: manualSearchController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: currentTitle.isNotEmpty ? 'Searching for: $currentTitle' : 'Search title on TMDb...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (q) {
                      if (q.trim().isNotEmpty) onSearchQuery(q.trim());
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.arrow_forward_rounded, color: AppColors.accentBright, size: 20),
                  onPressed: () {
                    final q = manualSearchController.text.trim();
                    if (q.isNotEmpty) onSearchQuery(q);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // TMDB Results list (if user searched manually)
        if (isSearchingTmdb)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: AppColors.accentBright)),
          )
        else if (tmdbResults.isNotEmpty)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: tmdbResults.length,
              itemBuilder: (ctx, i) {
                final item = tmdbResults[i];
                final t = item['title'] ?? item['name'] ?? 'Unknown';
                final r = item['release_date'] ?? item['first_air_date'] ?? '';
                final y = r.length >= 4 ? ' (${r.substring(0, 4)})' : '';
                return ListTile(
                  dense: true,
                  title: Text('$t$y', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(item['media_type'] == 'tv' ? 'TV Series' : 'Movie', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                  onTap: () => onSelectTmdbItem(item),
                );
              },
            ),
          )
        else if (loading)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.accentBright),
                  const SizedBox(height: 12),
                  const Text('Fetching subtitles from OpenSubtitles...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          )
        else if (errorMsg.isNotEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(errorMsg, style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onRetry,
                    child: Text('Retry Search', style: TextStyle(color: AppColors.accentBright, fontSize: 13)),
                  ),
                ],
              ),
            ),
          )
        else if (groupedTracks.isEmpty)
          const Expanded(
            child: Center(
              child: Text('No subtitles found on OpenSubtitles for this title.', style: TextStyle(color: Colors.white54, fontSize: 13)),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: groupedTracks.keys.length,
              itemBuilder: (context, index) {
                final langCode = groupedTracks.keys.elementAt(index);
                final langDisplay = langNames[langCode] ?? langCode.toUpperCase();
                final tracksList = groupedTracks[langCode] ?? [];
                final isExpanded = expandedLang == langCode;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.035),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        dense: true,
                        title: Text(
                          langDisplay,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${tracksList.length}',
                                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                              color: Colors.white54,
                              size: 20,
                            ),
                          ],
                        ),
                        onTap: () => onLangTap(langCode),
                      ),
                      if (isExpanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                          child: Column(
                            children: List.generate(tracksList.length, (idx) {
                              final track = tracksList[idx];
                              final encoding = track['SubEncoding']?.toString() ?? 'Default';
                              return GestureDetector(
                                onTap: () => onTrackSelected(track, langDisplay),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.file_download_done_rounded, color: AppColors.accentBright, size: 16),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Track ${idx + 1} ($langDisplay)',
                                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        encoding,
                                        style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildCustomUrlTab({
    required TextEditingController controller,
    required VoidCallback onImport,
  }) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Direct Subtitle File URL',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enter a direct HTTP or HTTPS link to a WebVTT (.vtt) or SubRip (.srt) subtitle file:',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'https://example.com/subtitles.srt',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentBright,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onImport,
            child: const Text('Apply Subtitle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildPopupMenuQ() {
    return Theme(
      data: Theme.of(context).copyWith(
        cardColor: AppColors.surface,
      ),
      child: PopupMenuButton<VideoTrack>(
        child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: _buildTopBarMenuIcon(Icons.tune_rounded),
        ),
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (track) {
          _player.setVideoTrack(track);
        },
        itemBuilder: (context) {
          final tracks = _player.state.tracks.video;
          final current = _player.state.track.video;
          return tracks.map((track) {
            String name = track.h != null ? '${track.h}p' : 'Track ${track.id}';
            if (track.id == 'auto') name = 'Auto';
            if (track.id == 'no') name = 'Off';
            final isCurrent = track.id == current.id;
            return PopupMenuItem<VideoTrack>(
              value: track,
              child: Row(
                children: [
                  Icon(
                    isCurrent ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: isCurrent ? AppColors.accentBright : Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    name,
                    style: TextStyle(
                      color: isCurrent ? Colors.white : Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }).toList();
        },
      ),
    );
  }

  Widget _buildPopupMenuM() {
    return Theme(
      data: Theme.of(context).copyWith(
        cardColor: AppColors.surface,
      ),
      child: PopupMenuButton<AudioTrack>(
        child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: _buildTopBarMenuIcon(Icons.audiotrack_rounded),
        ),
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (track) {
          _player.setAudioTrack(track);
        },
        itemBuilder: (context) {
          final tracks = _player.state.tracks.audio;
          final current = _player.state.track.audio;
          return tracks.map((track) {
            String name = track.title ?? track.language ?? 'Track ${track.id}';
            if (track.id == 'auto') name = 'Auto';
            if (track.id == 'no') name = 'Off';
            final isCurrent = track.id == current.id;
            return PopupMenuItem<AudioTrack>(
              value: track,
              child: Row(
                children: [
                  Icon(
                    isCurrent ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: isCurrent ? AppColors.accentBright : Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    name,
                    style: TextStyle(
                      color: isCurrent ? Colors.white : Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }).toList();
        },
      ),
    );
  }

  Widget _buildControlsLayout(BuildContext context) {
    final theme = ThemeManager.currentTheme;

    return Positioned.fill(
      child: Stack(
        children: [
          // 1. MAIN HUD WRAPPER (Top, Center, Bottom columns)
          Column(
            children: [
              // TOP BAR
              Container(
                height: 80,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left: Back button and Title
                    Flexible(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          color: Colors.black45,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.of(context).pop(_hasError),
                                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 14),
                              Flexible(
                                child: Text(
                                  widget.title ?? 'Movie Playback',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Right: Actions (PiP, Cast, CC Track, Subtitle Size, Quality, Audio, Lock)
                    Row(
                      children: [
                        ValueListenableBuilder<double>(
                            valueListenable: ProxyStats.speedNotifier,
                            builder: (context, speed, _) {
                              return ValueListenableBuilder<int>(
                                valueListenable: ProxyStats.totalDataNotifier,
                                builder: (context, totalBytes, _) {
                                  final speedText = speed <= 0
                                      ? '0 KB/s'
                                      : (speed < 1024 * 1024
                                          ? '${(speed / 1024).toStringAsFixed(1)} KB/s'
                                          : '${(speed / (1024 * 1024)).toStringAsFixed(2)} MB/s');
                                  
                                  final dataText = totalBytes < 1024 * 1024
                                      ? '${(totalBytes / 1024).toStringAsFixed(1)} KB'
                                      : (totalBytes < 1024 * 1024 * 1024
                                          ? '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                                          : '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB');

                                  return Container(
                                    margin: const EdgeInsets.only(right: 12),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black38,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.flash_on_rounded, color: Colors.amber, size: 10),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$speedText | $dataText',
                                          style: GoogleFonts.outfit(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        // Picture in Picture
                        _buildTopBarIcon(
                          const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 20),
                          () async {
                            setState(() => _showControls = false);
                            try {
                              await const MethodChannel('com.goxio.mob/pip')
                                  .invokeMethod('enterPip');
                            } catch (e) {
                              debugPrint('Error entering PiP: $e');
                            }
                          },
                        ),
                        // Cast
                        _buildTopBarIcon(
                          const Icon(Icons.cast_rounded, color: Colors.white, size: 20),
                          () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Searching for cast devices...')),
                            );
                          },
                        ),
                        
                        // Open in External Player (VLC / MX)
                        _buildTopBarIcon(
                          const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 20),
                          () async {
                            final source = widget.videoSource;
                            final displayName = await ExternalPlayerService.getPlayerDisplayName();
                            if (mounted) ExternalPlayerService.showLaunchDialog(context, displayName);
                            await ExternalPlayerService.launch(
                              url: source,
                              title: widget.title,
                              headers: widget.headers,
                            );
                          },
                        ),

                        // Modern Subtitle Manager (Tracks, OpenSubtitles Search, Size & Timing Sync)
                        _buildTopBarIcon(
                          const Icon(Icons.subtitles_rounded, color: Colors.white, size: 20),
                          _showSubtitleManagerSheet,
                        ),
                        _buildPopupMenuSubtitleSize(),
                        _buildPopupMenuQ(),
                        _buildTopBarIcon(
                          const Icon(Icons.audiotrack_rounded, color: Colors.white, size: 20),
                          () => _showSettingsSheet(initialPane: 2),
                        ),

                        // Lock Toggle
                        _buildTopBarIcon(
                          Icon(
                            _controlsLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                            color: _controlsLocked ? theme.accentBright : Colors.white,
                            size: 20,
                          ),
                          () {
                            setState(() {
                              _controlsLocked = !_controlsLocked;
                            });
                            _revealControls();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // STREMIO CLEAR LOGO ANIMATED OVERLAY (2s visible -> 2s hidden -> 2s visible)
              if (widget.logoUrl != null && widget.logoUrl!.isNotEmpty && (_showControls || _buffering || !_playing || _isSeeking))
                AnimatedOpacity(
                  opacity: _showPlayerLogoCrossFade ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 500),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    alignment: Alignment.center,
                    child: Image.network(
                      widget.logoUrl!,
                      height: 80,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),

              const Spacer(),

              // CENTER PLAY/PAUSE & CHEVRONS CONTROLS (Skip 5s)
              if (!_controlsLocked)
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Skip Backward 5s (<<) - Only for normal video
                      if (!widget.isLive) ...[
                        IconButton(
                          icon: const Icon(Icons.fast_rewind_rounded, color: Colors.white, size: 56),
                          onPressed: () => _seekRelative(-5),
                        ),
                        const SizedBox(width: 60),
                      ],
                      
                      // Play / Pause Large Toggle (||) wrapped in buffering indicator Stack
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_buffering || _isSeeking)
                            GradientCircularProgressIndicator(
                              size: 80.0,
                              colors: [
                                theme.accentBright.withValues(alpha: 0.05),
                                theme.accentBright,
                              ],
                              strokeWidth: 4.0,
                            ),
                          IconButton(
                            icon: Icon(
                              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 64,
                            ),
                            onPressed: _togglePlay,
                          ),
                        ],
                      ),
                      
                      // Skip Forward 5s (>>) - Only for normal video
                      if (!widget.isLive) ...[
                        const SizedBox(width: 60),
                        IconButton(
                          icon: const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 56),
                          onPressed: () => _seekRelative(5),
                        ),
                      ],
                    ],
                  ),
                )
              else if (_controlsLocked)
                // Locked Hint UI
                Center(
                  child: GlassPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    borderRadius: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded, color: theme.accentBright, size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'Controls Locked. Tap lock icon to modify.',
                          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

              const Spacer(),

              // BOTTOM BAR WITH ACTIONS AND SLIDER
              if (!_controlsLocked)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isLive) ...[
                        _buildLiveTvEpgLayout(theme),
                        const SizedBox(height: 16),
                      ],
                      // Seek bar + Duration on the right (hidden for Live TV)
                      if (!widget.isLive) ...[
                        Row(
                          children: [
                            Text(
                              _fmt(_dragValue != null && _duration > Duration.zero
                                  ? Duration(milliseconds: (_duration.inMilliseconds * _dragValue!).toInt())
                                  : _position),
                              style: GoogleFonts.outfit(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2.0,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6.0,
                                  ),
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: Colors.white,
                                  overlayColor: Colors.white.withValues(alpha: 0.15),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                                ),
                                child: Slider(
                                  value: _dragValue ?? (_duration > Duration.zero
                                      ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                                      : 0.0),
                                  onChanged: (fraction) {
                                    setState(() {
                                      _dragValue = fraction;
                                    });
                                  },
                                  onChangeEnd: (fraction) {
                                    setState(() {
                                      _dragValue = null;
                                    });
                                    _seekTo(fraction);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _fmt(_duration),
                              style: GoogleFonts.outfit(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      
                      // Bottom Actions (Speed, Clock Time, Rate)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Bottom Left: Speed button or LIVE indicator
                          widget.isLive
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.redAccent,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.redAccent,
                                            blurRadius: 6,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'LIVE',
                                      style: GoogleFonts.outfit(
                                        color: Colors.redAccent,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ],
                                )
                              : _buildBottomActionItem(
                                  icon: Icons.play_circle_outline_rounded,
                                  label: 'Speed ${_playbackSpeed == 1.0 ? '1' : _playbackSpeed}x',
                                  onTap: _changePlaybackSpeed,
                                ),
                          
                          // Bottom Center: Live system time
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _timeString,
                                style: GoogleFonts.outfit(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          
                          // Bottom Right: Rate (Favorite) button
                          _buildBottomActionItem(
                            icon: _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            label: 'Rate',
                            onTap: _toggleFavorite,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // 2. BRIGHTNESS SLIDER (Left side overlay, resized & centered, aligned above starting duration)
          if (!_controlsLocked)
            Positioned(
              left: 48,
              top: 0,
              bottom: 0,
              child: Center(
                child: SizedBox(
                  width: 32,
                  height: 180,
                  child: _buildVerticalSlider(
                    value: _brightness,
                    icon: Icons.light_mode_rounded,
                    onChanged: (val) {
                      setState(() {
                        _brightness = val.clamp(0.05, 1.0);
                      });
                      try {
                        ScreenBrightness().setApplicationScreenBrightness(_brightness);
                      } catch (_) {}
                    },
                  ),
                ),
              ),
            ),

          // 3. VOLUME SLIDER (Right side overlay, resized & centered, aligned above ending duration)
          if (!_controlsLocked)
            Positioned(
              right: 48,
              top: 0,
              bottom: 0,
              child: Center(
                child: SizedBox(
                  width: 32,
                  height: 180,
                  child: _buildVerticalSlider(
                    value: _volume / 100.0,
                    icon: _volume == 0 ? Icons.volume_mute_rounded : Icons.volume_up_rounded,
                    onChanged: (val) {
                      setState(() {
                        _volume = val * 100.0;
                        _player.setVolume(_volume);
                      });
                      try {
                        FlutterVolumeController.setVolume(_volume / 100.0);
                      } catch (_) {}
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _seekToAbsolute(Duration position) async {
    setState(() {
      _isSeeking = true;
      _buffering = true;
    });

    await _player.seek(position);

    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() {
        _isSeeking = false;
        _buffering = _player.state.buffering;
      });
    }
    _revealControls();
  }

  void _seekTo(double fraction) {
    if (_duration <= Duration.zero) return;
    final target = Duration(milliseconds: (_duration.inMilliseconds * fraction).toInt());
    _seekToAbsolute(target);
  }

  Widget _buildVerticalSlider({
    required double value,
    required IconData icon,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  final localY = details.localPosition.dy;
                  final newValue = (1.0 - (localY / height)).clamp(0.0, 1.0);
                  onChanged(newValue);
                },
                onTapDown: (details) {
                  final localY = details.localPosition.dy;
                  final newValue = (1.0 - (localY / height)).clamp(0.0, 1.0);
                  onChanged(newValue);
                },
                child: Center(
                  child: Container(
                    width: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        FractionallySizedBox(
                          heightFactor: value.clamp(0.0, 1.0),
                          child: Container(
                            width: 5,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(2.5),
                            ),
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
      ],
    );
  }

  Widget _buildBottomActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getAspectRatioName(int index) {
    switch (index) {
      case 0:
        return 'Auto';
      case 1:
        return '16:9';
      case 2:
        return '21:9';
      case 3:
        return '4:3';
      default:
        return 'Auto';
    }
  }

  String _getCurrentQualityLabel() {
    if (!_ready) return 'Auto';
    final currentVideo = _player.state.track.video;
    if (currentVideo.id == 'auto') return 'AUTO';
    if (currentVideo.id == 'no') return 'OFF';
    if (currentVideo.title != null && currentVideo.title!.isNotEmpty) {
      return currentVideo.title!.toUpperCase();
    }
    if (currentVideo.h != null) {
      return '${currentVideo.h}P';
    }
    return 'Track ${currentVideo.id}'.toUpperCase();
  }

  Widget _buildLiveTvEpgLayout(dynamic theme) {
    if (_currentProgram == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            const Icon(Icons.live_tv_rounded, color: Colors.white70, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Live Streaming (No EPG program schedule available)',
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final currentFmt = '${_formatEpgTime(_currentProgram!.startTime)} - ${_formatEpgTime(_currentProgram!.stopTime)}';
    final nextFmt = _nextProgram != null
        ? '${_formatEpgTime(_nextProgram!.startTime)} - ${_formatEpgTime(_nextProgram!.stopTime)}'
        : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accentBright.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'NOW',
                        style: GoogleFonts.outfit(
                          color: AppColors.accentBright,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      currentFmt,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _currentProgram!.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_currentProgram!.description.isNotEmpty && _currentProgram!.description != 'No description available') ...[
                  const SizedBox(height: 4),
                  Text(
                    _currentProgram!.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
                if (_nextProgram != null) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Divider(color: Colors.white10, height: 1),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'NEXT',
                          style: GoogleFonts.outfit(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _nextProgram!.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              nextFmt,
                              style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: Colors.black.withValues(alpha: 0.45),
            child: InkWell(
              onTap: _showUpcomingProgramsBottomSheet,
              child: Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatEpgTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour;
    final min = local.minute.toString().padLeft(2, '0');
    final isAm = hour < 12;
    final hr = hour % 12 == 0 ? 12 : hour % 12;
    final amPm = isAm ? 'AM' : 'PM';
    return '$hr:$min $amPm';
  }

  void _loadEPG() {
    if (!widget.isLive) return;
    setState(() {
      _currentProgram = EpgService.getCurrentProgram(widget.movieId, widget.title);
      _nextProgram = EpgService.getNextProgram(widget.movieId, widget.title);
      _upcomingPrograms = EpgService.getUpcomingPrograms(widget.movieId, widget.title);
    });
  }

  void _showUpcomingProgramsBottomSheet() {
    setState(() => _showControls = false);
    _hideControlsTimer?.cancel();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF16161A).withValues(alpha: 0.95),
                  const Color(0xFF0F0F12).withValues(alpha: 0.95),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(32),
                topRight: Radius.circular(32),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, color: AppColors.accentBright, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'UPCOMING PROGRAM GUIDE',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.title ?? 'Channel Schedule',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Divider(color: Colors.white10, height: 1),
                ),
                Expanded(
                  child: _upcomingPrograms.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.event_busy_rounded, color: Colors.white24, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                'No upcoming schedules available',
                                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: _upcomingPrograms.length,
                          itemBuilder: (context, index) {
                            final p = _upcomingPrograms[index];
                            final time = '${_formatEpgTime(p.startTime)} - ${_formatEpgTime(p.stopTime)}';
                            final isNow = DateTime.now().isAfter(p.startTime) && DateTime.now().isBefore(p.stopTime);
                            
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isNow ? AppColors.accentBright.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isNow ? AppColors.accentBright.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (isNow) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          margin: const EdgeInsets.only(right: 8),
                                          decoration: BoxDecoration(
                                            color: AppColors.accentBright,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'NOW',
                                            style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                      Text(
                                        time,
                                        style: TextStyle(
                                          color: isNow ? AppColors.accentBright : Colors.white54,
                                          fontSize: 11.5,
                                          fontWeight: isNow ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    p.title,
                                    style: GoogleFonts.outfit(
                                      color: isNow ? Colors.white : Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (p.description.isNotEmpty && p.description != 'No description available') ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      p.description,
                                      style: TextStyle(
                                        color: isNow ? Colors.white70 : Colors.white38,
                                        fontSize: 11,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ],
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
    ).then((_) {
      if (mounted) {
        setState(() => _showControls = true);
        _armHideControls();
      }
    });
  }

  void _showSettingsSheet({int initialPane = 0}) {
    _revealControls();
    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) {
        return _SettingsPopover(
          player: _player,
          aspectRatios: _aspectRatios,
          initialAspectRatioIndex: _aspectRatioIndex,
          subtitleFontSize: _subtitleFontSize,
          audioDelay: _audioDelay,
          subtitleDelay: _subtitleDelay,
          initialPane: initialPane,
          onAudioDelayChanged: (delay) {
            _changeAudioDelay(delay);
          },
          onSubtitleDelayChanged: (delay) {
            _changeSubtitleDelay(delay);
          },
          onSubtitleFontSizeChanged: (newSize) {
            _changeSubtitleSize(newSize);
          },
          onAspectRatioChanged: (index) {
            setState(() {
              _aspectRatioIndex = index;
            });
          },
          getAspectRatioName: _getAspectRatioName,
          onOpenSubtitleManager: _showSubtitleManagerSheet,
          onOpenExternalPlayer: () async {
            final source = widget.videoSource;
            final displayName = await ExternalPlayerService.getPlayerDisplayName();
            if (mounted) ExternalPlayerService.showLaunchDialog(context, displayName);
            await ExternalPlayerService.launch(
              url: source,
              title: widget.title,
              headers: widget.headers,
            );
          },
        );
      },
    );
  }
}

class _SettingsPopover extends StatefulWidget {
  final Player player;
  final List<double?> aspectRatios;
  final int initialAspectRatioIndex;
  final double subtitleFontSize;
  final double audioDelay;
  final double subtitleDelay;
  final int initialPane;
  final Function(double) onAudioDelayChanged;
  final Function(double) onSubtitleDelayChanged;
  final Function(double) onSubtitleFontSizeChanged;
  final Function(int) onAspectRatioChanged;
  final String Function(int) getAspectRatioName;
  final VoidCallback? onOpenSubtitleManager;
  final VoidCallback? onOpenExternalPlayer;

  const _SettingsPopover({
    required this.player,
    required this.aspectRatios,
    required this.initialAspectRatioIndex,
    required this.subtitleFontSize,
    required this.audioDelay,
    required this.subtitleDelay,
    this.initialPane = 0,
    required this.onAudioDelayChanged,
    required this.onSubtitleDelayChanged,
    required this.onSubtitleFontSizeChanged,
    required this.onAspectRatioChanged,
    required this.getAspectRatioName,
    this.onOpenSubtitleManager,
    this.onOpenExternalPlayer,
  });

  @override
  State<_SettingsPopover> createState() => _SettingsPopoverState();
}

class _SettingsPopoverState extends State<_SettingsPopover> {
  late int _currentPane; // 0: Main, 1: Aspect Ratio, 2: Audio, 3: Subtitle
  late int _aspectRatioIndex;
  late double _audioDelay;
  late double _subtitleDelay;

  @override
  void initState() {
    super.initState();
    _currentPane = widget.initialPane;
    _aspectRatioIndex = widget.initialAspectRatioIndex;
    _audioDelay = widget.audioDelay;
    _subtitleDelay = widget.subtitleDelay;
  }

  @override
  Widget build(BuildContext context) {
    String title = 'Settings';
    Widget body;

    switch (_currentPane) {
      case 0:
        title = 'Settings';
        body = _buildMainMenu();
        break;
      case 1:
        title = 'Aspect Ratio';
        body = _buildAspectRatioMenu();
        break;
      case 2:
        title = 'Audio';
        body = _buildAudioMenu();
        break;
      case 3:
        title = 'Subtitles';
        body = _buildSubtitleMenu();
        break;
      case 4:
        title = 'Quality';
        body = _buildQualityMenu();
        break;
      default:
        body = Container();
    }

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 90, right: 24),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: _currentPane == 2 ? 310 : 250,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12, width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            if (_currentPane != 0)
                              GestureDetector(
                                onTap: () => setState(() => _currentPane = 0),
                                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                              ),
                            if (_currentPane != 0) const SizedBox(width: 8),
                            Text(
                              title.toUpperCase(),
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      // Body
                      Flexible(
                        child: SingleChildScrollView(
                          child: body,
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

  Widget _buildMainMenu() {
    final currentAudio = widget.player.state.track.audio;
    final currentSubtitle = widget.player.state.track.subtitle;
    final currentVideo = widget.player.state.track.video;

    String audioName = currentAudio.title ?? currentAudio.language ?? 'Track ${currentAudio.id}';
    if (currentAudio.id == 'auto') audioName = 'Auto';
    if (currentAudio.id == 'no') audioName = 'Off';

    String subName = currentSubtitle.title ?? currentSubtitle.language ?? 'Track ${currentSubtitle.id}';
    if (currentSubtitle.id == 'auto') subName = 'Auto';
    if (currentSubtitle.id == 'no') subName = 'Off';

    String videoName = currentVideo.title ?? '';
    if (videoName.isEmpty) {
      if (currentVideo.h != null) {
        videoName = '${currentVideo.h}p';
      } else {
        videoName = 'Track ${currentVideo.id}';
      }
    }
    if (currentVideo.id == 'auto') videoName = 'Auto';
    if (currentVideo.id == 'no') videoName = 'Off';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMenuTile(
          icon: Icons.aspect_ratio_rounded,
          label: 'Aspect Ratio',
          value: widget.getAspectRatioName(_aspectRatioIndex),
          onTap: () => setState(() => _currentPane = 1),
        ),
        _buildMenuTile(
          icon: Icons.video_settings_rounded,
          label: 'Quality',
          value: videoName,
          onTap: () => setState(() => _currentPane = 4),
        ),
        _buildMenuTile(
          icon: Icons.audiotrack_rounded,
          label: 'Audio Track',
          value: audioName,
          onTap: () => setState(() => _currentPane = 2),
        ),
        _buildMenuTile(
          icon: Icons.open_in_new_rounded,
          label: 'External Player',
          value: 'VLC / MX',
          onTap: () {
            Navigator.of(context).pop();
            widget.onOpenExternalPlayer?.call();
          },
        ),
        _buildMenuTile(
          icon: Icons.subtitles_rounded,
          label: 'Subtitles & Online Subs',
          value: subName,
          onTap: () {
            Navigator.of(context).pop();
            widget.onOpenSubtitleManager?.call();
          },
        ),
      ],
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, color: Colors.white70, size: 18),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.toUpperCase(),
            style: TextStyle(color: AppColors.accentBright, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 16),
        ],
      ),
      onTap: onTap,
    );
  }

  void _adjustAudioDelay(double delta) {
    setState(() {
      _audioDelay += delta;
      _audioDelay = double.parse(_audioDelay.toStringAsFixed(3));
    });
    widget.onAudioDelayChanged(_audioDelay);
  }

  void _adjustSubtitleDelay(double delta) {
    setState(() {
      _subtitleDelay += delta;
      _subtitleDelay = double.parse(_subtitleDelay.toStringAsFixed(3));
    });
    widget.onSubtitleDelayChanged(_subtitleDelay);
  }

  Widget _buildAspectRatioMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(widget.aspectRatios.length, (index) {
        final isSelected = index == _aspectRatioIndex;
        final name = widget.getAspectRatioName(index);

        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(
            name.toUpperCase(),
            style: TextStyle(
              color: isSelected ? AppColors.accentBright : Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
          trailing: isSelected
              ? Icon(Icons.check_rounded, color: AppColors.accentBright, size: 16)
              : null,
          onTap: () {
            widget.onAspectRatioChanged(index);
            setState(() {
              _aspectRatioIndex = index;
            });
            Navigator.of(context).pop();
          },
        );
      }),
    );
  }

  Widget _buildAudioMenu() {
    final tracks = widget.player.state.tracks.audio;
    final current = widget.player.state.track.audio;

    final String delayText = _audioDelay == 0.0 
        ? '0 ms' 
        : (_audioDelay > 0.0 ? '+${(_audioDelay * 1000).round()} ms' : '${(_audioDelay * 1000).round()} ms');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Modern Sync Delay Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'AUDIO SYNC',
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    if (_audioDelay != 0.0)
                      GestureDetector(
                        onTap: () => _adjustAudioDelay(-_audioDelay),
                        child: Text(
                          'RESET',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFFC084FC),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _adjustAudioDelay(-0.05),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '-50 ms',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0x309333EA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFC084FC).withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        delayText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _adjustAudioDelay(0.05),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '+50 ms',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'SELECT AUDIO TRACK',
            style: GoogleFonts.outfit(
              color: Colors.white54,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          ...List.generate(tracks.length, (index) {
            final track = tracks[index];
            final isSelected = track.id == current.id;
            
            String name = track.title ?? track.language ?? 'Track ${track.id}';
            if (track.id == 'auto') name = 'Auto';
            if (track.id == 'no') name = 'Off';

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    widget.player.setAudioTrack(track);
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0x359333EA) : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFC084FC) : Colors.white.withValues(alpha: 0.08),
                        width: isSelected ? 1.4 : 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                          color: isSelected ? const Color(0xFFC084FC) : Colors.white38,
                          size: 17,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: MarqueeText(
                            text: name.toUpperCase(),
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC084FC).withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: Color(0xFFC084FC),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSubtitleMenu() {
    final tracks = widget.player.state.tracks.subtitle;
    final current = widget.player.state.track.subtitle;

    final String delayText = _subtitleDelay == 0.0 
        ? '0 ms' 
        : (_subtitleDelay > 0.0 ? '+${(_subtitleDelay * 1000).round()} ms' : '${(_subtitleDelay * 1000).round()} ms');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Search & Import Online Subtitles Button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: InkWell(
            onTap: () {
              Navigator.of(context).pop();
              widget.onOpenSubtitleManager?.call();
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accentBright.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accentBright.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.travel_explore_rounded, color: AppColors.accentBright, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Search Online (OpenSubtitles)',
                    style: TextStyle(color: AppColors.accentBright, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Subtitle Size Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SIZE',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white, size: 20),
                    onPressed: () {
                      if (widget.subtitleFontSize > 24.0) {
                        widget.onSubtitleFontSizeChanged(widget.subtitleFontSize - 4.0);
                        setState(() {});
                      }
                    },
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.subtitleFontSize.toInt()}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 20),
                    onPressed: () {
                      if (widget.subtitleFontSize < 72.0) {
                        widget.onSubtitleFontSizeChanged(widget.subtitleFontSize + 4.0);
                        setState(() {});
                      }
                    },
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Sync Subtitle Delay Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SYNC DELAY',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white, size: 20),
                    onPressed: () => _adjustSubtitleDelay(-0.1),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    delayText,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 20),
                    onPressed: () => _adjustSubtitleDelay(0.1),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        
        ...List.generate(tracks.length, (index) {
          final track = tracks[index];
          final isSelected = track.id == current.id;
          
          String name = track.title ?? track.language ?? 'Track ${track.id}';
          if (track.id == 'auto') name = 'Auto';
          if (track.id == 'no') name = 'Off';

          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text(
              name.toUpperCase(),
              style: TextStyle(
                color: isSelected ? AppColors.accentBright : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            trailing: isSelected
                ? Icon(Icons.check_rounded, color: AppColors.accentBright, size: 16)
                : null,
            onTap: () {
              widget.player.setSubtitleTrack(track);
              Navigator.of(context).pop();
            },
          );
        }),
      ],
    );
  }

  Widget _buildQualityMenu() {
    final tracks = widget.player.state.tracks.video;
    final current = widget.player.state.track.video;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(tracks.length, (index) {
        final track = tracks[index];
        final isSelected = track.id == current.id;
        
        String name = track.title ?? '';
        if (name.isEmpty) {
          if (track.h != null) {
            name = '${track.h}p';
          } else {
            name = 'Track ${track.id}';
          }
        }
        if (track.id == 'auto') name = 'Auto';
        if (track.id == 'no') name = 'Off';

        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(
            name.toUpperCase(),
            style: TextStyle(
              color: isSelected ? AppColors.accentBright : Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
          trailing: isSelected
              ? Icon(Icons.check_rounded, color: AppColors.accentBright, size: 16)
              : null,
          onTap: () async {
            await widget.player.setVideoTrack(track);
            if (mounted) {
              Navigator.of(context).pop();
            }
          },
        );
      }),
    );
  }

}

class GradientCircularProgressIndicator extends StatefulWidget {
  final double size;
  final List<Color> colors;
  final double strokeWidth;

  const GradientCircularProgressIndicator({
    super.key,
    required this.size,
    required this.colors,
    this.strokeWidth = 6.0,
  });

  @override
  State<GradientCircularProgressIndicator> createState() =>
      _GradientCircularProgressIndicatorState();
}

class _GradientCircularProgressIndicatorState
    extends State<GradientCircularProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _GradientCircularProgressPainter(
          colors: widget.colors,
          strokeWidth: widget.strokeWidth,
        ),
      ),
    );
  }
}

class _GradientCircularProgressPainter extends CustomPainter {
  final List<Color> colors;
  final double strokeWidth;

  _GradientCircularProgressPainter({
    required this.colors,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: colors,
        stops: const [0.0, 1.0],
      ).createShader(rect);

    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      0,
      3.141592653589793 * 1.9,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
