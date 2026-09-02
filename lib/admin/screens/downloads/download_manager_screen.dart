import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/download_task_model.dart';
import '../../services/download_manager_service.dart';
import '../../utils/drawer_helper.dart';
import '../../widgets/browser/download_destination_dialog.dart';
import '../../models/browser_tab_model.dart';
import '../../../../screens/video_player_screen.dart';

class DownloadManagerScreen extends StatefulWidget {
  const DownloadManagerScreen({super.key});

  @override
  State<DownloadManagerScreen> createState() => _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends State<DownloadManagerScreen> with SingleTickerProviderStateMixin {
  final _service = DownloadManagerService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _service.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _tabController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  List<DownloadTask> _filteredTasks(int tabIndex) {
    switch (tabIndex) {
      case 1:
        return _service.tasks.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.queued).toList();
      case 2:
        return _service.tasks.where((t) => t.status == DownloadStatus.completed).toList();
      case 3:
        return _service.tasks.where((t) => t.status == DownloadStatus.paused || t.status == DownloadStatus.failed).toList();
      default:
        return _service.tasks;
    }
  }

  void _showRefreshUrlDialog(DownloadTask task) {
    final urlController = TextEditingController(text: task.url);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 22),
            SizedBox(width: 8),
            Text('Refresh Download URL', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'If the original streaming link expired or timed out, paste the updated URL below to resume from the exact byte offset.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                hintText: 'Paste new stream/download URL',
                hintStyle: const TextStyle(color: Colors.white30),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
            onPressed: () {
              final newUrl = urlController.text.trim();
              if (newUrl.isNotEmpty) {
                Navigator.pop(ctx);
                _service.refreshTaskUrl(task.id, newUrl);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Download URL updated and resumed!')),
                );
              }
            },
            child: const Text('Update & Resume', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(DownloadTask task) {
    bool deleteFile = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Download?', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Remove "${task.filename}" from download manager?', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              if (task.savePath != null) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: deleteFile,
                  activeColor: Colors.redAccent,
                  title: const Text('Also delete downloaded file from device storage', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  onChanged: (v) => setDialogState(() => deleteFile = v ?? false),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                Navigator.pop(ctx);
                _service.deleteTask(task.id, deleteFile: deleteFile);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _service.tasks.where((t) => t.status == DownloadStatus.downloading).length;
    final completedCount = _service.tasks.where((t) => t.status == DownloadStatus.completed).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F19),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
          onPressed: () => DrawerProvider.scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text('Download Manager', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFEF4444),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            Tab(text: 'All (${_service.tasks.length})'),
            Tab(text: 'Active ($activeCount)'),
            Tab(text: 'Done ($completedCount)'),
            Tab(text: 'Paused'),
          ],
          onTap: (_) => setState(() {}),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: List.generate(4, (index) {
          final items = _filteredTasks(index);
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.cloud_download_outlined, color: Colors.white24, size: 54),
                  SizedBox(height: 12),
                  Text('No downloads in this section', style: TextStyle(color: Colors.white54, fontSize: 14)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _taskCard(items[i]),
          );
        }),
      ),
    );
  }

  Widget _taskCard(DownloadTask task) {
    Color statusColor;
    String statusText;
    switch (task.status) {
      case DownloadStatus.downloading:
        statusColor = const Color(0xFF10B981);
        statusText = 'Downloading • ${task.speedFormatted}';
        break;
      case DownloadStatus.queued:
        statusColor = const Color(0xFFF59E0B);
        statusText = 'Queued';
        break;
      case DownloadStatus.paused:
        statusColor = const Color(0xFF64748B);
        statusText = 'Paused';
        break;
      case DownloadStatus.completed:
        statusColor = const Color(0xFF3B82F6);
        statusText = 'Completed';
        break;
      case DownloadStatus.failed:
        statusColor = Colors.redAccent;
        statusText = task.errorMessage ?? 'Failed';
        break;
      case DownloadStatus.canceled:
        statusColor = Colors.grey;
        statusText = 'Canceled';
        break;
    }

    final isVideo = task.filename.endsWith('.mp4') || task.filename.endsWith('.mkv') || task.filename.endsWith('.m3u8') || task.filename.endsWith('.webm');

    return Container(
      padding: const EdgeInsets.all(16),
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isVideo ? Icons.movie_rounded : Icons.insert_drive_file_rounded,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.filename,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
                color: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onSelected: (val) {
                  if (val == 'refresh') _showRefreshUrlDialog(task);
                  if (val == 'cloud') {
                    final sniffed = SniffedMediaItem(
                      id: task.id,
                      url: task.url,
                      type: SniffedMediaType.genericVideo,
                      title: task.filename,
                      headers: task.headers,
                      detectedAt: DateTime.now(),
                    );
                    showDialog(
                      context: context,
                      builder: (_) => DownloadDestinationDialog(
                        item: sniffed,
                        localFilePath: task.savePath,
                      ),
                    );
                  }
                  if (val == 'copy') {
                    Clipboard.setData(ClipboardData(text: task.url));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download URL copied!')));
                  }
                  if (val == 'delete') _showDeleteDialog(task);
                },
                itemBuilder: (ctx) => [
                  if (task.status != DownloadStatus.completed)
                    const PopupMenuItem(
                      value: 'refresh',
                      child: Row(
                        children: [
                          Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 18),
                          SizedBox(width: 8),
                          Text('Refresh URL', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'cloud',
                    child: Row(
                      children: [
                        Icon(Icons.cloud_upload_rounded, color: Color(0xFFF59E0B), size: 18),
                        SizedBox(width: 8),
                        Text('Export to Cloud', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'copy',
                    child: Row(
                      children: [
                        Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                        SizedBox(width: 8),
                        Text('Copy Link', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: task.progress > 0 ? task.progress : (task.status == DownloadStatus.downloading ? null : 0.0),
              minHeight: 6,
              color: statusColor,
              backgroundColor: Colors.white12,
            ),
          ),
          const SizedBox(height: 8),
          // Stats Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(task.progress * 100).toStringAsFixed(1)}% • ${task.sizeFormatted}',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
              if (task.status == DownloadStatus.downloading && task.etaSeconds != null)
                Text(
                  'ETA: ${task.etaFormatted}',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Action Buttons Row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (task.status == DownloadStatus.downloading)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF334155),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.pause_rounded, color: Colors.white, size: 18),
                  label: const Text('Pause', style: TextStyle(color: Colors.white, fontSize: 12)),
                  onPressed: () => _service.pauseTask(task.id),
                )
              else if (task.status == DownloadStatus.paused || task.status == DownloadStatus.failed)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                  label: const Text('Resume', style: TextStyle(color: Colors.white, fontSize: 12)),
                  onPressed: () => _service.resumeTask(task.id),
                ),
              if (task.status == DownloadStatus.completed) ...[
                if (isVideo)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                    label: const Text('Play', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      if (task.savePath != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => VideoPlayerScreen(
                              videoSource: task.savePath!,
                              title: task.filename,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.photo_library_rounded, color: Colors.white, size: 16),
                  label: const Text('Save to Gallery', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    final path = await _service.saveToGalleryOrPublicDownloads(task);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(path != null ? 'Saved to phone Gallery / Movies!' : 'Failed to save'),
                          backgroundColor: path != null ? Colors.green : Colors.redAccent,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF334155)),
                  icon: const Icon(Icons.share_rounded, color: Colors.white70, size: 18),
                  tooltip: 'Share / Open File',
                  onPressed: () {
                    if (task.savePath != null) {
                      Share.shareXFiles([XFile(task.savePath!)]);
                    }
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
