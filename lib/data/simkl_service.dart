import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';
import 'tmdb_service.dart';

class SimklPinResponse {
  final String userCode;
  final String verificationUrl;
  final int expiresIn;
  final int interval;

  SimklPinResponse({
    required this.userCode,
    required this.verificationUrl,
    required this.expiresIn,
    required this.interval,
  });

  factory SimklPinResponse.fromJson(Map<String, dynamic> json) {
    return SimklPinResponse(
      userCode: json['user_code']?.toString() ?? '',
      verificationUrl: json['verification_url']?.toString() ?? '',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 900,
      interval: (json['interval'] as num?)?.toInt() ?? 5,
    );
  }
}

class SimklHistoryItem {
  final Movie movie;
  final DateTime watchedAt;
  final double? userRating;

  SimklHistoryItem({
    required this.movie,
    required this.watchedAt,
    this.userRating,
  });
}

class SimklService {
  // Default SIMKL Client Credentials
  static const String _defaultClientId = '25b906a64ef8139be6e01452174c8b66eec6a9e144d1804f323a6358c279c656';
  static const String _baseUrl = 'https://api.simkl.com';

  static const String _prefClientId = 'simkl_custom_client_id';
  static const String _prefAccessToken = 'simkl_access_token';
  static const String _prefUsername = 'simkl_username';
  static const String _prefAvatar = 'simkl_avatar';

  static String? _customClientId;
  static String? _accessToken;
  static String? _username;
  static String? _avatar;
  static bool _isInitialized = false;

  static String get clientId => _customClientId ?? _defaultClientId;

  static final ValueNotifier<bool> isAuthenticated = ValueNotifier(false);
  static final ValueNotifier<String?> currentUsername = ValueNotifier(null);
  static final ValueNotifier<String?> currentAvatar = ValueNotifier(null);

  /// Initialize SIMKL session on app start
  static Future<void> init() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    _customClientId = prefs.getString(_prefClientId);
    _accessToken = prefs.getString(_prefAccessToken);
    _username = prefs.getString(_prefUsername);
    _avatar = prefs.getString(_prefAvatar);

