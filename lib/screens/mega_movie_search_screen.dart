import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/widgets/special_search_dialog.dart';

class MegaMovieSearchScreen extends StatefulWidget {
  final bool initialSeriesSearch;
  const MegaMovieSearchScreen({super.key, this.initialSeriesSearch = false});

  @override
  State<MegaMovieSearchScreen> createState() => _MegaMovieSearchScreenState();
}

class _MegaMovieSearchScreenState extends State<MegaMovieSearchScreen> {
  static const String _tmdbApiKey = '3a73619bbb8fc6d47742d1b5b2b707b5';

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  late bool _isSeriesSearch;
  bool _searching = false;
  List<dynamic> _tmdbResults = [];
  Timer? _debounceTimer;

  // TMDB-discovered rows cache
  bool _loadingDiscovery = true;
  List<dynamic> _topIndianList = [];
  List<dynamic> _topMalayalamList = [];
  List<dynamic> _topTamilList = [];

  // In-memory cache for switching between Movies and Series without re-fetching
  final Map<String, List<dynamic>> _discoveryCache = {};

  bool get _hasQuery => _searchCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _isSeriesSearch = widget.initialSeriesSearch;
    _searchCtrl.addListener(_onSearchChanged);
    _loadDiscoveryRows();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadDiscoveryRows() async {
    final cacheKey = _isSeriesSearch ? 'series' : 'movies';
    if (_discoveryCache.containsKey('${cacheKey}_indian') &&
        _discoveryCache.containsKey('${cacheKey}_malayalam') &&
        _discoveryCache.containsKey('${cacheKey}_tamil')) {
      setState(() {
        _topIndianList = _discoveryCache['${cacheKey}_indian']!;
        _topMalayalamList = _discoveryCache['${cacheKey}_malayalam']!;
        _topTamilList = _discoveryCache['${cacheKey}_tamil']!;
        _loadingDiscovery = false;
      });
      return;
    }

    setState(() => _loadingDiscovery = true);

    try {
      if (!_isSeriesSearch) {
        // Movies: Hindi, Malayalam, Tamil from TMDB
        final results = await Future.wait([
          _fetchTmdbEndpoint('discover/movie?api_key=$_tmdbApiKey&with_original_language=hi&sort_by=popularity.desc'),
          _fetchTmdbEndpoint('discover/movie?api_key=$_tmdbApiKey&with_original_language=ml&sort_by=popularity.desc'),
          _fetchTmdbEndpoint('discover/movie?api_key=$_tmdbApiKey&with_original_language=ta&sort_by=popularity.desc'),
        ]);

        if (!mounted) return;
        _discoveryCache['${cacheKey}_indian'] = results[0];
        _discoveryCache['${cacheKey}_malayalam'] = results[1];
        _discoveryCache['${cacheKey}_tamil'] = results[2];

        setState(() {
          _topIndianList = results[0];
          _topMalayalamList = results[1];
          _topTamilList = results[2];
          _loadingDiscovery = false;
        });
      } else {
        // Web Series: Hindi Series, Trending TV, South Series from TMDB
        final results = await Future.wait([
          _fetchTmdbEndpoint('discover/tv?api_key=$_tmdbApiKey&with_original_language=hi&sort_by=popularity.desc'),
          _fetchTmdbEndpoint('trending/tv/week?api_key=$_tmdbApiKey'),
          _fetchTmdbEndpoint('discover/tv?api_key=$_tmdbApiKey&with_original_language=ta&sort_by=popularity.desc'),
        ]);

        if (!mounted) return;
        _discoveryCache['${cacheKey}_indian'] = results[0];
        _discoveryCache['${cacheKey}_malayalam'] = results[1];
        _discoveryCache['${cacheKey}_tamil'] = results[2];

        setState(() {
          _topIndianList = results[0];
          _topMalayalamList = results[1];
          _topTamilList = results[2];
          _loadingDiscovery = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading TMDB discovery: $e');
      if (mounted) setState(() => _loadingDiscovery = false);
    }
  }

  Future<List<dynamic>> _fetchTmdbEndpoint(String endpoint) async {
    final target = 'https://api.themoviedb.org/3/$endpoint';
    final proxy = 'https://movie-scraper-beige.vercel.app/api?url=${Uri.encodeComponent(target)}';
    try {
      final res = await http.get(Uri.parse(proxy)).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return (data['results'] as List<dynamic>?) ?? [];
      }
    } catch (e) {
      debugPrint('TMDB fetch error for $endpoint: $e');
    }
    return [];
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _tmdbResults = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 480), () => _fetchSearch(q));
  }

