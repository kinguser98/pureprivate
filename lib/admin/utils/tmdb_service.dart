import 'dart:convert';
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
  final int id;
  final String name;
  final String? photoPath;
  TmdbCast({required this.name, this.photoPath, this.id = 0});
}

class TmdbPersonDetails {
  final int id;
  final String name;
  final String? biography;
  final String? profilePath;
  final String? birthday;
  final String? placeOfBirth;
  final String? knownForDepartment;
  TmdbPersonDetails({
    required this.id,
    required this.name,
    this.biography,
    this.profilePath,
    this.birthday,
    this.placeOfBirth,
    this.knownForDepartment,
  });
}

class TmdbPersonFilmography {
  final int id;
  final String title;
  final String? posterPath;
  final String? releaseDate;
  final String? mediaType;
  final String? characterOrJob;
  TmdbPersonFilmography({
    required this.id,
    required this.title,
    this.posterPath,
    this.releaseDate,
    this.mediaType,
    this.characterOrJob,
  });
}

class TmdbMovieImages {
  final List<String> posters;
  final List<String> backdrops;
  TmdbMovieImages({required this.posters, required this.backdrops});
}

class TmdbService {
  static const String _apiKey = '8baba8ab6b8bbe247645bcae7df63d0d';
  static String customApiKey = '';
  static String customFanartApiKey = '0604b904d9e0303e83b1029320d91244';

  static String get apiKey => customApiKey.isNotEmpty ? customApiKey : _apiKey;

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

  static Future<TmdbMovieImages> getMovieImages(int tmdbId, {String? imdbId}) async {
    final List<String> posters = [];
    final List<String> backdrops = [];

    try {
      final res = await _dio.get('$_baseUrl/movie/$tmdbId/images', queryParameters: {
        'api_key': apiKey,
        'include_image_language': 'en,null,hi,ta,te,ml',
      });
      final data = res.data;
      if (data != null) {
        final pList = data['posters'] as List? ?? [];
        for (final p in pList) {
          if (p['file_path'] != null) {
            posters.add('$_posterBase${p['file_path']}');
          }
        }
        final bList = data['backdrops'] as List? ?? [];
        for (final b in bList) {
          if (b['file_path'] != null) {
            backdrops.add('$_backdropBase${b['file_path']}');
          }
        }
      }
    } catch (e) {
      debugPrint('TMDB getMovieImages error: $e');
    }

    try {
      final fanartKey = customFanartApiKey.isNotEmpty ? customFanartApiKey : '0604b904d9e0303e83b1029320d91244';
      final res = await _dio.get('https://webservice.fanart.tv/v3/movies/$tmdbId', queryParameters: {
        'api_key': fanartKey,
      });
      final data = res.data;
      if (data != null) {
        final fPosters = data['movieposter'] as List? ?? [];
        for (final fp in fPosters) {
          if (fp['url'] != null && !posters.contains(fp['url'])) {
            posters.add(fp['url'].toString());
          }
        }
        final fBackdrops = data['moviebackground'] as List? ?? [];
        for (final fb in fBackdrops) {
          if (fb['url'] != null && !backdrops.contains(fb['url'])) {
            backdrops.add(fb['url'].toString());
          }
        }
      }
    } catch (_) {}

    return TmdbMovieImages(posters: posters, backdrops: backdrops);
  }

