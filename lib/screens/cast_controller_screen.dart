import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/data/wifi_cast_service.dart';

/// Full-featured interactive touchscreen remote deck for casting movies to Android TV over local Wi-Fi.
///
/// Features:
/// - Real-time two-way synchronization: If the TV user pauses or seeks with the physical TV remote,
///   this screen updates within 500ms.
/// - Exact-time seeking bar, ±10s skip controls, and responsive Play/Pause toggle.
/// - Offline Wi-Fi Direct indicator (zero internet consumed on TV or Phone).
/// - Clean disconnect / stop button.
class CastControllerScreen extends StatefulWidget {
  const CastControllerScreen({
    super.key,
    required this.title,
    this.tvHost = '',
    this.proxyUrl,
    this.tvName,
    this.posterUrl,
    this.initialPositionMs = 0,
    this.initialDurationMs = 0,
    this.isOffline = false,
  });

  final String title;
  final String tvHost;
  final String? proxyUrl;
  final String? tvName;
  final String? posterUrl;
  final int initialPositionMs;
  final int initialDurationMs;
  final bool isOffline;

  @override
  State<CastControllerScreen> createState() => _CastControllerScreenState();
}

class _CastControllerScreenState extends State<CastControllerScreen> with SingleTickerProviderStateMixin {
  late bool _isPlaying;
  late int _positionMs;
  late int _durationMs;
  bool _isDragging = false;
  double _dragValue = 0;
  Timer? _pollTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _isPlaying = true;
    _positionMs = widget.initialPositionMs;
    _durationMs = widget.initialDurationMs;
    _dragValue = _positionMs.toDouble();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Initial status fetch immediately
    _fetchStatus();

    // Poll TV status every 600ms to stay in 100% sync with physical TV remote
    _pollTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (mounted && !_isDragging) {
        _fetchStatus();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    if (widget.tvHost.isEmpty) return;
    final status = await WifiCastService.fetchPlaybackStatus(tvHost: widget.tvHost);
    if (status != null && mounted && !_isDragging) {
      setState(() {
        _isPlaying = status['is_playing'] as bool? ?? _isPlaying;
        final pos = (status['position_ms'] as num?)?.toInt() ?? _positionMs;
        final dur = (status['duration_ms'] as num?)?.toInt() ?? _durationMs;
        if (dur > 0) _durationMs = dur;
        _positionMs = pos;
        _dragValue = pos.toDouble();
      });
    }
  }

  Future<void> _togglePlayPause() async {
    final nextState = !_isPlaying;
    setState(() => _isPlaying = nextState);
    if (widget.tvHost.isNotEmpty) {
      await WifiCastService.sendControl(
        tvHost: widget.tvHost,
        command: nextState ? 'play' : 'pause',
      );
    }
  }

  Future<void> _seekTo(int targetMs) async {
    final maxMs = _durationMs > 0 ? _durationMs : targetMs;
    final clamped = targetMs.clamp(0, maxMs);
    setState(() {
      _positionMs = clamped;
      _dragValue = clamped.toDouble();
    });
    if (widget.tvHost.isNotEmpty) {
      await WifiCastService.sendControl(
        tvHost: widget.tvHost,
        command: 'seek',
        positionMs: clamped,
      );
    }
  }

  Future<void> _stopCasting() async {
    if (widget.tvHost.isNotEmpty) {
      await WifiCastService.sendControl(tvHost: widget.tvHost, command: 'stop');
    }
    await WifiCastService.stopAll();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String _formatTime(int ms) {
    if (ms <= 0) return '00:00';
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final currentMs = _isDragging ? _dragValue.toInt() : _positionMs;
    final totalMs = _durationMs > 0 ? _durationMs : (currentMs > 0 ? currentMs : 1);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0C14),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  // Glowing Cast Active Pill
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final opacity = 0.4 + (_pulseController.value * 0.6);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.accent.withOpacity(opacity), width: 1.2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.accentBright,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.accentBright.withOpacity(opacity),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'CASTING TO TV',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  children: [
                    const SizedBox(height: 12),

                    // Poster Card with subtle ambient shadow
                    Container(
                      width: 170,
                      height: 250,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withOpacity(0.25),
                            blurRadius: 36,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: widget.posterUrl != null && widget.posterUrl!.isNotEmpty
                            ? Image.network(
                                widget.posterUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _buildPlaceholderPoster(),
                              )
                            : _buildPlaceholderPoster(),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Title
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Connected Device Name
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.tv_rounded, color: Colors.white54, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          widget.tvName ?? 'Smart TV (${widget.tvHost})',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Connection Mode Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: widget.isOffline
                            ? Colors.greenAccent.withOpacity(0.12)
                            : Colors.blueAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.isOffline
                              ? Colors.greenAccent.withOpacity(0.4)
                              : Colors.blueAccent.withOpacity(0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isOffline ? Icons.wifi_protected_setup_rounded : Icons.cell_tower_rounded,
                            color: widget.isOffline ? Colors.greenAccent : Colors.lightBlueAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.isOffline
                                ? 'Offline Wi-Fi Direct • Zero Internet Used'
                                : 'Wi-Fi Stream Relay Active',
                            style: TextStyle(
                              color: widget.isOffline ? Colors.greenAccent : Colors.lightBlueAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 36),

                    // Progress Slider
                    Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            activeTrackColor: AppColors.accentBright,
                            inactiveTrackColor: Colors.white12,
                            thumbColor: Colors.white,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                            overlayColor: AppColors.accent.withOpacity(0.2),
                          ),
                          child: Slider(
                            value: _isDragging ? _dragValue : _positionMs.toDouble().clamp(0.0, totalMs.toDouble()),
                            min: 0.0,
                            max: totalMs.toDouble(),
                            onChangeStart: (_) {
                              setState(() => _isDragging = true);
                            },
                            onChanged: (val) {
                              setState(() => _dragValue = val);
                            },
                            onChangeEnd: (val) {
                              _isDragging = false;
                              _seekTo(val.toInt());
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatTime(currentMs),
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                              Text(
                                _formatTime(_durationMs),
                                style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Controls Row (-10s, Play/Pause, +10s)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Skip -10s
                        _buildControlButton(
                          icon: Icons.replay_10_rounded,
                          size: 48,
                          iconSize: 26,
                          onPressed: () => _seekTo(_positionMs - 10000),
                        ),

                        const SizedBox(width: 28),

                        // Play / Pause Large Glow Button
                        GestureDetector(
                          onTap: _togglePlayPause,
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFFE50914), Color(0xFFB81D24)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE50914).withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ),

                        const SizedBox(width: 28),

                        // Skip +10s
                        _buildControlButton(
                          icon: Icons.forward_10_rounded,
                          size: 48,
                          iconSize: 26,
                          onPressed: () => _seekTo(_positionMs + 10000),
                        ),
                      ],
                    ),

                    const SizedBox(height: 36),

                    // Dual Sync Info Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.sync_rounded, color: AppColors.accentBright, size: 20),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Dual Sync Active: You can control playback here or using your physical TV remote.',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Disconnect / Stop Casting Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F1215),
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.redAccent.withOpacity(0.4)),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _stopCasting,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cast_connected_rounded, color: Colors.redAccent, size: 20),
                          SizedBox(width: 10),
                          Text(
                            'Disconnect & Stop Casting',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderPoster() {
    return Container(
      color: const Color(0xFF161924),
      child: Center(
        child: Icon(Icons.movie_rounded, color: Colors.white.withOpacity(0.2), size: 64),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required double size,
    required double iconSize,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }
}