  Future<void> _fetchSearch(String query) async {
    final path = _isSeriesSearch ? 'search/tv' : 'search/movie';
    final target = 'https://api.themoviedb.org/3/$path?api_key=$_tmdbApiKey&query=${Uri.encodeComponent(query)}';
    final proxy = 'https://movie-scraper-beige.vercel.app/api?url=${Uri.encodeComponent(target)}';
    try {
      final res = await http.get(Uri.parse(proxy)).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          _tmdbResults = (data['results'] as List<dynamic>?) ?? [];
          _searching = false;
        });
      } else {
        setState(() => _searching = false);
      }
    } catch (e) {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _switchMode(bool series) {
    if (_isSeriesSearch == series) return;
    setState(() {
      _isSeriesSearch = series;
      _tmdbResults = [];
    });
    _loadDiscoveryRows();
    if (_hasQuery) _fetchSearch(_searchCtrl.text.trim());
  }

  void _openMovieOverlay(Map<String, dynamic> movie) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.90,
        decoration: BoxDecoration(
          color: const Color(0xFF0C0E1A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 30,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Column(
            children: [
              // Drag indicator handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: SpecialSearchDialog(
                  isEmbedded: true,
                  detailMode: true,
                  initialMovieData: movie,
                  isSeriesSearch: _isSeriesSearch,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B14),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildMobileHeroHeader(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _hasQuery ? _buildSearchResultsView() : _buildDiscoveryView(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile Hero Header (Back button, Branding, Search Box, Pill Toggle)
  // ---------------------------------------------------------------------------
  Widget _buildMobileHeroHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF111425), Color(0x00090B14)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Navigation Bar
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFEC4899).withValues(alpha: 0.25),
                      const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.accentBright.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: AppColors.accentBright, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'MEGA SEARCH',
                      style: GoogleFonts.outfit(
                        color: AppColors.accentBright,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Explore Any Movie or Web Series',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 12),

          // Search Box
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF131728),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _searchFocus.hasFocus ? AppColors.accentBright : Colors.white.withValues(alpha: 0.12),
                width: _searchFocus.hasFocus ? 1.8 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
                if (_searchFocus.hasFocus)
                  BoxShadow(
                    color: AppColors.accentBright.withValues(alpha: 0.25),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
              cursorColor: AppColors.accentBright,
              decoration: InputDecoration(
                hintText: _isSeriesSearch
                    ? 'Search TV series & web shows...'
                    : 'Search movies across all providers...',
                hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: _hasQuery ? AppColors.accentBright : Colors.white54,
                  size: 22,
                ),
                suffixIcon: _hasQuery
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          _searchFocus.requestFocus();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Centralised Movies & Web Series Toggle
          Center(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _toggleBtn('Movies', !_isSeriesSearch, () => _switchMode(false)),
                  const SizedBox(width: 4),
                  _toggleBtn('Web Series', _isSeriesSearch, () => _switchMode(true)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)])
              : null,
          color: active ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: active ? Colors.white : Colors.white54,
            fontWeight: active ? FontWeight.bold : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Discovery Rows (Direct from TMDB for Indian, Malayalam, Tamil)
  // ---------------------------------------------------------------------------
  Widget _buildDiscoveryView() {
    if (_loadingDiscovery && _topIndianList.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accentBright),
      );
    }

    return ListView(
      key: ValueKey('discovery_${_isSeriesSearch ? 'series' : 'movies'}'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _buildTmdbRow(
          title: _isSeriesSearch ? 'Top Indian Web Series' : 'Top Indian Films',
          subtitle: _isSeriesSearch ? 'Popular Hindi OTT Originals & Series' : 'Popular Bollywood & Hindi Cinema',
          items: _topIndianList,
          accentColor: const Color(0xFFF97316),
        ),
        const SizedBox(height: 22),
        _buildTmdbRow(
          title: _isSeriesSearch ? 'Trending Web Series' : 'Top Malayalam Films',
          subtitle: _isSeriesSearch ? 'Global Trending Shows This Week' : 'Best of Mollywood Cinema',
          items: _topMalayalamList,
          accentColor: const Color(0xFF06B6D4),
        ),
        const SizedBox(height: 22),
        _buildTmdbRow(
          title: _isSeriesSearch ? 'Top South Regional Series' : 'Top Tamil Films',
          subtitle: _isSeriesSearch ? 'Popular Tamil & Regional Web Series' : 'Best of Kollywood Cinema',
          items: _topTamilList,
          accentColor: const Color(0xFFA78BFA),
        ),
      ],
    );
  }

  Widget _buildTmdbRow({
    required String title,
    required String subtitle,
    required List<dynamic> items,
    required Color accentColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3.5,
              height: 22,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.45),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (items.isEmpty)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(color: accentColor, strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 195,
          child: items.isEmpty
              ? ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 5,
                  separatorBuilder: (ctx, i) => const SizedBox(width: 12),
                  itemBuilder: (ctx, i) => Container(
                    width: 126,
                    height: 195,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accentColor.withValues(alpha: 0.10)),
                    ),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (ctx, i) => const SizedBox(width: 12),
                  itemBuilder: (ctx, i) {
                    final item = items[i] as Map<String, dynamic>;
                    return SizedBox(
                      width: 126,
                      height: 195,
                      child: _MobilePosterTile(
                        movie: item,
                        onTap: () => _openMovieOverlay(item),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Search Results Grid (3 columns on phone, 4 on tablet)
  // ---------------------------------------------------------------------------
  Widget _buildSearchResultsView() {
    final screenWidth = MediaQuery.of(context).size.width;
    final cols = screenWidth > 600 ? 4 : 3;

    return Column(
      key: const ValueKey('search_results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: _searching
              ? Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        color: AppColors.accentBright,
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Searching all databases on TMDB & web...',
                      style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                )
              : Text(
                  '${_tmdbResults.length} results found for "${_searchCtrl.text}"',
                  style: GoogleFonts.outfit(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        Expanded(
          child: _tmdbResults.isEmpty && !_searching
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        color: Colors.white.withValues(alpha: 0.15),
                        size: 64,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No results found.',
                        style: GoogleFonts.outfit(
                          color: Colors.white54,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Try a different title or toggle Movies / Web Series above.',
                        style: GoogleFonts.outfit(color: Colors.white24, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: _tmdbResults.length,
                  itemBuilder: (ctx, i) => _MobilePosterTile(
                    movie: _tmdbResults[i],
                    onTap: () => _openMovieOverlay(_tmdbResults[i] as Map<String, dynamic>),
                  ),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _MobilePosterTile – Responsive mobile poster card with embedded metadata
// ---------------------------------------------------------------------------
class _MobilePosterTile extends StatelessWidget {
  const _MobilePosterTile({
    required this.movie,
    required this.onTap,
  });

  final dynamic movie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final posterPath = movie['poster_path']?.toString();
    final title = (movie['title'] ?? movie['name'])?.toString() ?? 'Unknown';
    final year = (movie['release_date'] ?? movie['first_air_date'])?.toString().split('-').first ?? '';
    final rating = (movie['vote_average'] as num?)?.toStringAsFixed(1) ?? '-';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF131728),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              posterPath != null && posterPath.isNotEmpty
                  ? Image.network(
                      'https://image.tmdb.org/t/p/w342$posterPath',
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, url, err) => _placeholder(title),
                    )
                  : _placeholder(title),
              // Bottom gradient with title & year
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.95),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (year.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          year,
                          style: GoogleFonts.outfit(
                            color: Colors.white54,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Rating Badge
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.5),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 9),
                      const SizedBox(width: 2.5),
                      Text(
                        rating,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
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
    );
  }

  Widget _placeholder(String title) => Container(
        color: const Color(0xFF131728),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_rounded, color: Colors.white12, size: 28),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white24, fontSize: 9.5),
              ),
            ),
          ],
        ),
      );
}
