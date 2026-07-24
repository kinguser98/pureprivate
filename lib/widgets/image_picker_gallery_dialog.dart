import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../admin/utils/tmdb_service.dart';
import '../admin/utils/image_search_service.dart';

class ImagePickerGalleryDialog extends StatefulWidget {
  final int tmdbId;
  final String? imdbId;
  final String movieTitle;
  final bool isPoster;

  const ImagePickerGalleryDialog({
    super.key,
    required this.tmdbId,
    this.imdbId,
    required this.movieTitle,
    required this.isPoster,
  });

  @override
  State<ImagePickerGalleryDialog> createState() => _ImagePickerGalleryDialogState();
}

class _ImagePickerGalleryDialogState extends State<ImagePickerGalleryDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  bool _loadingTmdb = true;
  bool _loadingFanart = true;
  bool _loadingGoogle = true;
  bool _loadingPinterest = true;

  List<String> _tmdbImages = [];
  List<String> _fanartImages = [];
  List<ImageSearchResult> _googleImages = [];
  List<ImageSearchResult> _pinterestImages = [];

  final _manualSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _manualSearchCtrl.text = widget.movieTitle;
    _fetchAllSources();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _manualSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAllSources() async {
    _fetchTmdbAndFanart();
    _fetchGoogle();
    _fetchPinterest();
  }

  Future<void> _fetchTmdbAndFanart() async {
    if (widget.tmdbId > 0 || (widget.imdbId != null && widget.imdbId!.isNotEmpty)) {
      final tmdbRes = await TmdbService.getMovieImages(widget.tmdbId, imdbId: widget.imdbId);
      final fanartRes = await TmdbService.getFanartImages(widget.tmdbId, imdbId: widget.imdbId, isPoster: widget.isPoster);
      if (mounted) {
        setState(() {
          _tmdbImages = widget.isPoster ? tmdbRes.posters : tmdbRes.backdrops;
          _fanartImages = fanartRes;
          _loadingTmdb = false;
          _loadingFanart = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _loadingTmdb = false;
          _loadingFanart = false;
        });
      }
    }
  }

  Future<void> _fetchGoogle() async {
    final query = _manualSearchCtrl.text.trim();
    if (query.isNotEmpty) {
      final results = await ImageSearchService.searchGoogleImages(query, isPoster: widget.isPoster);
      if (mounted) {
        setState(() {
          _googleImages = results;
          _loadingGoogle = false;
        });
      }
    } else {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  Future<void> _fetchPinterest() async {
    final query = _manualSearchCtrl.text.trim();
    if (query.isNotEmpty) {
      final results = await ImageSearchService.searchPinterestImages(query, isPoster: widget.isPoster);
      if (mounted) {
        setState(() {
          _pinterestImages = results;
          _loadingPinterest = false;
        });
      }
    } else {
      if (mounted) setState(() => _loadingPinterest = false);
    }
  }

  void _triggerSearch() {
    setState(() {
      _loadingGoogle = true;
      _loadingPinterest = true;
    });
    _fetchGoogle();
    _fetchPinterest();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withOpacity(0.12)),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * (isMobile ? 0.95 : 0.8),
        height: MediaQuery.of(context).size.height * 0.82,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.collections_rounded, color: Color(0xFF8B5CF6), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.isPoster ? 'Poster Artwork Gallery' : 'Backdrop Artwork Gallery',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white60),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Search Bar for custom title query
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: TextField(
                      controller: _manualSearchCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Search movie title keywords for Google & Pinterest...',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                        prefixIcon: Icon(Icons.search_rounded, color: Colors.white38, size: 18),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onSubmitted: (_) => _triggerSearch(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _triggerSearch,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Search'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Modern Category Tab Bar
            Container(
              height: 42,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFF8B5CF6),
                  borderRadius: BorderRadius.circular(11),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12),
                tabs: [
                  Tab(text: 'TMDB (${_tmdbImages.length})'),
                  Tab(text: 'Fanart.tv (${_fanartImages.length})'),
                  Tab(text: 'Google (${_googleImages.length})'),
                  Tab(text: 'Pinterest (${_pinterestImages.length})'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: TMDB
                  _buildUrlGrid(_tmdbImages, _loadingTmdb, 'TMDB'),

                  // Tab 2: Fanart.tv
                  _buildUrlGrid(_fanartImages, _loadingFanart, 'Fanart.tv'),

                  // Tab 3: Google
                  _buildSearchResultGrid(_googleImages, _loadingGoogle, 'Google'),

                  // Tab 4: Pinterest
                  _buildSearchResultGrid(_pinterestImages, _loadingPinterest, 'Pinterest'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrlGrid(List<String> urls, bool isLoading, String providerName) {
    if (isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)));
    if (urls.isEmpty) {
      return Center(
        child: Text('No artwork found on $providerName for this title.', style: const TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.isPoster ? 4 : 2,
        childAspectRatio: widget.isPoster ? 0.67 : 1.77,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: urls.length,
      itemBuilder: (context, index) {
        final url = urls[index];
        return InkWell(
          onTap: () => Navigator.of(context).pop(url),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: Colors.white10),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchResultGrid(List<ImageSearchResult> results, bool isLoading, String providerName) {
    if (isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)));
    if (results.isEmpty) {
      return Center(
        child: Text('No results found on $providerName. Try refining search keywords above.', style: const TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.isPoster ? 4 : 2,
        childAspectRatio: widget.isPoster ? 0.67 : 1.77,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        return InkWell(
          onTap: () => Navigator.of(context).pop(item.imageUrl),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                item.thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.network(
                  item.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.white10),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
