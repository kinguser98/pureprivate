import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/simkl_service.dart';
import '../data/tmdb_service.dart';

class QuickMovieRaterDialog extends StatefulWidget {
  final List<String> existingRatedTmdbIds;
  final VoidCallback onDataChanged;

  const QuickMovieRaterDialog({
    super.key,
    required this.existingRatedTmdbIds,
    required this.onDataChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required List<String> existingRatedTmdbIds,
    required VoidCallback onDataChanged,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Quick Movie Rater',
      barrierColor: Colors.black.withOpacity(0.92),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (ctx, anim1, anim2) => QuickMovieRaterDialog(
        existingRatedTmdbIds: existingRatedTmdbIds,
        onDataChanged: onDataChanged,
      ),
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<QuickMovieRaterDialog> createState() => _QuickMovieRaterDialogState();
}

class _QuickMovieItem {
  final String tmdbId;
  final String title;
  final String? originalTitle;
  final String? posterPath;
  final String? backdropPath;
  final String releaseDate;
  final int? year;
  final double voteAverage;
  final int voteCount;
  final String overview;
  final String originalLanguage;
  final List<String> genreNames;
  bool isFavorite;
  double? existingRating; // If already rated previously

  _QuickMovieItem({
    required this.tmdbId,
    required this.title,
    this.originalTitle,
    this.posterPath,
    this.backdropPath,
    required this.releaseDate,
    this.year,
    required this.voteAverage,
    required this.voteCount,
    required this.overview,
    required this.originalLanguage,
    required this.genreNames,
    this.isFavorite = false,
    this.existingRating,
  });

  String get posterUrl => posterPath != null && posterPath!.isNotEmpty
      ? 'https://image.tmdb.org/t/p/w780$posterPath'
      : '';

  String get backdropUrl => backdropPath != null && backdropPath!.isNotEmpty
      ? 'https://image.tmdb.org/t/p/w1280$backdropPath'
      : '';
}

class _QuickMovieRaterDialogState extends State<QuickMovieRaterDialog>
    with SingleTickerProviderStateMixin {
  final List<_QuickMovieItem> _movieQueue = [];
  final Set<String> _excludedIds = {};
  final Set<String> _skippedIds = {};
  final Set<String> _locallyRatedIds = {};
  final Set<String> _favoriteIds = {};

  bool _isLoading = true;
  bool _isFetchingMore = false;
  int _sessionRatedCount = 0;

  // Rating state for the current active movie (0.0 to 5.0 with 0.5 step, default 0.0)
  double _currentSelectedRating = 0.0;

  // Animation controller for card transitions
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // Filter States
  String _selectedLanguage = 'all'; // 'all', 'ml', 'ta', 'hi', 'te', 'kn', 'en', 'ko', etc.
  final Set<int> _selectedYears = {}; // Empty means all years
  bool _hideAlreadyRated = true;

  // History stack for Undo
  final List<Map<String, dynamic>> _undoHistory = [];

  // Available Languages
  static const List<Map<String, String>> _availableLanguages = [
    {'code': 'all', 'name': 'All Languages'},
    {'code': 'ml', 'name': 'Malayalam (മലയാളം)'},
    {'code': 'ta', 'name': 'Tamil (தமிழ்)'},
    {'code': 'hi', 'name': 'Hindi (हिंदी)'},
    {'code': 'te', 'name': 'Telugu (తెలుగు)'},
    {'code': 'kn', 'name': 'Kannada (ಕನ್ನಡ)'},
    {'code': 'en', 'name': 'English'},
    {'code': 'ko', 'name': 'Korean (한국어)'},
    {'code': 'ja', 'name': 'Japanese (日本語)'},
    {'code': 'es', 'name': 'Spanish'},
    {'code': 'fr', 'name': 'French'},
  ];

  // TMDB Genre Map
  static const Map<int, String> _genreMap = {
    28: 'Action',
    12: 'Adventure',
    16: 'Animation',
    35: 'Comedy',
    80: 'Crime',
    99: 'Documentary',
    18: 'Drama',
    10751: 'Family',
    14: 'Fantasy',
    36: 'History',
    27: 'Horror',
    10402: 'Music',
    9648: 'Mystery',
    10749: 'Romance',
    878: 'Sci-Fi',
    10770: 'TV Movie',
    53: 'Thriller',
    10752: 'War',
    37: 'Western',
  };

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1.2, 0.0),
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeInOutCubic));

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeIn));

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeIn));

    _initFiltersAndQueue();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _initFiltersAndQueue() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Load skipped movies
    final savedSkipped = prefs.getStringList('skipped_movie_ids') ?? [];
    _skippedIds.addAll(savedSkipped);

    // 2. Load locally rated movies
    final savedRated = prefs.getStringList('quick_rated_movie_ids') ?? [];
    _locallyRatedIds.addAll(savedRated);

    // 3. Load favorites
    final savedFavs = prefs.getStringList('favorites') ?? [];
    _favoriteIds.addAll(savedFavs);

    // 4. Load manual timeline overrides
    try {
      final raw = prefs.getString('timeline_manual_overrides');
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _locallyRatedIds.addAll(decoded.keys.map((k) => k.toString()));
        }
      }
    } catch (_) {}

    // 5. Load filter preferences
    _selectedLanguage = prefs.getString('quick_rater_lang') ?? 'all';
    _hideAlreadyRated = prefs.getBool('quick_rater_hide_rated') ?? true;
    final savedYearList = prefs.getStringList('quick_rater_years');
    if (savedYearList != null && savedYearList.isNotEmpty) {
      _selectedYears.clear();
      for (final y in savedYearList) {
        final parsed = int.tryParse(y);
        if (parsed != null) _selectedYears.add(parsed);
      }
    }

    // 6. Build excluded list
    _excludedIds.addAll(widget.existingRatedTmdbIds);
    _excludedIds.addAll(_skippedIds);
    _excludedIds.addAll(_locallyRatedIds);

    // 7. Also fetch TMDB user rated movies in background if user is logged in
    _fetchTmdbUserRatedIds();

    await _fetchMovies(clearExisting: true);
  }

  Future<void> _fetchTmdbUserRatedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('tmdb_session_id');
      final accountId = prefs.getString('tmdb_account_id');
      if (sessionId != null && accountId != null) {
        final url = 'https://api.themoviedb.org/3/account/$accountId/rated/movies?api_key=${TmdbService.apiKey}&session_id=$sessionId';
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final results = data['results'] as List? ?? [];
          for (final m in results) {
            final id = m['id']?.toString();
            if (id != null) {
              _excludedIds.add(id);
              _locallyRatedIds.add(id);
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveFilterPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('quick_rater_lang', _selectedLanguage);
    await prefs.setBool('quick_rater_hide_rated', _hideAlreadyRated);
    await prefs.setStringList(
      'quick_rater_years',
      _selectedYears.map((y) => y.toString()).toList(),
    );
  }

  final Map<String, int> _pageTracker = {};

  Future<void> _fetchMovies({bool clearExisting = false}) async {
    if (clearExisting) {
      setState(() {
        _isLoading = true;
        _movieQueue.clear();
        _currentSelectedRating = 0.0;
        _pageTracker.clear();
      });
    } else {
      if (_isFetchingMore) return;
      _isFetchingMore = true;
    }

    try {
      final List<_QuickMovieItem> fetchedItems = [];
      final List<int?> targetYears = _selectedYears.isEmpty ? [null] : _selectedYears.toList();

      // We want to fetch until we have gathered at least 30 fresh unrated movies (or reached total pages)
      int loopCycles = 0;
      const int maxCycles = 25; // scan up to 25 page rounds to cover all pages

      while (fetchedItems.length < 30 && loopCycles < maxCycles) {
        loopCycles++;
        bool anyResultsFoundInRound = false;

        for (final yr in targetYears) {
          final trackerKey = '$_selectedLanguage-$yr';
          final currentPage = _pageTracker[trackerKey] ?? 1;
          _pageTracker[trackerKey] = currentPage + 1;

          // Build query params
          final queryParams = <String, String>{
            'api_key': TmdbService.apiKey,
            'include_adult': 'false',
            'page': currentPage.toString(),
          };

          if (_selectedLanguage != 'all') {
            queryParams['with_original_language'] = _selectedLanguage;
          }

          if (yr != null) {
            queryParams['primary_release_year'] = yr.toString();
            queryParams['sort_by'] = 'popularity.desc';
          } else {
            final sortOptions = [
              'popularity.desc',
              'vote_count.desc',
              'revenue.desc',
              'vote_average.desc',
            ];
            queryParams['sort_by'] = sortOptions[(currentPage - 1) % sortOptions.length];
            queryParams['primary_release_date.gte'] = '1990-01-01';
            queryParams['primary_release_date.lte'] = DateTime.now().toIso8601String().split('T')[0];
            if (_selectedLanguage == 'all') {
              queryParams['vote_count.gte'] = '5';
            }
          }

          final uri = Uri.https('api.themoviedb.org', '/3/discover/movie', queryParams);
          final res = await http.get(uri).timeout(const Duration(seconds: 8));

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final results = data['results'] as List? ?? [];
            final totalPages = (data['total_pages'] as num?)?.toInt() ?? 1;

            if (results.isNotEmpty) {
              anyResultsFoundInRound = true;
            }

            if (currentPage >= totalPages) {
              _pageTracker[trackerKey] = totalPages + 10;
            }

            for (final item in results) {
              final id = item['id']?.toString() ?? '';
              if (id.isEmpty) continue;

              // Only skip if already in excluded list
              if (_hideAlreadyRated && _excludedIds.contains(id)) continue;

              final relDate = item['release_date']?.toString() ?? '';
              int? parsedYear;
              if (relDate.isNotEmpty && relDate.length >= 4) {
                parsedYear = int.tryParse(relDate.substring(0, 4));
              }

              final genreIds = (item['genre_ids'] as List? ?? []).cast<int>();
              final genreNames = genreIds
                  .map((gId) => _genreMap[gId] ?? '')
                  .where((g) => g.isNotEmpty)
                  .take(3)
                  .toList();

              final isFav = _favoriteIds.contains(id);

              fetchedItems.add(_QuickMovieItem(
                tmdbId: id,
                title: item['title']?.toString() ?? 'Untitled Movie',
                originalTitle: item['original_title']?.toString(),
                posterPath: item['poster_path']?.toString(),
                backdropPath: item['backdrop_path']?.toString(),
                releaseDate: relDate,
                year: parsedYear,
                voteAverage: (item['vote_average'] as num?)?.toDouble() ?? 0.0,
                voteCount: (item['vote_count'] as num?)?.toInt() ?? 0,
                overview: item['overview']?.toString() ?? '',
                originalLanguage: item['original_language']?.toString() ?? 'en',
                genreNames: genreNames,
                isFavorite: isFav,
              ));
            }
          }
        }

        if (!anyResultsFoundInRound) {
          break;
        }
      }

      // Deduplicate by TMDB ID
      final Map<String, _QuickMovieItem> uniqueMap = {};
      for (final item in fetchedItems) {
        uniqueMap[item.tmdbId] = item;
      }
      final uniqueList = uniqueMap.values.toList();

      if (mounted) {
        setState(() {
          _movieQueue.addAll(uniqueList);
          _isLoading = false;
          _isFetchingMore = false;
          _currentSelectedRating = 0.0;
        });
      }
    } catch (e) {
      debugPrint('Error fetching quick rater movies: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
    }
  }

  void _nextMovie() {
    if (_movieQueue.isNotEmpty) {
      _movieQueue.removeAt(0);
      if (_movieQueue.length < 8) {
        _fetchMovies(clearExisting: false);
      }
    }
    _animController.reset();
    setState(() {
      _currentSelectedRating = 0.0;
    });
  }

  Future<void> _rateMovie(_QuickMovieItem movie, double rating5) async {
    if (rating5 <= 0.0) return;
    HapticFeedback.mediumImpact();

    final rating10 = (rating5 * 2.0).round().clamp(1, 10);

    // 1. Record in excluded and locally rated sets
    _excludedIds.add(movie.tmdbId);
    _locallyRatedIds.add(movie.tmdbId);
    _sessionRatedCount++;

    // 2. Save to SharedPreferences for permanent local cache
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('quick_rated_movie_ids', _locallyRatedIds.toList());

    // 3. Save to Watch Timeline Manual Overrides
    try {
      final raw = prefs.getString('timeline_manual_overrides');
      Map<String, dynamic> overrides = {};
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) overrides = Map<String, dynamic>.from(decoded);
      }

      DateTime releaseDateTime = DateTime.now();
      if (movie.releaseDate.isNotEmpty) {
        releaseDateTime = DateTime.tryParse(movie.releaseDate) ?? DateTime.now();
      }

      overrides[movie.tmdbId] = {
        'release_date': movie.releaseDate,
        'rating': rating5,
        'notes': 'Rated via Quick Movie Rater',
        'title': movie.title,
        'poster_url': movie.posterUrl,
        'year': movie.year ?? releaseDateTime.year,
      };
      await prefs.setString('timeline_manual_overrides', jsonEncode(overrides));
    } catch (e) {
      debugPrint('Error saving timeline override: $e');
    }

    // 4. Add to Undo Stack
    _undoHistory.add({
      'type': 'rate',
      'movie': movie,
      'rating5': rating5,
      'rating10': rating10,
    });

    // 5. Asynchronously sync to SIMKL & TMDB
    SimklService.submitRating(
      tmdbId: movie.tmdbId,
      rating: rating10,
      isSeries: false,
    );
    TmdbService.rateMovie(movie.tmdbId, rating10.toDouble());

    // 6. Notify parent timeline screen to refresh
    widget.onDataChanged();

    // 7. Trigger smooth exit animation
    await _animController.forward();
    _nextMovie();
  }

  Future<void> _skipMovie(_QuickMovieItem movie) async {
    HapticFeedback.lightImpact();

    // 1. Mark as skipped from deck ONLY (does NOT overwrite or touch existing ratings)
    _excludedIds.add(movie.tmdbId);
    _skippedIds.add(movie.tmdbId);

    // 2. Save to SharedPreferences so it never comes back in discovery deck
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('skipped_movie_ids', _skippedIds.toList());

    // 3. Add to Undo Stack
    _undoHistory.add({
      'type': 'skip',
      'movie': movie,
    });

    // 4. Trigger animation
    await _animController.forward();
    _nextMovie();
  }

  Future<void> _toggleFavorite(_QuickMovieItem movie) async {
    HapticFeedback.mediumImpact();
    final newFav = !movie.isFavorite;

    setState(() {
      movie.isFavorite = newFav;
      if (newFav) {
        _favoriteIds.add(movie.tmdbId);
      } else {
        _favoriteIds.remove(movie.tmdbId);
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', _favoriteIds.toList());

    // Sync to TMDB
    TmdbService.markAsFavorite(movie.tmdbId, newFav);

    // Sync to SIMKL
    if (newFav) {
      SimklService.addToFavorites(tmdbId: movie.tmdbId);
    } else {
      SimklService.removeFromFavorites(tmdbId: movie.tmdbId);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newFav ? '❤️ Added to Favorites on TMDb & SIMKL' : '💔 Removed from Favorites',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: newFav ? Colors.pinkAccent.shade700 : Colors.grey.shade900,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _undoLast() async {
    if (_undoHistory.isEmpty) return;
    HapticFeedback.mediumImpact();

    final lastAction = _undoHistory.removeLast();
    final movie = lastAction['movie'] as _QuickMovieItem;
    final type = lastAction['type'] as String;

    _excludedIds.remove(movie.tmdbId);
    final prefs = await SharedPreferences.getInstance();

    if (type == 'rate') {
      _locallyRatedIds.remove(movie.tmdbId);
      await prefs.setStringList('quick_rated_movie_ids', _locallyRatedIds.toList());
      if (_sessionRatedCount > 0) _sessionRatedCount--;

      // Remove from timeline overrides
      try {
        final raw = prefs.getString('timeline_manual_overrides');
        if (raw != null) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          decoded.remove(movie.tmdbId);
          await prefs.setString('timeline_manual_overrides', jsonEncode(decoded));
        }
      } catch (_) {}

      // Delete rating on TMDB
      TmdbService.deleteRating(movie.tmdbId);
      widget.onDataChanged();
    } else if (type == 'skip') {
      _skippedIds.remove(movie.tmdbId);
      await prefs.setStringList('skipped_movie_ids', _skippedIds.toList());
    }

    // Insert back at the top of the queue
    _movieQueue.insert(0, movie);
    _animController.reset();
    setState(() {
      _currentSelectedRating = 0.0;
    });
  }

  String _getRatingDescription(double r) {
    if (r <= 0.0) return '0.0 / 5 ★ (Slide to rate)';
    if (r <= 0.5) return '0.5 / 5 ★ Terrible';
    if (r <= 1.0) return '1.0 / 5 ★ Poor';
    if (r <= 1.5) return '1.5 / 5 ★ Below Average';
    if (r <= 2.0) return '2.0 / 5 ★ Mediocre';
    if (r <= 2.5) return '2.5 / 5 ★ Average';
    if (r <= 3.0) return '3.0 / 5 ★ Good';
    if (r <= 3.5) return '3.5 / 5 ★ Very Good';
    if (r <= 4.0) return '4.0 / 5 ★ Great';
    if (r <= 4.5) return '4.5 / 5 ★ Excellent';
    return '5.0 / 5 ★ Masterpiece! 🏆';
  }

  void _showFilterSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setFilterState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.5,
              maxChildSize: 0.92,
              expand: false,
              builder: (ctx, scrollController) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.tune_rounded, color: Colors.amberAccent, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Filter Movies',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              setFilterState(() {
                                _selectedLanguage = 'all';
                                _selectedYears.clear();
                                _hideAlreadyRated = true;
                              });
                            },
                            child: const Text('Reset All', style: TextStyle(color: Colors.white54, fontSize: 13)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: [
                            // 1. Hide already rated switch
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Hide Already Rated Movies',
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              subtitle: const Text(
                                'Filter out movies already rated in your timeline or TMDB',
                                style: TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                              value: _hideAlreadyRated,
                              activeColor: Colors.amberAccent,
                              onChanged: (val) {
                                setFilterState(() => _hideAlreadyRated = val);
                              },
                            ),
                            const Divider(color: Colors.white12, height: 24),

                            // 2. Language Section
                            Text(
                              'Language',
                              style: GoogleFonts.outfit(
                                color: Colors.amberAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _availableLanguages.map((lang) {
                                final isSel = _selectedLanguage == lang['code'];
                                return ChoiceChip(
                                  label: Text(lang['name']!),
                                  selected: isSel,
                                  selectedColor: Colors.amberAccent,
                                  backgroundColor: Colors.white.withOpacity(0.08),
                                  labelStyle: TextStyle(
                                    color: isSel ? Colors.black : Colors.white70,
                                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                  onSelected: (_) {
                                    setFilterState(() => _selectedLanguage = lang['code']!);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),

                            // 3. Year Filter (Multi-Select)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Release Years (Multi-Select)',
                                  style: GoogleFonts.outfit(
                                    color: Colors.amberAccent,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                if (_selectedYears.isNotEmpty)
                                  Text(
                                    '${_selectedYears.length} Selected',
                                    style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Decade Quick Presets
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildDecadeChip('2020s (2020–2026)', 2020, 2026, setFilterState),
                                _buildDecadeChip('2010s (2010–2019)', 2010, 2019, setFilterState),
                                _buildDecadeChip('2000s (2000–2009)', 2000, 2009, setFilterState),
                                _buildDecadeChip('1990s (1990–1999)', 1990, 1999, setFilterState),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Individual Year Grid
                            Text(
                              'Individual Years',
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: List.generate(27, (index) {
                                final year = 2026 - index;
                                final isSel = _selectedYears.contains(year);
                                return FilterChip(
                                  label: Text(year.toString()),
                                  selected: isSel,
                                  selectedColor: Colors.amberAccent,
                                  backgroundColor: Colors.white.withOpacity(0.06),
                                  showCheckmark: false,
                                  labelStyle: TextStyle(
                                    color: isSel ? Colors.black : Colors.white70,
                                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                  onSelected: (selected) {
                                    setFilterState(() {
                                      if (selected) {
                                        _selectedYears.add(year);
                                      } else {
                                        _selectedYears.remove(year);
                                      }
                                    });
                                  },
                                );
                              }),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),

                      // Apply Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amberAccent,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () {
                            _saveFilterPrefs();
                            Navigator.of(ctx).pop();
                            _fetchMovies(clearExisting: true);
                          },
                          child: Text(
                            'Apply & Refresh Deck',
                            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDecadeChip(String label, int startYear, int endYear, StateSetter setFilterState) {
    final decadeYears = List.generate(endYear - startYear + 1, (i) => startYear + i);
    final allSelected = decadeYears.every((y) => _selectedYears.contains(y));

    return FilterChip(
      label: Text(label),
      selected: allSelected,
      selectedColor: Colors.amberAccent,
      backgroundColor: Colors.white.withOpacity(0.08),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: allSelected ? Colors.black : Colors.white70,
        fontWeight: allSelected ? FontWeight.bold : FontWeight.w500,
        fontSize: 12,
      ),
      onSelected: (selected) {
        setFilterState(() {
          if (selected) {
            _selectedYears.addAll(decadeYears);
          } else {
            _selectedYears.removeAll(decadeYears);
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentMovie = _movieQueue.isNotEmpty ? _movieQueue.first : null;

    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Dynamic Ambient Background Wallpaper
          if (currentMovie != null && currentMovie.backdropUrl.isNotEmpty)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: CachedNetworkImage(
                key: ValueKey(currentMovie.backdropUrl),
                imageUrl: currentMovie.backdropUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorWidget: (_, __, ___) => Container(color: const Color(0xFF070B14)),
              ),
            ),

          // 2. Heavy Glassmorphic Blur & Dark Gradient Overlay
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF070B14).withOpacity(0.85),
                      const Color(0xFF070B14).withOpacity(0.92),
                      const Color(0xFF070B14).withOpacity(0.98),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. Main Content
          SafeArea(
            child: Column(
              children: [
                // Top Action Bar
                _buildTopBar(currentMovie),

                // Center Movie Card Deck
                Expanded(
                  child: _isLoading
                      ? _buildLoadingState()
                      : currentMovie == null
                          ? _buildEmptyQueueState()
                          : _buildAnimatedMovieCard(currentMovie),
                ),

                // Bottom Rating & Skip Bar
                if (currentMovie != null && !_isLoading)
                  _buildBottomRatingSection(currentMovie),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(_QuickMovieItem? currentMovie) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Close button
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 24),
            onPressed: () => Navigator.of(context).pop(),
          ),

          // Title & Session Counter
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Quick Movie Rater',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '⚡ $_sessionRatedCount Rated',
                        style: const TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  _selectedLanguage == 'all'
                      ? 'All Languages • ${_selectedYears.isEmpty ? 'All Years' : '${_selectedYears.length} Years'}'
                      : '${_selectedLanguage.toUpperCase()} • ${_selectedYears.isEmpty ? 'All Years' : '${_selectedYears.length} Years'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),



          // Undo Button
          if (_undoHistory.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.undo_rounded, color: Colors.white70, size: 20),
              tooltip: 'Undo Last Action',
              onPressed: _undoLast,
            ),

          // Filter Button
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.tune_rounded, color: Colors.amberAccent, size: 22),
                if (_selectedLanguage != 'all' || _selectedYears.isNotEmpty || !_hideAlreadyRated)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: 'Filter Movies',
            onPressed: _showFilterSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedMovieCard(_QuickMovieItem movie) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF131B2E).withOpacity(0.75),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  children: [
                    // Movie Poster & Backdrop Area
                    Expanded(
                      flex: 6,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (movie.posterUrl.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: movie.posterUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: Colors.white10,
                                child: const Center(child: CircularProgressIndicator(color: Colors.amberAccent, strokeWidth: 2)),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.white10,
                                child: const Icon(Icons.movie_rounded, color: Colors.white30, size: 48),
                              ),
                            )
                          else
                            Container(
                              color: Colors.white10,
                              child: const Icon(Icons.movie_rounded, color: Colors.white30, size: 48),
                            ),

                          // Top-right release year tag
                          if (movie.year != null)
                            Positioned(
                              top: 14,
                              right: 14,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.75),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Text(
                                  movie.year.toString(),
                                  style: GoogleFonts.outfit(
                                    color: Colors.amberAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),

                          // Top-left Favorite pill
                          if (movie.isFavorite)
                            Positioned(
                              top: 14,
                              left: 14,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.pinkAccent.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.favorite_rounded, color: Colors.white, size: 12),
                                    SizedBox(width: 4),
                                    Text('FAVORITE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),

                          // Bottom Vignette inside poster
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            height: 60,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    const Color(0xFF131B2E),
                                    const Color(0xFF131B2E).withOpacity(0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Movie Details Area
                    Expanded(
                      flex: 4,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title
                            Text(
                              movie.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Release Date & Genres & TMDB Rating Row
                            Row(
                              children: [
                                if (movie.releaseDate.isNotEmpty) ...[
                                  const Icon(Icons.calendar_today_rounded, color: Colors.white54, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    movie.releaseDate,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                if (movie.voteAverage > 0) ...[
                                  const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 14),
                                  const SizedBox(width: 2),
                                  Text(
                                    movie.voteAverage.toStringAsFixed(1),
                                    style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                if (movie.genreNames.isNotEmpty)
                                  Expanded(
                                    child: Text(
                                      movie.genreNames.join(' • '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // Overview Text
                            Expanded(
                              child: Text(
                                movie.overview.isNotEmpty ? movie.overview : 'No overview available.',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),

                            // Centered Add to Favorite Button
                            Center(
                              child: InkWell(
                                onTap: () => _toggleFavorite(movie),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: movie.isFavorite 
                                        ? Colors.pinkAccent.withOpacity(0.2) 
                                        : Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: movie.isFavorite 
                                          ? Colors.pinkAccent.withOpacity(0.6) 
                                          : Colors.white24,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        movie.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                        color: movie.isFavorite ? Colors.pinkAccent : Colors.white70,
                                        size: 15,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        movie.isFavorite ? 'Favorited' : 'Add to Favorites',
                                        style: GoogleFonts.outfit(
                                          color: movie.isFavorite ? Colors.pinkAccent : Colors.white70,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomRatingSection(_QuickMovieItem movie) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rating dynamic description prompt
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your Rating (out of 5 ★):',
                style: GoogleFonts.outfit(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _getRatingDescription(_currentSelectedRating),
                style: GoogleFonts.outfit(
                  color: _currentSelectedRating > 0 ? Colors.amberAccent : Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // 5-Star Visual Display (with half-star representation & direct touch support)
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              final RenderBox box = context.findRenderObject() as RenderBox;
              final width = box.size.width - 36;
              final localX = details.localPosition.dx.clamp(0.0, width);
              final fraction = localX / width;
              final rawRating = fraction * 5.0;
              final stepped = (rawRating * 2).round() / 2.0; // 0.5 steps
              final clamped = stepped.clamp(0.0, 5.0);
              if (clamped != _currentSelectedRating) {
                HapticFeedback.selectionClick();
                setState(() => _currentSelectedRating = clamped);
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (starIdx) {
                final starPos = starIdx + 1;
                IconData starIcon;
                Color starColor;

                if (_currentSelectedRating >= starPos) {
                  starIcon = Icons.star_rounded;
                  starColor = Colors.amberAccent;
                } else if (_currentSelectedRating >= starPos - 0.5) {
                  starIcon = Icons.star_half_rounded;
                  starColor = Colors.amberAccent;
                } else {
                  starIcon = Icons.star_outline_rounded;
                  starColor = Colors.white24;
                }

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (_currentSelectedRating == starPos.toDouble()) {
                        _currentSelectedRating = starPos - 0.5;
                      } else if (_currentSelectedRating == starPos - 0.5) {
                        _currentSelectedRating = starPos.toDouble();
                      } else {
                        _currentSelectedRating = starPos.toDouble();
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Icon(starIcon, color: starColor, size: 36),
                  ),
                );
              }),
            ),
          ),

          // Continuous 0.5 Step Slider (0.0 to 5.0)
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.amberAccent,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.amberAccent,
              overlayColor: Colors.amberAccent.withOpacity(0.2),
              trackHeight: 3.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: _currentSelectedRating,
              min: 0.0,
              max: 5.0,
              divisions: 10,
              onChanged: (val) {
                HapticFeedback.selectionClick();
                setState(() => _currentSelectedRating = val);
              },
            ),
          ),

          const SizedBox(height: 6),

          // Action Buttons: Submit Rating OR Skip
          Row(
            children: [
              // Not Watched (Skip) Button
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: Colors.white.withOpacity(0.04),
                    ),
                    icon: const Icon(Icons.visibility_off_rounded, color: Colors.white60, size: 16),
                    label: Text(
                      'Not Watched',
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () => _skipMovie(movie),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Rate & Add Button (Active when rating > 0)
              Expanded(
                flex: 6,
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _currentSelectedRating > 0 ? Colors.amberAccent : Colors.white12,
                      foregroundColor: _currentSelectedRating > 0 ? Colors.black : Colors.white38,
                      elevation: _currentSelectedRating > 0 ? 4 : 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: Icon(
                      Icons.star_rounded,
                      size: 18,
                      color: _currentSelectedRating > 0 ? Colors.black : Colors.white38,
                    ),
                    label: Text(
                      _currentSelectedRating > 0
                          ? 'Rate & Add (${_currentSelectedRating.toStringAsFixed(1)} ★)'
                          : 'Select Stars to Rate',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _currentSelectedRating > 0
                        ? () => _rateMovie(movie, _currentSelectedRating)
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.amberAccent),
          SizedBox(height: 16),
          Text(
            'Discovering movies for your timeline...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyQueueState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded, color: Colors.amberAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              'No Unrated Movies Found',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try changing the language or year filters to discover more classic and recent films to rate!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Adjust Filters', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _showFilterSheet,
                ),
                if (_skippedIds.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Review Skipped'),
                    onPressed: _resetSkippedList,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetSkippedList() async {
    HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    _skippedIds.clear();
    await prefs.remove('skipped_movie_ids');

    _excludedIds.clear();
    _excludedIds.addAll(widget.existingRatedTmdbIds);
    _excludedIds.addAll(_locallyRatedIds);

    await _fetchMovies(clearExisting: true);
  }
}
