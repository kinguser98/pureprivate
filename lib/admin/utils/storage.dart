import 'package:hive_flutter/hive_flutter.dart';
import '../models/movie.dart';
import '../models/iptv_channel.dart';
import '../models/language.dart';
import '../models/user.dart';

class Storage {
  static const String _moviesBoxName = 'movies_cache';
  static const String _channelsBoxName = 'channels_cache';
  static const String _settingsBoxName = 'app_settings';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(MovieAdapter());
    Hive.registerAdapter(IptvChannelAdapter());
    Hive.registerAdapter(LanguageAdapter());
    Hive.registerAdapter(UserAdapter());
  }

  // Movies Cache
  static Future<Box<Movie>> get _moviesBox async => await Hive.openBox<Movie>(_moviesBoxName);

  static Future<void> cacheMovies(List<Movie> movies) async {
    final box = await _moviesBox;
    await box.clear();
    for (final movie in movies) {
      await box.put(movie.id, movie);
    }
  }

  static Future<List<Movie>> getCachedMovies() async {
    final box = await _moviesBox;
    return box.values.toList();
  }

  static Future<Movie?> getCachedMovie(int id) async {
    final box = await _moviesBox;
    return box.get(id);
  }

  // Channels Cache
  static Future<Box<IptvChannel>> get _channelsBox async => await Hive.openBox<IptvChannel>(_channelsBoxName);

  static Future<void> cacheChannels(List<IptvChannel> channels) async {
    final box = await _channelsBox;
    await box.clear();
    for (final channel in channels) {
      await box.put(channel.id, channel);
    }
  }

  static Future<List<IptvChannel>> getCachedChannels() async {
    final box = await _channelsBox;
    return box.values.toList();
  }

  // App Settings
  static Future<Box<String>> get _settingsBox async => await Hive.openBox<String>(_settingsBoxName);

  static Future<void> saveSetting(String key, String value) async {
    final box = await _settingsBox;
    await box.put(key, value);
  }

  static Future<String?> getSetting(String key) async {
    final box = await _settingsBox;
    return box.get(key);
  }

  static Future<Map<String, String>> getAllSettings() async {
    final box = await _settingsBox;
    final map = <String, String>{};
    for (final key in box.keys) {
      final value = box.get(key);
      if (value != null) {
        map[key] = value;
      }
    }
    return map;
  }

  // Auth
  static Future<void> saveToken(String token) async {
    final box = await _settingsBox;
    await box.put('auth_token', token);
  }

  static Future<String?> getToken() async {
    final box = await _settingsBox;
    return box.get('auth_token');
  }

  static Future<void> clearAuth() async {
    final box = await _settingsBox;
    await box.delete('auth_token');
  }

  // Clear all caches
  static Future<void> clearAll() async {
    await Hive.deleteBoxFromDisk(_moviesBoxName);
    await Hive.deleteBoxFromDisk(_channelsBoxName);
    await Hive.deleteBoxFromDisk(_settingsBoxName);
  }
}
