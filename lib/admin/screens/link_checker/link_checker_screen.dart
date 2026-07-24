import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/movie_provider.dart';
import '../../widgets/common/glass_card.dart';
import '../../utils/drawer_helper.dart';

class LinkCheckerScreen extends ConsumerStatefulWidget {
  const LinkCheckerScreen({super.key});

  @override
  ConsumerState<LinkCheckerScreen> createState() => _LinkCheckerScreenState();
}

class _LinkCheckerScreenState extends ConsumerState<LinkCheckerScreen> {
  String _filter = 'All';
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(movieProvider.notifier).fetchMovies(refresh: true);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final movieState = ref.watch(movieProvider);
    final allMovies = movieState.movies;

    final activeMovies = allMovies.where((m) => !m.isBroken).toList();
    final brokenMovies = allMovies.where((m) => m.isBroken).toList();

    List<dynamic> filtered = _filter == 'All'
        ? allMovies
        : (_filter == 'Active' ? activeMovies : brokenMovies);

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((m) => m.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    final healthPct = allMovies.isNotEmpty
        ? ((activeMovies.length / allMovies.length) * 100).toStringAsFixed(1)
        : '100';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: DrawerProvider.openDrawer,
        ),
        title: Text(
          'Stream Health & Link Checker',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Re-sync Catalog',
            onPressed: () => ref.read(movieProvider.notifier).fetchMovies(refresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // KPI Stats Section
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _kpiBadge('Active Streams', '${activeMovies.length}', const Color(0xFF10B981), Icons.check_circle_rounded),
                    const SizedBox(width: 10),
                    _kpiBadge('Broken Streams', '${brokenMovies.length}', const Color(0xFFEF4444), Icons.error_rounded),
                    const SizedBox(width: 10),
                    _kpiBadge('Health Score', '$healthPct%', const Color(0xFF38BDF8), Icons.speed_rounded),
                  ],
                ),
                const SizedBox(height: 14),

                // Search & Filter Bar
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          onChanged: (v) => setState(() => _searchQuery = v.trim()),
                          decoration: const InputDecoration(
                            hintText: 'Search title...',
                            hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                            prefixIcon: Icon(Icons.search, color: Colors.white38, size: 18),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Filter dropdown
                    Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _filter,
                          dropdownColor: const Color(0xFF1E293B),
                          icon: const Icon(Icons.filter_list, color: Colors.white60, size: 18),
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          items: ['All', 'Active', 'Broken']
                              .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _filter = v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Movies List
          Expanded(
            child: movieState.isLoading && allMovies.isEmpty
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.verified_user_rounded, size: 48, color: Colors.white.withOpacity(0.2)),
                            const SizedBox(height: 12),
                            Text('No $_filter streams found', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final movie = filtered[index];
                          final isBroken = movie.isBroken;
                          final statusColor = isBroken ? const Color(0xFFEF4444) : const Color(0xFF10B981);
                          final sourcesCount = movie.streamSources?.length ?? (movie.streamUrl.isNotEmpty ? 1 : 0);

                          return GlassCard(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                // Poster preview
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: CachedNetworkImage(
                                    imageUrl: movie.posterUrl,
                                    width: 44,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      width: 44,
                                      height: 60,
                                      color: const Color(0xFF1E293B),
                                      child: const Icon(Icons.movie, color: Colors.white38, size: 20),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Title & Stream Sources info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        movie.title,
                                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: statusColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isBroken ? 'Broken Stream' : 'Active • $sourcesCount Source(s)',
                                            style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Last checked: ${movie.lastChecked ?? "System Auto Scanner"}',
                                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),

                                // Edit Action
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded, color: Color(0xFF8B5CF6), size: 20),
                                  tooltip: 'Edit Stream Sources',
                                  onPressed: () => context.go('/edit-movie?id=${movie.id}'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _kpiBadge(String title, String val, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 4),
                Text(val, style: GoogleFonts.outfit(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 2),
            Text(title, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
