import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/data/api_service.dart';

enum DownloadStatus {
  queued,
  downloading,
  paused,
  failed,
  completed
}

class DownloadTask {
  final Movie movie;
  final String downloadUrl;
  final String localPath;
  DownloadStatus status;
  double progress;
  int totalBytes;
  int receivedBytes;
  String? error;
  Map<String, String>? headers;

  // Runtime fields (non-persisted)
  int speedBytesPerSecond = 0;
  Duration elapsedTime = Duration.zero;
  Duration eta = Duration.zero;

  String get speedText {
    if (speedBytesPerSecond <= 0) return '0 KB/s';
    final kb = speedBytesPerSecond / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB/s';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB/s';
  }

  String get elapsedTimeText {
    final minutes = elapsedTime.inMinutes;
    final seconds = elapsedTime.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get etaText {
    if (status == DownloadStatus.completed) return 'Done';
    if (speedBytesPerSecond <= 0) return '--:--';
    final minutes = eta.inMinutes;
    final seconds = eta.inSeconds % 60;
    if (minutes > 60) {
      final hours = minutes ~/ 60;
      final remMin = minutes % 60;
      return '${hours}h ${remMin}m';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  DownloadTask({
    required this.movie,
    required this.downloadUrl,
    required this.localPath,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.error,
    this.headers,
  });

  Map<String, dynamic> toJson() {
    final movieMap = {
      'id': movie.id,
      'title': movie.title,
      'genre': movie.genre,
      'poster_url': movie.posterUrl,
      'backdrop_url': movie.backdropUrl,
      'description': movie.description,
      'release_date': movie.year != null ? '${movie.year}-01-01' : '2026-01-01',
      'runtime': movie.runtime,
      'contentRating': movie.contentRating,
      'tags': movie.tags,
      'cast': movie.castMembers.map((c) => c.name).join(', '),
      'cast_photos': movie.castMembers.map((c) => c.profileUrl).join(', '),
      'director': movie.director,
      'stream_url': movie.videoSource,
      'trailer_url': movie.trailerUrl,
      'language_id': movie.language == 'Tamil' ? '1' : (movie.language == 'Hindi' ? '3' : '2'),
      'tmdb_id': movie.tmdbId,
      'stream_sources': movie.streamSources.map((s) => {'name': s.name, 'url': s.url}).toList(),
    };

    return {
      'movie': movieMap,
      'downloadUrl': downloadUrl,
      'localPath': localPath,
      'status': status.name,
      'progress': progress,
      'totalBytes': totalBytes,
      'receivedBytes': receivedBytes,
      'error': error,
      'headers': headers,
    };
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    final parsedMovies = ApiService.parseMovies([json['movie']]);
    final movie = parsedMovies.isNotEmpty
        ? parsedMovies.first
        : Movie(id: '0', title: 'Unknown', genre: 'Drama', rating: 7.0, posterUrl: '');
    return DownloadTask(
      movie: movie,
      downloadUrl: json['downloadUrl']?.toString() ?? '',
      localPath: json['localPath']?.toString() ?? '',
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadStatus.queued,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      totalBytes: json['totalBytes'] as int? ?? 0,
      receivedBytes: json['receivedBytes'] as int? ?? 0,
      error: json['error'] as String?,
      headers: json['headers'] != null ? Map<String, String>.from(json['headers'] as Map) : null,
    );
  }
}

abstract final class DownloadManager {
  /// Reactive notifier containing the list of all active/queued/paused tasks
  static final ValueNotifier<List<DownloadTask>> downloadTasks = ValueNotifier([]);

  /// Legacy reactive notifier mapping movieId -> progress percentage (0.0 to 1.0)
  static final ValueNotifier<Map<String, double>> downloadProgress = ValueNotifier({});
  
  /// Legacy reactive list of movie IDs actively downloading
  static final ValueNotifier<List<String>> downloadingIds = ValueNotifier([]);

  static final Map<String, http.Client> _activeClients = {};

  /// Restores queue from SharedPreferences and handles app restart transitions
  static Future<void> init() async {
    await loadTasks();
    
    // Convert active statuses from a previous run to 'paused'
    bool changed = false;
    for (final task in downloadTasks.value) {
      if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued) {
        task.status = DownloadStatus.paused;
        changed = true;
      }
    }
    if (changed) {
      _notify();
      await saveTasksToPrefs();
    }
  }

  static Future<void> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('download_manager_queue') ?? '[]';
    try {
      final List<dynamic> decoded = json.decode(raw);
      downloadTasks.value = decoded.map((j) => DownloadTask.fromJson(j)).toList();
    } catch (e) {
      debugPrint('Error loading download queue: $e');
      downloadTasks.value = [];
    }
    _syncLegacyNotifiers();
  }

  static Future<void> saveTasksToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = downloadTasks.value.map((t) => t.toJson()).toList();
    await prefs.setString('download_manager_queue', json.encode(list));
  }

