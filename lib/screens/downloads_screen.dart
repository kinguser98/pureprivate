import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/data/download_manager.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/widgets/movie_image.dart';
import 'package:private_cinema_mobile/screens/movie_detail_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<Movie> _completedDownloads = [];
  bool _loadingCompleted = true;

  @override
  void initState() {
    super.initState();
    _loadCompleted();
  }

  Future<void> _loadCompleted() async {
    setState(() => _loadingCompleted = true);
    final completed = await DownloadManager.getDownloadedMovies();
    if (mounted) {
      setState(() {
        _completedDownloads = completed;
        _loadingCompleted = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double val = bytes.toDouble();
    while (val >= 1024 && i < suffixes.length - 1) {
      val /= 1024;
      i++;
    }
    return '${val.toStringAsFixed(1)} ${suffixes[i]}';
  }

  void _showDeleteConfirmDialog(Movie movie) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Delete Download?',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to delete the downloaded file for "${movie.title}"?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                await DownloadManager.deleteTask(movie.id);
                _loadCompleted();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ValueListenableBuilder<List<DownloadTask>>(
          valueListenable: DownloadManager.downloadTasks,
          builder: (context, tasks, _) {
            // Filter active/queued/failed/paused tasks
            final activeTasks = tasks.where((t) => t.status != DownloadStatus.completed).toList();

            return DefaultTabController(
              length: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header Title
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Downloads',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Tab Bar Selector
                  TabBar(
                    tabs: [
                      Tab(text: 'Library (${_completedDownloads.length})'),
                      Tab(text: 'Queue (${activeTasks.length})'),
                    ],
                    indicatorColor: AppColors.accentBright,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white38,
                    labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                    dividerColor: Colors.white10,
                  ),

                  // Tab View
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Tab 1: Completed Library List
                        _buildLibraryTab(),

                        // Tab 2: Active Queue list
                        _buildQueueTab(activeTasks),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLibraryTab() {
    if (_loadingCompleted) {
      return Center(child: CircularProgressIndicator(color: AppColors.accentBright));
    }

    if (_completedDownloads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.download_done_rounded, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            Text(
              'No completed downloads.',
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Movies you download will appear here\nfor offline playback.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white30, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      itemCount: _completedDownloads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final movie = _completedDownloads[index];
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 50,
                height: 75,
                child: MovieImage(source: movie.posterUrl),
              ),
            ),
            title: Text(
              movie.title,
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: Text(
              '${movie.genre} • ${movie.year ?? 2026} • ${movie.runtime ?? "2h"}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              onPressed: () => _showDeleteConfirmDialog(movie),
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MovieDetailScreen(movie: movie),
                ),
              ).then((_) => _loadCompleted());
            },
          ),
        );
      },
    );
  }

  Widget _buildQueueTab(List<DownloadTask> activeTasks) {
    if (activeTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_empty_rounded, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            Text(
              'No active downloads.',
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      itemCount: activeTasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final task = activeTasks[index];
        final movie = task.movie;
        final speedLabel = task.status == DownloadStatus.downloading
            ? task.speedText
            : task.status.name.toUpperCase();
        
        String detailsText = '${_formatSize(task.receivedBytes)} / ${task.totalBytes > 0 ? _formatSize(task.totalBytes) : "Unknown"}';
        if (task.status == DownloadStatus.downloading) {
          detailsText += ' • Elapsed: ${task.elapsedTimeText} • ETA: ${task.etaText}';
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 44,
                      height: 66,
                      child: MovieImage(source: movie.posterUrl),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          movie.title,
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$speedLabel • $detailsText',
                          style: const TextStyle(color: Colors.white30, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  // Control Buttons
                  if (task.status == DownloadStatus.downloading)
                    IconButton(
                      icon: const Icon(Icons.pause_rounded, color: Colors.white70),
                      onPressed: () => DownloadManager.pauseTask(movie.id),
                    )
                  else if (task.status == DownloadStatus.paused || task.status == DownloadStatus.failed)
                    IconButton(
                      icon: const Icon(Icons.play_arrow_rounded, color: Colors.white70),
                      onPressed: () => DownloadManager.startTask(movie.id),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
                    onPressed: () => DownloadManager.deleteTask(movie.id),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Linear Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: task.progress,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    task.status == DownloadStatus.failed ? Colors.redAccent : AppColors.accentBright,
                  ),
                ),
              ),
              if (task.error != null) ...[
                const SizedBox(height: 4),
                Text(
                  task.error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ]
            ],
          ),
        );
      },
    );
  }
}
