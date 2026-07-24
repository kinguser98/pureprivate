import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/movie_provider.dart';
import '../../models/movie.dart';
import '../../widgets/cards/movie_card.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/error_widget.dart';
import '../../utils/drawer_helper.dart';

enum MovieSort { az, za, views, date, addedOrder }

class MoviesScreen extends ConsumerStatefulWidget {
  const MoviesScreen({super.key});
  @override
  ConsumerState<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends ConsumerState<MoviesScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSearch = false;
  MovieSort _sort = MovieSort.addedOrder;

  PopupMenuItem<MovieSort> _popupItem(String label, MovieSort sort, IconData icon) {
    return PopupMenuItem(
      value: sort,
      child: Row(children: [
        Icon(icon, size: 18, color: _sort == sort ? const Color(0xFFEF4444) : Colors.white.withOpacity(0.6)),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: _sort == sort ? const Color(0xFFEF4444) : Colors.white, fontSize: 14)),
      ]),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(movieProvider.notifier).fetchMovies(refresh: true);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Movie> _sortMovies(List<Movie> movies) {
    final sorted = List<Movie>.from(movies);
    switch (_sort) {
      case MovieSort.addedOrder:
        sorted.sort((a, b) => b.id.compareTo(a.id));
        break;
      case MovieSort.az:
        sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case MovieSort.za:
        sorted.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case MovieSort.views:
        sorted.sort((a, b) => b.views.compareTo(a.views));
        break;
      case MovieSort.date:
        sorted.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
        break;
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final movieState = ref.watch(movieProvider);
    final allMovies = _sortMovies(movieState.movies);
    final displayMovies = _searchQuery.isNotEmpty
        ? allMovies.where((m) => m.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList()
        : allMovies;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: DrawerProvider.openDrawer),
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search movies...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Text('All Movies'),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () => setState(() { _showSearch = !_showSearch; if (!_showSearch) { _searchController.clear(); _searchQuery = ''; } }),
          ),
          PopupMenuButton<MovieSort>(
            icon: const Icon(Icons.sort),
            color: const Color(0xFF1A1F2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withOpacity(0.1))),
            onSelected: (sort) => setState(() => _sort = sort),
            itemBuilder: (_) => [
              _popupItem('Recently Added (System ID)', MovieSort.addedOrder, Icons.history_rounded),
              _popupItem('A-Z', MovieSort.az, Icons.sort_by_alpha),
              _popupItem('Z-A', MovieSort.za, Icons.sort_by_alpha),
              _popupItem('Most Views', MovieSort.views, Icons.visibility),
              _popupItem('Ingestion Date', MovieSort.date, Icons.access_time),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.read(movieProvider.notifier).fetchMovies(refresh: true)),
        ],
      ),
      body: _buildBody(movieState, displayMovies),
    );
  }

  Widget _buildBody(MovieState movieState, List<Movie> displayMovies) {
    if (movieState.isLoading && movieState.movies.isEmpty) return const LoadingWidget(message: 'Loading movies...');
    if (movieState.error != null && movieState.movies.isEmpty) {
      return ErrorDisplayWidget(message: movieState.error!, onRetry: () => ref.read(movieProvider.notifier).fetchMovies(refresh: true));
    }
    if (displayMovies.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.movie_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(_searchQuery.isNotEmpty ? 'No movies found' : 'No movies yet', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16)),
        ]),
      );
    }

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Text('${displayMovies.length} movies', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
          const Spacer(),
          Text('Sorted: ${_sort == MovieSort.addedOrder ? "Recently Added" : _sort == MovieSort.az ? "A-Z" : _sort == MovieSort.za ? "Z-A" : _sort == MovieSort.views ? "Views" : "Ingestion Date"}', style: TextStyle(color: const Color(0xFFEF4444).withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.6),
          itemCount: displayMovies.length,
          itemBuilder: (context, index) {
            final movie = displayMovies[index];
            return Stack(
              children: [
                MovieCard(movie: movie, onTap: () => _showMovieDetails(movie)),
                Positioned(
                  top: 4, right: 4,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => context.go('/edit-movie?id=${movie.id}'),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.edit, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ]);
  }

  void _showMovieDetails(Movie movie) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1F2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => _MovieDetailsSheet(movie: movie),
    );
  }
}

class _MovieDetailsSheet extends ConsumerWidget {
  final Movie movie;
  const _MovieDetailsSheet({required this.movie});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(movie.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => context.go('/edit-movie?id=${movie.id}'),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1A1F2E),
                      title: const Text('Delete Movie', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      content: Text('Are you sure you want to permanently delete "${movie.title}"?', style: const TextStyle(color: Colors.white70)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    Navigator.pop(context); // Close details sheet
                    final scaffold = ScaffoldMessenger.of(context);
                    
                    // Show progress loader
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFFEF4444))),
                    );
                    
                    try {
                      final result = await ref.read(movieProvider.notifier).deleteMovie(movie.id);
                      if (context.mounted) {
                        Navigator.pop(context); // Dismiss progress
                        scaffold.showSnackBar(SnackBar(
                          content: Text(result['message'] ?? 'Movie deleted'),
                          backgroundColor: result['success'] == true ? const Color(0xFF10B981) : Colors.red,
                        ));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        Navigator.pop(context); // Dismiss progress
                        scaffold.showSnackBar(SnackBar(content: Text('Error deleting movie: $e'), backgroundColor: Colors.red));
                      }
                    }
                  }
                },
                icon: const Icon(Icons.delete, size: 16, color: Colors.white),
                label: const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              if (movie.qualityTag != null) ...[
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(6)),
                  child: Text(movie.qualityTag!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                const SizedBox(width: 8),
              ],
              Icon(Icons.visibility, size: 14, color: Colors.white.withOpacity(0.5)),
              const SizedBox(width: 4),
              Text('${_formatViews(movie.views)} views', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
              if (movie.releaseDate != null) ...[
                const SizedBox(width: 12),
                Text(movie.releaseDate!, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
              ],
            ]),
            const SizedBox(height: 20),
            if (movie.genre.isNotEmpty) ...[
              Wrap(spacing: 8, children: movie.genre.split(',').map((g) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                child: Text(g.trim(), style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)))).toList()),
              const SizedBox(height: 20),
            ],
            if (movie.description != null) ...[
              Text('Description', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
              const SizedBox(height: 8),
              Text(movie.description!, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14, height: 1.5)),
              const SizedBox(height: 20),
            ],
            if (movie.cast != null && movie.cast!.isNotEmpty) ...[
              Text('Cast', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
              const SizedBox(height: 8),
              Text(movie.cast!, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
              const SizedBox(height: 20),
            ],
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: (movie.isBroken ? Colors.red : Colors.green).withOpacity(0.1), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: (movie.isBroken ? Colors.red : Colors.green).withOpacity(0.3))),
              child: Row(children: [
                Icon(movie.isBroken ? Icons.error : Icons.check_circle, color: movie.isBroken ? Colors.red : Colors.green, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(movie.isBroken ? 'Stream Broken' : 'Stream Active', style: TextStyle(color: movie.isBroken ? Colors.red : Colors.green, fontWeight: FontWeight.bold, fontSize: 14)),
                  if (movie.lastChecked != null) Text('Last checked: ${movie.lastChecked}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                ])),
              ]),
            ),
            const SizedBox(height: 32),
          ]),
        );
      },
    );
  }

  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K';
    return views.toString();
  }
}