  static Future<List<TmdbMovie>> search(String query) async {
    if (query.isEmpty) return [];
    try {
      final res = await _dio.get('$_baseUrl/search/movie', queryParameters: {'api_key': apiKey, 'query': query});
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
      final res = await _dio.get('$_baseUrl/movie/$id', queryParameters: {'api_key': apiKey, 'append_to_response': 'credits,videos'});
      final data = res.data;
      if (data == null || data['success'] == false) return null;

      final credits = data['credits'] as Map? ?? {};
      final castList = (credits['cast'] as List? ?? []).take(15).map<TmdbCast>((c) => TmdbCast(
        id: c['id'] ?? 0,
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

  static Future<int?> searchPersonId(String name) async {
    if (name.isEmpty) return null;
    try {
      final res = await _dio.get('$_baseUrl/search/person', queryParameters: {'api_key': apiKey, 'query': name});
      final results = res.data?['results'] as List?;
      if (results != null && results.isNotEmpty) {
        return results.first['id'] as int?;
      }
    } catch (e) {
      debugPrint('TMDB searchPersonId error: $e');
    }
    return null;
  }

  static Future<TmdbPersonDetails?> getPersonDetails(int personId) async {
    try {
      final res = await _dio.get('$_baseUrl/person/$personId', queryParameters: {'api_key': apiKey});
      final d = res.data;
      if (d == null) return null;
      return TmdbPersonDetails(
        id: d['id'] ?? personId,
        name: d['name'] ?? '',
        biography: d['biography'],
        profilePath: d['profile_path'] != null ? '$_profileBase${d['profile_path']}' : null,
        birthday: d['birthday'],
        placeOfBirth: d['place_of_birth'],
        knownForDepartment: d['known_for_department'],
      );
    } catch (e) {
      debugPrint('TMDB getPersonDetails error: $e');
      return null;
    }
  }

  static Future<List<TmdbPersonFilmography>> getPersonFilmography(int personId) async {
    try {
      final res = await _dio.get('$_baseUrl/person/$personId/combined_credits', queryParameters: {'api_key': apiKey});
      final data = res.data;
      if (data == null) return [];

      final List<TmdbPersonFilmography> list = [];
      final cast = data['cast'] as List? ?? [];
      final crew = data['crew'] as List? ?? [];

      for (final item in cast) {
        final title = item['title'] ?? item['name'] ?? '';
        if (title.isEmpty) continue;
        list.add(TmdbPersonFilmography(
          id: item['id'] ?? 0,
          title: title,
          posterPath: item['poster_path'] != null ? '$_posterBase${item['poster_path']}' : null,
          releaseDate: item['release_date'] ?? item['first_air_date'],
          mediaType: item['media_type'] ?? 'movie',
          characterOrJob: item['character'],
        ));
      }

      for (final item in crew) {
        if (item['job'] == 'Director') {
          final title = item['title'] ?? item['name'] ?? '';
          if (title.isEmpty) continue;
          final isDup = list.any((e) => e.id == item['id']);
          if (!isDup) {
            list.add(TmdbPersonFilmography(
              id: item['id'] ?? 0,
              title: title,
              posterPath: item['poster_path'] != null ? '$_posterBase${item['poster_path']}' : null,
              releaseDate: item['release_date'] ?? item['first_air_date'],
              mediaType: item['media_type'] ?? 'movie',
              characterOrJob: 'Director',
            ));
          }
        }
      }

      // Sort filmography: latest release date first (descending order)
      list.sort((a, b) {
        final dateA = a.releaseDate ?? '';
        final dateB = b.releaseDate ?? '';
        if (dateA.isEmpty && dateB.isEmpty) return 0;
        if (dateA.isEmpty) return 1;
        if (dateB.isEmpty) return -1;
        return dateB.compareTo(dateA);
      });

      return list;
    } catch (e) {
      debugPrint('TMDB getPersonFilmography error: $e');
      return [];
    }
  }

  static Future<List<String>> getFanartImages(int tmdbId, {String? imdbId, bool isPoster = true}) async {
    final List<String> images = [];
    final List<String> queryIds = [];
    if (tmdbId > 0) queryIds.add(tmdbId.toString());
    if (imdbId != null && imdbId.isNotEmpty && imdbId != '0' && imdbId != 'null') queryIds.add(imdbId);

    for (final id in queryIds) {
      try {
        final res = await _dio.get(
          'https://webservice.fanart.tv/v3/movies/$id',
          options: Options(
            headers: {
              'api-key': '4d1fd752b36b281f62111d4f6c4c9258',
              'Accept': 'application/json',
            },
          ),
          queryParameters: {
            'api_key': '4d1fd752b36b281f62111d4f6c4c9258',
          },
        );
        dynamic data = res.data;
        if (data is String) {
          try { data = jsonDecode(data); } catch (_) {}
        }
        if (data is Map) {
          if (isPoster) {
            final keys = ['movieposter', 'moviethumb', 'moviebanner', 'movieart'];
            for (final k in keys) {
              final list = data[k] as List? ?? [];
              for (final item in list) {
                final url = item['url']?.toString();
                if (url != null && url.startsWith('http') && !images.contains(url)) {
                  images.add(url);
                }
              }
            }
          } else {
            final keys = ['moviebackground', 'hdmovieclearart', 'hdmovielogo', 'movielogo', 'hdmovieart'];
            for (final k in keys) {
              final list = data[k] as List? ?? [];
              for (final item in list) {
                final url = item['url']?.toString();
                if (url != null && url.startsWith('http') && !images.contains(url)) {
                  images.add(url);
                }
              }
            }
          }
          if (images.isNotEmpty) break;
        }
      } catch (e) {
        debugPrint('Fanart API error for id $id: $e');
      }
    }

    if (images.isEmpty && tmdbId > 0) {
      final tmdbImages = await getMovieImages(tmdbId, imdbId: imdbId);
      final fallback = isPoster ? tmdbImages.posters : tmdbImages.backdrops;
      images.addAll(fallback);
    }

    return images;
  }
}
