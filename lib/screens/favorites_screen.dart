import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/data/api_service.dart';
import 'package:private_cinema_mobile/data/mock_catalog.dart';
import 'package:private_cinema_mobile/data/simkl_service.dart';
import 'package:private_cinema_mobile/data/tmdb_service.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/widgets/movie_card.dart';
import 'package:private_cinema_mobile/screens/movie_detail_screen.dart';
import 'package:private_cinema_mobile/screens/simkl_login_screen.dart';

enum FavoriteFilter { all, favorites, watchlist }

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  FavoriteFilter _selectedFilter = FavoriteFilter.all;
  
  List<Movie> _allList = [];
  List<Movie> _favoritesList = [];
  List<Movie> _watchlistList = [];
  
  bool _isLoading = true;
  bool _isSimklConnected = false;
  bool _isTmdbConnected = false;

  @override
  void initState() {
    super.initState();
    _loadAllFavoritesAndWatchlist();
  }

  List<Movie> get _masterCatalog {
    if (ApiService.cachedMovies.isNotEmpty) return ApiService.cachedMovies;
    if (MockCatalog.allMovies.isNotEmpty) return MockCatalog.allMovies;
    return [];
  }

  Movie? _resolveMovie(String idOrTmdbId, {String? title}) {
    final catalog = _masterCatalog;
    
    // 1. Direct ID match
    for (final m in catalog) {
      if (m.id == idOrTmdbId) return m;
    }
    // 2. TMDb ID match
    for (final m in catalog) {
      if (m.tmdbId != null && m.tmdbId == idOrTmdbId) return m;
    }
    // 3. Title match if provided
    if (title != null && title.trim().isNotEmpty) {
      final tNorm = title.trim().toLowerCase();
      for (final m in catalog) {
        if (m.title.trim().toLowerCase() == tNorm) return m;
      }
    }
    return null;
  }

  Future<void> _loadAllFavoritesAndWatchlist() async {
    setState(() => _isLoading = true);

    _isSimklConnected = SimklService.isAuthenticated.value;
    _isTmdbConnected = TmdbService.isAuthenticated;

    final Map<String, Movie> favMap = {};
    final Map<String, Movie> watchMap = {};

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Local Favorites
      final localFavIds = prefs.getStringList('favorites') ?? [];
      for (final id in localFavIds) {
        final movie = _resolveMovie(id);
        if (movie != null) {
          favMap[movie.id] = movie;
        }
      }

      // 2. Local Watchlist
      final localWatchIds = prefs.getStringList('watchlist_ids') ?? [];
      for (final id in localWatchIds) {
        final movie = _resolveMovie(id);
        if (movie != null) {
          watchMap[movie.id] = movie;
        }
      }

      // 3. Cloud API Favorites
      try {
        final cloudFavs = await ApiService.fetchFavoritesCloud();
        for (final m in cloudFavs) {
          final resolved = _resolveMovie(m.id) ?? m;
          favMap[resolved.id] = resolved;
        }
      } catch (e) {
        debugPrint('Error loading cloud favorites: $e');
      }

      // 4. TMDb Favorites & Watchlist (if authenticated)
      if (_isTmdbConnected) {
        try {
          final tmdbFavs = await TmdbService.fetchFavorites();
          for (final item in tmdbFavs) {
            final tmdbId = item['id']?.toString() ?? '';
            final title = item['title']?.toString() ?? item['name']?.toString() ?? '';
            final resolved = _resolveMovie(tmdbId, title: title);
            if (resolved != null) {
              favMap[resolved.id] = resolved;
            } else if (title.isNotEmpty) {
              final posterPath = item['poster_path']?.toString() ?? '';
              final posterUrl = posterPath.isNotEmpty ? 'https://image.tmdb.org/t/p/w500$posterPath' : '';
              final m = Movie(
                id: 'tmdb_$tmdbId',
                title: title,
                genre: 'Cinema',
                rating: (item['vote_average'] as num?)?.toDouble() ?? 8.0,
                posterUrl: posterUrl,
                backdropUrl: posterUrl,
                posterColor: const Color(0xFF1E1B4B),
                year: int.tryParse((item['release_date']?.toString() ?? '').split('-').first) ?? 2024,
                tmdbId: tmdbId,
              );
              favMap[m.id] = m;
            }
          }
        } catch (e) {
          debugPrint('Error loading TMDb favorites: $e');
        }

        try {
          final tmdbWatch = await TmdbService.fetchWatchlist();
          for (final item in tmdbWatch) {
            final tmdbId = item['id']?.toString() ?? '';
            final title = item['title']?.toString() ?? item['name']?.toString() ?? '';
            final resolved = _resolveMovie(tmdbId, title: title);
            if (resolved != null) {
              watchMap[resolved.id] = resolved;
            } else if (title.isNotEmpty) {
              final posterPath = item['poster_path']?.toString() ?? '';
              final posterUrl = posterPath.isNotEmpty ? 'https://image.tmdb.org/t/p/w500$posterPath' : '';
              final m = Movie(
                id: 'tmdb_$tmdbId',
                title: title,
                genre: 'Cinema',
                rating: (item['vote_average'] as num?)?.toDouble() ?? 8.0,
                posterUrl: posterUrl,
                backdropUrl: posterUrl,
                posterColor: const Color(0xFF1E1B4B),
                year: int.tryParse((item['release_date']?.toString() ?? '').split('-').first) ?? 2024,
                tmdbId: tmdbId,
              );
              watchMap[m.id] = m;
            }
          }
        } catch (e) {
          debugPrint('Error loading TMDb watchlist: $e');
        }
      }

      // 5. SIMKL Watchlist (if authenticated)
      if (_isSimklConnected) {
        try {
          final simklList = await SimklService.fetchWatchlist();
          for (final m in simklList) {
            final resolved = _resolveMovie(m.id, title: m.title) ?? m;
            watchMap[resolved.id] = resolved;
          }
        } catch (e) {
          debugPrint('Error loading SIMKL watchlist: $e');
        }
      }

    } catch (e) {
      debugPrint('FavoritesScreen _loadAllFavoritesAndWatchlist error: $e');
    }

    final Map<String, Movie> allCombined = {};
    for (final entry in favMap.entries) {
      allCombined[entry.key] = entry.value;
    }
    for (final entry in watchMap.entries) {
      allCombined[entry.key] = entry.value;
    }

    if (mounted) {
      setState(() {
        _favoritesList = favMap.values.toList();
        _watchlistList = watchMap.values.toList();
        _allList = allCombined.values.toList();
        _isLoading = false;
      });
    }
  }

  List<Movie> get _currentDisplayList {
    switch (_selectedFilter) {
      case FavoriteFilter.all:
        return _allList;
      case FavoriteFilter.favorites:
        return _favoritesList;
      case FavoriteFilter.watchlist:
        return _watchlistList;
    }
  }

  void _showSimklConnectDialog(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SimklLoginScreen()),
    );
    if (result == true && mounted) {
      _loadAllFavoritesAndWatchlist();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to SIMKL (@${SimklService.currentUsername.value})!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  Widget _buildFilterChip(String label, FavoriteFilter filter, int count) {
    final isSelected = _selectedFilter == filter;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _selectedFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0x359333EA) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFC084FC) : Colors.white.withOpacity(0.12),
            width: isSelected ? 1.5 : 0.8,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF9333EA).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF9333EA) : Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final int crossAxisCount = isLandscape ? 5 : 3;
    final double spacing = 12.0;

    final double cardWidth = 115.0;
    final double cardHeight = 172.5;
    final double childAspectRatio = cardWidth / cardHeight;

    final displayList = _currentDisplayList;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Favorites & Watchlist',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_isSimklConnected) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amberAccent.withOpacity(0.4), width: 0.8),
                          ),
                          child: Text(
                            '🍿 SIMKL',
                            style: GoogleFonts.outfit(
                              color: Colors.amberAccent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      if (_isTmdbConnected) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF01B4E4).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF01B4E4).withOpacity(0.4), width: 0.8),
                          ),
                          child: Text(
                            '🎬 TMDb',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFF01B4E4),
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 22),
                    onPressed: _loadAllFavoritesAndWatchlist,
                  ),
                ],
              ),
            ),

            // Filter Tabs Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('All', FavoriteFilter.all, _allList.length),
                    const SizedBox(width: 8),
                    _buildFilterChip('Favorites', FavoriteFilter.favorites, _favoritesList.length),
                    const SizedBox(width: 8),
                    _buildFilterChip('Watchlist', FavoriteFilter.watchlist, _watchlistList.length),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 6),

            // Main Content
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: AppColors.accentBright),
                    )
                  : displayList.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(22),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF9333EA).withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.favorite_border_rounded,
                                    size: 48,
                                    color: Color(0xFFC084FC),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  _selectedFilter == FavoriteFilter.favorites
                                      ? 'No favorites yet'
                                      : _selectedFilter == FavoriteFilter.watchlist
                                          ? 'Your watchlist is empty'
                                          : 'No saved movies yet',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap the heart or bookmark icon on any movie detail page to save it for quick access.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.55),
                                    fontSize: 13,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                if (!_isSimklConnected)
                                  OutlinedButton.icon(
                                    onPressed: () => _showSimklConnectDialog(context),
                                    icon: const Text('🍿', style: TextStyle(fontSize: 16)),
                                    label: Text(
                                      'Connect SIMKL Account',
                                      style: GoogleFonts.outfit(
                                        color: Colors.amberAccent,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: Colors.amberAccent.withOpacity(0.6)),
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            childAspectRatio: childAspectRatio,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                          ),
                          itemCount: displayList.length,
                          itemBuilder: (context, index) {
                            final movie = displayList[index];
                            return MovieCard(
                              movie: movie,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MovieDetailScreen(movie: movie),
                                  ),
                                );
                                _loadAllFavoritesAndWatchlist();
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