  static void _notify() {
    downloadTasks.value = List.from(downloadTasks.value);
    _syncLegacyNotifiers();
  }

  static void _syncLegacyNotifiers() {
    final downloading = downloadTasks.value
        .where((t) => t.status == DownloadStatus.downloading)
        .map((t) => t.movie.id)
        .toList();
    downloadingIds.value = downloading;

    final progressMap = <String, double>{};
    for (final t in downloadTasks.value) {
      progressMap[t.movie.id] = t.progress;
    }
    downloadProgress.value = progressMap;
  }

  /// Retrieves a task by movie ID
  static DownloadTask? getTask(String movieId) {
    try {
      return downloadTasks.value.firstWhere((t) => t.movie.id == movieId);
    } catch (_) {
      return null;
    }
  }

  /// Enqueues and starts downloading a movie stream link in the background.
  static Future<void> downloadMovie(Movie movie, String downloadUrl, {Map<String, String>? headers}) async {
    var task = getTask(movie.id);

    if (task == null) {
      String localPath = '';
      if (!kIsWeb) {
        final docDir = await getApplicationDocumentsDirectory();
        final downloadsDir = Directory(p.join(docDir.path, 'downloads'));
        if (!await downloadsDir.exists()) {
          await downloadsDir.create(recursive: true);
        }
        String ext = p.extension(Uri.parse(downloadUrl).path);
        if (ext.isEmpty) ext = '.mp4';
        localPath = p.join(downloadsDir.path, 'movie_${movie.id}$ext');
      } else {
        localPath = 'web_mock_download_${movie.id}.mp4';
      }

      task = DownloadTask(
        movie: movie,
        downloadUrl: downloadUrl,
        localPath: localPath,
        status: DownloadStatus.queued,
        headers: headers,
      );

      downloadTasks.value = List.from(downloadTasks.value)..add(task);
      _notify();
      await saveTasksToPrefs();
    }

    await startTask(movie.id);
  }

  /// Starts or resumes a download task
  static Future<void> startTask(String movieId) async {
    final task = getTask(movieId);
    if (task == null) return;
    if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.completed) return;

    task.status = DownloadStatus.downloading;
    task.error = null;
    _notify();
    await saveTasksToPrefs();

