import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TmdbService {
  static const String apiKey = '8baba8ab6b8bbe247645bcae7df63d0d';
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  static const String _prefSessionId = 'tmdb_session_id';
  static const String _prefAccountId = 'tmdb_account_id';
  static const String _prefUsername = 'tmdb_username';

  static String? _sessionId;
  static String? _accountId;
  static String? _username;

  static final ValueNotifier<bool> isAuthenticated = ValueNotifier(false);
  static final ValueNotifier<String?> currentUsername = ValueNotifier(null);

  /// Initialize TMDB session from SharedPreferences
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionId = prefs.getString(_prefSessionId);
    _accountId = prefs.getString(_prefAccountId);
    _username = prefs.getString(_prefUsername);

    if (_sessionId != null && _sessionId!.isNotEmpty) {
      isAuthenticated.value = true;
      currentUsername.value = _username;
    }
  }

  /// Step 1: Create a new request token for web authorization
  static Future<String?> createRequestToken() async {
    try {
      final url = '$_baseUrl/authentication/token/new?api_key=$apiKey';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['request_token']?.toString();
      }
    } catch (e) {
      debugPrint('TMDB createRequestToken error: $e');
    }
    return null;
  }

  /// Step 2: Convert authorized request token into a persistent session_id
  static Future<bool> createSession(String requestToken) async {
    try {
      final url = '$_baseUrl/authentication/session/new?api_key=$apiKey';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'request_token': requestToken}),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final sid = data['session_id']?.toString();
        if (sid != null && sid.isNotEmpty) {
          _sessionId = sid;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefSessionId, sid);

          // Fetch account details
          await fetchAccountDetails();
          isAuthenticated.value = true;
          return true;
        }
      }
    } catch (e) {
      debugPrint('TMDB createSession error: $e');
    }
    return false;
  }

  /// Fetches the authenticated TMDB user's username & account ID
  static Future<void> fetchAccountDetails() async {
    if (_sessionId == null) return;
    try {
      final url = '$_baseUrl/account?api_key=$apiKey&session_id=$_sessionId';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _username = data['username']?.toString();
        _accountId = data['id']?.toString();

        final prefs = await SharedPreferences.getInstance();
        if (_username != null) await prefs.setString(_prefUsername, _username!);
        if (_accountId != null) await prefs.setString(_prefAccountId, _accountId!);

        currentUsername.value = _username;
      }
    } catch (e) {
      debugPrint('TMDB fetchAccountDetails error: $e');
    }
  }

  /// Logout from TMDB
  static Future<void> logout() async {
    _sessionId = null;
    _accountId = null;
    _username = null;
    isAuthenticated.value = false;
    currentUsername.value = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefSessionId);
    await prefs.remove(_prefAccountId);
    await prefs.remove(_prefUsername);
  }

  /// Fetch user's personal rating for a specific movie on TMDb
  static Future<double?> getUserRating(String tmdbId) async {
    if (_sessionId == null) return null;
    try {
      final url = '$_baseUrl/movie/$tmdbId/account_states?api_key=$apiKey&session_id=$_sessionId';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rated = data['rated'];
        if (rated is Map && rated['value'] != null) {
          return (rated['value'] as num).toDouble();
        }
      }
    } catch (e) {
      debugPrint('TMDB getUserRating error: $e');
    }
    return null;
  }

  /// Post a user rating to TMDb (1.0 - 10.0)
  static Future<bool> rateMovie(String tmdbId, double rating) async {
    if (_sessionId == null) return false;
    try {
      final url = '$_baseUrl/movie/$tmdbId/rating?api_key=$apiKey&session_id=$_sessionId';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json;charset=utf-8'},
        body: jsonEncode({'value': rating.clamp(0.5, 10.0)}),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('TMDB rateMovie error: $e');
      return false;
    }
  }

  /// Delete a rating on TMDb
  static Future<bool> deleteRating(String tmdbId) async {
    if (_sessionId == null) return false;
    try {
      final url = '$_baseUrl/movie/$tmdbId/rating?api_key=$apiKey&session_id=$_sessionId';
      final res = await http.delete(Uri.parse(url));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('TMDB deleteRating error: $e');
      return false;
    }
  }

  /// Mark/Unmark movie as favorite on TMDb
  static Future<bool> markAsFavorite(String tmdbId, bool isFavorite) async {
    if (_sessionId == null) return false;
    try {
      final accountId = _accountId ?? 'account_id';
      final url = '$_baseUrl/account/$accountId/favorite?api_key=$apiKey&session_id=$_sessionId';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json;charset=utf-8'},
        body: jsonEncode({
          'media_type': 'movie',
          'media_id': int.tryParse(tmdbId) ?? tmdbId,
          'favorite': isFavorite,
        }),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('TMDB markAsFavorite error: $e');
      return false;
    }
  }

  /// Add/Remove movie from watchlist on TMDb
  static Future<bool> addToWatchlist(String tmdbId, bool inWatchlist) async {
    if (_sessionId == null) return false;
    try {
      final accountId = _accountId ?? 'account_id';
      final url = '$_baseUrl/account/$accountId/watchlist?api_key=$apiKey&session_id=$_sessionId';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json;charset=utf-8'},
        body: jsonEncode({
          'media_type': 'movie',
          'media_id': int.tryParse(tmdbId) ?? tmdbId,
          'watchlist': inWatchlist,
        }),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('TMDB addToWatchlist error: $e');
      return false;
    }
  }

  /// Fetch full movie details from TMDb
  static Future<Map<String, dynamic>?> getMovieDetails(String tmdbId) async {
    try {
      final url = '$_baseUrl/movie/$tmdbId?api_key=$apiKey&append_to_response=credits,external_ids';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('TMDB getMovieDetails error: $e');
    }
    return null;
  }
}
