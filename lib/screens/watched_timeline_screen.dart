import 'dart:convert';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';
import '../data/simkl_service.dart';
import '../data/tmdb_service.dart';
import '../widgets/quick_movie_rater_dialog.dart';
import 'movie_detail_screen.dart';

class MonthTimelineGroup {
  final String key; // e.g. "2026-08"
  final String displayTitle; // e.g. "August 2026"
  final String shortMonth; // e.g. "AUG"
  final int year;
  final int month;
  final List<SimklHistoryItem> items;

  MonthTimelineGroup({
    required this.key,
    required this.displayTitle,
    required this.shortMonth,
    required this.year,
    required this.month,
    required this.items,
  });

  double get avgRating {
    final rated = items.where((i) => i.userRating != null && i.userRating! > 0).toList();
    if (rated.isEmpty) return 0.0;
    final sum = rated.map((i) => i.userRating!).reduce((a, b) => a + b);
    return sum / rated.length;
  }
}

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

  // Timeline Mode: 'watched_date' vs 'release_date'
  String _dateMode = 'watched_date';

  // Selected Month Key for Drilldown (null = Month Stacks Overview)
  String? _selectedMonthKey;

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
        _dateMode = prefs.getString('timeline_date_mode') ?? 'watched_date';
      });
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('timeline_bg_url', _bgWallpaperUrl);
    await prefs.setDouble('timeline_bg_blur', _bgBlur);
    await prefs.setDouble('timeline_bg_vignette', _bgVignette);
    await prefs.setDouble('timeline_bg_darkness', _bgDarkness);
    await prefs.setString('timeline_date_mode', _dateMode);
  }

  DateTime _getEffectiveDate(SimklHistoryItem item) {
    if (_dateMode == 'release_date') {
      if (item.releaseDate != null) return item.releaseDate!;
      if (item.movie.year != null && item.movie.year! > 1800) {
        return DateTime(item.movie.year!, 1, 1);
      }
    }
    return item.watchedAt;
  }

  void _sortItems() {
    _historyItems.sort((a, b) {
      final aDate = _getEffectiveDate(a);
      final bDate = _getEffectiveDate(b);
      return bDate.compareTo(aDate);
    });
  }

  Future<void> _loadTimeline() async {
    setState(() => _isLoading = true);
    await _loadLocalOverrides();
    final items = await SimklService.fetchWatchedTimeline();

    // Apply any local manual overrides (Custom release date, watched date, rating, etc.)
    for (int i = 0; i < items.length; i++) {
      final key = items[i].movie.tmdbId ?? items[i].movie.id;
      if (_manualOverrides.containsKey(key)) {
        final override = _manualOverrides[key]!;
        DateTime customWatched = items[i].watchedAt;
        // Only override watched date if explicitly modified by the user in the timeline editor
        if (override['is_manual_date'] == true && override['watched_date'] != null) {
          customWatched = DateTime.tryParse(override['watched_date'].toString()) ?? items[i].watchedAt;
        }
        DateTime? customRelease = items[i].releaseDate;
        if (override['is_manual_release'] == true && override['release_date'] != null) {
          customRelease = DateTime.tryParse(override['release_date'].toString()) ?? items[i].releaseDate;
        }
        double? customRating = items[i].userRating;
        if (override['rating'] != null) {
          customRating = (override['rating'] as num).toDouble();
        }
        items[i] = SimklHistoryItem(
          movie: items[i].movie,
          watchedAt: customWatched,
          releaseDate: customRelease,
          userRating: customRating,
        );
      }
    }

    // Include locally rated movies from Quick Movie Rater that might still be syncing
    final existingKeys = items.map((i) => i.movie.tmdbId ?? i.movie.id).toSet();
    _manualOverrides.forEach((key, data) {
      if (!existingKeys.contains(key) && data['title'] != null) {
        final relDate = data['release_date'] != null ? DateTime.tryParse(data['release_date'].toString()) : null;
        final watchDate = data['watched_date'] != null
            ? (DateTime.tryParse(data['watched_date'].toString()) ?? DateTime.now())
            : (relDate ?? DateTime.now());
        final rating = data['rating'] != null ? (data['rating'] as num).toDouble() : null;
        items.add(SimklHistoryItem(
          movie: Movie(
            id: key,
            title: data['title']?.toString() ?? 'Movie',
            year: data['year'] as int? ?? relDate?.year ?? watchDate.year,
            description: data['notes']?.toString() ?? '',
            tmdbId: key,
            genre: 'Rated',
            posterUrl: data['poster_url']?.toString() ?? '',
            rating: (rating ?? 0.0) * 2,
          ),
          watchedAt: watchDate,
          releaseDate: relDate ?? watchDate,
          userRating: rating,
        ));
      }
    });

    _historyItems = items;
    _sortItems();

    if (mounted) {
      setState(() {
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

  List<MonthTimelineGroup> _getMonthGroups() {
    final Map<String, List<SimklHistoryItem>> map = {};
    for (final item in _historyItems) {
      final d = _getEffectiveDate(item);
      final key = DateFormat('yyyy-MM').format(d);
      map.putIfAbsent(key, () => []).add(item);
    }

    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));

    return keys.map((key) {
      final list = map[key]!;
      final firstDate = _getEffectiveDate(list.first);
      return MonthTimelineGroup(
        key: key,
        displayTitle: DateFormat('MMMM yyyy').format(firstDate),
        shortMonth: DateFormat('MMM').format(firstDate).toUpperCase(),
        year: firstDate.year,
        month: firstDate.month,
        items: list,
      );
    }).toList();
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
              child: SingleChildScrollView(
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
                    const SizedBox(height: 14),

                    // Date Mode Toggle
                    Text(
                      'Timeline Date Grouping Mode',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _dateMode = 'watched_date';
                                  _sortItems();
                                });
                                setModalState(() {});
                                _saveSettings();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _dateMode == 'watched_date' ? Colors.amberAccent : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.visibility_rounded,
                                        size: 15,
                                        color: _dateMode == 'watched_date' ? Colors.black : Colors.white70,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Watched Date',
                                        style: GoogleFonts.outfit(
                                          color: _dateMode == 'watched_date' ? Colors.black : Colors.white70,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _dateMode = 'release_date';
                                  _sortItems();
                                });
                                setModalState(() {});
                                _saveSettings();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _dateMode == 'release_date' ? Colors.amberAccent : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.theaters_rounded,
                                        size: 15,
                                        color: _dateMode == 'release_date' ? Colors.black : Colors.white70,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Release Date',
                                        style: GoogleFonts.outfit(
                                          color: _dateMode == 'release_date' ? Colors.black : Colors.white70,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _dateMode == 'watched_date'
                          ? '• Showing timeline based on exact date watched/rated.'
                          : '• Showing timeline based on theatrical movie release date.',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 18),

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
    DateTime selectedWatchedDate = item.watchedAt;
    DateTime selectedReleaseDate = item.releaseDate ?? item.watchedAt;
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
              child: SingleChildScrollView(
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
                    const SizedBox(height: 18),

                    // 1. Watched Date Picker
                    Text('Watched / Rating Date', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedWatchedDate,
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
                          setSheetState(() => selectedWatchedDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.visibility_rounded, color: Colors.amberAccent, size: 18),
                            const SizedBox(width: 10),
                            Text(
                              DateFormat('dd MMMM yyyy').format(selectedWatchedDate),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 2. Theatrical Release Date Picker
                    Text('Theatrical Release Date', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedReleaseDate,
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
                          setSheetState(() => selectedReleaseDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.theaters_rounded, color: Colors.amberAccent, size: 18),
                            const SizedBox(width: 10),
                            Text(
                              DateFormat('dd MMMM yyyy').format(selectedReleaseDate),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. User Rating Slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Your Rating', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              '${selectedRating.toStringAsFixed(1)} / 5.0',
                              style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Slider(
                      value: selectedRating,
                      min: 0.5,
                      max: 5.0,
                      divisions: 9,
                      activeColor: Colors.amberAccent,
                      label: selectedRating.toStringAsFixed(1),
                      onChanged: (v) => setSheetState(() => selectedRating = v),
                    ),
                    const SizedBox(height: 12),

                    // 4. Personal Memory / Note
                    Text('Memory / Note', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. Watched in theater with friends...',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amberAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 4,
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _saveLocalOverride(movieId, {
                            'release_date': selectedReleaseDate.toIso8601String(),
                            'watched_date': selectedWatchedDate.toIso8601String(),
                            'rating': selectedRating,
                            'notes': noteController.text.trim(),
                            'is_manual_date': true,
                            'is_manual_release': true,
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
    return PopScope(
      canPop: _selectedMonthKey == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedMonthKey != null) {
          setState(() => _selectedMonthKey = null);
        }
      },
      child: Scaffold(
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
            onPressed: () {
              if (_selectedMonthKey != null) {
                setState(() => _selectedMonthKey = null);
              } else {
                Navigator.of(context).pop();
              }
            },
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedMonthKey != null ? 'Month Timeline' : 'My Watch Timeline',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      _dateMode == 'watched_date' ? 'By Watched Date' : 'By Release Date',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            // Quick Date Mode Toggle Pill
            GestureDetector(
              onTap: () {
                setState(() {
                  _dateMode = _dateMode == 'watched_date' ? 'release_date' : 'watched_date';
                  _sortItems();
                });
                _saveSettings();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 1),
                    content: Text(
                      _dateMode == 'watched_date'
                          ? 'Timeline Mode: Watched / Rating Date'
                          : 'Timeline Mode: Theatrical Release Date',
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amberAccent.withOpacity(0.6), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _dateMode == 'watched_date' ? Icons.visibility_rounded : Icons.theaters_rounded,
                      size: 13,
                      color: Colors.amberAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _dateMode == 'watched_date' ? 'Watched' : 'Release',
                      style: GoogleFonts.outfit(
                        color: Colors.amberAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
    final groups = _getMonthGroups();

    if (_selectedMonthKey != null) {
      final selectedGroup = groups.firstWhere(
        (g) => g.key == _selectedMonthKey,
        orElse: () => groups.isNotEmpty ? groups.first : MonthTimelineGroup(
          key: '',
          displayTitle: '',
          shortMonth: '',
          year: 0,
          month: 0,
          items: [],
        ),
      );

      return _buildSingleMonthDetailedView(selectedGroup);
    }

    // Default: Month Stacks Overview View
    return _buildMonthStacksOverview(groups);
  }

  /// Primary Month Stacks Overview (Fanned decks per month with live wave zoom)
  Widget _buildMonthStacksOverview(List<MonthTimelineGroup> groups) {
    return Column(
      children: [
        // Top Glass Stats Bar (Completed • Months • Avg Score • Watch Time)
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
              _buildStatMetric(Icons.date_range_rounded, '${groups.length}', 'Months', color: const Color(0xFF10B981)),
              Container(width: 1, height: 24, color: Colors.white12),
              _buildStatMetric(Icons.star_rounded, _calculateAvgRating(), 'Avg Score', color: Colors.amberAccent),
              Container(width: 1, height: 24, color: Colors.white12),
              _buildStatMetric(Icons.schedule_rounded, _calculateTotalWatchHours(), 'Watch Time', color: const Color(0xFF38BDF8)),
            ],
          ),
        ),

        // Glowing Cinema Reel Track with Month Stacks
        Expanded(
          child: Stack(
            children: [
              // Central Glowing Film Rope Spine
              _buildSpine(),

              // Animated Month Stacks with Wave Scaling
              AnimatedBuilder(
                animation: _scrollController,
                builder: (context, _) {
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      final isLeft = index % 2 == 0;

                      // Year Transition Checkpoint
                      bool showYearCheckpoint = false;
                      if (index == 0) {
                        showYearCheckpoint = true;
                      } else {
                        final prevGroup = groups[index - 1];
                        if (group.year != prevGroup.year) {
                          showYearCheckpoint = true;
                        }
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showYearCheckpoint) _buildYearCheckpoint(group.year),
                          _LiveMonthStackCard(
                            group: group,
                            isLeft: isLeft,
                            scrollController: _scrollController,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() => _selectedMonthKey = group.key);
                            },
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

  /// Single Month Detailed View (All movies for selected month)
  Widget _buildSingleMonthDetailedView(MonthTimelineGroup group) {
    return Column(
      children: [
        // Month Breadcrumb & Navigation Bar
        Container(
          margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF131D31).withOpacity(0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () => setState(() => _selectedMonthKey = null),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amberAccent.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_rounded, color: Colors.amberAccent, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'All Months',
                        style: GoogleFonts.outfit(
                          color: Colors.amberAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.displayTitle,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${group.items.length} ${group.items.length == 1 ? "Movie" : "Movies"}${group.avgRating > 0 ? " • ★ ${group.avgRating.toStringAsFixed(1)} Avg Score" : ""}',
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Glowing Cinema Reel Track with individual movies for that month
        Expanded(
          child: Stack(
            children: [
              _buildSpine(),
              AnimatedBuilder(
                animation: _scrollController,
                builder: (context, _) {
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                    itemCount: group.items.length,
                    itemBuilder: (context, index) {
                      final item = group.items[index];
                      final isLeft = index % 2 == 0;
                      return _LiveWaveCard(
                        item: item,
                        isLeft: isLeft,
                        dateMode: _dateMode,
                        scrollController: _scrollController,
                        onTap: () => _openFullMovieDetails(item),
                        onLongPress: () => _showEditItemSheet(item),
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

  Widget _buildSpine() {
    return Positioned(
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
    );
  }

  /// Big Prominent Year Checkpoint
  Widget _buildYearCheckpoint(int year) {
    return Container(
      margin: const EdgeInsets.only(top: 18, bottom: 12),
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

/// Live Month Stack Card (Overlapping Poster Deck + Stats + Continuous Wave Scaling)
class _LiveMonthStackCard extends StatefulWidget {
  const _LiveMonthStackCard({
    required this.group,
    required this.isLeft,
    required this.scrollController,
    required this.onTap,
  });

  final MonthTimelineGroup group;
  final bool isLeft;
  final ScrollController scrollController;
  final VoidCallback onTap;

  @override
  State<_LiveMonthStackCard> createState() => _LiveMonthStackCardState();
}

class _LiveMonthStackCardState extends State<_LiveMonthStackCard> {
  final GlobalKey _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cardWidth = (width / 2) - 28;

    // Live RenderBox viewport coordinates calculation for wave scaling
    double scale = 0.85;
    double opacity = 0.80;

    final renderBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize && renderBox.attached) {
      final cardCenterY = renderBox.localToGlobal(Offset.zero).dy + (renderBox.size.height / 2);
      final screenHeight = MediaQuery.of(context).size.height;
      final screenCenterY = screenHeight / 2;

      final distance = (cardCenterY - screenCenterY).abs().clamp(0.0, screenCenterY);
      final normalized = distance / screenCenterY;
      final waveProgress = (1.0 - normalized).clamp(0.0, 1.0);

      scale = 0.68 + (waveProgress * 0.32);
      opacity = 0.55 + (waveProgress * 0.45);
    }

    final posters = widget.group.items
        .map((i) => i.movie.posterUrl)
        .where((p) => p.isNotEmpty)
        .take(4)
        .toList();

    return KeyedSubtree(
      key: _cardKey,
      child: Container(
        width: width,
        padding: const EdgeInsets.only(bottom: 14.0),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Curved Golden Connector Bridge
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

            // 2. Center Dot on rope
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

            // 3. Month Stack Card
            Row(
              mainAxisAlignment: widget.isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
              children: [
                if (!widget.isLeft) SizedBox(width: (width / 2) + 12),
                Transform.scale(
                  scale: scale,
                  alignment: widget.isLeft ? Alignment.centerRight : Alignment.centerLeft,
                  child: Opacity(
                    opacity: opacity.clamp(0.50, 1.0),
                    child: SizedBox(
                      width: cardWidth,
                      child: GestureDetector(
                        onTap: widget.onTap,
                        child: Transform.rotate(
                          angle: widget.isLeft ? -0.03 : 0.03,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF141C2B).withOpacity(0.95),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.amberAccent.withOpacity(0.6),
                                width: 1.4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.7),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                                BoxShadow(
                                  color: Colors.amberAccent.withOpacity(0.2),
                                  blurRadius: 10,
                                  spreadRadius: -2,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Month Header
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.amberAccent.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: const Icon(Icons.calendar_month_rounded, color: Colors.amberAccent, size: 14),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        widget.group.displayTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Fanned / Stacked Poster Deck
                                _buildPosterDeck(posters, cardWidth - 20),
                                const SizedBox(height: 8),

                                // Footer: Movie Count & Avg Rating & Action
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.movie_rounded, color: Colors.amberAccent, size: 11),
                                          const SizedBox(width: 3.5),
                                          Text(
                                            '${widget.group.items.length}',
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (widget.group.avgRating > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F172A),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.amberAccent.withOpacity(0.5)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 11),
                                            const SizedBox(width: 2.5),
                                            Text(
                                              widget.group.avgRating.toStringAsFixed(1),
                                              style: GoogleFonts.outfit(
                                                color: Colors.amberAccent,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Open',
                                          style: GoogleFonts.outfit(
                                            color: Colors.amberAccent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.amberAccent, size: 9),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.isLeft) SizedBox(width: (width / 2) + 12),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosterDeck(List<String> posters, double availableWidth) {
    if (posters.isEmpty) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Icon(Icons.movie_filter_rounded, color: Colors.white24, size: 32),
        ),
      );
    }

    final double posterW = (availableWidth * 0.44).clamp(52.0, 68.0);
    final double posterH = posterW * 1.45;

    if (posters.length == 1) {
      return Center(
        child: _buildSinglePoster(posters[0], posterW * 1.15, posterH * 1.15, 0.0, isFront: true),
      );
    }

    if (posters.length == 2) {
      return SizedBox(
        width: double.infinity,
        height: posterH + 16,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Background poster peeking to the left & slightly higher
            Transform.translate(
              offset: const Offset(-18, -4),
              child: _buildSinglePoster(posters[1], posterW * 0.90, posterH * 0.90, -0.14, opacity: 0.88),
            ),
            // Front poster centered
            _buildSinglePoster(posters[0], posterW * 1.05, posterH * 1.05, 0.0, isFront: true),
            if (widget.group.items.length > 1)
              Positioned(
                bottom: 0,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.90),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amberAccent, width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.6),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Text(
                    '+${widget.group.items.length - 1}',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // 3 or more posters: Fanned Deck with last rated movie front & center, and min 2 back posters clearly peeking out
    return SizedBox(
      width: double.infinity,
      height: posterH + 18,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 4th movie (if available) peeking from top-center
          if (posters.length >= 4)
            Transform.translate(
              offset: const Offset(0, -8),
              child: _buildSinglePoster(posters[3], posterW * 0.78, posterH * 0.78, 0.0, opacity: 0.60),
            ),
          // Left card peeking out from back
          Transform.translate(
            offset: const Offset(-22, -2),
            child: _buildSinglePoster(posters[1], posterW * 0.88, posterH * 0.88, -0.16, opacity: 0.88),
          ),
          // Right card peeking out from back
          Transform.translate(
            offset: const Offset(22, -2),
            child: _buildSinglePoster(posters[2], posterW * 0.88, posterH * 0.88, 0.16, opacity: 0.88),
          ),
          // Front & Center Poster
          _buildSinglePoster(posters[0], posterW * 1.05, posterH * 1.05, 0.0, isFront: true),

          // Badge on bottom right of the deck
          if (widget.group.items.length > 1)
            Positioned(
              bottom: 0,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.90),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amberAccent, width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  '+${widget.group.items.length - 1}',
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSinglePoster(
    String url,
    double w,
    double h,
    double angle, {
    bool isFront = false,
    double opacity = 1.0,
  }) {
    return Transform.rotate(
      angle: angle,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isFront ? Colors.amberAccent.withOpacity(0.85) : Colors.white24,
              width: isFront ? 1.4 : 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isFront ? 0.85 : 0.50),
                blurRadius: isFront ? 12 : 6,
                offset: Offset(0, isFront ? 5 : 3),
              ),
              if (isFront)
                BoxShadow(
                  color: Colors.amberAccent.withOpacity(0.20),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: const Color(0xFF0F172A)),
              errorWidget: (_, __, ___) => Container(
                color: const Color(0xFF0F172A),
                child: const Icon(Icons.movie_creation_rounded, color: Colors.white24, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wave Animated Movie Poster Card
class _LiveWaveCard extends StatefulWidget {
  const _LiveWaveCard({
    required this.item,
    required this.isLeft,
    required this.dateMode,
    required this.scrollController,
    required this.onTap,
    required this.onLongPress,
  });

  final SimklHistoryItem item;
  final bool isLeft;
  final String dateMode;
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

    final effectiveDate = widget.dateMode == 'release_date'
        ? (widget.item.releaseDate ?? widget.item.watchedAt)
        : widget.item.watchedAt;

    final releaseYear = widget.item.movie.year ?? widget.item.releaseDate?.year ?? widget.item.watchedAt.year;
    final dateFormatted = DateFormat('dd MMM yyyy').format(effectiveDate);

    // Live RenderBox viewport coordinates calculation
    double scale = 0.85;
    double opacity = 0.80;

    final renderBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize && renderBox.attached) {
      final cardCenterY = renderBox.localToGlobal(Offset.zero).dy + (renderBox.size.height / 2);
      final screenHeight = MediaQuery.of(context).size.height;
      final screenCenterY = screenHeight / 2;

      final distance = (cardCenterY - screenCenterY).abs().clamp(0.0, screenCenterY);
      final normalized = distance / screenCenterY;
      final waveProgress = (1.0 - normalized).clamp(0.0, 1.0);

      scale = 0.65 + (waveProgress * 0.35);
      opacity = 0.50 + (waveProgress * 0.50);
    }

    return KeyedSubtree(
      key: _cardKey,
      child: Container(
        width: width,
        padding: const EdgeInsets.only(bottom: 10.0),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Curved Golden Connector Bridge
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

            // 2. Center Dot - LOCKED on the central yellow rope line
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
                          angle: widget.isLeft ? -0.035 : 0.035,
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
                                // Portrait Poster
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

                                    // Year / Mode Pill
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
                                            Icon(
                                              widget.dateMode == 'release_date'
                                                  ? Icons.theaters_rounded
                                                  : Icons.visibility_rounded,
                                              color: Colors.amberAccent,
                                              size: 10,
                                            ),
                                            const SizedBox(width: 3.5),
                                            Text(
                                              widget.dateMode == 'release_date'
                                                  ? '$releaseYear'
                                                  : DateFormat('MMM yy').format(effectiveDate),
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

                                    // Rating Pill
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
                                          Icon(
                                            widget.dateMode == 'release_date'
                                                ? Icons.calendar_today_rounded
                                                : Icons.event_available_rounded,
                                            color: Colors.amberAccent,
                                            size: 10,
                                          ),
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
