import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/auth_provider.dart';
import '../../providers/movie_provider.dart';
import '../../providers/iptv_provider.dart';
import '../../widgets/sliders/hero_slider.dart';
import '../../widgets/cards/stats_card.dart';
import '../../utils/drawer_helper.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(movieProvider.notifier).fetchMovies();
      ref.read(iptvProvider.notifier).fetchChannels();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final movieState = ref.watch(movieProvider);
    final iptvState = ref.watch(iptvProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: DrawerProvider.openDrawer,
        ),
        title: const Text('Engine Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(movieProvider.notifier).fetchMovies(refresh: true);
              ref.read(iptvProvider.notifier).fetchChannels();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(movieProvider.notifier).fetchMovies(refresh: true);
          await ref.read(iptvProvider.notifier).fetchChannels();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome header
              _buildWelcomeHeader(authState),
              const SizedBox(height: 20),
              // Stats grid
              _buildStatsGrid(movieState, iptvState),
              const SizedBox(height: 24),
              // Hero slider with featured movies
              if (movieState.movies.isNotEmpty)
                HeroSlider(
                  movies: movieState.topMovies.take(5).toList(),
                ),
              const SizedBox(height: 24),
              // Top movies
              _buildSectionHeader('Top Performance', 'See All', () {}),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: movieState.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: movieState.topMovies.length,
                        itemBuilder: (context, index) {
                          final movie = movieState.topMovies[index];
                          return _buildMovieListItem(movie, index);
                        },
                      ),
              ),
              const SizedBox(height: 24),
              // Recent movies
              _buildSectionHeader('Recently Ingested', 'See All', () {}),
              const SizedBox(height: 8),
              SizedBox(
                height: 180,
                child: movieState.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: movieState.recentMovies.length,
                        itemBuilder: (context, index) {
                          final movie = movieState.recentMovies[index];
                          return _buildRecentMovieItem(movie);
                        },
                      ),
              ),
              const SizedBox(height: 24),
              // Broken streams section
              if (movieState.brokenMovies.isNotEmpty)
                _buildBrokenStreamsSection(movieState),
              // IPTV quick stats
              if (iptvState.channels.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildSectionHeader(
                    'IPTV Overview', 'View All', () => context.go('/iptv')),
                const SizedBox(height: 8),
                _buildIptvCard(iptvState),
              ],
              const SizedBox(height: 24),
              // Bottom spacing
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader(AuthState authState) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1F2E), Color(0xFF0F1520)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                (authState.username ?? 'U')[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  authState.username ?? 'Admin',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(MovieState movieState, IptvState iptvState) {
    final totalMovies = movieState.movies.length;
    final totalViews = movieState.movies.fold<int>(0, (sum, m) => sum + m.views);
    final brokenCount = movieState.brokenMovies.length;
    final iptvTotal = iptvState.channels.length;
    final iptvEnabled = iptvState.enabledChannels.length;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.1,
      children: [
        StatsCard(
          title: 'Total Titles',
          value: totalMovies.toString(),
          icon: Icons.movie,
          color: const Color(0xFFEF4444),
          progress: 0.66,
        ),
        StatsCard(
          title: 'Total Views',
          value: _formatViews(totalViews),
          icon: Icons.visibility,
          color: const Color(0xFF10B981),
          progress: 0.5,
        ),
        StatsCard(
          title: 'Broken Streams',
          value: brokenCount.toString(),
          icon: Icons.error_outline,
          color: Colors.red,
          progress: totalMovies > 0 ? brokenCount / totalMovies : 0,
          isAlert: brokenCount > 0,
        ),
        StatsCard(
          title: 'IPTV Channels',
          value: '$iptvEnabled/$iptvTotal',
          icon: Icons.tv,
          color: const Color(0xFF8B5CF6),
          progress: iptvTotal > 0 ? iptvEnabled / iptvTotal : 0,
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String actionText, VoidCallback onAction) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          TextButton(
            onPressed: onAction,
            child: Text(
              actionText,
              style: TextStyle(
                color: const Color(0xFFEF4444),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovieListItem(dynamic movie, int index) {
    final backdrop = (movie.backdropUrl?.toString().isNotEmpty == true) ? movie.backdropUrl!.toString() : movie.posterUrl.toString();
    return GestureDetector(
      onTap: () => context.go('/edit-movie?id=${movie.id}'),
      child: Container(
        width: 250,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: backdrop,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[850],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[850],
                  child: const Center(
                    child: Icon(Icons.movie, color: Colors.grey, size: 40),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.85),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      movie.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.visibility, size: 11, color: Colors.white.withOpacity(0.6)),
                        const SizedBox(width: 4),
                        Text(
                          '${_formatViews(movie.views)} views',
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10),
                        ),
                      ],
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

  Widget _buildRecentMovieItem(dynamic movie) {
    return GestureDetector(
      onTap: () => context.go('/edit-movie?id=${movie.id}'),
      child: Container(
        width: 110,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F2E).withOpacity(0.45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: CachedNetworkImage(
                  imageUrl: movie.posterUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[850],
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[850],
                    child: Center(
                      child: Icon(Icons.movie, color: Colors.grey[700], size: 28),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                movie.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrokenStreamsSection(MovieState movieState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Broken Streams',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.withOpacity(0.2)),
          ),
          child: Column(
            children: movieState.brokenMovies.take(3).map((movie) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.broken_image, color: Colors.red.withOpacity(0.7), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        movie.title,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 18),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildIptvCard(IptvState iptvState) {
    final totalCategories = iptvState.channelsByCategory.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E).withOpacity(0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tv, color: Color(0xFF8B5CF6), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'IPTV Channels',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '$totalCategories categories',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${iptvState.enabledChannels.length} live',
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K';
    return views.toString();
  }
}
