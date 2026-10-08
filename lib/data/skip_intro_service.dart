import 'package:shared_preferences/shared_preferences.dart';

class SkipIntroService {
  static const String _keyPrefix = 'skip_intro_sec_';
  static final Map<String, int> _cache = {};
  static bool _initialized = false;

  /// Preload cached skip intro timestamps
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (key.startsWith(_keyPrefix)) {
          final val = prefs.getInt(key);
          if (val != null) {
            _cache[key.substring(_keyPrefix.length)] = val;
          }
        }
      }
      _initialized = true;
    } catch (_) {}
  }

  /// Get skip intro seconds for a movie
  static int? getSkipIntro({String? movieId, String? title, int? modelSkipIntro}) {
    if (modelSkipIntro != null && modelSkipIntro > 0) return modelSkipIntro;
    if (movieId != null && _cache.containsKey(movieId)) {
      return _cache[movieId];
    }
    if (title != null && _cache.containsKey(title.trim().toLowerCase())) {
      return _cache[title.trim().toLowerCase()];
    }
    return null;
  }

  /// Persist skip intro seconds for a movie
  static Future<void> setSkipIntro({
    String? movieId,
    required int seconds,
    String? title,
  }) async {
    final cleanId = movieId?.trim() ?? '';
    final cleanTitle = title?.trim().toLowerCase() ?? '';
    if (cleanId.isNotEmpty) {
      _cache[cleanId] = seconds;
    }
    if (cleanTitle.isNotEmpty) {
      _cache[cleanTitle] = seconds;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (cleanId.isNotEmpty) {
        await prefs.setInt('$_keyPrefix$cleanId', seconds);
      }
      if (cleanTitle.isNotEmpty) {
        await prefs.setInt('$_keyPrefix$cleanTitle', seconds);
      }
    } catch (_) {}
  }

  /// Remove skip intro for a movie
  static Future<void> removeSkipIntro({String? movieId, String? title}) async {
    final cleanId = movieId?.trim() ?? '';
    final cleanTitle = title?.trim().toLowerCase() ?? '';
    if (cleanId.isNotEmpty) _cache.remove(cleanId);
    if (cleanTitle.isNotEmpty) _cache.remove(cleanTitle);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (cleanId.isNotEmpty) await prefs.remove('$_keyPrefix$cleanId');
      if (cleanTitle.isNotEmpty) await prefs.remove('$_keyPrefix$cleanTitle');
    } catch (_) {}
  }

  /// Parses timestamps like "00.45", "00:45", "01.30", "01:30", "45", "45s", "90" into total seconds
  static int? parseTimestamp(dynamic input) {
    if (input == null) return null;
    if (input is int) return input > 0 ? input : null;
    if (input is double) return input.toInt() > 0 ? input.toInt() : null;
    var str = input.toString().trim().toLowerCase();
    if (str.isEmpty) return null;

    // Strip trailing 's' or 'sec' (e.g. "45s", "90sec")
    str = str.replaceAll(RegExp(r'\s*(s|sec|seconds)$'), '').trim();

    // Support both colon ":" and dot "." separators (e.g. 00:45 or 00.45 or 1.30)
    if (str.contains(':') || str.contains('.')) {
      final sep = str.contains(':') ? ':' : '.';
      final parts = str.split(sep);
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]) ?? 0;
        final s = int.tryParse(parts[1]) ?? 0;
        final total = m * 60 + s;
        return total > 0 ? total : null;
      } else if (parts.length == 3) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final s = int.tryParse(parts[2]) ?? 0;
        final total = h * 3600 + m * 60 + s;
        return total > 0 ? total : null;
      }
    }
    final sec = int.tryParse(str);
    return (sec != null && sec > 0) ? sec : null;
  }

  /// Formats seconds (e.g. 90) into "01:30" display string
  static String formatTimestamp(int seconds) {
    if (seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final mStr = m.toString().padLeft(2, '0');
    final sStr = s.toString().padLeft(2, '0');
    return '$mStr:$sStr';
  }
}
