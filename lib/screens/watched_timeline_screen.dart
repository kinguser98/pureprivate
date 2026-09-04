import 'dart:convert';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';
import '../theme/app_colors.dart';
import '../data/simkl_service.dart';
import '../data/tmdb_service.dart';
import '../widgets/quick_movie_rater_dialog.dart';
import 'movie_detail_screen.dart';

class WatchedTimelineScreen extends StatefulWidget {
  const WatchedTimelineScreen({super.key});

  @override
  State<WatchedTimelineScreen> createState() => _WatchedTimelineScreenState();
}

class _WatchedTimelineScreenState extends State<WatchedTimelineScreen> {
  List<SimklHistoryItem> _historyItems = [];
  bool _isLoading = true;
  final Map<String, Map<String, dynamic>> _manualOverrides = {};
  final ScrollController _scrollController = ScrollController();

  // Live Ambience & Wallpaper Settings
  String _bgWallpaperUrl = 'https://images.unsplash.com/photo-1536440136628-849c177e76a1?q=80&w=1280&auto=format&fit=crop';
  double _bgBlur = 12.0;
  double _bgVignette = 0.65;
  double _bgDarkness = 0.60;

  final List<Map<String, String>> _presetWallpapers = [
    {
      'name': 'Cinema Velvet',
      'url': 'https://images.unsplash.com/photo-1536440136628-849c177e76a1?q=80&w=1280&auto=format&fit=crop',
    },
    {
      'name': 'Deep Nebula',
      'url': 'https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?q=80&w=1280&auto=format&fit=crop',
    },
    {
      'name': 'Golden Noir',
      'url': 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?q=80&w=1280&auto=format&fit=crop',
    },
    {
      'name': 'Cyber Reel',
      'url': 'https://images.unsplash.com/photo-1517604931442-7e0c8ed2963c?q=80&w=1280&auto=format&fit=crop',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadTimeline();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _bgWallpaperUrl = prefs.getString('timeline_bg_url') ?? _bgWallpaperUrl;
        _bgBlur = prefs.getDouble('timeline_bg_blur') ?? _bgBlur;
        _bgVignette = prefs.getDouble('timeline_bg_vignette') ?? _bgVignette;
        _bgDarkness = prefs.getDouble('timeline_bg_darkness') ?? _bgDarkness;
      });
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('timeline_bg_url', _bgWallpaperUrl);
    await prefs.setDouble('timeline_bg_blur', _bgBlur);
    await prefs.setDouble('timeline_bg_vignette', _bgVignette);
    await prefs.setDouble('timeline_bg_darkness', _bgDarkness);
  }

  Future<void> _loadTimeline() async {
    setState(() => _isLoading = true);
    await _loadLocalOverrides();
    final items = await SimklService.fetchWatchedTimeline();

    // Apply any local manual overrides (Custom release date, custom rating, etc.)
    for (int i = 0; i < items.length; i++) {
      final key = items[i].movie.tmdbId ?? items[i].movie.id;
      if (_manualOverrides.containsKey(key)) {
        final override = _manualOverrides[key]!;
        DateTime customDate = items[i].watchedAt;
        if (override['release_date'] != null) {
          customDate = DateTime.tryParse(override['release_date']) ?? items[i].watchedAt;
        }
        double? customRating = items[i].userRating;
        if (override['rating'] != null) {
          customRating = (override['rating'] as num).toDouble();
        }
        items[i] = SimklHistoryItem(
          movie: items[i].movie,
          watchedAt: customDate,
          userRating: customRating,
        );
      }
    }

    // Sort chronologically by Release Date (Newest to Oldest)
    items.sort((a, b) {
      final aYear = a.movie.year ?? a.watchedAt.year;
      final bYear = b.movie.year ?? b.watchedAt.year;
      if (aYear != bYear) return bYear.compareTo(aYear);
      return b.watchedAt.compareTo(a.watchedAt);
    });

    if (mounted) {
      setState(() {
        _historyItems = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadLocalOverrides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('timeline_manual_overrides');
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _manualOverrides.clear();
        decoded.forEach((k, v) {
          if (v is Map) {
            _manualOverrides[k] = Map<String, dynamic>.from(v);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveLocalOverride(String movieId, Map<String, dynamic> data) async {
    _manualOverrides[movieId] = data;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('timeline_manual_overrides', jsonEncode(_manualOverrides));
    _loadTimeline();
  }

  void _showLiveAmbienceSettings() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.palette_rounded, color: Colors.amberAccent, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Live Ambience & Wallpaper',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.check_circle_rounded, color: Colors.amberAccent),
                        onPressed: () {
                          _saveSettings();
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Wallpaper Presets
                  Text('Backdrop Theme', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _presetWallpapers.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final preset = _presetWallpapers[i];
                        final isSel = _bgWallpaperUrl == preset['url'];
                        return ChoiceChip(
                          label: Text(preset['name']!),
                          selected: isSel,
                          selectedColor: Colors.amberAccent,
                          labelStyle: TextStyle(
                            color: isSel ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          backgroundColor: Colors.white10,
                          onSelected: (_) {
                            setState(() => _bgWallpaperUrl = preset['url']!);
                            setModalState(() {});
                            _saveSettings();
                          },
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Blur Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Glass Blur Intensity', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
                      Text('${_bgBlur.toStringAsFixed(0)} px', style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _bgBlur,
                    min: 0.0,
                    max: 25.0,
                    activeColor: Colors.amberAccent,
                    onChanged: (v) {
                      setState(() => _bgBlur = v);
                      setModalState(() {});
                    },
                  ),

                  // Vignette Edge Darkening Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Edge Vignette Darkness', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
                      Text('${(_bgVignette * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _bgVignette,
                    min: 0.0,
                    max: 1.0,
                    activeColor: Colors.amberAccent,
                    onChanged: (v) {
                      setState(() => _bgVignette = v);
                      setModalState(() {});
                    },
                  ),

                  // Background Dimming Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Background Dimming', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
                      Text('${(_bgDarkness * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _bgDarkness,
                    min: 0.1,
                    max: 0.95,
                    activeColor: Colors.amberAccent,
                    onChanged: (v) {
                      setState(() => _bgDarkness = v);
                      setModalState(() {});
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showEditItemSheet(SimklHistoryItem item) {
    HapticFeedback.mediumImpact();
    final movieId = item.movie.tmdbId ?? item.movie.id;
    DateTime selectedDate = item.watchedAt;
    double selectedRating = item.userRating ?? 4.0;
    final noteController = TextEditingController(
      text: _manualOverrides[movieId]?['notes']?.toString() ?? '',
    );

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF131B2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.edit_calendar_rounded, color: Colors.amberAccent, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Timeline Entry',
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              item.movie.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 1. Release / Timeline Date Picker
                  Text('Release / Timeline Date', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        builder: (context, child) {
                          return Theme(
                            data: ThemeData.dark().copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: Colors.amberAccent,
                                onPrimary: Colors.black,
                                surface: Color(0xFF1E293B),
                                onSurface: Colors.white,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setSheetState(() => selectedDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, color: Colors.amberAccent, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            DateFormat('dd MMMM yyyy').format(selectedDate),
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 2. Personal Star Rating
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Your Rating', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(
                        '${selectedRating.toStringAsFixed(selectedRating % 1 == 0 ? 0 : 1)} / 5 ★',
                        style: GoogleFonts.outfit(color: Colors.amberAccent, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SliderTheme(
                    data: SliderTheme.of(ctx).copyWith(
                      activeTrackColor: Colors.amberAccent,
                      thumbColor: Colors.amberAccent,
                      inactiveTrackColor: Colors.white24,
                    ),
                    child: Slider(
                      value: selectedRating,
                      min: 0.5,
                      max: 5.0,
                      divisions: 9,
                      onChanged: (v) => setSheetState(() => selectedRating = v),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Save Action Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amberAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await _saveLocalOverride(movieId, {
                          'release_date': selectedDate.toIso8601String(),
                          'rating': selectedRating,
                          'notes': noteController.text.trim(),
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Updated "${item.movie.title}" in Timeline!'),
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        );
                      },
                      child: const Text('Save Timeline Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openFullMovieDetails(SimklHistoryItem item) async {
    HapticFeedback.lightImpact();
    final tmdbId = item.movie.tmdbId ?? item.movie.id.replaceAll('simkl_', '').replaceAll('ptw_', '');
    Movie targetMovie = item.movie;

    if (tmdbId.isNotEmpty && tmdbId != '0' && int.tryParse(tmdbId) != null) {
      try {
        final tmdbDetails = await TmdbService.getMovieDetails(tmdbId);
        if (tmdbDetails != null) {
          targetMovie = Movie(
            id: tmdbId,
            title: tmdbDetails['title'] ?? item.movie.title,
            year: int.tryParse(tmdbDetails['release_date']?.toString().split('-').first ?? '') ?? item.movie.year,
            description: tmdbDetails['overview'] ?? item.movie.description,
            tmdbId: tmdbId,
            imdbId: tmdbDetails['imdb_id'] ?? item.movie.imdbId,
            genre: (tmdbDetails['genres'] as List?)?.map((g) => g['name']).join(', ') ?? item.movie.genre,
            posterUrl: tmdbDetails['poster_path'] != null
                ? 'https://image.tmdb.org/t/p/w500${tmdbDetails['poster_path']}'
                : item.movie.posterUrl,
            backdropUrl: tmdbDetails['backdrop_path'] != null
                ? 'https://image.tmdb.org/t/p/w1280${tmdbDetails['backdrop_path']}'
                : item.movie.backdropUrl,
            rating: (tmdbDetails['vote_average'] as num?)?.toDouble() ?? item.movie.rating,
          );
        }
      } catch (_) {}
    }

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: targetMovie)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A).withOpacity(0.85),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.movie_filter_rounded, color: Colors.black, size: 17),
            ),
            const SizedBox(width: 10),
            Text(
              'My Watch Timeline',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded, color: Colors.amberAccent),
            tooltip: 'Quick Movie Rater',
            onPressed: () {
              final existingIds = _historyItems
                  .map((item) => item.movie.tmdbId ?? item.movie.id)
                  .where((id) => id.isNotEmpty)
                  .toList();
              QuickMovieRaterDialog.show(
                context,
                existingRatedTmdbIds: existingIds,
                onDataChanged: _loadTimeline,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.palette_rounded, color: Colors.amberAccent),
            tooltip: 'Live Ambience & Wallpaper',
            onPressed: _showLiveAmbienceSettings,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refresh Timeline',
            onPressed: _loadTimeline,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live Wallpaper Background
          if (_bgWallpaperUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: _bgWallpaperUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: const Color(0xFF090D16)),
              errorWidget: (_, __, ___) => Container(color: const Color(0xFF090D16)),
            ),

          // 2. Live Glass Blur Filter
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: _bgBlur, sigmaY: _bgBlur),
              child: Container(color: Colors.black.withOpacity(_bgDarkness)),
            ),
          ),

          // 3. Live Edge Vignette Radial Overlay
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.1,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(_bgVignette * 0.4),
                  Colors.black.withOpacity(_bgVignette),
                ],
                stops: const [0.35, 0.75, 1.0],
              ),
            ),
          ),

          // 4. Main Timeline Content
          SafeArea(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.amberAccent),
                        SizedBox(height: 16),
                        Text('Loading your watch timeline...', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  )
                : _historyItems.isEmpty
                    ? _buildEmptyState()
                    : _buildTimelineContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Colors.amberAccent.withOpacity(0.2), Colors.transparent],
                ),
              ),
              child: const Text('🍿', style: TextStyle(fontSize: 56)),
            ),
            const SizedBox(height: 16),
            Text(
              'Your Watch Timeline is Ready',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Rate or mark movies as completed in the app to populate your vertical glowing watch timeline!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amberAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh Timeline', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _loadTimeline,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineContent() {
    // Group movie counts per month for dynamic proportional sizing
    final Map<String, int> monthCounts = {};
    for (final item in _historyItems) {
      final key = DateFormat('MMM yyyy').format(item.watchedAt);
      monthCounts[key] = (monthCounts[key] ?? 0) + 1;
    }

    return Column(
      children: [
        // Top Glass Stats Bar (Completed • Avg Score • Total Watch Hours)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF131D31).withOpacity(0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatMetric(Icons.movie_creation_rounded, '${_historyItems.length}', 'Completed'),
              Container(width: 1, height: 24, color: Colors.white12),
              _buildStatMetric(Icons.star_rounded, _calculateAvgRating(), 'Avg Score', color: Colors.amberAccent),
              Container(width: 1, height: 24, color: Colors.white12),
              _buildStatMetric(Icons.schedule_rounded, _calculateTotalWatchHours(), 'Watch Time', color: const Color(0xFF38BDF8)),
            ],
          ),
        ),

        // Glowing Cinema Reel Track with Continuous Wave Zoom & Proportional Checkpoints
        Expanded(
          child: Stack(
            children: [
              // Central Glowing Film Rope Spine
              Positioned(
                top: 0,
                bottom: 0,
                left: MediaQuery.of(context).size.width / 2 - 2,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFFFD54F),
                        Color(0xFFF59E0B),
                        Color(0xFFD97706),
                        Color(0xFFFFD54F),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amberAccent.withOpacity(0.6),
                        blurRadius: 16,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),

              // Animated Timeline Items with Wave Zoom Controller
              AnimatedBuilder(
                animation: _scrollController,
                builder: (context, _) {
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                    itemCount: _historyItems.length,
                    itemBuilder: (context, index) {
                      final item = _historyItems[index];
                      final isLeft = index % 2 == 0;

                      // Check year and month transitions
                      final currentYear = item.movie.year ?? item.watchedAt.year;
                      final currentMonthKey = DateFormat('MMM yyyy').format(item.watchedAt);

                      bool showYearCheckpoint = false;
                      bool showMonthCheckpoint = false;

                      if (index == 0) {
                        showYearCheckpoint = true;
                        showMonthCheckpoint = true;
                      } else {
                        final prevItem = _historyItems[index - 1];
                        final prevYear = prevItem.movie.year ?? prevItem.watchedAt.year;
                        final prevMonthKey = DateFormat('MMM yyyy').format(prevItem.watchedAt);

                        if (currentYear != prevYear) {
                          showYearCheckpoint = true;
                        }
                        if (currentMonthKey != prevMonthKey) {
                          showMonthCheckpoint = true;
                        }
                      }

                      final int countInMonth = monthCounts[currentMonthKey] ?? 1;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 1. Prominent Year Checkpoint
                          if (showYearCheckpoint) _buildYearCheckpoint(currentYear),

                          // 2. Dynamic Sized Month Checkpoint (Scales with movie count)
                          if (showMonthCheckpoint) _buildMonthCheckpoint(DateFormat('MMMM').format(item.watchedAt).toUpperCase(), countInMonth),

                          // 3. Wave Animated Movie Poster Card
                          _LiveWaveCard(
                            item: item,
                            isLeft: isLeft,
                            scrollController: _scrollController,
                            onTap: () => _openFullMovieDetails(item),
                            onLongPress: () => _showEditItemSheet(item),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Big Prominent Year Checkpoint
  Widget _buildYearCheckpoint(int year) {
    return Container(
      margin: const EdgeInsets.only(top: 24, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.amberAccent, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.amberAccent.withOpacity(0.6),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.stars_rounded, color: Colors.black, size: 16),
          const SizedBox(width: 6),
          Text(
            '$year',
            style: GoogleFonts.outfit(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Month Checkpoint with Dynamic Size based on Watched Movie Count
  Widget _buildMonthCheckpoint(String monthName, int count) {
    // Dynamic proportional sizing
    final double extraPadding = (count.clamp(1, 8) * 1.2);
    final double fontSize = 9.5 + (count.clamp(1, 6) * 0.4);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: EdgeInsets.symmetric(horizontal: 10 + extraPadding, vertical: 3.5 + (extraPadding * 0.3)),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amberAccent.withOpacity(0.8), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.amberAccent.withOpacity(0.25 + (count * 0.05).clamp(0.0, 0.4)),
            blurRadius: 8 + (count * 1.5).clamp(0.0, 10.0),
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$monthName • $count ${count == 1 ? "Movie" : "Movies"}',
            style: GoogleFonts.outfit(
              color: Colors.amberAccent,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  String _calculateAvgRating() {
    final rated = _historyItems.where((i) => i.userRating != null && i.userRating! > 0).toList();
    if (rated.isEmpty) return '5.0★';
    final sum = rated.map((i) => i.userRating!).reduce((a, b) => a + b);
    return '${(sum / rated.length).toStringAsFixed(1)}★';
  }

  String _calculateTotalWatchHours() {
    if (_historyItems.isEmpty) return '0 hrs';
    int totalMinutes = 0;
    for (final item in _historyItems) {
      if (item.movie.runtime != null) {
        final match = RegExp(r'(\d+)').firstMatch(item.movie.runtime!);
        if (match != null) {
          totalMinutes += int.tryParse(match.group(1)!) ?? 115;
          continue;
        }
      }
      totalMinutes += 115;
    }

    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (mins == 0) return '$hours hrs';
    return '${hours}h ${mins}m';
  }

  Widget _buildStatMetric(IconData icon, String value, String label, {Color color = Colors.white}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

class _RopeConnectorPainter extends CustomPainter {
  _RopeConnectorPainter({required this.isLeft, required this.color});
  final bool isLeft;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final path = Path();
    if (isLeft) {
      path.moveTo(size.width, size.height / 2);
      path.quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.70,
        0,
        size.height / 2,
      );
    } else {
      path.moveTo(0, size.height / 2);
      path.quadraticBezierTo(
        size.width * 0.55,
        size.height * 0.70,
        size.width,
        size.height / 2,
      );
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MarqueeText extends StatefulWidget {
  const _MarqueeText({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  late final ScrollController _scrollController = ScrollController();
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }

  @override
  void dispose() {
    _disposed = true;
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startScrolling() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    while (!_disposed && mounted && _scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll <= 0) break;

      await _scrollController.animateTo(
        maxScroll,
        duration: Duration(milliseconds: (maxScroll * 35).toInt().clamp(1500, 5000)),
        curve: Curves.easeInOut,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      if (!_disposed && mounted && _scrollController.hasClients) {
        await _scrollController.animateTo(
          0.0,
          duration: Duration(milliseconds: (maxScroll * 30).toInt().clamp(1200, 4000)),
          curve: Curves.easeInOut,
        );
        await Future<void>.delayed(const Duration(milliseconds: 1000));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, style: widget.style),
    );
  }
}

class _LiveWaveCard extends StatefulWidget {
  const _LiveWaveCard({
    required this.item,
    required this.isLeft,
    required this.scrollController,
    required this.onTap,
    required this.onLongPress,
  });

  final SimklHistoryItem item;
  final bool isLeft;
  final ScrollController scrollController;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_LiveWaveCard> createState() => _LiveWaveCardState();
}

class _LiveWaveCardState extends State<_LiveWaveCard> {
  final GlobalKey _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cardWidth = (width / 2) - 34;
    final releaseYear = widget.item.movie.year ?? widget.item.watchedAt.year;
    final dateFormatted = DateFormat('dd MMM yyyy').format(widget.item.watchedAt);

    // Live RenderBox viewport coordinates calculation
    double scale = 0.85;
    double opacity = 0.80;

    final renderBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize && renderBox.attached) {
      final cardCenterY = renderBox.localToGlobal(Offset.zero).dy + (renderBox.size.height / 2);
      final screenHeight = MediaQuery.of(context).size.height;
      final screenCenterY = screenHeight / 2;

      // Distance from screen center (0 at middle, screenCenterY at top/bottom edges)
      final distance = (cardCenterY - screenCenterY).abs().clamp(0.0, screenCenterY);
      final normalized = distance / screenCenterY; // 0.0 (middle) to 1.0 (edges)
      final waveProgress = (1.0 - normalized).clamp(0.0, 1.0); // 1.0 (middle) to 0.0 (edges)

      // Continuous wave formula: 0.65x at bottom/top, 1.00x at exact center!
      scale = 0.65 + (waveProgress * 0.35);
      opacity = 0.50 + (waveProgress * 0.50);
    }

    return KeyedSubtree(
      key: _cardKey,
      child: Container(
        width: width,
        padding: const EdgeInsets.only(bottom: 10.0), // Reduced tight vertical gap
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Curved Golden Connector Bridge (Anchored from center dot to card)
            Positioned(
              left: widget.isLeft ? (width / 2) - 26 : (width / 2),
              width: 26,
              height: 24,
              child: CustomPaint(
                painter: _RopeConnectorPainter(
                  isLeft: widget.isLeft,
                  color: Colors.amberAccent,
                ),
              ),
            ),

            // 2. Center Dot - LOCKED 100% on the central yellow rope line
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF090D16),
                border: Border.all(color: Colors.amberAccent, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amberAccent.withOpacity(0.9),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // 3. Movie Poster Card with Curved Angle & Center-Anchored Wave Scale
            Row(
              mainAxisAlignment: widget.isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
              children: [
                if (!widget.isLeft) SizedBox(width: (width / 2) + 14),
                Transform.scale(
                  scale: scale,
                  alignment: widget.isLeft ? Alignment.centerRight : Alignment.centerLeft,
                  child: Opacity(
                    opacity: opacity.clamp(0.50, 1.0),
                    child: SizedBox(
                      width: cardWidth,
                      child: GestureDetector(
                        onTap: widget.onTap,
                        onLongPress: widget.onLongPress,
                        child: Transform.rotate(
                          angle: widget.isLeft ? -0.035 : 0.035, // organic curve angle
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF141C2B).withOpacity(0.95),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.amberAccent.withOpacity(0.55),
                                width: 1.3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.7),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                                BoxShadow(
                                  color: Colors.amberAccent.withOpacity(0.18),
                                  blurRadius: 10,
                                  spreadRadius: -2,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Compact Portrait Poster
                                Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                                      child: AspectRatio(
                                        aspectRatio: 2 / 2.6,
                                        child: widget.item.movie.posterUrl.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: widget.item.movie.posterUrl,
                                                fit: BoxFit.cover,
                                                placeholder: (_, __) => Container(color: const Color(0xFF0F172A)),
                                                errorWidget: (_, __, ___) => Container(
                                                  color: const Color(0xFF0F172A),
                                                  child: const Icon(Icons.movie_creation_rounded, color: Colors.white24, size: 28),
                                                ),
                                              )
                                            : Container(
                                                color: const Color(0xFF0F172A),
                                                child: const Icon(Icons.movie_creation_rounded, color: Colors.white24, size: 28),
                                              ),
                                      ),
                                    ),

                                    // Prominent Release Date Stamp
                                    Positioned(
                                      top: 6,
                                      left: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.88),
                                          borderRadius: BorderRadius.circular(7),
                                          border: Border.all(color: Colors.amberAccent, width: 1.0),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.5),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.calendar_today_rounded, color: Colors.amberAccent, size: 10),
                                            const SizedBox(width: 3.5),
                                            Text(
                                              '$releaseYear',
                                              style: GoogleFonts.outfit(
                                                color: Colors.white,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Prominent Rating Pill on Poster
                                    if (widget.item.userRating != null)
                                      Positioned(
                                        bottom: 6,
                                        right: 6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0F172A).withOpacity(0.92),
                                            borderRadius: BorderRadius.circular(7),
                                            border: Border.all(color: Colors.amberAccent, width: 1.0),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.amberAccent.withOpacity(0.3),
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 12),
                                              const SizedBox(width: 2.5),
                                              Text(
                                                widget.item.userRating!.toStringAsFixed(1),
                                                style: GoogleFonts.outfit(
                                                  color: Colors.amberAccent,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                    // Long-press icon
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.75),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.touch_app_rounded, color: Colors.white60, size: 10),
                                      ),
                                    ),
                                  ],
                                ),

                                // Metadata Footer
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Auto-Scrolling Title for Long Names
                                      _MarqueeText(
                                        text: widget.item.movie.title,
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          const Icon(Icons.event_available_rounded, color: Colors.amberAccent, size: 10),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              dateFormatted,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.outfit(
                                                color: Colors.white70,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
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
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.isLeft) SizedBox(width: (width / 2) + 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
