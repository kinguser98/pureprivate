import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_ios/data/api_service.dart';
import 'package:private_cinema_ios/data/mock_catalog.dart';
import 'package:private_cinema_ios/models/movie.dart';

abstract final class PlaybackTracker {
  static const String _listKey = 'continue_watching_list';

  /// Generates or loads a pseudo-unique device ID to link progress & favorites in the cloud.
  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');
    if (deviceId == null) {
      deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecondsSinceEpoch % 9000))}';
      await prefs.setString('device_id', deviceId);
    }
    return deviceId;
  }

  /// Saves the current playback position.
  /// If the progress is >= 95%, the movie is considered completed and removed.
  static Future<void> saveProgress(String id, int positionMs, int durationMs) async {
    if (durationMs <= 0) return;
    
    // 1. Save Locally
    final prefs = await SharedPreferences.getInstance();
    final progress = positionMs / durationMs;
    
    if (progress >= 0.95 || positionMs <= 1000) {
      await prefs.remove('resume_position_$id');
      await prefs.remove('resume_duration_$id');
      await prefs.remove('resume_timestamp_$id');
      
      final list = prefs.getStringList(_listKey) ?? [];
      if (list.contains(id)) {
        list.remove(id);
        await prefs.setStringList(_listKey, list);
      }
    } else {
      await prefs.setInt('resume_position_$id', positionMs);
      await prefs.setInt('resume_duration_$id', durationMs);
      await prefs.setInt('resume_timestamp_$id', DateTime.now().millisecondsSinceEpoch);

      final list = prefs.getStringList(_listKey) ?? [];
      if (!list.contains(id)) {
        list.add(id);
        await prefs.setStringList(_listKey, list);
      }
    }

    // 2. Save to Cloud Asynchronously
    _saveToCloud(id, positionMs, durationMs);
  }

  static Future<void> _saveToCloud(String id, int positionMs, int durationMs) async {
    try {
      final deviceId = await getOrCreateDeviceId();
      final uri = Uri.parse('${ApiService.apiUrl}?action=save_progress');
      await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'},
        body: {
          'movie_id': id,
          'device_id': deviceId,
          'position_ms': positionMs.toString(),
          'duration_ms': durationMs.toString(),
        },
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      // Offline fallback: ignore cloud post errors
      print('Cloud save progress failed: $e');
    }
  }

  /// Gets the saved playback position in milliseconds for a movie.
  static Future<int> getSavedPosition(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('resume_position_$id') ?? 0;
  }

  /// Gets the progress fraction (0.0 to 1.0) for a movie.
  static Future<double?> getWatchProgress(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final pos = prefs.getInt('resume_position_$id');
    final dur = prefs.getInt('resume_duration_$id');
    if (pos == null || dur == null || dur <= 0) return null;
    return pos / dur;
  }

  /// Returns the list of movies currently being watched, synced from the cloud.
  static Future<List<Movie>> getContinueWatchingMovies() async {
    final prefs = await SharedPreferences.getInstance();
    List<Movie> cloudMovies = [];

    // 1. Fetch from cloud
    try {
      final deviceId = await getOrCreateDeviceId();
      final uri = Uri.parse('${ApiService.apiUrl}?action=get_progress&device_id=$deviceId');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final jsonString = utf8.decode(response.bodyBytes);
        final rawList = json.decode(jsonString) as List<dynamic>;
        
        final parsed = ApiService.parseMovies(rawList);
        for (var i = 0; i < parsed.length; i++) {
          final rawItem = rawList[i];
          final pos = int.tryParse(rawItem['position_ms']?.toString() ?? '0') ?? 0;
          final dur = int.tryParse(rawItem['duration_ms']?.toString() ?? '1') ?? 1;
          final progress = pos / dur;
          
          parsed[i] = _updateMovieProgress(parsed[i], progress);

          // Update local shared preferences to keep offline-mode in sync
          final mid = parsed[i].id;
          await prefs.setInt('resume_position_$mid', pos);
          await prefs.setInt('resume_duration_$mid', dur);
          await prefs.setInt('resume_timestamp_$mid', DateTime.now().millisecondsSinceEpoch);
        }
        cloudMovies = parsed;
      }
    } catch (e) {
      print('Failed to load cloud progress: $e');
    }

    if (cloudMovies.isNotEmpty) {
      return cloudMovies;
    }

    // 2. Offline Fallback: Local progress
    final list = prefs.getStringList(_listKey) ?? [];
    final List<Movie> localMovies = [];
    for (final id in list) {
      final movieIndex = MockCatalog.allMovies.indexWhere((m) => m.id == id);
      if (movieIndex == -1) continue;
      final movie = MockCatalog.allMovies[movieIndex];
      
      final pos = prefs.getInt('resume_position_$id') ?? 0;
      final dur = prefs.getInt('resume_duration_$id') ?? 1;
      final progress = pos / dur;
      localMovies.add(_updateMovieProgress(movie, progress));
    }
    return localMovies;
  }

  static Movie _updateMovieProgress(Movie movie, double progress) {
    return Movie(
      id: movie.id,
      title: movie.title,
      genre: movie.genre,
      rating: movie.rating,
      posterUrl: movie.posterUrl,
      backdropUrl: movie.backdropUrl,
      description: movie.description,
      watchProgress: progress,
      posterColor: movie.posterColor,
      year: movie.year,
      runtime: movie.runtime,
      contentRating: movie.contentRating,
      tags: movie.tags,
      cast: movie.cast,
      director: movie.director,
      videoSource: movie.videoSource,
      trailerUrl: movie.trailerUrl,
      castMembers: movie.castMembers,
      language: movie.language,
      tmdbId: movie.tmdbId,
      imdbId: movie.imdbId,
      streamSources: movie.streamSources,
    );
  }
}
