import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/browser_tab_model.dart';
import '../../models/cloud_account_model.dart';
import '../../services/cloud_auth_service.dart';
import '../../services/download_exporter_service.dart';
import 'add_download_bottom_sheet.dart';

class ImageContextMenuBottomSheet extends StatefulWidget {
  final String imageUrl;
  final String pageTitle;

  const ImageContextMenuBottomSheet({
    super.key,
    required this.imageUrl,
    required this.pageTitle,
  });

  @override
  State<ImageContextMenuBottomSheet> createState() => _ImageContextMenuBottomSheetState();
}

class _ImageContextMenuBottomSheetState extends State<ImageContextMenuBottomSheet> {
  bool _isSharingToTelegram = false;

  Future<void> _shareDirectToTelegram() async {
    final accounts = await CloudAuthService.getAccounts();
    final tgAccount = accounts.where((a) => a.provider == CloudProvider.telegramBot || a.provider == CloudProvider.telegramMtproto).firstOrNull;

    if (tgAccount == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Telegram account connected. Connect in Cloud Storages first.')),
        );
      }
      return;
    }

    setState(() => _isSharingToTelegram = true);
    final item = SniffedMediaItem(
      id: 'tg_img_${DateTime.now().millisecondsSinceEpoch}',
      url: widget.imageUrl,
      type: SniffedMediaType.image,
      title: 'Image_${DateTime.now().millisecondsSinceEpoch}',
      detectedAt: DateTime.now(),
    );

    final success = await DownloadExporterService.uploadToTelegram(
      account: tgAccount,
      item: item,
      customFilename: 'Image_${DateTime.now().millisecondsSinceEpoch}',
    );

    if (mounted) {
      setState(() => _isSharingToTelegram = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Image sent to Telegram!' : 'Failed to send image to Telegram.'),
          backgroundColor: success ? Colors.green : Colors.redAccent,
        ),
      );
    }
  }

  void _openFullQualityPreview() {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: Image.network(widget.imageUrl, fit: BoxFit.contain),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Preview Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    widget.imageUrl,
                    width: 54,
                    height: 54,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 54,
                      height: 54,
                      color: const Color(0xFF0F172A),
                      child: const Icon(Icons.image_outlined, color: Colors.white38),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Image Options', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        widget.imageUrl,
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _actionTile(
            icon: Icons.fullscreen_rounded,
            title: 'Open in Full Quality',
            subtitle: 'Zoom and pan high resolution image',
            onTap: _openFullQualityPreview,
          ),
          const SizedBox(height: 8),
          _actionTile(
            icon: Icons.download_rounded,
            color: const Color(0xFF3B82F6),
            title: 'Download Image',
            subtitle: 'Save to Local Storage, GDrive, OneDrive, or Telegram',
            onTap: () {
              Navigator.pop(context);
              AddDownloadBottomSheet.show(
                context,
                url: widget.imageUrl,
                suggestedFilename: 'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
              );
            },
          ),
          const SizedBox(height: 8),
          _actionTile(
            icon: Icons.send_rounded,
            color: const Color(0xFF2AABEE),
            title: _isSharingToTelegram ? 'Sending to Telegram...' : 'Direct Share to Telegram',
            subtitle: 'Upload immediately to connected Telegram chat',
            onTap: _isSharingToTelegram ? () {} : _shareDirectToTelegram,
          ),
          const SizedBox(height: 8),
          _actionTile(
            icon: Icons.copy_rounded,
            title: 'Copy Image Link',
            subtitle: 'Copy direct image URL to clipboard',
            onTap: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: widget.imageUrl));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image link copied!')));
            },
          ),
          const SizedBox(height: 8),
          _actionTile(
            icon: Icons.share_rounded,
            title: 'Share Image',
            subtitle: 'Share image link with external apps',
            onTap: () {
              Navigator.pop(context);
              Share.share(widget.imageUrl);
            },
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    Color color = Colors.white70,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }
}
