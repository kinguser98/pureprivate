import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/data/mock_catalog.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/widgets/movie_card.dart';
import 'package:private_cinema_mobile/screens/movie_detail_screen.dart';

class AllMoviesScreen extends StatefulWidget {
  const AllMoviesScreen({super.key});

  @override
  State<AllMoviesScreen> createState() => _AllMoviesScreenState();
}

class _AllMoviesScreenState extends State<AllMoviesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedGenre = 'All';
  String _selectedLanguage = 'All';
  
  List<Movie> _filteredMovies = [];
  List<String> _genres = ['All'];
  List<String> _languages = ['All'];

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _applyFilters();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadFilters() {
    final all = MockCatalog.allMovies;
    final genres = all.map((m) => m.genre).toSet().toList()..sort();
    final languages = all.map((m) => m.language).whereType<String>().toSet().toList()..sort();

    setState(() {
      _genres = ['All', ...genres];
      _languages = ['All', ...languages];
    });
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();
    var list = List<Movie>.from(MockCatalog.allMovies);

    if (query.isNotEmpty) {
      list = list.where((m) {
        final matchesTitle = m.title.toLowerCase().contains(query);
        final matchesDesc = m.description?.toLowerCase().contains(query) ?? false;
        final matchesDirector = m.director?.toLowerCase().contains(query) ?? false;
        final matchesCast = m.cast.any((c) => c.toLowerCase().contains(query));
        return matchesTitle || matchesDesc || matchesDirector || matchesCast;
      }).toList();
    }

    if (_selectedGenre != 'All') {
      list = list.where((m) => m.genre == _selectedGenre).toList();
    }

    if (_selectedLanguage != 'All') {
      list = list.where((m) => m.language == _selectedLanguage).toList();
    }

    setState(() {
      _filteredMovies = list;
    });
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
            // Search Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Explore Catalog',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Modern Search Field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: AppColors.accentBright,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white38),
                            onPressed: () {
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                            },
                          )
                        : null,
                    hintText: 'Search title, cast, genre or director...',
                    hintStyle: const TextStyle(color: Colors.white30),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),

            // Horizontal Filters Row (Genres)
            const SizedBox(height: 4),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _genres.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final genre = _genres[index];
                  final isSelected = _selectedGenre == genre;
                  return ChoiceChip(
                    label: Text(genre),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedGenre = genre;
                        _applyFilters();
                      });
                    },
                    selectedColor: AppColors.accent.withValues(alpha: 0.25),
                    backgroundColor: AppColors.surface,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white60,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? AppColors.accentBright : Colors.white12,
                      ),
                    ),
                  );
                },
              ),
            ),

            // Horizontal Filters Row (Languages)
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _languages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final lang = _languages[index];
                  final isSelected = _selectedLanguage == lang;
                  return ChoiceChip(
                    label: Text(lang),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedLanguage = lang;
                        _applyFilters();
                      });
                    },
                    selectedColor: AppColors.accent.withValues(alpha: 0.25),
                    backgroundColor: AppColors.surface,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white60,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? AppColors.accentBright : Colors.white12,
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Grid Content
            Expanded(
              child: _filteredMovies.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search_off_rounded, color: Colors.white24, size: 64),
                          const SizedBox(height: 16),
                          Text(
                            'No matches found.',
                            style: GoogleFonts.outfit(
                              color: Colors.white38,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 110 + mediaQuery.padding.bottom),
                      itemCount: _filteredMovies.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        childAspectRatio: childAspectRatio,
                      ),
                      itemBuilder: (context, index) {
                        final movie = _filteredMovies[index];
                        return MovieCard(
                          movie: movie,
                          showAllMoviesDesign: true,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => MovieDetailScreen(movie: movie),
                              ),
                            ).then((_) => _applyFilters());
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
