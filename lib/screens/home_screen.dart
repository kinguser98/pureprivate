import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/data/mock_catalog.dart';
import 'package:private_cinema_mobile/data/api_service.dart';
import 'package:private_cinema_mobile/data/playback_tracker.dart';
import 'package:private_cinema_mobile/data/download_manager.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/models/language_item.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/widgets/movie_image.dart';
import 'package:private_cinema_mobile/widgets/movie_section_row.dart';
import 'package:private_cinema_mobile/widgets/language_section_row.dart';
import 'package:private_cinema_mobile/screens/movie_detail_screen.dart';
import 'package:private_cinema_mobile/screens/category_grid_screen.dart';
import 'package:private_cinema_mobile/screens/all_movies_screen.dart';
import 'package:private_cinema_mobile/screens/downloads_screen.dart';
import 'package:private_cinema_mobile/widgets/special_search_dialog.dart';

class HomeScreen extends StatefulWidget {
  final Function(int)? onSwitchTab;
  const HomeScreen({super.key, this.onSwitchTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Movie> _featuredMovies = [];
  List<Movie> _continueWatchingMovies = [];
  List<LanguageItem> _languages = [];
  List<String> _movieGenres = [];
  List<String> _movieCollections = [];
  
  bool _isLoading = true;
  bool _isOfflineMode = false;
  
  int _carouselIndex = 0;
  Timer? _carouselTimer;
  final PageController _carouselController = PageController(initialPage: 1000, viewportFraction: 0.62);

  final List<String> _categoryTabs = const ['Movies', 'Live TV', 'Series', 'Library'];
  String _selectedCategoryTab = 'Movies';

  @override
  void initState() {
    super.initState();
    _fetchApiData();
    _startCarouselTimer();
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _carouselController.dispose();
    super.dispose();
  }

  void _startCarouselTimer() {
    _carouselTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      final carouselMovies = _getCarouselMovies();
      if (carouselMovies.isNotEmpty && _carouselController.hasClients) {
        final next = _carouselController.page!.round() + 1;
        _carouselController.animateToPage(
          next,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  void _setupInitialCarouselPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final carouselMovies = _getCarouselMovies();
      if (carouselMovies.isNotEmpty && _carouselController.hasClients) {
        final len = carouselMovies.length;
        final targetPage = (1000 ~/ len) * len;
        _carouselController.jumpToPage(targetPage);
        setState(() {
          _carouselIndex = 0;
        });
      }
    });
  }

  Future<void> _initializeMockPlaybackProgress(List<Movie> movies) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList('continue_watching_list');
      final needsOverride = existing == null || existing.isEmpty;

      if (needsOverride && movies.length >= 2) {
        final id1 = movies[0].id;
        final id2 = movies[1].id;
        await prefs.setStringList('continue_watching_list', [id1, id2]);
        await prefs.setInt('resume_position_$id1', 1200000); // 20 mins
        await prefs.setInt('resume_duration_$id1', 3600000); // 60 mins
        await prefs.setInt('resume_timestamp_$id1', DateTime.now().millisecondsSinceEpoch);

        await prefs.setInt('resume_position_$id2', 1800000); // 30 mins
        await prefs.setInt('resume_duration_$id2', 4800000); // 80 mins
        await prefs.setInt('resume_timestamp_$id2', DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint('Error writing mock playback progress: $e');
    }
  }

  Future<void> _fetchApiData() async {
    try {
      final rawData = await ApiService.fetchRawData();
      final rawMovies = rawData['movies'] as List<dynamic>? ?? [];
      final rawLanguages = rawData['languages'] as List<dynamic>? ?? [];

      final parsedMovies = ApiService.parseMovies(rawMovies, rawLanguages);
      final parsedLanguages = ApiService.parseLanguages(rawLanguages);

      final recent = parsedMovies.where((m) => m.year != null && m.year! >= 2024).toList();
      final recentList = recent.isNotEmpty ? recent : parsedMovies.take(10).toList();

      final rawTrending = List<dynamic>.from(rawMovies)
        ..sort((a, b) {
          final va = int.tryParse(a['views']?.toString() ?? '0') ?? 0;
          final vb = int.tryParse(b['views']?.toString() ?? '0') ?? 0;
          return vb.compareTo(va);
        });
      final parsedTrending = ApiService.parseMovies(rawTrending);

      final parsedTopRated = List<Movie>.from(parsedMovies)
        ..sort((a, b) => b.rating.compareTo(a.rating));

      final genres = parsedMovies
          .map((m) => m.genre)
          .where((g) => g.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      final collections = parsedMovies
          .map((m) => m.collection)
          .where((c) => c != null && c.trim().isNotEmpty)
          .map((c) => c!.trim())
          .toSet()
          .toList()
        ..sort();

      MockCatalog.populateCatalog(
        all: parsedMovies,
        recent: recentList,
        trend: parsedTrending,
        rated: parsedTopRated,
      );

      await _initializeMockPlaybackProgress(parsedMovies);
      await _loadContinueWatching();

      final featured = parsedMovies.where((m) => m.rating >= 8.5).toList();

      if (mounted) {
        setState(() {
          _featuredMovies = featured.isNotEmpty ? featured : parsedMovies.take(5).toList();
          _languages = parsedLanguages;
          _movieGenres = genres;
          _movieCollections = collections;
          _isOfflineMode = false;
          _isLoading = false;
        });
        _setupInitialCarouselPage();
      }
    } catch (e) {
      debugPrint('Error loading API data: $e');
      final downs = await DownloadManager.getDownloadedMovies();
      if (mounted) {
        setState(() {
          _isOfflineMode = true;
          _isLoading = false;
          _languages = [];
        });
      }
      if (downs.isNotEmpty) {
        MockCatalog.populateCatalog(
          all: downs,
          recent: downs,
          trend: downs,
          rated: downs,
        );
        await _initializeMockPlaybackProgress(downs);
        await _loadContinueWatching();
        if (mounted) {
          setState(() {
            final genres = downs
                .map((m) => m.genre)
                .where((g) => g.trim().isNotEmpty)
                .toSet()
                .toList()
              ..sort();
            _movieGenres = genres;
            _movieCollections = [];
            _featuredMovies = downs.take(5).toList();
          });
          _setupInitialCarouselPage();
        }
      } else {
        // Fallback to offline catalog (mock data)
        MockCatalog.populateCatalog(
          all: MockCatalog.allMovies,
          recent: MockCatalog.recentlyReleased,
          trend: MockCatalog.trending,
          rated: MockCatalog.topRated,
        );
        await _loadContinueWatching();
        if (mounted) {
          setState(() {
            _featuredMovies = MockCatalog.allMovies.take(5).toList();
            _movieGenres = MockCatalog.allMovies.map((m) => m.genre).toSet().toList();
          });
          _setupInitialCarouselPage();
        }
      }
    }
  }

  Future<void> _loadContinueWatching() async {
    final list = await PlaybackTracker.getContinueWatchingMovies();
    if (mounted) {
      setState(() {
        _continueWatchingMovies = list;
      });
    }
  }

  void _openMovieDetail(Movie movie) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MovieDetailScreen(movie: movie),
      ),
    ).then((_) => _loadContinueWatching());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.accentBright),
              const SizedBox(height: 24),
              Text(
                'SYNCING GOXIO',
                style: GoogleFonts.outfit(
                  color: Colors.white30,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _fetchApiData,
        color: AppColors.accentBright,
        backgroundColor: AppColors.surface,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top GoXio App Header
              _buildTopHeader(),

              // Top Category Tabs
              _buildCategoryTabs(),

              const SizedBox(height: 12),

              // Carousel Featured Banner
              _buildCarousel(),

              // Carousel Metadata Info
              _buildCarouselMetadata(),

              const SizedBox(height: 24),

              // 1. "New" Section (Pure posters matching mockup)
              MovieSectionRow(
                title: 'New',
                movies: MockCatalog.recentlyReleased,
                hideTitle: true,
                onMoviePressed: _openMovieDetail,
                onSeeAllPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CategoryGridScreen(
                        title: 'New',
                        movies: MockCatalog.recentlyReleased,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // 2. "Language" Section
              LanguageSectionRow(
                languages: _languages,
                onLanguageSelected: (lang) {
                  final langMovies = MockCatalog.allMovies.where((m) => m.language == lang).toList();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CategoryGridScreen(
                        title: '$lang Movies',
                        movies: langMovies,
                      ),
                    ),
                  ).then((_) => _loadContinueWatching());
                },
              ),

              const SizedBox(height: 20),

              // 3. "Top Rated" Section
              MovieSectionRow(
                title: 'Top Rated',
                movies: MockCatalog.topRated,
                onMoviePressed: _openMovieDetail,
                onSeeAllPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CategoryGridScreen(
                        title: 'Top Rated',
                        movies: MockCatalog.topRated,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // 4. "Continue Watching" Section (if present)
              if (_continueWatchingMovies.isNotEmpty) ...[
                MovieSectionRow(
                  title: 'Continue Watching',
                  movies: _continueWatchingMovies,
                  isLandscape: true,
                  onMoviePressed: _openMovieDetail,
                  onSeeAllPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CategoryGridScreen(
                          title: 'Continue Watching',
                          movies: _continueWatchingMovies,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
              ],

              // 5. Curated Collections
              for (final colName in _movieCollections) ...[
                MovieSectionRow(
                  title: colName,
                  movies: MockCatalog.allMovies.where((m) => m.collection?.trim().toLowerCase() == colName.toLowerCase()).toList(),
                  onMoviePressed: _openMovieDetail,
                  onSeeAllPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CategoryGridScreen(
                          title: colName,
                          movies: MockCatalog.allMovies.where((m) => m.collection?.trim().toLowerCase() == colName.toLowerCase()).toList(),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
              ],

              // 6. Genres
              for (final genre in _movieGenres) ...[
                MovieSectionRow(
                  title: '$genre Movies',
                  movies: MockCatalog.allMovies.where((m) => m.genre == genre).toList(),
                  onMoviePressed: _openMovieDetail,
                  onSeeAllPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CategoryGridScreen(
                          title: '$genre Movies',
                          movies: MockCatalog.allMovies.where((m) => m.genre == genre).toList(),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
              ],

              // 7. General Movies Section
              MovieSectionRow(
                title: 'Movies',
                movies: MockCatalog.allMovies,
                onMoviePressed: _openMovieDetail,
                onSeeAllPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CategoryGridScreen(
                        title: 'Movies',
                        movies: MockCatalog.allMovies,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Movie> _getCarouselMovies() {
    return MockCatalog.recentlyReleased.isNotEmpty ? MockCatalog.recentlyReleased : _featuredMovies;
  }

  void _onCategoryTabSelected(String tab) {
    if (tab == 'Movies') {
      widget.onSwitchTab?.call(1);
    } else if (tab == 'Live TV') {
      widget.onSwitchTab?.call(2);
    } else if (tab == 'Series') {
      showDialog<void>(
        context: context,
        builder: (context) => const SpecialSearchDialog(isSeriesSearch: true),
      );
    } else if (tab == 'Library') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DownloadsScreen()),
      );
    }
  }

  Widget _buildTopHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // App Title / Logo
          Text(
            'GoXio',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          // Action Buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Special Live Search Button (Catchy gradient design)
              GestureDetector(
                onTap: () {
                  showDialog<void>(
                    context: context,
                    barrierDismissible: true,
                    builder: (context) => const SpecialSearchDialog(),
                  );
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF9E00FF), // Neon Purple
                        Color(0xFF00E5FF), // Neon Cyan
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF9E00FF).withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Search Icon Box
              _buildHeaderIcon(Icons.search_rounded, () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AllMoviesScreen(),
                  ),
                );
              }),
              const SizedBox(width: 12),
              // Downloads Icon Box
              _buildHeaderIcon(Icons.download_for_offline_rounded, () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DownloadsScreen(),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIcon(IconData icon, VoidCallback onTap, {bool showRedDot = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 22,
            ),
            if (showRedDot)
              Positioned(
                top: 10,
                right: 10,
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
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categoryTabs.length,
              itemBuilder: (context, index) {
                final tab = _categoryTabs[index];
                return GestureDetector(
                  onTap: () => _onCategoryTabSelected(tab),
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        tab,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isOfflineMode)
            const Padding(
              padding: EdgeInsets.only(left: 8, right: 16),
              child: Icon(
                Icons.signal_wifi_off_rounded,
                color: Colors.amberAccent,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCarouselMetadata() {
    final carouselMovies = _getCarouselMovies();
    if (carouselMovies.isEmpty || _carouselIndex >= carouselMovies.length) {
      return const SizedBox.shrink();
    }
    final movie = carouselMovies[_carouselIndex];

    return Column(
      children: [
        const SizedBox(height: 12),
        // Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            movie.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Badges Row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPillBadge(movie.genre),
            const SizedBox(width: 8),
            _buildPillBadge((movie.runtime != null && movie.runtime!.trim().isNotEmpty) ? movie.runtime! : '1h 45m'),
            const SizedBox(width: 8),
            _buildRatingBadge(movie.rating),
          ],
        ),
        const SizedBox(height: 16),
        // Page Indicator Dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            carouselMovies.length > 5 ? 5 : carouselMovies.length,
            (index) {
              final actualIndex = carouselMovies.length > 5
                  ? index + (_carouselIndex - 2).clamp(0, carouselMovies.length - 5)
                  : index;
              final isSelected = _carouselIndex == actualIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: isSelected ? 16 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3.0),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPillBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildRatingBadge(double rating) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.star_rounded,
            color: Colors.amber,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: GoogleFonts.outfit(
              color: Colors.amber,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarousel() {
    final carouselMovies = _getCarouselMovies();
    if (carouselMovies.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 310,
      child: PageView.builder(
        controller: _carouselController,
        onPageChanged: (idx) {
          setState(() {
            _carouselIndex = idx % carouselMovies.length;
          });
        },
        itemCount: 10000,
        itemBuilder: (context, index) {
          final movie = carouselMovies[index % carouselMovies.length];
          return AnimatedBuilder(
            animation: _carouselController,
            builder: (context, child) {
              double value = 0.0;
              if (_carouselController.position.haveDimensions) {
                value = index - _carouselController.page!;
              } else {
                final currentPage = _carouselController.hasClients ? _carouselController.page?.round() ?? 1000 : 1000;
                value = (index - currentPage).toDouble();
              }
              
              // Apply scaling, translation, and opacity for coverflow stack effect
              final double percent = value.clamp(-1.0, 1.0);
              final double scale = 1.0 - (percent.abs() * 0.16);
              final double opacity = 1.0 - (percent.abs() * 0.55);
              final double translationX = -percent * 28.0; // overlap translation

              return Opacity(
                opacity: opacity.clamp(0.4, 1.0),
                child: Transform.translate(
                  offset: Offset(translationX, 0),
                  child: Transform.scale(
                    scale: scale,
                    child: child,
                  ),
                ),
              );
            },
            child: GestureDetector(
              onTap: () => _openMovieDetail(movie),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: MovieImage(
                        source: movie.posterUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                    if (movie.rating > 0)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  width: 0.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Colors.amber,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    movie.rating.toStringAsFixed(1),
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
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
            ),
          );
        },
      ),
    );
  }
}