    // Run download in the background asynchronously
    unawaited(_runDownloadProcess(task));
  }

  /// Pauses an active download task
  static Future<void> pauseTask(String movieId) async {
    final task = getTask(movieId);
    if (task == null) return;
    if (task.status != DownloadStatus.downloading && task.status != DownloadStatus.queued) return;

    task.status = DownloadStatus.paused;
    _notify();
    await saveTasksToPrefs();

    // Abort active client request to break the stream loop
    _activeClients[movieId]?.close();
    _activeClients.remove(movieId);
  }

  /// Cancels, deletes files, and removes a download task from the queue
  static Future<void> deleteTask(String movieId) async {
    await pauseTask(movieId);

    final task = getTask(movieId);
    if (task != null) {
      if (!kIsWeb) {
        try {
          final file = File(task.localPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('Error deleting local files: $e');
        }
      }
      downloadTasks.value = List.from(downloadTasks.value)..removeWhere((t) => t.movie.id == movieId);
      _notify();
      await saveTasksToPrefs();
    }

    // Clean up completed metadata list too
    await deleteDownload(movieId);
  }

  /// Restarts a task from 0% progress
  static Future<void> restartTask(String movieId) async {
    final task = getTask(movieId);
    if (task == null) return;

    await pauseTask(movieId);

    if (!kIsWeb) {
      try {
        final file = File(task.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting file for restart: $e');
      }
    }

    task.status = DownloadStatus.downloading;
    task.progress = 0.0;
    task.receivedBytes = 0;
    task.totalBytes = 0;
    task.error = null;
    task.elapsedTime = Duration.zero;
    task.speedBytesPerSecond = 0;
    task.eta = Duration.zero;
    _notify();
    await saveTasksToPrefs();

    unawaited(_runDownloadProcess(task));
  }

  static Future<void> _runDownloadProcess(DownloadTask task) async {
    final movieId = task.movie.id;

    try {
      if (kIsWeb) {
        // Mock download progress for web
        while (task.progress < 1.0) {
          if (task.status != DownloadStatus.downloading) return;
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (task.status != DownloadStatus.downloading) return;

          task.progress = (task.progress + 0.05).clamp(0.0, 1.0);
          task.totalBytes = 100 * 1024 * 1024; // 100MB
          task.receivedBytes = (task.progress * task.totalBytes).toInt();
          _notify();
          await saveTasksToPrefs();
        }

        task.status = DownloadStatus.completed;
        _notify();
        await saveTasksToPrefs();

        // Complete save metadata
        await _saveMetadata(task.movie, task.localPath);
        return;
      }

      // Native platform download with range support
      final file = File(task.localPath);
      int fileLength = 0;
      if (await file.exists()) {
        fileLength = await file.length();
      }

      final client = http.Client();
      _activeClients[movieId] = client;

      final request = http.Request('GET', Uri.parse(task.downloadUrl));
      if (fileLength > 0) {
        request.headers['Range'] = 'bytes=$fileLength-';
      }
      if (task.headers != null) {
        request.headers.addAll(task.headers!);
      }

      final response = await client.send(request);
      final isRangeResponse = response.statusCode == 206;

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('Server returned error status code: ${response.statusCode}');
      }

      IOSink sink;
      if (isRangeResponse) {
        sink = file.openWrite(mode: FileMode.append);
        task.receivedBytes = fileLength;
        task.totalBytes = fileLength + (response.contentLength ?? 0);
      } else {
        sink = file.openWrite(mode: FileMode.write);
        task.receivedBytes = 0;
        task.totalBytes = response.contentLength ?? 0;
      }

      // Stream loop with manual pause checking
      int lastNotifyTime = DateTime.now().millisecondsSinceEpoch;
      double lastProgress = -1.0;
      final sessionStartBytes = task.receivedBytes;
      final sessionStartTimeMs = DateTime.now().millisecondsSinceEpoch;
      final baselineElapsedTime = task.elapsedTime;
      try {
        await for (final chunk in response.stream) {
          if (task.status != DownloadStatus.downloading) {
            break;
          }
          sink.add(chunk);
          task.receivedBytes += chunk.length;
          if (task.totalBytes > 0) {
            task.progress = (task.receivedBytes / task.totalBytes).clamp(0.0, 1.0);
          }
          
          final now = DateTime.now().millisecondsSinceEpoch;
          final elapsedMs = now - sessionStartTimeMs;
          if (elapsedMs > 0) {
            final sessionBytes = task.receivedBytes - sessionStartBytes;
            task.speedBytesPerSecond = (sessionBytes * 1000) ~/ elapsedMs;
            task.elapsedTime = baselineElapsedTime + Duration(milliseconds: elapsedMs);
            
            final remainingBytes = task.totalBytes - task.receivedBytes;
            if (task.speedBytesPerSecond > 0 && remainingBytes > 0) {
              final etaSeconds = remainingBytes / task.speedBytesPerSecond;
              task.eta = Duration(seconds: etaSeconds.round());
            } else {
              task.eta = Duration.zero;
            }
          }
          
          if (now - lastNotifyTime > 500 || task.progress >= 1.0 || (task.progress - lastProgress).abs() >= 0.01) {
            _notify();
            lastNotifyTime = now;
            lastProgress = task.progress;
          }
        }
      } catch (e) {
        if (task.status == DownloadStatus.downloading) {
          rethrow;
        }
      } finally {
        await sink.close();
      }

      _activeClients.remove(movieId);

      if (task.status == DownloadStatus.downloading) {
        task.status = DownloadStatus.completed;
        task.progress = 1.0;
        _notify();
        await saveTasksToPrefs();

        // Save metadata for local library
        await _saveMetadata(task.movie, task.localPath);
      }

    } catch (e) {
      debugPrint('Download error for movie $movieId: $e');
      if (task.status == DownloadStatus.downloading) {
        task.status = DownloadStatus.failed;
        task.error = e.toString();
        _notify();
        await saveTasksToPrefs();
      }
      _activeClients.remove(movieId);
    }
  }

  /// Persists metadata into SharedPreferences so it can be loaded offline.
  static Future<void> _saveMetadata(Movie movie, String localPath) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getString('downloaded_movies_metadata') ?? '[]';
    final List<dynamic> decoded = json.decode(rawList);

    // Remove duplicates if they exist
    decoded.removeWhere((item) => item['id']?.toString() == movie.id);

    final map = {
      'id': movie.id,
      'title': movie.title,
      'genre': movie.genre,
      'rating': movie.rating,
      'poster_url': movie.posterUrl,
      'backdrop_url': movie.backdropUrl,
      'description': movie.description,
      'year': movie.year,
      'runtime': movie.runtime,
      'contentRating': movie.contentRating,
      'tags': movie.tags,
      'cast': movie.castMembers.map((c) => c.name).join(', '),
      'cast_photos': movie.castMembers.map((c) => c.profileUrl).join(', '),
      'director': movie.director,
      'stream_url': localPath, // Redirect stream URL to the local file path
      'trailer_url': movie.trailerUrl,
      'language_id': movie.language == 'Tamil' ? '1' : (movie.language == 'Hindi' ? '3' : '2'),
      'tmdb_id': movie.tmdbId,
      'stream_sources': [
        {'name': 'Local Download', 'url': localPath}
      ],
    };

    decoded.add(map);
    await prefs.setString('downloaded_movies_metadata', json.encode(decoded));
  }

  /// Checks if a movie has been fully downloaded and the file exists.
  static Future<bool> isDownloaded(String movieId) async {
    final path = await getLocalPath(movieId);
    if (path == null) return false;
    if (kIsWeb) return true; // On web, if metadata exists, consider it downloaded
    return File(path).exists();
  }

  /// Returns the local path where the movie video file is stored.
  static Future<String?> getLocalPath(String movieId) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getString('downloaded_movies_metadata') ?? '[]';
    final List<dynamic> decoded = json.decode(rawList);

    final match = decoded.firstWhere(
      (item) => item['id']?.toString() == movieId,
      orElse: () => null,
    );
    if (match == null) return null;
    return match['stream_url']?.toString();
  }

  /// Retrieves a list of all fully downloaded Movie models.
  static Future<List<Movie>> getDownloadedMovies() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getString('downloaded_movies_metadata') ?? '[]';
    final List<dynamic> decoded = json.decode(rawList);

    if (kIsWeb) {
      return ApiService.parseMovies(decoded);
    }

    final List<dynamic> validMetadata = [];
    for (final item in decoded) {
      final path = item['stream_url']?.toString();
      if (path != null && await File(path).exists()) {
        validMetadata.add(item);
      }
    }

    // Rewrite cleaned list if missing files were detected and removed
    if (validMetadata.length != decoded.length) {
      await prefs.setString('downloaded_movies_metadata', json.encode(validMetadata));
    }

    return ApiService.parseMovies(validMetadata);
  }

  /// Deletes a download from disk and cleans up its stored metadata.
  static Future<void> deleteDownload(String movieId) async {
    final path = await getLocalPath(movieId);
    if (path != null && !kIsWeb) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting local movie file: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getString('downloaded_movies_metadata') ?? '[]';
    final List<dynamic> decoded = json.decode(rawList);
    decoded.removeWhere((item) => item['id']?.toString() == movieId);
    await prefs.setString('downloaded_movies_metadata', json.encode(decoded));
  }
}
