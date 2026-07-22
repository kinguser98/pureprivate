import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/data/download_manager.dart';
import 'package:private_cinema_mobile/data/sync_service.dart';
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
  String? _pairedTvDeviceId;

  @override
  void initState() {
    super.initState();
    _loadCompleted();
    _loadPairedTv();
  }

  Future<void> _loadPairedTv() async {
    final tvId = await SyncService.getPairedTvDeviceId();
    if (mounted) {
      setState(() {
        _pairedTvDeviceId = tvId;
      });
    }
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
                  // Header Title & Actions Row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Downloads',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            // Pairing Action Button
                            IconButton(
                              onPressed: _showPairingDialog,
                              icon: Icon(
                                _pairedTvDeviceId != null ? Icons.tv_rounded : Icons.tv_off_rounded,
                                color: _pairedTvDeviceId != null ? AppColors.accentBright : Colors.white38,
                              ),
                              tooltip: 'TV Pairing Settings',
                            ),
                            const SizedBox(width: 8),
                            // Manual Download Add Button
                            IconButton(
                              onPressed: _showAddManualDownloadDialog,
                              icon: const Icon(Icons.add_rounded, color: Colors.white70),
                              tooltip: 'Add Manual Link',
                            ),
                          ],
                        ),
                      ],
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
            subtitle: Builder(
              builder: (context) {
                final task = DownloadManager.getTask(movie.id);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${movie.genre} • ${movie.year ?? 2026} • ${movie.runtime ?? "2h"}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    if (task != null && (task.selectedQuality != null || task.selectedAudio != null)) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${task.selectedQuality != null ? "[${task.selectedQuality}] " : ""}${task.selectedAudio != null ? "[${task.selectedAudio}]" : ""}',
                        style: TextStyle(color: AppColors.accentBright, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                );
              }
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.tv_rounded,
                    color: _pairedTvDeviceId != null ? AppColors.accentBright : Colors.white24,
                  ),
                  tooltip: 'Send Download Link to TV',
                  onPressed: () async {
                    if (_pairedTvDeviceId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please pair with your TV first using the TV icon at the top.'),
                          backgroundColor: Colors.orangeAccent,
                        ),
                      );
                      return;
                    }
                    final task = DownloadManager.getTask(movie.id);
                    final downloadUrl = task?.downloadUrl ?? movie.videoSource;

                    if (downloadUrl == null || downloadUrl.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No valid stream source link found for this media.'),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }

                    final success = await SyncService.sendRemoteDownload(
                      title: movie.title,
                      downloadUrl: downloadUrl,
                      posterUrl: movie.posterUrl,
                      tmdbId: movie.tmdbId,
                      description: movie.description,
                      genre: movie.genre,
                      language: movie.language,
                    );

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(success
                              ? 'Request to download "${movie.title}" sent to TV successfully!'
                              : 'Failed to send remote download request. Please check connections.'),
                          backgroundColor: success ? AppColors.accent : Colors.redAccent,
                        ),
                      );
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  onPressed: () => _showDeleteConfirmDialog(movie),
                ),
              ],
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
                          '${task.selectedQuality != null ? "[${task.selectedQuality}] " : ""}${task.selectedAudio != null ? "[${task.selectedAudio}] • " : ""}$speedLabel • $detailsText',
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

  void _showPairingDialog() {
    final codeController = TextEditingController();
    bool pairing = false;

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.tv_rounded, color: AppColors.accentBright),
                  const SizedBox(width: 10),
                  Text(
                    'TV Pairing Setup',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_pairedTvDeviceId != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Paired with TV Device:\n${_pairedTvDeviceId!.length > 12 ? _pairedTvDeviceId!.substring(0, 12) + "..." : _pairedTvDeviceId}',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'You can now send any completed download link directly to your TV.',
                      style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                    ),
                  ] else ...[
                    const Text(
                      'Enter the 6-digit pairing code shown on your TV Local Library screen to connect:',
                      style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: codeController,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2),
                      maxLength: 6,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'SYNC CODE (e.g. A1B2C3)',
                        hintStyle: TextStyle(color: Colors.white24, letterSpacing: 0, fontSize: 13),
                        counterText: '',
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.accentBright),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                if (_pairedTvDeviceId != null)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('paired_tv_device_id');
                      await _loadPairedTv();
                      if (mounted) Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Unpaired TV successfully.'), backgroundColor: Colors.orangeAccent),
                      );
                    },
                    child: const Text('Unpair', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  )
                else
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentBright,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: pairing
                        ? null
                        : () async {
                            final code = codeController.text.trim().toUpperCase();
                            if (code.length != 6) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please enter a valid 6-digit sync code.')),
                              );
                              return;
                            }
                            setDialogState(() => pairing = true);
                            final success = await SyncService.pairWithTv(code);
                            setDialogState(() => pairing = false);
                            
                            if (success) {
                              await _loadPairedTv();
                              if (mounted) Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: const Text('Paired with TV successfully!'), backgroundColor: AppColors.accent),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Pairing failed. Please check the sync code and try again.'), backgroundColor: Colors.redAccent),
                              );
                            }
                          },
                    child: pairing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Text('Pair Device', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddManualDownloadDialog() {
    final titleController = TextEditingController();
    final urlController = TextEditingController();
    bool sendToTv = _pairedTvDeviceId != null;

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.add_circle_outline_rounded, color: AppColors.accentBright),
                  const SizedBox(width: 10),
                  Text(
                    'Add Manual Download',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              content: Form(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Title (Optional)',
                          labelStyle: const TextStyle(color: Colors.white60),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: urlController,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Download / Video Stream URL',
                          labelStyle: const TextStyle(color: Colors.white60),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white10),
                          ),
                        ),
                      ),
                      if (_pairedTvDeviceId != null) ...[
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          title: const Text('Send request to paired TV', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          subtitle: const Text('Adds link to TV queue instead of downloading locally', style: TextStyle(color: Colors.white30, fontSize: 10)),
                          value: sendToTv,
                          activeColor: AppColors.accentBright,
                          checkColor: Colors.black,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) {
                            setDialogState(() {
                              sendToTv = val ?? false;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentBright,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final downloadUrl = urlController.text.trim();
                    if (downloadUrl.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid video stream URL.')),
                      );
                      return;
                    }

                    String rawTitle = titleController.text.trim();
                    if (rawTitle.isEmpty) {
                      rawTitle = 'Link Download ${DateTime.now().toString().substring(11, 16)}';
                    }

                    Navigator.of(context).pop();

                    if (sendToTv) {
                      final success = await SyncService.sendRemoteDownload(
                        title: rawTitle,
                        downloadUrl: downloadUrl,
                        posterUrl: '',
                        genre: 'Manual Link',
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success
                                ? 'Manual link request sent to TV successfully!'
                                : 'Failed sending link to TV.'),
                            backgroundColor: success ? AppColors.accent : Colors.redAccent,
                          ),
                        );
                      }
                    } else {
                      final mockMovie = Movie(
                        id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
                        title: rawTitle,
                        genre: 'Manual Link',
                        rating: 8.0,
                        posterUrl: '',
                        backdropUrl: '',
                        description: 'Manually added video link.',
                        year: DateTime.now().year,
                        runtime: 'Unknown',
                        contentRating: 'PG',
                        tags: ['Manual Link'],
                        cast: [],
                        director: '',
                        videoSource: downloadUrl,
                        trailerUrl: '',
                        castMembers: [],
                        language: 'English',
                        streamSources: [
                          StreamSource(name: 'Manual Download', url: downloadUrl)
                        ],
                      );

                      await DownloadManager.downloadMovie(mockMovie, downloadUrl);
                      _loadCompleted();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Added manual download link: "$rawTitle"'),
                            backgroundColor: AppColors.accent,
                          ),
                        );
                      }
                    }
                  },
                  child: Text(
                    sendToTv ? 'Send to TV' : 'Download',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
