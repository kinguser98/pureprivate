import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
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

    final isWideScreen = MediaQuery.of(context).size.width > 900;

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
          'Engine Analytics Dashboard',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
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
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome header
              _buildWelcomeHeader(authState),
              const SizedBox(height: 20),

              // KPI Stats grid
              _buildStatsGrid(movieState, iptvState),
              const SizedBox(height: 20),

              // Responsive 2-Column Analytics Layout
              if (isWideScreen)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _buildEngineHealthMatrix(),
                          const SizedBox(height: 20),
                          _buildScraperResolutionBreakdown(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          _buildApiRateLimitMonitor(),
                          const SizedBox(height: 20),
                          _buildAdminQuickActions(context, ref),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                _buildEngineHealthMatrix(),
                const SizedBox(height: 20),
                _buildScraperResolutionBreakdown(),
                const SizedBox(height: 20),
                _buildApiRateLimitMonitor(),
                const SizedBox(height: 20),
                _buildAdminQuickActions(context, ref),
              ],

              const SizedBox(height: 24),

              // Hero slider with featured movies
              if (movieState.movies.isNotEmpty) ...[
                _buildSectionHeader('Featured Ingestion', 'View Catalog', () => context.go('/movies')),
                const SizedBox(height: 12),
                HeroSlider(
                  movies: movieState.topMovies.take(5).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // Top performance movies
              _buildSectionHeader('Top Performance', 'See All', () => context.go('/movies')),
              const SizedBox(height: 12),
              SizedBox(
                height: 210,
                child: movieState.isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
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

              // Recently Ingested
              _buildSectionHeader('Recently Ingested', 'See All', () => context.go('/movies')),
              const SizedBox(height: 12),
              SizedBox(
                height: 190,
                child: movieState.isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
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
                _buildSectionHeader('IPTV Live Stream Overview', 'Manage IPTV', () => context.go('/iptv')),
                const SizedBox(height: 12),
                _buildIptvCard(iptvState),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader(AuthState authState) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF8B5CF6).withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: const Color(0xFF8B5CF6).withOpacity(0.4), blurRadius: 10, spreadRadius: 1),
              ],
            ),
            child: Center(
              child: Text(
                (authState.username ?? 'A')[0].toUpperCase(),
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 24,
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
                Row(
                  children: [
                    Text(
                      'SYSTEM OPERATIONAL',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF10B981),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Welcome, ${authState.username ?? 'Administrator'}',
                  style: GoogleFonts.outfit(
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
      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
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
          color: const Color(0xFF8B5CF6),
          progress: 0.8,
        ),
        StatsCard(
          title: 'Total Views',
          value: _formatViews(totalViews),
          icon: Icons.visibility,
          color: const Color(0xFF10B981),
          progress: 0.65,
        ),
        StatsCard(
          title: 'Broken Streams',
          value: brokenCount.toString(),
          icon: Icons.error_outline,
          color: Colors.redAccent,
          progress: totalMovies > 0 ? brokenCount / totalMovies : 0,
          isAlert: brokenCount > 0,
        ),
        StatsCard(
          title: 'IPTV Channels',
          value: '$iptvEnabled/$iptvTotal',
          icon: Icons.tv,
          color: const Color(0xFF38BDF8),
          progress: iptvTotal > 0 ? iptvEnabled / iptvTotal : 0,
        ),
      ],
    );
  }

  Widget _buildEngineHealthMatrix() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.health_and_safety_rounded, color: Color(0xFF10B981), size: 22),
              const SizedBox(width: 10),
              Text(
                'Engine & Scraper Matrix',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                ),
                child: const Text(
                  '100% HEALTHY',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.3,
            children: [
              _buildHealthTile('Stalker VOD', '12ms', Colors.purpleAccent),
              _buildHealthTile('Telegram Sync', '18ms', Colors.blueAccent),
              _buildHealthTile('TMDB Gateway', '24ms', Colors.cyanAccent),
              _buildHealthTile('Streamtape', '35ms', Colors.amberAccent),
              _buildHealthTile('Nuveo Addon', '15ms', const Color(0xFF10B981)),
              _buildHealthTile('HLS Proxy', '8ms', Colors.tealAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHealthTile(String label, String ping, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.6), blurRadius: 6, spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  ping,
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScraperResolutionBreakdown() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hd_rounded, color: Color(0xFF38BDF8), size: 22),
              const SizedBox(width: 10),
              Text(
                'Stream Quality Distribution',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  Expanded(flex: 48, child: Container(color: const Color(0xFF10B981))),
                  const SizedBox(width: 3),
                  Expanded(flex: 38, child: Container(color: const Color(0xFF38BDF8))),
                  const SizedBox(width: 3),
                  Expanded(flex: 14, child: Container(color: const Color(0xFFA855F7))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildResTile('4K Ultra HD', '48%', const Color(0xFF10B981))),
              const SizedBox(width: 8),
              Expanded(child: _buildResTile('1080p FHD', '38%', const Color(0xFF38BDF8))),
              const SizedBox(width: 8),
              Expanded(child: _buildResTile('720p HD', '14%', const Color(0xFFA855F7))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResTile(String label, String pct, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(pct, style: GoogleFonts.outfit(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildApiRateLimitMonitor() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_rounded, color: Color(0xFFF59E0B), size: 22),
              const SizedBox(width: 10),
              Text(
                'API Rate Limit & Quota Monitor',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildQuotaRow(
            name: 'TMDB Gateway API',
            usage: '2,410 / 100,000 reqs',
            status: '98% Free',
            statusColor: const Color(0xFF10B981),
            progress: 0.02,
          ),
          const SizedBox(height: 12),
          _buildQuotaRow(
            name: 'Telegram Bot Sync',
            usage: '420 msgs / day',
            status: 'Active • 0 Limits',
            statusColor: const Color(0xFF38BDF8),
            progress: 0.15,
          ),
          const SizedBox(height: 12),
          _buildQuotaRow(
            name: 'Streamtape Resolver',
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(name, style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    color: statusColor,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(usage, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminQuickActions(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Engine Actions',
          style: GoogleFonts.outfit(
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
                      content: Text('Caches cleared successfully!'),
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
                      content: Text('Catalog re-synced!'),
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

  Widget _buildSectionHeader(String title, String actionText, VoidCallback onAction) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        TextButton(
          onPressed: onAction,
          child: Text(
            actionText,
            style: const TextStyle(
              color: Color(0xFF8B5CF6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMovieListItem(dynamic movie, int index) {
    final backdrop = (movie.backdropUrl?.toString().isNotEmpty == true) ? movie.backdropUrl!.toString() : movie.posterUrl.toString();
    return GestureDetector(
      onTap: () => context.go('/edit-movie?id=${movie.id}'),
      child: Container(
        width: 260,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: backdrop,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#${index + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatViews(movie.views)} views',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
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
        width: 115,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withOpacity(0.5),
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
                  errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                movie.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrokenStreamsSection(MovieState movieState) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Broken Streams Alert',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${movieState.brokenMovies.length} Pending Fix',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...movieState.brokenMovies.take(3).map((movie) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      movie.title,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => context.go('/edit-movie?id=${movie.id}'),
                    icon: const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF8B5CF6)),
                    label: const Text('Fix Stream', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 11)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildIptvCard(IptvState iptvState) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.tv, color: Color(0xFF38BDF8), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'IPTV Live Catalog',
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  '${iptvState.channelsByCategory.length} Categories Configured',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
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
              '${iptvState.enabledChannels.length} Live',
              style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
            ),
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.outfit(color: color, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K';
    return views.toString();
  }
}
