import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../admin/utils/tmdb_service.dart';
import '../models/movie.dart';
import '../screens/movie_detail_screen.dart';
import '../theme/app_colors.dart';

class PersonDetailSheet extends StatefulWidget {
  final int? personId;
  final String personName;
  final String? photoUrl;

  const PersonDetailSheet({
    super.key,
    this.personId,
    required this.personName,
    this.photoUrl,
  });

  static void show(BuildContext context, {int? personId, required String personName, String? photoUrl}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PersonDetailSheet(
        personId: personId,
        personName: personName,
        photoUrl: photoUrl,
      ),
    );
  }

  @override
  State<PersonDetailSheet> createState() => _PersonDetailSheetState();
}

class _PersonDetailSheetState extends State<PersonDetailSheet> {
  bool _isLoading = true;
  TmdbPersonDetails? _details;
  List<TmdbPersonFilmography> _filmography = [];
  bool _showFullBio = false;

  @override
  void initState() {
    super.initState();
    _loadPersonData();
  }

  Future<void> _loadPersonData() async {
    int? pid = widget.personId;
    if (pid == null || pid == 0) {
      pid = await TmdbService.searchPersonId(widget.personName);
    }

    if (pid != null && pid > 0) {
      final d = await TmdbService.getPersonDetails(pid);
      final f = await TmdbService.getPersonFilmography(pid);
      if (mounted) {
        setState(() {
          _details = d;
          _filmography = f;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _details?.profilePath ?? widget.photoUrl;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF1E1B4B).withOpacity(0.92),
                const Color(0xFF0F172A).withOpacity(0.96),
                const Color(0xFF020617),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withOpacity(0.25),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag Handle Indicator
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Header Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.4), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: photo != null && photo.startsWith('http')
                            ? CachedNetworkImage(
                                imageUrl: photo,
                                width: 72,
                                height: 95,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 72,
                                height: 95,
                                color: const Color(0xFF1E293B),
                                child: const Icon(Icons.person_rounded, color: Colors.white38, size: 38),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _details?.name ?? widget.personName,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (_details?.knownForDepartment != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF8B5CF6).withOpacity(0.3),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    _details!.knownForDepartment!.toUpperCase(),
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              if (_details?.birthday != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  _details!.birthday!,
                                  style: GoogleFonts.outfit(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ],
                          ),
                          if (_details?.placeOfBirth != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, color: Colors.white38, size: 13),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    _details!.placeOfBirth!,
                                    style: GoogleFonts.outfit(color: Colors.white60, fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              Divider(color: Colors.white.withOpacity(0.08), height: 1),

              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFFA855F7), strokeWidth: 2.5),
                      )
                    : CustomScrollView(
                        slivers: [
                          // Biography Section
                          if (_details?.biography != null && _details!.biography!.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Container(
                                margin: const EdgeInsets.all(16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.menu_book_rounded, color: Color(0xFFA855F7), size: 16),
                                        const SizedBox(width: 8),
                                        Text(
                                          'BIOGRAPHY',
                                          style: GoogleFonts.outfit(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _details!.biography!,
                                      style: GoogleFonts.outfit(
                                        color: Colors.white.withOpacity(0.85),
                                        fontSize: 13,
                                        height: 1.5,
                                      ),
                                      maxLines: _showFullBio ? 100 : 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (_details!.biography!.length > 140)
                                      GestureDetector(
                                        onTap: () => setState(() => _showFullBio = !_showFullBio),
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(
                                            _showFullBio ? 'Show Less ▲' : 'Read More ▼',
                                            style: GoogleFonts.outfit(
                                              color: const Color(0xFFA855F7),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                          // Filmography Header
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.movie_filter_rounded, color: Color(0xFFA855F7), size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'FILMOGRAPHY',
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                                    ),
                                    child: Text(
                                      '${_filmography.length} titles (Latest first)',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Filmography Grid
                          _filmography.isEmpty
                              ? const SliverFillRemaining(
                                  child: Center(
                                    child: Text(
                                      'No filmography available',
                                      style: TextStyle(color: Colors.white38, fontSize: 13),
                                    ),
                                  ),
                                )
                              : SliverPadding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  sliver: SliverGrid(
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      childAspectRatio: 0.58,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 16,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final item = _filmography[index];
                                        final year = item.releaseDate != null && item.releaseDate!.length >= 4
                                            ? item.releaseDate!.substring(0, 4)
                                            : null;

                                        return GestureDetector(
                                          onTap: () {
                                            Navigator.pop(context);
                                            final m = Movie(
                                              id: item.id.toString(),
                                              title: item.title,
                                              genre: item.mediaType == 'tv' ? 'TV Series' : 'Movie',
                                              rating: 8.0,
                                              posterUrl: item.posterPath ?? '',
                                              tmdbId: item.id.toString(), // CRITICAL: Pass tmdbId to trigger Castle, Stravo, Stremio/Nuveo & Torrents!
                                              year: year != null ? int.tryParse(year) : null,
                                            );
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => MovieDetailScreen(movie: m),
                                              ),
                                            );
                                          },
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(16),
                                              color: Colors.white.withOpacity(0.03),
                                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      ClipRRect(
                                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                                        child: item.posterPath != null
                                                            ? CachedNetworkImage(
                                                                imageUrl: item.posterPath!,
                                                                fit: BoxFit.cover,
                                                              )
                                                            : Container(
                                                                color: const Color(0xFF1E293B),
                                                                child: const Center(
                                                                  child: Icon(Icons.movie_rounded, color: Colors.white24, size: 30),
                                                                ),
                                                              ),
                                                      ),
                                                      if (year != null)
                                                        Positioned(
                                                          top: 6,
                                                          right: 6,
                                                          child: Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                            decoration: BoxDecoration(
                                                              color: Colors.black.withOpacity(0.75),
                                                              borderRadius: BorderRadius.circular(6),
                                                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                                                            ),
                                                            child: Text(
                                                              year,
                                                              style: GoogleFonts.outfit(
                                                                color: Colors.white,
                                                                fontSize: 9,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets.all(8.0),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        item.title,
                                                        style: GoogleFonts.outfit(
                                                          color: Colors.white,
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        item.characterOrJob != null && item.characterOrJob!.isNotEmpty
                                                            ? item.characterOrJob!
                                                            : (item.mediaType == 'tv' ? 'TV Series' : 'Movie'),
                                                        style: GoogleFonts.outfit(
                                                          color: const Color(0xFFA855F7),
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                      childCount: _filmography.length,
                                    ),
                                  ),
                                ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
