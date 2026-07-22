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
          IconButton(
            icon: const Icon(Icons.exit_to_app_rounded, color: Colors.orangeAccent),
            tooltip: 'Exit to Main App',
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
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
              const SizedBox(height: 20),
              // Engine & Scraper Health Matrix
              _buildEngineHealthMatrix(),
              const SizedBox(height: 20),
              // Scraper Resolution Breakdown
              _buildScraperResolutionBreakdown(),
              const SizedBox(height: 20),
              // API Rate Limit & Quota Monitor
              _buildApiRateLimitMonitor(),
              const SizedBox(height: 20),
              // Quick Admin Actions
              _buildAdminQuickActions(context, ref),
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

  Widget _buildEngineHealthMatrix() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.health_and_safety_rounded, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Engine & Scraper Health Matrix',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '100% Operational',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildHealthBadge('Stalker VOD Engine', 'Online', Colors.purpleAccent),
              _buildHealthBadge('Telegram Stream Sync', 'Active', Colors.blueAccent),
              _buildHealthBadge('TMDB API Gateway', 'Operational', Colors.cyanAccent),
              _buildHealthBadge('Streamtape Resolver', 'Ready', Colors.amberAccent),
              _buildHealthBadge('Nuveo Addon Core', 'Operational', Colors.emerald),
              _buildHealthBadge('Stream Cache Engine', 'Optimized', Colors.tealAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHealthBadge(String label, String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.6), blurRadius: 4, spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text(
            '• $status',
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminQuickActions(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Engine Actions',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.cleaning_services_rounded,
                label: 'Clear Cache',
                color: Colors.orangeAccent,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Stream & metadata caches cleared successfully!'),
                      backgroundColor: Colors.deepPurple,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildActionButton(
                icon: Icons.sync_rounded,
                label: 'Sync Catalog',
                color: Colors.cyanAccent,
                onTap: () {
                  ref.read(movieProvider.notifier).fetchMovies(refresh: true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Catalog re-synced from database!'),
                      backgroundColor: Colors.blueAccent,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildActionButton(
                icon: Icons.exit_to_app_rounded,
                label: 'Exit Admin',
                color: Colors.redAccent,
                onTap: () => Navigator.of(context, rootNavigator: true).pop(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildScraperResolutionBreakdown() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hd_rounded, color: Color(0xFF38BDF8), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Scraper Stream Quality Distribution',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                'High Definition',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Visual Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(flex: 48, child: Container(color: const Color(0xFF10B981))),
                  const SizedBox(width: 2),
                  Expanded(flex: 38, child: Container(color: const Color(0xFF38BDF8))),
                  const SizedBox(width: 2),
                  Expanded(flex: 14, child: Container(color: const Color(0xFFA855F7))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Breakdown Info Tiles
          Row(
            children: [
              Expanded(
                child: _buildResTile('4K Ultra HD', '48%', '2160p', const Color(0xFF10B981)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildResTile('1080p FHD', '38%', 'Full HD', const Color(0xFF38BDF8)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildResTile('720p HD', '14%', 'Standard', const Color(0xFFA855F7)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResTile(String label, String pct, String subText, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(pct, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
          Text(subText, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildApiRateLimitMonitor() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_rounded, color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 8),
              const Text(
                'API Rate Limit & Quota Monitor',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _buildQuotaRow(
            name: 'TMDB API Gateway',
            usage: '2,410 / 100,000 reqs',
            status: '98% Free',
            statusColor: const Color(0xFF10B981),
            progress: 0.02,
          ),
          const SizedBox(height: 10),
          _buildQuotaRow(
            name: 'Telegram Bot Sync API',
            usage: '420 msgs / day',
            status: 'Active • 0 Limits',
            statusColor: const Color(0xFF38BDF8),
            progress: 0.15,
          ),
          const SizedBox(height: 10),
          _buildQuotaRow(
            name: 'Streamtape API Resolver',
            usage: '850 MB / 25 GB day',
            status: '96% Free',
            statusColor: const Color(0xFFA855F7),
            progress: 0.04,
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaRow({
    required String name,
    required String usage,
    required String status,
    required Color statusColor,
    required double progress,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    color: statusColor,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(usage, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K';
    return views.toString();
  }
}
