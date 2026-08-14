import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:private_cinema_mobile/models/movie.dart';
import 'package:private_cinema_mobile/models/language_item.dart';
import 'package:private_cinema_mobile/data/playback_tracker.dart';
import 'package:private_cinema_mobile/data/dio_client.dart';
import 'package:dio/dio.dart' as dio_pkg;

class ApiService {
  static const String apiUrl = 'https://ott.goprivate.fun/api.php';
  static Map<String, String> _langMap = {};

  static String _capitalize(String name) {
    if (name.isEmpty) return '';
    return name[0].toUpperCase() + name.substring(1).toLowerCase();
  }

  static Map<String, String> _buildLanguageMap(List<dynamic>? rawLanguages) {
    final Map<String, String> map = {};
    if (rawLanguages != null) {
      for (final lang in rawLanguages) {
        final id = lang['id']?.toString();
        final name = lang['name']?.toString() ?? '';
        if (id != null && name.isNotEmpty) {
          map[id] = _capitalize(name);
        }
      }
    }
    return map;
  }

  /// Fetches raw JSON data from the OTT admin panel API using persistent Dio client.
  static Future<Map<String, dynamic>> fetchRawData() async {
    int attempts = 0;
    const maxAttempts = 3;
    final backoffs = [1500, 3000];
    final client = DioClient().dio;

    while (attempts < maxAttempts) {
      attempts++;
      try {
        final response = await client.get<dynamic>(
          apiUrl,
          options: dio_pkg.Options(
            responseType: dio_pkg.ResponseType.json,
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
        if (response.statusCode == 200) {
          final data = response.data;
          if (data is Map<String, dynamic>) {
            return data;
          } else if (data is String) {
            return json.decode(data) as Map<String, dynamic>;
          }
          throw Exception('Unexpected response payload type: ${data.runtimeType}');
        } else if (response.statusCode == 429) {
          if (attempts < maxAttempts) {
            final delay = backoffs[attempts - 1];
            debugPrint('API fetchRawData rate-limited (429). Retrying in ${delay}ms...');
            await Future.delayed(Duration(milliseconds: delay));
            continue;
          }
          throw Exception('HTTP Error 429 (Too Many Requests)');
        } else {
          throw Exception('HTTP Error: ${response.statusCode}');
        }
      } catch (e) {
        if (attempts >= maxAttempts) {
          throw Exception('Fetch error after $maxAttempts attempts: $e');
        }
        final delay = backoffs[attempts - 1];
        debugPrint('API fetchRawData error ($e). Retrying in ${delay}ms...');
        await Future.delayed(Duration(milliseconds: delay));
      }
    }
    throw Exception('Fetch error');
  }

  /// Parses the JSON movies list into Movie models with deterministic fallbacks.
  static List<Movie> parseMovies(List<dynamic> jsonList, [List<dynamic>? rawLanguages]) {
    if (rawLanguages != null) {
      _langMap = _buildLanguageMap(rawLanguages);
    }
    
    // Find the maximum ID in the catalogue to determine recency (newly added)
    int maxId = 0;
    for (final json in jsonList) {
      final idVal = int.tryParse(json['id']?.toString() ?? '') ?? 0;
      if (idVal > maxId) maxId = idVal;
    }

    return jsonList.map((json) {
      final idStr = json['id']?.toString() ?? '0';
      final idInt = int.tryParse(idStr) ?? 0;
      
      final title = json['title']?.toString() ?? 'Untitled Cinema';
      final posterUrl = json['poster_url']?.toString() ?? '';
      final backdropUrl = json['backdrop_url']?.toString() ?? '';
      
      // Release year parsing
      final releaseDate = json['release_date']?.toString() ?? '';
      final year = int.tryParse(releaseDate.split('-').first) ?? 2026;
      
      // Parse genres
      final genreStr = json['genre']?.toString() ?? 'Drama';
      final tags = genreStr.split(',').map((g) => g.trim()).toList();
      final primaryGenre = tags.isNotEmpty ? tags.first : 'Drama';
      
      // Map language based on language_id (1 = Tamil, 2 = Malayalam, 3 = Hindi)
      final langId = json['language_id']?.toString() ?? '2';
      String language = _langMap[langId] ?? (langId == '1' ? 'Tamil' : (langId == '3' ? 'Hindi' : 'Malayalam'));
      
      final streamUrl = json['stream_url']?.toString() ?? '';
      final trailerUrl = json['trailer_url']?.toString() ?? '';
      final description = json['description']?.toString() ?? 
          'Enjoy high-quality streaming of $title, now playing on your GoXio.';
      
      // 1. Deterministic premium rating (7.5 to 9.5)
      final rating = 7.5 + ((idInt * 17) % 20) / 10.0;
      
      // 2. Deterministic runtime (90 to 165 minutes)
      final totalMinutes = 90 + ((idInt * 31) % 76);
      final runtime = '${totalMinutes ~/ 60}h ${totalMinutes % 60}m';
      
      // 3. Deterministic content rating
      final ratingPool = ['PG-13', 'UA', 'R', 'TV-MA'];
      final contentRating = ratingPool[(idInt * 13) % ratingPool.length];
      
      // 4. Deterministic dark theme color
      final titleHash = title.hashCode;
      final r = 10 + (titleHash.abs() % 35);
      final g = 10 + ((titleHash.abs() >> 8) % 35);
      final b = 10 + ((titleHash.abs() >> 16) % 35);
      final posterColor = Color.fromARGB(255, r, g, b);
      
      // Parse tmdb_id
      final tmdbId = json['tmdb_id']?.toString();
      // Parse imdb_id
      final imdbId = json['imdb_id']?.toString();
      // Parse collection
      final collection = json['collection']?.toString();

      // Parse actual cast and cast photos from database
      final List<CastMember> dbCastMembers = [];
      final castStr = json['cast']?.toString() ?? '';
      final castPhotosStr = json['cast_photos']?.toString() ?? '';
      
      if (castStr.isNotEmpty) {
        final names = castStr.split(',').map((s) => s.trim()).toList();
        final photos = castPhotosStr.split(',').map((s) => s.trim()).toList();
        
        for (int i = 0; i < names.length; i++) {
          final name = names[i];
          final photoUrl = i < photos.length ? photos[i] : '';
          dbCastMembers.add(CastMember(name: name, profileUrl: photoUrl));
        }
      }

      // Parse stream_sources
      final List<StreamSource> streamSources = [];
      final rawSources = json['stream_sources'];
      if (rawSources is List) {
        for (final src in rawSources) {
          if (src is Map) {
            final name = src['name']?.toString() ?? 'Server';
            final url = src['url']?.toString() ?? '';
            final seeders = src['seeders'] != null ? int.tryParse(src['seeders'].toString()) : null;
            final peers = src['peers'] != null ? int.tryParse(src['peers'].toString()) : null;
            if (url.isNotEmpty) {
              streamSources.add(StreamSource(
                name: name,
                url: url,
                seeders: seeders,
                peers: peers,
              ));
            }
          }
        }
      }
      
      // Fallback if streamSources is empty but streamUrl is not
      if (streamSources.isEmpty && streamUrl.isNotEmpty) {
        streamSources.add(StreamSource(name: 'Default Server', url: streamUrl));
      }

      // Fallback to deterministic cast if DB cast is empty
      final castMembers = dbCastMembers.isNotEmpty 
          ? dbCastMembers 
          : _getDeterministicCast(langId, idInt);
      
      // 6. Director & photo from DB (fallback to deterministic if not set)
      final director = json['director']?.toString().isNotEmpty == true
          ? json['director']!.toString()
          : _getDeterministicDirector(langId, idInt);

      final directorPhoto = json['director_photo']?.toString().isNotEmpty == true
          ? json['director_photo']!.toString()
          : null;

      // Determine if movie is released in the last 7 days or has recent database insert ID
      bool isRecentlyAdded = idInt >= maxId - 15;
      try {
        if (releaseDate.isNotEmpty) {
          final parsedDate = DateTime.tryParse(releaseDate);
          if (parsedDate != null) {
            final now = DateTime.now();
            final difference = now.difference(parsedDate).inDays;
            if (difference >= 0 && difference <= 7) {
              isRecentlyAdded = true;
            }
          }
        }
      } catch (_) {}

      return Movie(
        id: idStr,
        title: title,
        genre: primaryGenre,
        rating: rating,
        posterUrl: posterUrl,
        backdropUrl: backdropUrl.isNotEmpty ? backdropUrl : posterUrl,
        description: description,
        posterColor: posterColor,
        year: year,
        runtime: runtime,
        contentRating: contentRating,
        tags: tags,
        cast: castMembers.map((c) => c.name).toList(),
        director: director,
        directorPhoto: directorPhoto,
        videoSource: streamUrl,
        trailerUrl: trailerUrl,
        castMembers: castMembers,
        language: language,
        tmdbId: tmdbId,
        imdbId: imdbId,
        streamSources: streamSources,
        collection: collection,
        isNew: isRecentlyAdded,
        // OTT provider fields
        ottName: json['ott_name']?.toString(),
        ottLogo: json['ott_logo']?.toString(),
        ottId: json['ott_id'] != null ? int.tryParse(json['ott_id'].toString()) : null,
      );
    }).toList();
  }

  /// Parses the JSON languages list, adding English and Other fallbacks.
  static List<LanguageItem> parseLanguages(List<dynamic> jsonList) {
    _langMap = _buildLanguageMap(jsonList);
    final List<LanguageItem> result = [];
    
    // Map of name -> details (gradient values)
    final Map<String, LinearGradient> gradientMap = {
      'TAMIL': const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF5E2A0F), Color(0xFF2E1305)],
      ),
      'MALAYALAM': const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0F3A20), Color(0xFF071B10)],
      ),
      'HINDI': const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF4A1035), Color(0xFF230518)],
      ),
      'ENGLISH': const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0F2C4A), Color(0xFF071424)],
      ),
    };

    bool hasEnglish = false;

    for (final json in jsonList) {
      final rawName = json['name']?.toString() ?? '';
      if (rawName.isEmpty) continue;
      
      final nameUpper = rawName.toUpperCase();
      final capitalized = _capitalize(rawName);

      if (nameUpper == 'ENGLISH') {
        hasEnglish = true;
      }
      
      final displayName = '$capitalized Movies';
      final filterValue = capitalized;
      
      result.add(LanguageItem(
        name: displayName,
        filterValue: filterValue,
        backdropUrl: json['image_url']?.toString() ?? '',
        gradient: gradientMap[nameUpper] ?? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF333333), Color(0xFF1E1E1E)],
        ),
      ));
    }
    
    // Always append English fallback at the end ONLY if it wasn't in the database list
    if (!hasEnglish) {
      result.add(const LanguageItem(
        name: 'English Movies',
        filterValue: 'English',
        backdropUrl: 'https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?w=600&auto=format&fit=crop',
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F2C4A), Color(0xFF071424)],
        ),
      ));
    }
    
    // Always append Other movies
    result.add(const LanguageItem(
      name: 'Other Movies',
      filterValue: 'Other',
      backdropUrl: 'https://images.unsplash.com/photo-1535320903710-d993d3d77d29?w=600&auto=format&fit=crop',
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3A3A3A), Color(0xFF1E1E1E)],
      ),
    ));

    return result;
  }

  static List<CastMember> _getDeterministicCast(String langId, int movieId) {
    const tamilCast = [
      CastMember(name: 'Vijay', profileUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150'),
      CastMember(name: 'Suriya', profileUrl: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=150'),
      CastMember(name: 'Dhanush', profileUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150'),
      CastMember(name: 'Vijay Sethupathi', profileUrl: 'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=150'),
      CastMember(name: 'Nayanthara', profileUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150'),
      CastMember(name: 'Trisha Krishnan', profileUrl: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=150'),
    ];
    const malayalamCast = [
      CastMember(name: 'Mohanlal', profileUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150'),
      CastMember(name: 'Mammootty', profileUrl: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=150'),
      CastMember(name: 'Fahadh Faasil', profileUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150'),
      CastMember(name: 'Dulquer Salmaan', profileUrl: 'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=150'),
      CastMember(name: 'Prithviraj Sukumaran', profileUrl: 'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=150'),
      CastMember(name: 'Manju Warrier', profileUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150'),
    ];
    const hindiCast = [
      CastMember(name: 'Shah Rukh Khan', profileUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150'),
      CastMember(name: 'Aamir Khan', profileUrl: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=150'),
      CastMember(name: 'Ranbir Kapoor', profileUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150'),
      CastMember(name: 'Alia Bhatt', profileUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150'),
      CastMember(name: 'Deepika Padukone', profileUrl: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=150'),
      CastMember(name: 'Ranveer Singh', profileUrl: 'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=150'),
    ];

    final List<CastMember> selectedPool;
    if (langId == '1') {
      selectedPool = tamilCast;
    } else if (langId == '2') {
      selectedPool = malayalamCast;
    } else if (langId == '3') {
      selectedPool = hindiCast;
    } else {
      selectedPool = malayalamCast;
    }

    final List<CastMember> cast = [];
    final List<int> indices = [0, 1, 2, 3, 4, 5];
    int state = movieId;
    for (int i = 0; i < 4; i++) {
      state = (state * 33 + 7).abs() % indices.length;
      final idx = indices.removeAt(state);
      cast.add(selectedPool[idx]);
    }
    return cast;
  }

  static String _getDeterministicDirector(String langId, int movieId) {
    final directors = {
      '1': ['Lokesh Kanagaraj', 'Atlee', 'Vetri Maaran', 'Mani Ratnam', 'Sudha Kongara'],
      '2': ['Jeethu Joseph', 'Amal Neerad', 'Lijo Jose Pellissery', 'Basil Joseph', 'Dileesh Pothan'],
      '3': ['Anurag Kashyap', 'Rajkumar Hirani', 'Sanjay Leela Bhansali', 'Karan Johar', 'Zoya Akhtar'],
    };
    final list = directors[langId] ?? directors['2']!;
    return list[movieId.abs() % list.length];
  }

  /// Toggles favorite status in the cloud. Returns whether it is favorited.
  static Future<bool> toggleFavoriteCloud(String movieId) async {
    try {
      final deviceId = await PlaybackTracker.getOrCreateDeviceId();
      final uri = Uri.parse('$apiUrl?action=toggle_favorite');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'},
        body: {'movie_id': movieId, 'device_id': deviceId},
      ).timeout(const Duration(seconds: 4));
      
      if (response.statusCode == 200) {
        final jsonString = utf8.decode(response.bodyBytes);
        final data = json.decode(jsonString) as Map<String, dynamic>;
        return data['is_favorite'] == true;
      }
    } catch (e) {
      print('Cloud toggle favorite failed: $e');
    }
    return false;
  }

  /// Checks if a movie is favorited in the cloud.
  static Future<bool> checkFavoriteCloud(String movieId) async {
    try {
      final deviceId = await PlaybackTracker.getOrCreateDeviceId();
      final uri = Uri.parse('$apiUrl?action=check_favorite&movie_id=$movieId&device_id=$deviceId');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final jsonString = utf8.decode(response.bodyBytes);
        final data = json.decode(jsonString) as Map<String, dynamic>;
        return data['is_favorite'] == true;
      }
    } catch (e) {
      print('Cloud check favorite failed: $e');
    }
    return false;
  }

  /// Fetches the favorites list from the cloud.
  static Future<List<Movie>> fetchFavoritesCloud() async {
    try {
      final deviceId = await PlaybackTracker.getOrCreateDeviceId();
      final uri = Uri.parse('$apiUrl?action=get_favorites&device_id=$deviceId');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final jsonString = utf8.decode(response.bodyBytes);
        final rawList = json.decode(jsonString) as List<dynamic>;
        return parseMovies(rawList);
      }
    } catch (e) {
      print('Cloud fetch favorites failed: $e');
    }
    return [];
  }

  /// Fetches Stalker VOD categories from the backend database.
  static Future<List<Map<String, dynamic>>> fetchStalkerVodCategories() async {
    try {
      final uri = Uri.parse('$apiUrl?action=get_stalker_vod_categories');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final jsonString = utf8.decode(response.bodyBytes);
        final rawList = json.decode(jsonString);
        if (rawList is List) {
          return rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('Fetch Stalker VOD categories failed: $e');
    }
    return [
      {'category_id': 'all', 'name': 'All Stalker VOD'},
    ];
  }

  /// Fetches Stalker VOD catalog with full metadata (posters, description, ratings).
  static Future<List<Movie>> fetchStalkerVodCatalog({
    String? categoryId,
    String? search,
    int page = 1,
    int limit = 100,
  }) async {
    try {
      final queryParams = <String, String>{
        'action': 'get_stalker_vod_movies',
        'page': page.toString(),
        'limit': limit.toString(),
      };
      if (categoryId != null && categoryId != 'all' && categoryId != 'home') {
        queryParams['category'] = categoryId;
      }
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      final uri = Uri.parse(apiUrl).replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final jsonString = utf8.decode(response.bodyBytes);
        final data = json.decode(jsonString);
        List<dynamic> rawList = [];
        if (data is List) {
          rawList = data;
        } else if (data is Map && data['movies'] is List) {
          rawList = data['movies'];
        }
        return parseMovies(rawList);
      }
    } catch (e) {
      debugPrint('Fetch Stalker VOD catalog failed: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> fetchStalkerVodHome() async {
    try {
      final uri = Uri.parse('$apiUrl?action=get_stalker_vod_home');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final jsonString = utf8.decode(response.bodyBytes);
        final data = json.decode(jsonString);
        if (data is List) {
          final List<Map<String, dynamic>> result = [];
          for (final item in data) {
            if (item is Map) {
              final catId = item['category_id']?.toString() ?? '';
              final name = item['name']?.toString() ?? catId;
              final rawMovies = item['movies'] as List<dynamic>? ?? [];
              final movies = parseMovies(rawMovies);
              if (catId.isNotEmpty && movies.isNotEmpty) {
                result.add({
                  'category_id': catId,
                  'name': name,
                  'movies': movies,
                });
              }
            }
          }
          return result;
        }
      }
    } catch (e) {
      debugPrint('Fetch Stalker VOD Home failed: $e');
    }
    return [];
  }
}

