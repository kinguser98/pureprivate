import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

class TmdbMovie {
  final int id;
  final String title;
  final String? posterPath;
  final String? releaseDate;
  TmdbMovie({required this.id, required this.title, this.posterPath, this.releaseDate});
}

class TmdbDetails {
  final int id;
  final String title;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final int? runtime;
  final String? imdbId;
  final List<String> genres;
  final List<TmdbCast> cast;
  final String? director;
  final String? directorPhoto;
  final String? trailerKey;
  TmdbDetails({
    required this.id, required this.title, this.overview = '', this.posterPath, this.backdropPath,
    this.releaseDate, this.runtime, this.imdbId, this.genres = const [],
    this.cast = const [], this.director, this.directorPhoto, this.trailerKey,
  });
}

class TmdbCast {
  final String name;
  final String? photoPath;
  TmdbCast({required this.name, this.photoPath});
}

class TmdbService {
  static const String _apiKey = '8baba8ab6b8bbe247645bcae7df63d0d';
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _posterBase = 'https://image.tmdb.org/t/p/w500';
  static const String _backdropBase = 'https://image.tmdb.org/t/p/original';
  static const String _thumbBase = 'https://image.tmdb.org/t/p/w92';
  static const String _profileBase = 'https://image.tmdb.org/t/p/w185';

  static final Dio _dio = _createDio();

  static Dio _createDio() {
    final d = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 15)));
    try { (d.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = (client) { client.badCertificateCallback = (cert, host, port) => true; return client; }; } catch (_) {}
    return d;
  }

  static Future<List<TmdbMovie>> search(String query) async {
    if (query.isEmpty) return [];
    try {
      final res = await _dio.get('$_baseUrl/search/movie', queryParameters: {'api_key': _apiKey, 'query': query});
      final data = res.data;
      if (data == null || data['results'] == null) return [];
      final results = data['results'] as List;
      return results.take(6).map<TmdbMovie>((r) => TmdbMovie(
        id: r['id'] ?? 0, title: r['title'] ?? '',
        posterPath: r['poster_path'] != null ? '$_thumbBase${r['poster_path']}' : null,
        releaseDate: r['release_date'],
      )).toList();
    } catch (e) {
      debugPrint('TMDB search error: $e');
      return [];
    }
  }

  static Future<TmdbDetails?> getDetails(int id) async {
    try {
      final res = await _dio.get('$_baseUrl/movie/$id', queryParameters: {'api_key': _apiKey, 'append_to_response': 'credits,videos'});
      final data = res.data;
      if (data == null || data['success'] == false) return null;

      final credits = data['credits'] as Map? ?? {};
      final castList = (credits['cast'] as List? ?? []).take(10).map<TmdbCast>((c) => TmdbCast(
        name: c['name'] ?? '',
        photoPath: c['profile_path'] != null ? '$_profileBase${c['profile_path']}' : null,
      )).toList();

      final crew = credits['crew'] as List? ?? [];
      Map<String, dynamic>? directorObj;
      for (final c in crew) { if (c['job'] == 'Director') { directorObj = c; break; } }

      final videos = data['videos'] as Map? ?? {};
      String? trailerKey;
      if (videos['results'] != null) {
        for (final v in videos['results']) { if (v['site'] == 'YouTube' && v['type'] == 'Trailer') { trailerKey = v['key']; break; } }
      }

      return TmdbDetails(
        id: data['id'] ?? id, title: data['title'] ?? '', overview: data['overview'] ?? '',
        posterPath: data['poster_path'] != null ? '$_posterBase${data['poster_path']}' : null,
        backdropPath: data['backdrop_path'] != null ? '$_backdropBase${data['backdrop_path']}' : null,
        releaseDate: data['release_date'], runtime: data['runtime'], imdbId: data['imdb_id'],
        genres: (data['genres'] as List? ?? []).map<String>((g) => g['name'] as String).toList(),
        cast: castList, director: directorObj?['name'],
        directorPhoto: directorObj?['profile_path'] != null ? '$_profileBase${directorObj!['profile_path']}' : null,
        trailerKey: trailerKey,
      );
    } catch (e) {
      debugPrint('TMDB details error: $e');
      return null;
    }
  }
}
