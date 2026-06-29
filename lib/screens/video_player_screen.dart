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
  });

  final String videoSource;
  final String? title;
  final String? subtitle;
  final String? movieId;
  final String? imdbId;
  final bool resumeDirectly;
  final Map<String, String>? headers;
  final bool isLive;

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
  double _subtitleFontSize = 32.0; // Increased by 2x
  bool _isFavorite = false;
  double _playbackSpeed = 1.0;

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
    
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _hudTimer?.cancel();
    _clockTimer?.cancel();
    _player.dispose();
    
    // Reset orientations when exiting player
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _bindStreams() {
    _player.stream.playing.listen((v) {
      if (mounted) setState(() => _playing = v);
    });
    _player.stream.position.listen((v) {
      if (mounted) {
        setState(() {
          _position = v;
          if (v.inMilliseconds > 0 && !_hasStartedPlaying) {
            _hasStartedPlaying = true;
          }
        });

        // Save progress every 5 seconds
        final currentMs = v.inMilliseconds;
        if (widget.movieId != null && _duration.inMilliseconds > 0 && (currentMs - _lastSavedMs).abs() > 5000) {
          _lastSavedMs = currentMs;
          PlaybackTracker.saveProgress(widget.movieId!, currentMs, _duration.inMilliseconds);
        }
      }
    });
    _player.stream.duration.listen((v) {
      if (mounted) setState(() => _duration = v);
    });
    _player.stream.buffering.listen((v) {
      if (mounted) setState(() => _buffering = v);
    });
    _player.stream.volume.listen((v) {
      if (mounted) setState(() => _volume = v);
    });
    _player.stream.track.listen((_) {
      if (mounted) setState(() {});
    });
    _player.stream.error.listen((e) {
      debugPrint('VideoPlayerScreen player error: $e');
      if (mounted) {
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
        // If the player is not ready or has not started playing yet, automatically pop with failure status after 2 seconds
        if (!_ready || !_hasStartedPlaying) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).pop(true);
            }
          });
        }
      }
    });
    _player.stream.log.listen((event) {
      debugPrint('libmpv log: [${event.level}] ${event.prefix}: ${event.text}');
    });
  }

  Future<void> _open() async {
    try {
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
      if (widget.headers != null) {
        playHeaders.addAll(widget.headers!);
      } else if (widget.videoSource.startsWith('http')) {
        playHeaders.addAll({
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          if (widget.videoSource.contains('.m3u8') || widget.videoSource.contains('/hls/'))
            'Referer': 'https://streamimdb.ru/',
        });
      }
      
      // Parse inline headers from the stream URL if present
      if (widget.videoSource.startsWith('http')) {
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
        
        if (playHeaders.isNotEmpty) {
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
            headerList.add('$key: $value');
          });
          if (headerList.isNotEmpty) {
            await nativePlayer.setProperty('http-header-fields', headerList.join(','));
          }
        }
        // Enable hardware decoding
        await nativePlayer.setProperty('hwdec', 'auto');
        
        if (widget.isLive) {
          // Disable cache completely or use minimum readahead buffer for instantaneous live playback
          await nativePlayer.setProperty('cache', 'no');
          await nativePlayer.setProperty('demuxer-readahead-secs', '1');
          await nativePlayer.setProperty('cache-secs', '1');
          await nativePlayer.setProperty('network-timeout', '15');
          await nativePlayer.setProperty('hr-seek', 'no');
        } else {
          // Increase network timeout to prevent slow proxied sources (like AList/Streamtape on Koyeb) from timing out (default in media_kit is 5s)
          await nativePlayer.setProperty('network-timeout', '40');
          
          // Buffering/Streaming optimizations for low latency and memory safety
          await nativePlayer.setProperty('cache', 'yes');
          await nativePlayer.setProperty('demuxer-max-bytes', '52428800'); // 50MB buffer (safe for low RAM)
          await nativePlayer.setProperty('demuxer-max-back-bytes', '10485760'); // 10MB backward seek cache
          await nativePlayer.setProperty('demuxer-readahead-secs', '30'); // 30 seconds readahead
          await nativePlayer.setProperty('cache-secs', '30'); // 30 seconds cache duration
          await nativePlayer.setProperty('cache-pause-wait', '2'); // Buffer 2 seconds before resuming
        }
        
        // Explicit Audio/Video Synchronization and drift correction
        await nativePlayer.setProperty('video-sync', 'audio');
        await nativePlayer.setProperty('autosync', '10');
        await nativePlayer.setProperty('ao', 'audiotrack,opensles,');
      }

      var resolvedSource = widget.videoSource;
      bool isProxied = false;
      
      if (resolvedSource.startsWith('http')) {
        try {
          final uri = Uri.parse(resolvedSource);
          final host = uri.host;
          final lowerHost = host.toLowerCase();
          
          // Force proxy if URL has custom headers or is in the blocklist
          bool shouldProxy = uri.queryParameters.containsKey('headers');
          if (!shouldProxy) {
            for (final pattern in MyHttpOverrides.blocklist) {
              if (lowerHost.contains(pattern)) {
                shouldProxy = true;
                break;
              }
            }
          }
          
          if (shouldProxy) {
            final dnsProxy = CustomDnsProxy();
            if (dnsProxy.port != null) {
              final hostWithPort = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
              resolvedSource = 'http://127.0.0.1:${dnsProxy.port}/proxy/${uri.scheme}/$hostWithPort${uri.path}${uri.hasQuery ? "?" + uri.query : ""}';
              debugPrint('VideoPlayerScreen: Rewrote source to proxy relay: $resolvedSource');
              isProxied = true;
            }
          }
        } catch (e) {
          debugPrint('VideoPlayerScreen error rewriting proxy URL: $e');
        }
      }

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
      await _player.open(Media(resolvedSource, httpHeaders: playHeaders), play: false);
      
      if (seekToMs > 0) {
        // Wait reactively for media metadata/duration to resolve before seeking
        await _player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(
          const Duration(seconds: 10),
          onTimeout: () => Duration.zero,
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await _player.seek(Duration(milliseconds: seekToMs));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      
      await _player.play();

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

  void _revealControls() {
    setState(() => _showControls = true);
    _armHideControls();
  }

  void _togglePlay() {
    _player.playOrPause();
    _revealControls();
  }

  Future<void> _seekRelative(int seconds) async {
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
    _revealControls();
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
      _revealControls();
    } else if (details.pointerCount == 1 && _isDraggingHUD && _dragStartPoint != null) {
      // Single finger drag: Swipe up/down for Volume/Brightness
      final deltaY = details.localFocalPoint.dy - _dragStartPoint!.dy;
      final startX = _dragStartPoint!.dx;
      
      if (startX < screenWidth / 2) {
        // Left side: Brightness
        setState(() {
          if (_dragStartBrightness != null) {
            _brightness = (_dragStartBrightness! - deltaY / 150).clamp(0.1, 1.0);
          }
        });
      } else {
        // Right side: Volume
        setState(() {
          if (_dragStartVolume != null) {
            _volume = (_dragStartVolume! - deltaY / 2.5).clamp(0.0, 100.0);
          }
          _player.setVolume(_volume);
        });
      }
      _revealControls();
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _isDraggingHUD = false;
    _dragStartVolume = null;
    _dragStartBrightness = null;
    _dragStartPoint = null;
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
              onTap: widget.isLive ? _togglePlay : _revealControls,
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

  Widget _buildHudOverlay() {
    if (_hudType != 'seek') {
      return const SizedBox.shrink();
    }

    final isForward = (_seekOverlayValue ?? 0) > 0;
    final icon = isForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded;
    final label = isForward ? '+ 5' : '- 5';

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 64),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 28,
            ),
          ),
        ],
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
    return Theme(
      data: Theme.of(context).copyWith(
        cardColor: AppColors.surface,
      ),
      child: PopupMenuButton<SubtitleTrack>(
        child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: _buildTopBarMenuIcon(Icons.subtitles_rounded),
        ),
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (track) {
          if (track.id == 'import_online') {
            _showOnlineSubtitleImportDialog();
          } else {
            _player.setSubtitleTrack(track);
          }
        },
        itemBuilder: (context) {
          final tracks = _player.state.tracks.subtitle;
          final current = _player.state.track.subtitle;
          final List<PopupMenuEntry<SubtitleTrack>> items = [];
          
          items.addAll(tracks.map((track) {
            String name = track.title ?? track.language ?? 'Track ${track.id}';
            if (track.id == 'auto') name = 'Auto';
            if (track.id == 'no') name = 'Off';
            final isCurrent = track.id == current.id;
            return PopupMenuItem<SubtitleTrack>(
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
          }));

          items.add(const PopupMenuDivider());
          items.add(
            PopupMenuItem<SubtitleTrack>(
              value: const SubtitleTrack('import_online', 'Import Online Subtitle...', 'en'),
              child: Row(
                children: [
                  Icon(Icons.add_link_rounded, color: AppColors.accentBright, size: 18),
                  const SizedBox(width: 10),
                  const Text(
                    'Import Online Subtitle...',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          );

          return items;
        },
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

  void _showOnlineSubtitleImportDialog() {
    final textController = TextEditingController();
    int activeTab = 0; // 0: OpenSubtitles Search, 1: Manual URL
    bool loading = false;
    List<dynamic> subtitleTracks = [];
    Map<String, List<dynamic>> groupedTracks = {};
    String? expandedLang;
    String errorMsg = '';

    final langNames = {
      'eng': 'English',
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
      'hin': 'Hindi',
      'tam': 'Tamil',
      'tel': 'Telugu',
      'mal': 'Malayalam',
      'kan': 'Kannada',
      'ind': 'Indonesian',
      'may': 'Malay',
      'tha': 'Thai',
      'tur': 'Turkish',
      'vie': 'Vietnamese',
      'dut': 'Dutch',
      'pol': 'Polish',
      'swe': 'Swedish',
      'nor': 'Norwegian',
      'dan': 'Danish',
      'fin': 'Finnish',
      'heb': 'Hebrew',
      'gre': 'Greek',
      'bul': 'Bulgarian',
      'ron': 'Romanian',
      'hun': 'Hungarian',
      'cze': 'Czech',
      'slv': 'Slovenian',
      'hrv': 'Croatian',
      'srp': 'Serbian',
      'slk': 'Slovak',
      'ukr': 'Ukrainian',
      'est': 'Estonian',
      'lav': 'Latvian',
      'lit': 'Lithuanian',
    };

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> fetchSubtitles() async {
              final imdb = widget.imdbId;
              if (imdb == null || imdb.isEmpty || imdb == 'null') {
                setDialogState(() {
                  errorMsg = 'No IMDb ID available for this movie.';
                });
                return;
              }

              setDialogState(() {
                loading = true;
                errorMsg = '';
              });

              try {
                final url = 'https://opensubtitles-v3.strem.io/subtitles/movie/$imdb.json';
                debugPrint('Querying subtitles from stremio API: $url');
                final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
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

                  setDialogState(() {
                    subtitleTracks = subs;
                    groupedTracks = grouped;
                    loading = false;
                  });
                } else {
                  throw Exception('HTTP error ${response.statusCode}');
                }
              } catch (e) {
                debugPrint('Failed to query OpenSubtitles: $e');
                setDialogState(() {
                  loading = false;
                  errorMsg = 'Could not retrieve subtitles from OpenSubtitles.';
                });
              }
            }

            // Auto-trigger subtitles fetch on first load of the OpenSubtitles search tab
            if (activeTab == 0 && subtitleTracks.isEmpty && !loading && errorMsg.isEmpty) {
              Future.microtask(() => fetchSubtitles());
            }

            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              title: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setDialogState(() => activeTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: activeTab == 0 ? AppColors.accentBright : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          'OpenSubtitles Search',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: activeTab == 0 ? Colors.white : Colors.white54,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setDialogState(() => activeTab = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: activeTab == 1 ? AppColors.accentBright : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          'Custom URL Importer',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: activeTab == 1 ? Colors.white : Colors.white54,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 450,
                height: 180, // Landscape compatible size
                child: activeTab == 0
                    ? _buildOpenSubtitlesTab(
                        loading: loading,
                        errorMsg: errorMsg,
                        groupedTracks: groupedTracks,
                        expandedLang: expandedLang,
                        langNames: langNames,
                        onRetry: fetchSubtitles,
                        onLangTap: (lang) {
                          setDialogState(() {
                            expandedLang = expandedLang == lang ? null : lang;
                          });
                        },
                        onTrackSelected: (track, displayLang) {
                          final subUrl = track['url']?.toString() ?? '';
                          if (subUrl.isNotEmpty) {
                            _player.setSubtitleTrack(SubtitleTrack.uri(subUrl, title: 'OpenSubtitles: $displayLang', language: displayLang));
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('OpenSubtitles ($displayLang) loaded successfully.')),
                            );
                          }
                        },
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Enter a direct URL to a WebVTT (.vtt) or SubRip (.srt) subtitle file:',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: textController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'https://example.com/subtitles.srt',
                              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                              filled: true,
                              fillColor: Colors.black26,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                if (activeTab == 1)
                  ElevatedButton(
                    onPressed: () {
                      final url = textController.text.trim();
                      if (url.isNotEmpty && url.startsWith('http')) {
                        _player.setSubtitleTrack(SubtitleTrack.uri(url, title: 'Imported Subtitle', language: 'Imported'));
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('Online subtitle imported successfully.')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a valid HTTP/HTTPS URL.')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentBright,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('Import', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildOpenSubtitlesTab({
    required bool loading,
    required String errorMsg,
    required Map<String, List<dynamic>> groupedTracks,
    required String? expandedLang,
    required Map<String, String> langNames,
    required VoidCallback onRetry,
    required ValueChanged<String> onLangTap,
    required void Function(dynamic track, String displayLang) onTrackSelected,
  }) {
    if (loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.accentBright),
            const SizedBox(height: 12),
            const Text('Searching OpenSubtitles...', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );
    }

    if (errorMsg.isNotEmpty) {
      return Center(
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
      );
    }

    if (groupedTracks.isEmpty) {
      return const Center(
        child: Text('No subtitles found for this movie.', style: TextStyle(color: Colors.white54, fontSize: 13)),
      );
    }

    return ListView.builder(
      itemCount: groupedTracks.keys.length,
      itemBuilder: (context, index) {
        final langCode = groupedTracks.keys.elementAt(index);
        final langDisplay = langNames[langCode] ?? langCode.toUpperCase();
        final tracksList = groupedTracks[langCode] ?? [];
        final isExpanded = expandedLang == langCode;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              title: Text(
                langDisplay,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              trailing: Icon(
                isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                color: Colors.white54,
                size: 18,
              ),
              onTap: () => onLangTap(langCode),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(tracksList.length, (idx) {
                    final track = tracksList[idx];
                    final encoding = track['SubEncoding']?.toString() ?? 'Default';
                    return GestureDetector(
                      onTap: () => onTrackSelected(track, langDisplay),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Track ${idx + 1} ($langDisplay)',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            Text(
                              encoding,
                              style: const TextStyle(color: Colors.white30, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            const Divider(color: Colors.white12, height: 1),
          ],
        );
      },
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
                    ClipRRect(
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
                            Text(
                              widget.title ?? 'Movie Playback',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Right: Actions (PiP, Cast, CC Track, Subtitle Size, Quality, Audio, Lock)
                    Row(
                      children: [
                        // Picture in Picture
                        _buildTopBarIcon(
                          const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 20),
                          () async {
                            setState(() => _showControls = false);
                            try {
                              await const MethodChannel('com.privatecinema.private_cinema_mobile/pip')
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
                        
                        // Popup menu selectors (S, CC Size, Q, M)
                        _buildPopupMenuS(),
                        _buildPopupMenuSubtitleSize(),
                        _buildPopupMenuQ(),
                        _buildPopupMenuM(),

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
                          Text(
                            _timeString,
                            style: GoogleFonts.outfit(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
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
                        _brightness = val.clamp(0.1, 1.0);
                      });
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

  void _showSettingsSheet() {
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
          onSubtitleFontSizeChanged: (newSize) {
            _changeSubtitleSize(newSize);
          },
          onAspectRatioChanged: (index) {
            setState(() {
              _aspectRatioIndex = index;
            });
          },
          getAspectRatioName: _getAspectRatioName,
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
  final Function(double) onSubtitleFontSizeChanged;
  final Function(int) onAspectRatioChanged;
  final String Function(int) getAspectRatioName;

  const _SettingsPopover({
    required this.player,
    required this.aspectRatios,
    required this.initialAspectRatioIndex,
    required this.subtitleFontSize,
    required this.onSubtitleFontSizeChanged,
    required this.onAspectRatioChanged,
    required this.getAspectRatioName,
  });

  @override
  State<_SettingsPopover> createState() => _SettingsPopoverState();
}

class _SettingsPopoverState extends State<_SettingsPopover> {
  int _currentPane = 0; // 0: Main, 1: Aspect Ratio, 2: Audio, 3: Subtitle
  late int _aspectRatioIndex;

  @override
  void initState() {
    super.initState();
    _aspectRatioIndex = widget.initialAspectRatioIndex;
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
            width: 250,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
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
          icon: Icons.subtitles_rounded,
          label: 'Subtitles',
          value: subName,
          onTap: () => setState(() => _currentPane = 3),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(tracks.length, (index) {
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
            widget.player.setAudioTrack(track);
            Navigator.of(context).pop();
          },
        );
      }),
    );
  }

  Widget _buildSubtitleMenu() {
    final tracks = widget.player.state.tracks.subtitle;
    final current = widget.player.state.track.subtitle;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
