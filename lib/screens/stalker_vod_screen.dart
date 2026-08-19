import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_mobile/data/api_service.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/screens/movie_detail_screen.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/widgets/movie_image.dart';

class StalkerVodScreen extends StatefulWidget {
  const StalkerVodScreen({super.key});

  @override
  State<StalkerVodScreen> createState() => _StalkerVodScreenState();
}

class _StalkerVodScreenState extends State<StalkerVodScreen> {
  List<Map<String, dynamic>> _categories = [];
  String _selectedCategoryId = 'home';
  List<Movie> _movies = [];
  Map<String, List<Movie>> _homeCategoryMovies = {};
  bool _loadingCategories = true;
  bool _loadingMovies = true;
  bool _loadingHomeData = true;
  int _currentPage = 1;
  int _totalVodCount = 0;
  String _searchQuery = '';

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final cats = await ApiService.fetchStalkerVodCategories();
    if (mounted) {
      final allEntry = cats.where((c) {
        final id = (c['category_id'] ?? '').toString().toLowerCase();
        final name = (c['name'] ?? '').toString().toLowerCase();
        return id == 'all' || name == 'all stalker vod';
      }).firstOrNull;

      final total = allEntry != null
          ? int.tryParse(allEntry['count']?.toString() ?? '0') ?? 0
          : cats.fold<int>(0, (sum, c) => sum + (int.tryParse(c['count']?.toString() ?? '0') ?? 0));

      final filtered = cats.where((c) {
        final id = (c['category_id'] ?? '').toString().toLowerCase();
        final name = (c['name'] ?? '').toString().toLowerCase();
        return id != 'all' && name != 'all stalker vod' && name != 'all' && id.isNotEmpty;
      }).toList();

      final categoriesWithHome = [
        {'category_id': 'home', 'name': 'HOME', 'count': total},
        ...filtered,
      ];

      setState(() {
        _categories = categoriesWithHome;
        _loadingCategories = false;
        _totalVodCount = total;
        _selectedCategoryId = 'home';
      });

      _loadHomeData();
    }
  }

  Future<void> _loadHomeData() async {
    if (!mounted) return;
    setState(() => _loadingHomeData = true);
    
    // Tier 1: Try optimized single endpoint call
    try {
      final homeList = await ApiService.fetchStalkerVodHome();
      if (mounted && homeList.isNotEmpty) {
        final Map<String, List<Movie>> homeMap = {};
        for (final item in homeList) {
          final catId = item['category_id']?.toString() ?? '';
          final movies = item['movies'] as List<Movie>? ?? [];
          if (catId.isNotEmpty && movies.isNotEmpty) {
            homeMap[catId] = movies;
          }
        }
        if (homeMap.isNotEmpty) {
          setState(() {
            _homeCategoryMovies = homeMap;
            _loadingHomeData = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Fast home API failed: $e');
    }

    // Tier 2: Sequential per-category fallback
    final Map<String, List<Movie>> homeMap = {};
    final activeCategories = _categories.where((c) => c['category_id'] != 'home').toList();

    for (final cat in activeCategories) {
      final catId = cat['category_id']?.toString() ?? '';
      if (catId.isEmpty) continue;
      try {
        final list = await ApiService.fetchStalkerVodCatalog(categoryId: catId, page: 1, limit: 10);
        if (list.isNotEmpty) {
          homeMap[catId] = list;
          if (mounted) {
            setState(() {
              _homeCategoryMovies = Map.from(homeMap);
              _loadingHomeData = false;
            });
          }
        }
      } catch (e) {
        debugPrint('Category row fetch failed for $catId: $e');
      }
    }

    if (mounted) {
      setState(() {
        _homeCategoryMovies = homeMap;
        _loadingHomeData = false;
      });
    }
  }

  Future<void> _loadMovies() async {
    if (!mounted) return;
    if (_selectedCategoryId == 'home' && _searchQuery.isEmpty) {
      _loadHomeData();
      return;
    }

    setState(() => _loadingMovies = true);
    final list = await ApiService.fetchStalkerVodCatalog(
      categoryId: _selectedCategoryId,
      search: _searchQuery,
      page: _currentPage,
    );
    if (mounted) {
      setState(() {
        _movies = list;
        _loadingMovies = false;
      });
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    }
  }

  void _onCategorySelected(String categoryId) {
    if (_selectedCategoryId == categoryId && _currentPage == 1 && _searchQuery.isEmpty) return;
    setState(() {
      _selectedCategoryId = categoryId;
      _currentPage = 1;
      _searchQuery = '';
      _searchController.clear();
    });
    _loadMovies();
  }

  void _onSearchSubmitted(String value) {
    setState(() {
      _searchQuery = value.trim();
      _currentPage = 1;
      if (_searchQuery.isNotEmpty) _selectedCategoryId = '';
    });
    _loadMovies();
  }

  void _changePage(int delta) {
    final newPage = _currentPage + delta;
    if (newPage < 1) return;
    setState(() => _currentPage = newPage);
    _loadMovies();
  }

  void _playMovie(Movie movie) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MovieDetailScreen(movie: movie),
      ),
    );
  }

  bool get _hasNextPage => _movies.length >= 100;
  bool get _hasPrevPage => _currentPage > 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accentBright.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.movie_filter_rounded, color: AppColors.accentBright, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              'STALKER VOD',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),

            if (_totalVodCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.accentBright.withValues(alpha: 0.3),
                      const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.accentBright.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  _formatCount(_totalVodCount),
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: TextField(
                controller: _searchController,
                onSubmitted: _onSearchSubmitted,
                textInputAction: TextInputAction.search,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search Stalker VOD...',
                  hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.accentBright, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchSubmitted('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          // Categories horizontal list
          _buildCategoryChips(),

          const SizedBox(height: 8),

          // Content View
          Expanded(
            child: _searchQuery.isNotEmpty
                ? _buildCategoryGrid()
                : (_selectedCategoryId == 'home'
                    ? _buildHomeRowsView()
                    : _buildCategoryGrid()),
          ),

          if (_selectedCategoryId != 'home' || _searchQuery.isNotEmpty) ...[
            _buildPaginationBar(),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildHomeRowsView() {
    if (_loadingHomeData && _homeCategoryMovies.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.accentBright),
            const SizedBox(height: 12),
            Text(
              'Loading Stalker VOD Categories...',
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final activeCats = _categories.where((c) {
      final catId = c['category_id']?.toString() ?? '';
      return catId != 'home' && (_homeCategoryMovies[catId]?.isNotEmpty ?? false);
    }).toList();

    if (activeCats.isEmpty) {
      return Center(
        child: Text(
          'No VOD categories available',
          style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: activeCats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 20),
      itemBuilder: (context, index) {
        final cat = activeCats[index];
        final catId = cat['category_id']?.toString() ?? '';
        final rawName = cat['name']?.toString() ?? 'Category';
        final catName = rawName.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '').trim();
        final movies = _homeCategoryMovies[catId] ?? [];

        return _buildHomeCategorySection(catName, catId, movies);
      },
    );
  }

  Widget _buildHomeCategorySection(String catName, String catId, List<Movie> movies) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Row Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.accentBright,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    catName.toUpperCase(),
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _onCategorySelected(catId),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'VIEW ALL',
                        style: GoogleFonts.outfit(
                          color: AppColors.accentBright,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppColors.accentBright),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Horizontal Movies Row (height 180, poster fills tile 100%)
        SizedBox(
          height: 180,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: movies.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index < movies.length) {
                return _buildHorizontalMovieCard(movies[index]);
              } else {
                return _buildViewAllCard(catName, catId);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalMovieCard(Movie movie) {
    return GestureDetector(
      onTap: () => _playMovie(movie),
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox.expand(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MovieImage(
                        source: movie.posterUrl.isNotEmpty ? movie.posterUrl : (movie.backdropUrl ?? ''),
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.amber, size: 10),
                              const SizedBox(width: 2),
                              Text(
                                movie.rating.toStringAsFixed(1),
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
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
            const SizedBox(height: 5),
            Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (movie.year != null && movie.year! > 0)
              Text(
                '${movie.year}',
                style: GoogleFonts.outfit(
                  color: Colors.white54,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewAllCard(String catName, String catId) {
    return GestureDetector(
      onTap: () => _onCategorySelected(catId),
      child: Container(
        width: 110,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.accentBright.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accentBright.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_forward_rounded, color: AppColors.accentBright, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              'VIEW ALL',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                catName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white54,
                  fontSize: 9,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    if (_loadingMovies) {
      return Center(child: CircularProgressIndicator(color: AppColors.accentBright));
    }
    if (_movies.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No movies matching "$_searchQuery"'
                  : 'No movies found in this category',
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: _movies.length,
      itemBuilder: (context, index) {
        final movie = _movies[index];
        return _buildMovieCard(movie);
      },
    );
  }

  Widget _buildCategoryChips() {
    if (_loadingCategories) {
      return SizedBox(
        height: 36,
        child: Center(child: CircularProgressIndicator(color: AppColors.accentBright, strokeWidth: 2)),
      );
    }
    if (_categories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 36,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final catId = cat['category_id']?.toString() ?? '';
          final rawName = cat['name']?.toString() ?? 'Category';
          final catName = rawName.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '').trim();
          final count = cat['count'] != null ? int.tryParse(cat['count'].toString()) : null;
          final isSelected = _selectedCategoryId == catId;

          return GestureDetector(
            onTap: () => _onCategorySelected(catId),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accentBright : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppColors.accentBright : Colors.white24,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (catId == 'home')
                    const Padding(
                      padding: EdgeInsets.only(right: 5),
                      child: Icon(Icons.home_rounded, color: Colors.white, size: 14),
                    ),
                  Text(
                    catName.toUpperCase(),
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (count != null && count > 0 && catId != 'home') ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white.withValues(alpha: 0.25) : Colors.white12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$count',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMovieCard(Movie movie) {
    return GestureDetector(
      onTap: () => _playMovie(movie),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox.expand(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MovieImage(
                      source: movie.posterUrl.isNotEmpty ? movie.posterUrl : (movie.backdropUrl ?? ''),
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 11),
                            const SizedBox(width: 2),
                            Text(
                              movie.rating.toStringAsFixed(1),
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
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
          const SizedBox(height: 6),
          Text(
            movie.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (movie.year != null && movie.year! > 0)
            Text(
              '${movie.year}',
              style: GoogleFonts.outfit(
                color: Colors.white54,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPaginationBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: _hasPrevPage ? () => _changePage(-1) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _hasPrevPage ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
            foregroundColor: _hasPrevPage ? Colors.white : Colors.white24,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: _hasPrevPage ? Colors.white : Colors.white24),
              const SizedBox(width: 4),
              Text('PREV', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(width: 12),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.accentBright.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.accentBright.withValues(alpha: 0.4)),
          ),
          child: Text(
            'PAGE $_currentPage',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),

        ElevatedButton(
          onPressed: _hasNextPage ? () => _changePage(1) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _hasNextPage ? AppColors.accentBright : Colors.white.withValues(alpha: 0.04),
            foregroundColor: _hasNextPage ? Colors.white : Colors.white24,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('NEXT', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios_rounded, size: 12, color: _hasNextPage ? Colors.white : Colors.white24),
            ],
          ),
        ),
      ],
    );
  }

  String _formatCount(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}
