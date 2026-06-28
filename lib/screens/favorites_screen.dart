import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/data/api_service.dart';
import 'package:private_cinema_mobile/data/mock_catalog.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/widgets/movie_card.dart';
import 'package:private_cinema_mobile/screens/movie_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Movie> _favoriteMovies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);
    
    // 1. Try cloud load
    final cloudList = await ApiService.fetchFavoritesCloud();
    if (cloudList.isNotEmpty) {
      if (mounted) {
        setState(() {
          _favoriteMovies = cloudList;
          _isLoading = false;
        });
      }
      return;
    }

    // 2. Local Fallback
    final prefs = await SharedPreferences.getInstance();
    final localIds = prefs.getStringList('favorites') ?? [];
    final List<Movie> list = [];
    for (final id in localIds) {
      final index = MockCatalog.allMovies.indexWhere((m) => m.id == id);
      if (index != -1) {
        list.add(MockCatalog.allMovies[index]);
      }
    }

    if (mounted) {
      setState(() {
        _favoriteMovies = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final int crossAxisCount = isLandscape ? 5 : 3;
    final double spacing = 12.0;

    // Aspect ratio matching MovieCard
    final double cardWidth = 115.0;
    final double cardHeight = 220.0;
    final double childAspectRatio = cardWidth / cardHeight;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Favorites',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                    onPressed: _loadFavorites,
                  ),
                ],
              ),
            ),

            // Main Content
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: AppColors.accentBright),
                    )
                  : _favoriteMovies.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.03),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.favorite_border_rounded,
                                  color: Colors.white24,
                                  size: 64,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Your favorite list is empty.',
                                style: GoogleFonts.outfit(
                                  color: Colors.white54,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Tap the heart icon on any movie detail\npage to add it here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white30,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 110 + mediaQuery.padding.bottom),
                          itemCount: _favoriteMovies.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                            childAspectRatio: childAspectRatio,
                          ),
                          itemBuilder: (context, index) {
                            final movie = _favoriteMovies[index];
                            return MovieCard(
                              movie: movie,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => MovieDetailScreen(movie: movie),
                                  ),
                                ).then((_) => _loadFavorites());
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