    if (_accessToken != null && _accessToken!.isNotEmpty) {
      isAuthenticated.value = true;
      currentUsername.value = _username ?? 'SIMKL User';
      currentAvatar.value = _avatar;
    }
    _isInitialized = true;
  }

  /// Save custom SIMKL Client ID
  static Future<void> saveClientId(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return;
    _customClientId = cleanId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefClientId, cleanId);
  }

  static Map<String, String> _headers({bool requireAuth = false}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'simkl-api-key': clientId,
    };
    if (requireAuth && _accessToken != null && _accessToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_accessToken';
    }
    return h;
  }

  // ==========================================
  // PIN AUTHORIZATION (1-CLICK GOOGLE LOGIN)
  // ==========================================

  /// Step 1: Request a user code and verification link (e.g. simkl.com/pin/XXXX)
  static Future<SimklPinResponse?> generatePin() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/oauth/pin?client_id=$clientId'),
        headers: _headers(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return SimklPinResponse.fromJson(data);
      } else {
        debugPrint('SIMKL generatePin response: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('SIMKL generatePin error: $e');
    }
    return null;
  }

  /// Step 2: Poll for user approval at simkl.com/pin
  static Future<bool> checkPin(String userCode) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/oauth/pin/$userCode?client_id=$clientId'),
        headers: _headers(),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['result'] == 'OK' && data['access_token'] != null) {
          final token = data['access_token'].toString();
          await setCustomToken(token);
          return true;
        }
      }
    } catch (e) {
      debugPrint('SIMKL checkPin error: $e');
    }
    return false;
  }

  /// Set token manually or via login
  static Future<bool> setCustomToken(String token) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return false;

    _accessToken = cleanToken;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefAccessToken, cleanToken);
    isAuthenticated.value = true;

    // Fetch user profile
    await fetchUserProfile();
    return true;
  }

  /// Fetch user profile (username, avatar)
  static Future<void> fetchUserProfile() async {
    if (_accessToken == null) return;
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/users/settings'),
        headers: _headers(requireAuth: true),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final user = data['user'] as Map? ?? {};
        _username = user['name']?.toString() ?? 'SIMKL User';
        _avatar = user['avatar']?.toString();

        final prefs = await SharedPreferences.getInstance();
        if (_username != null) await prefs.setString(_prefUsername, _username!);
        if (_avatar != null) await prefs.setString(_prefAvatar, _avatar!);

        currentUsername.value = _username;
        currentAvatar.value = _avatar;
      }
    } catch (e) {
      debugPrint('SIMKL fetchUserProfile error: $e');
    }
  }

  /// Log out from SIMKL
  static Future<void> disconnect() async {
    _accessToken = null;
    _username = null;
    _avatar = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefAccessToken);
    await prefs.remove(_prefUsername);
    await prefs.remove(_prefAvatar);

    isAuthenticated.value = false;
    currentUsername.value = null;
    currentAvatar.value = null;
  }

  // In-memory ratings cache for instant poster rendering
  static final Map<String, double> _cachedRatings = {};

  // ==========================================
  // RATINGS (DUAL SYNC WITH TMDB)
  // ==========================================

  /// Fetch personal user rating for a movie (1 - 10)
  static Future<double?> fetchUserRating({required String tmdbId}) async {
    final cleanId = tmdbId.trim();
    if (cleanId.isEmpty) return null;

    // Check memory cache first
    if (_cachedRatings.containsKey(cleanId)) {
      return _cachedRatings[cleanId];
    }

    if (_accessToken == null) return null;

    // 1. Check completed items (which contains user_rating for all watched movies)
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/sync/all-items/movies/completed?extended=full'),
        headers: _headers(requireAuth: true),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['movies'] as List? ?? [];
        for (final item in list) {
          final m = item['movie'] as Map? ?? {};
          final ids = m['ids'] as Map? ?? {};
          final tId = ids['tmdb']?.toString();
          final userRate = (item['user_rating'] as num?)?.toDouble();
          if (tId != null && userRate != null) {
            _cachedRatings[tId] = userRate;
          }
        }
        if (_cachedRatings.containsKey(cleanId)) {
          return _cachedRatings[cleanId];
        }
      }
    } catch (_) {}

    // 2. Fallback to /sync/ratings/movies
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/sync/ratings/movies'),
        headers: _headers(requireAuth: true),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final movies = data['movies'] as List? ?? [];
        for (final m in movies) {
          final ids = m['movie']?['ids'] as Map? ?? {};
          final tId = ids['tmdb']?.toString();
          final r = (m['rating'] ?? m['user_rating']) as num?;
          if (tId != null && r != null) {
            _cachedRatings[tId] = r.toDouble();
          }
        }
        if (_cachedRatings.containsKey(cleanId)) {
          return _cachedRatings[cleanId];
        }
      }
    } catch (_) {}

    return null;
  }

  /// Submit rating (1 - 10) to SIMKL AND TMDb simultaneously + mark as watched
  static Future<bool> submitRating({required String tmdbId, required int rating, bool isSeries = false}) async {
    bool simklSuccess = false;
    if (_accessToken != null) {
      try {
        final itemKey = isSeries ? 'shows' : 'movies';
        final body = {
          itemKey: [
            {
              'rating': rating,
              'ids': {'tmdb': int.tryParse(tmdbId) ?? tmdbId}
            }
          ]
        };
        final res = await http.post(
          Uri.parse('$_baseUrl/sync/ratings'),
          headers: _headers(requireAuth: true),
          body: jsonEncode(body),
        );
        simklSuccess = res.statusCode == 200 || res.statusCode == 201;

        // Also mark as Completed / Watched in SIMKL history
        await markAsWatched(tmdbId: tmdbId, isSeries: isSeries);
      } catch (e) {
        debugPrint('SIMKL submitRating error: $e');
      }
    }

    // Simultaneously sync to user's TMDb account
    try {
      await TmdbService.rateMovie(tmdbId, rating.toDouble());
    } catch (_) {}

    return simklSuccess;
  }

  // ==========================================
  // WATCHED HISTORY & TIMELINE
  // ==========================================

  /// Mark movie as Completed / Watched
  static Future<bool> markAsWatched({required String tmdbId, bool isSeries = false, DateTime? watchedAt}) async {
    if (_accessToken == null) return false;
    try {
      final itemKey = isSeries ? 'shows' : 'movies';
      final timestamp = (watchedAt ?? DateTime.now().toUtc()).toIso8601String();
      final body = {
        itemKey: [
          {
            'watched_at': timestamp,
            'ids': {'tmdb': int.tryParse(tmdbId) ?? tmdbId}
          }
        ]
      };
      final res = await http.post(
        Uri.parse('$_baseUrl/sync/history'),
        headers: _headers(requireAuth: true),
        body: jsonEncode(body),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('SIMKL markAsWatched error: $e');
      return false;
    }
  }

  static final Map<String, String> _releaseDateCache = {};

  static Future<String?> _getTmdbReleaseDate(String tmdbId) async {
    if (_releaseDateCache.containsKey(tmdbId)) return _releaseDateCache[tmdbId];
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('rel_date_$tmdbId');
      if (cached != null && cached.isNotEmpty) {
        _releaseDateCache[tmdbId] = cached;
        return cached;
      }

      final details = await TmdbService.getMovieDetails(tmdbId);
      final relDate = details?['release_date']?.toString();
      if (relDate != null && relDate.isNotEmpty) {
        _releaseDateCache[tmdbId] = relDate;
        await prefs.setString('rel_date_$tmdbId', relDate);
        return relDate;
      }
    } catch (_) {}
    return null;
  }

  /// Fetch user's Completed / Watched Movies list for Timeline
  static Future<List<SimklHistoryItem>> fetchWatchedTimeline() async {
    if (_accessToken == null) return [];
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/sync/all-items/movies/completed?extended=full'),
        headers: _headers(requireAuth: true),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final moviesList = data['movies'] as List? ?? [];
        final items = <SimklHistoryItem>[];

        await Future.wait(moviesList.map((item) async {
          final m = item['movie'] as Map? ?? {};
          final ids = m['ids'] as Map? ?? {};
          final tmdb = ids['tmdb']?.toString();
          final title = m['title']?.toString() ?? 'Movie';
          final poster = m['poster'] != null ? 'https://simkl.in/posters/${m['poster']}_m.webp' : '';
          final rating = (m['ratings']?['simkl']?['rating'] as num?)?.toDouble() ?? 0.0;
          final userRate = (item['user_rating'] as num?)?.toDouble();

          DateTime releaseDate = DateTime.now();
          if (tmdb != null && tmdb.isNotEmpty && tmdb != '0') {
            final exactRel = await _getTmdbReleaseDate(tmdb);
            if (exactRel != null) {
              releaseDate = DateTime.tryParse(exactRel) ?? releaseDate;
            } else if (m['release_date'] != null) {
              releaseDate = DateTime.tryParse(m['release_date'].toString()) ?? releaseDate;
            } else if (item['last_watched_at'] != null) {
              releaseDate = DateTime.tryParse(item['last_watched_at'].toString()) ?? DateTime.now();
            }
          } else if (m['release_date'] != null) {
            releaseDate = DateTime.tryParse(m['release_date'].toString()) ?? releaseDate;
          } else if (item['last_watched_at'] != null) {
            releaseDate = DateTime.tryParse(item['last_watched_at'].toString()) ?? DateTime.now();
          }

          items.add(SimklHistoryItem(
            movie: Movie(
              id: 'simkl_${ids['simkl'] ?? tmdb}',
              title: title,
              year: releaseDate.year,
              description: m['overview']?.toString() ?? '',
              tmdbId: tmdb,
              genre: 'Watched',
              posterUrl: poster,
              rating: rating,
            ),
            watchedAt: releaseDate,
            userRating: userRate != null ? (userRate / 2.0) : null,
          ));
        }));

        // Sort descending by exact release date
        items.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
        return items;
      }
    } catch (e) {
      debugPrint('SIMKL fetchWatchedTimeline error: $e');
    }
    return [];
  }

  // ==========================================
  // PLAN TO WATCH (WATCHLIST / FAVORITES)
  // ==========================================

  /// Fetch user's Plan to Watch / Watchlist
  static Future<List<Movie>> fetchWatchlist() async {
    if (_accessToken == null) return [];
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/sync/all-items/movies/plantowatch?extended=full'),
        headers: _headers(requireAuth: true),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['movies'] as List? ?? [];
        final movies = <Movie>[];

        for (final item in list) {
          final m = item['movie'] as Map? ?? {};
          final ids = m['ids'] as Map? ?? {};
          final tmdb = ids['tmdb']?.toString();
          final title = m['title']?.toString() ?? 'Movie';
          final year = int.tryParse(m['year']?.toString() ?? '');
          final poster = m['poster'] != null ? 'https://simkl.in/posters/${m['poster']}_m.webp' : '';
          final rating = (m['ratings']?['simkl']?['rating'] as num?)?.toDouble() ?? 0.0;

          movies.add(Movie(
            id: 'simkl_ptw_${ids['simkl'] ?? tmdb}',
            title: title,
            year: year,
            description: m['overview']?.toString() ?? '',
            tmdbId: tmdb,
            genre: 'Plan to Watch',
            posterUrl: poster,
            rating: rating,
          ));
        }
        return movies;
      }
    } catch (e) {
      debugPrint('SIMKL fetchWatchlist error: $e');
    }
    return [];
  }

  /// Add movie to Plan to Watch (Watchlist)
  static Future<bool> addToWatchlist({required String tmdbId, bool isSeries = false}) async {
    if (_accessToken == null) return false;
    try {
      final itemKey = isSeries ? 'shows' : 'movies';
      final body = {
        itemKey: [
          {
            'to': 'plantowatch',
            'ids': {'tmdb': int.tryParse(tmdbId) ?? tmdbId}
          }
        ]
      };
      final res = await http.post(
        Uri.parse('$_baseUrl/sync/add-to-list'),
        headers: _headers(requireAuth: true),
        body: jsonEncode(body),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('SIMKL addToWatchlist error: $e');
      return false;
    }
  }

  /// Remove movie from Watchlist
  static Future<bool> removeFromWatchlist({required String tmdbId, bool isSeries = false}) async {
    if (_accessToken == null) return false;
    try {
      final itemKey = isSeries ? 'shows' : 'movies';
      final body = {
        itemKey: [
          {
            'ids': {'tmdb': int.tryParse(tmdbId) ?? tmdbId}
          }
        ]
      };
      final res = await http.post(
        Uri.parse('$_baseUrl/sync/remove-from-list'),
        headers: _headers(requireAuth: true),
        body: jsonEncode(body),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('SIMKL removeFromWatchlist error: $e');
      return false;
    }
  }

  /// Add movie to Favorites (SIMKL)
  static Future<bool> addToFavorites({required String tmdbId, bool isSeries = false}) async {
    if (_accessToken == null) return false;
    try {
      final itemKey = isSeries ? 'shows' : 'movies';
      final body = {
        itemKey: [
          {
            'to': 'favorites',
            'ids': {'tmdb': int.tryParse(tmdbId) ?? tmdbId}
          }
        ]
      };
      final res = await http.post(
        Uri.parse('$_baseUrl/sync/add-to-list'),
        headers: _headers(requireAuth: true),
        body: jsonEncode(body),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('SIMKL addToFavorites error: $e');
      return false;
    }
  }

  /// Remove movie from Favorites (SIMKL)
  static Future<bool> removeFromFavorites({required String tmdbId, bool isSeries = false}) async {
    if (_accessToken == null) return false;
    try {
      final itemKey = isSeries ? 'shows' : 'movies';
      final body = {
        itemKey: [
          {
            'ids': {'tmdb': int.tryParse(tmdbId) ?? tmdbId}
          }
        ]
      };
      final res = await http.post(
        Uri.parse('$_baseUrl/sync/remove-from-list'),
        headers: _headers(requireAuth: true),
        body: jsonEncode(body),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('SIMKL removeFromFavorites error: $e');
      return false;
    }
  }
}
