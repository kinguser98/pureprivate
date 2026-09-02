import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/browser_tab_model.dart';
import 'add_download_bottom_sheet.dart';
import '../../../../screens/video_player_screen.dart';

class MediaGrabberBottomSheet extends StatefulWidget {
  final List<SniffedMediaItem> mediaItems;
  final VoidCallback? onClear;

  const MediaGrabberBottomSheet({
    super.key,
    required this.mediaItems,
    this.onClear,
  });

  @override
  State<MediaGrabberBottomSheet> createState() => _MediaGrabberBottomSheetState();
}

class _MediaGrabberBottomSheetState extends State<MediaGrabberBottomSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<SniffedMediaItem> get _videoItems => widget.mediaItems.where((m) =>
      m.type == SniffedMediaType.hlsStream ||
      m.type == SniffedMediaType.mpdStream ||
      m.type == SniffedMediaType.mp4Video ||
      m.type == SniffedMediaType.genericVideo ||
      m.type == SniffedMediaType.audio).toList();

  List<SniffedMediaItem> get _imageItems => widget.mediaItems.where((m) =>
      m.type == SniffedMediaType.image).toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showImagePreviewDialog(BuildContext context, SniffedMediaItem item) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  item.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    padding: const EdgeInsets.all(32),
                    color: const Color(0xFF1E293B),
                    child: const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
                      icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                      label: const Text('Download Image', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                        AddDownloadBottomSheet.show(
                          context,
                          url: item.url,
                          suggestedFilename: item.title.isNotEmpty ? item.title : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    style: IconButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                    icon: const Icon(Icons.copy_rounded, color: Colors.white70),
                    tooltip: 'Copy Link',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: item.url));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image link copied!')));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Media Sniffer (${widget.mediaItems.length})',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (widget.onClear != null && widget.mediaItems.isNotEmpty)
                TextButton(
                  onPressed: widget.onClear,
                  child: const Text('Clear All', style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Tabs Selector
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFEF4444),
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: [
              Tab(text: 'Videos & Audio (${_videoItems.length})'),
              Tab(text: 'Images (${_imageItems.length})'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Videos Tab View
                _videoItems.isEmpty
                    ? _emptyView(icon: Icons.movie_outlined, message: 'No video streams detected yet.\nPlay a video on the webpage to sniff.')
                    : ListView.separated(
                        itemCount: _videoItems.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (ctx, index) => _videoItemCard(context, _videoItems[index]),
                      ),

                // Images Tab View (Preview Grid)
                _imageItems.isEmpty
                    ? _emptyView(icon: Icons.photo_library_outlined, message: 'No images detected on this page.')
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.8,
                        ),
                        itemCount: _imageItems.length,
                        itemBuilder: (ctx, index) => _imageGridCard(context, _imageItems[index]),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyView({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _videoItemCard(BuildContext context, SniffedMediaItem item) {
    Color badgeColor;
    switch (item.type) {
      case SniffedMediaType.hlsStream:
        badgeColor = const Color(0xFF8B5CF6);
        break;
      case SniffedMediaType.mpdStream:
        badgeColor = const Color(0xFFEC4899);
        break;
      case SniffedMediaType.mp4Video:
      case SniffedMediaType.genericVideo:
        badgeColor = const Color(0xFF3B82F6);
        break;
      case SniffedMediaType.audio:
        badgeColor = const Color(0xFF10B981);
        break;
      case SniffedMediaType.image:
        badgeColor = const Color(0xFFF59E0B);
        break;
    }

    final isVideo = item.type != SniffedMediaType.audio;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  item.typeBadge,
                  style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.url,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (isVideo) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                    label: const Text('Play in App', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(
                            videoSource: item.url,
                            title: item.title,
                            headers: item.headers,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                  label: const Text('Download', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(context);
                    AddDownloadBottomSheet.show(
                      context,
                      url: item.url,
                      suggestedFilename: item.title,
                      headers: item.headers,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 16),
                tooltip: 'Copy URL',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: item.url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied to clipboard!')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _imageGridCard(BuildContext context, SniffedMediaItem item) {
    return InkWell(
      onTap: () => _showImagePreviewDialog(context, item),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              item.url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.image_not_supported_rounded, color: Colors.white24, size: 28),
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
