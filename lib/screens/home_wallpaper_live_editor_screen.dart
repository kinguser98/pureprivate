import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_mobile/data/mock_catalog.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/theme/home_wallpaper_manager.dart';
import 'package:private_cinema_mobile/widgets/movie_image.dart';

class HomeWallpaperLiveEditorScreen extends StatefulWidget {
  const HomeWallpaperLiveEditorScreen({super.key});

  @override
  State<HomeWallpaperLiveEditorScreen> createState() => _HomeWallpaperLiveEditorScreenState();
}

class _HomeWallpaperLiveEditorScreenState extends State<HomeWallpaperLiveEditorScreen> {
  bool _isPanelCollapsed = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HomeWallpaperSettings>(
      valueListenable: HomeWallpaperManager.notifier,
      builder: (context, settings, _) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Live Ambient Wallpaper Layer
              if (settings.localPath != null &&
                  settings.localPath!.isNotEmpty &&
                  File(settings.localPath!).existsSync())
                Image.file(
                  File(settings.localPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: const Color(0xFF090D16)),
                )
              else if (settings.wallpaperUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: settings.wallpaperUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: const Color(0xFF090D16)),
                  errorWidget: (_, __, ___) => Container(color: const Color(0xFF090D16)),
                ),

              // 2. Live Glass Blur & Darkness Overlay
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: settings.blur, sigmaY: settings.blur),
                  child: Container(color: Colors.black.withOpacity(settings.darkness)),
                ),
              ),

              // 3. Live Edge Vignette Radial Overlay
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.1,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(settings.vignette * 0.4),
                      Colors.black.withOpacity(settings.vignette),
                    ],
                    stops: const [0.35, 0.75, 1.0],
                  ),
                ),
              ),

              // 4. Dummy Home Layout (Non-clickable, scrollable to test feel)
              SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    bottom: _isPanelCollapsed ? 120 : 380,
                    top: 10,
                  ),
                  child: IgnorePointer(
                    child: _buildDummyHomeLayout(),
                  ),
                ),
              ),

              // 5. Top Bar Overlay
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: 'Back to Settings',
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Live Home Ambience Preview',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                'Adjust sliders below to see live changes',
                                style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _isPanelCollapsed ? Icons.tune_rounded : Icons.visibility_rounded,
                            color: Colors.amberAccent,
                            size: 20,
                          ),
                          tooltip: _isPanelCollapsed ? 'Show Controls' : 'Hide Controls',
                          onPressed: () {
                            setState(() => _isPanelCollapsed = !_isPanelCollapsed);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 6. Floating Glassmorphic Adjustment Sheet
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildControlPanel(settings),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlPanel(HomeWallpaperSettings settings) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle / Toggle Header
          GestureDetector(
            onTap: () => setState(() => _isPanelCollapsed = !_isPanelCollapsed),
            behavior: HitTestBehavior.opaque,
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.palette_rounded, color: Colors.amberAccent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Live Ambience Adjustments',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      _isPanelCollapsed ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: Colors.white60,
                      size: 22,
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (!_isPanelCollapsed) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),

            // Presets row + Gallery button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Wallpapers & Gallery',
                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                InkWell(
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    await HomeWallpaperManager.pickFromGallery();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accentBright.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.accentBright.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_library_rounded, color: AppColors.accentBright, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          settings.localPath != null ? 'Gallery Active' : 'Pick Gallery',
                          style: GoogleFonts.outfit(
                            color: AppColors.accentBright,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Presets Horizontal list
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: HomeWallpaperManager.presets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final p = HomeWallpaperManager.presets[i];
                  final isSelected = settings.localPath == null && settings.wallpaperUrl == p['url'];
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      HomeWallpaperManager.update(
                        settings.copyWith(
                          wallpaperUrl: p['url'],
                          clearLocalPath: true,
                          enabled: true,
                        ),
                      );
                    },
                    child: Container(
                      width: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? AppColors.accentBright : Colors.white12,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: p['url']!,
                              fit: BoxFit.cover,
                            ),
                            Container(color: Colors.black.withOpacity(0.45)),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  p['name']!,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Sliders Grid / Column
            // 1. Glass Blur
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Glass Blur Intensity',
                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${settings.blur.toStringAsFixed(1)} px',
                  style: GoogleFonts.outfit(color: AppColors.accentBright, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.accentBright,
                thumbColor: AppColors.accentBright,
                inactiveTrackColor: Colors.white24,
                trackHeight: 2.5,
              ),
              child: Slider(
                value: settings.blur,
                min: 0.0,
                max: 25.0,
                onChanged: (v) {
                  HomeWallpaperManager.update(settings.copyWith(blur: v, enabled: true));
                },
              ),
            ),

            // 2. Edge Vignette
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Edge Vignette Darkness',
                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${(settings.vignette * 100).toInt()}%',
                  style: GoogleFonts.outfit(color: AppColors.accentBright, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.accentBright,
                thumbColor: AppColors.accentBright,
                inactiveTrackColor: Colors.white24,
                trackHeight: 2.5,
              ),
              child: Slider(
                value: settings.vignette,
                min: 0.0,
                max: 1.0,
                onChanged: (v) {
                  HomeWallpaperManager.update(settings.copyWith(vignette: v, enabled: true));
                },
              ),
            ),

            // 3. Background Dimming
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Background Dimming',
                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${(settings.darkness * 100).toInt()}%',
                  style: GoogleFonts.outfit(color: AppColors.accentBright, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.accentBright,
                thumbColor: AppColors.accentBright,
                inactiveTrackColor: Colors.white24,
                trackHeight: 2.5,
              ),
              child: Slider(
                value: settings.darkness,
                min: 0.0,
                max: 1.0,
                onChanged: (v) {
                  HomeWallpaperManager.update(settings.copyWith(darkness: v, enabled: true));
                },
              ),
            ),

            const SizedBox(height: 6),
            SizedBox(
              height: 42,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentBright,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: Text(
                  'Save & Apply to Home',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDummyHomeLayout() {
    final movies = MockCatalog.allMovies.isNotEmpty ? MockCatalog.allMovies : <Movie>[];
    final featured = movies.isNotEmpty ? movies.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 60),

        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'GOXIO',
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2.5,
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.search, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)]),
                    ),
                    child: const Icon(Icons.person, color: Colors.white, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Category Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: ['Movies', 'Live TV', 'Series', 'Vault'].map((tab) {
              final isSel = tab == 'Movies';
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: isSel ? AppColors.accentBright : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tab,
                  style: TextStyle(
                    color: isSel ? Colors.black : Colors.white70,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 20),

        // Featured Banner
        if (featured != null)
          Container(
            height: 190,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MovieImage(
                    source: (featured.backdropUrl != null && featured.backdropUrl!.isNotEmpty)
                        ? featured.backdropUrl!
                        : featured.posterUrl,
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.85),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accentBright,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'FEATURED',
                            style: GoogleFonts.outfit(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          featured.title,
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${featured.genre} • ${featured.year ?? 2024} • ★ ${featured.rating.toStringAsFixed(1)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 24),

        // Section: "New" Posters Row
        _buildDummySection('New Releases', movies.take(5).toList()),

        const SizedBox(height: 20),

        // Section: "Languages"
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Explore by Language',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: ['Malayalam', 'Tamil', 'Hindi', 'Telugu', 'English'].map((lang) {
              return Container(
                margin: const EdgeInsets.only(right: 10),
                width: 105,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF1E293B), const Color(0xFF0F172A)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                alignment: Alignment.center,
                child: Text(
                  lang,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 24),

        // Section: "Top Rated" Posters Row
        _buildDummySection('Top Rated Movies', movies.skip(2).take(5).toList()),
      ],
    );
  }

  Widget _buildDummySection(String title, List<Movie> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Text('See all', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              final m = list[i];
              return Container(
                width: 110,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 3)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MovieImage(source: m.posterUrl, fit: BoxFit.cover),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '★ ${m.rating.toStringAsFixed(1)}',
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
