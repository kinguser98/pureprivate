import 'movie.dart';

class DashboardStats {
  final int totalMovies;
  final int totalViews;
  final int brokenStreams;
  final int iptvChannelsTotal;
  final int iptvChannelsEnabled;
  final int iptvPortals;
  final int iptvVodsTotal;
  final double dbSize;
  final List<Movie> topMovies;
  final List<Movie> recentMovies;
  final List<Movie> brokenMovies;
  final Map<String, int> languageDistribution;
  final Map<String, int> genreDistribution;

  DashboardStats({
    required this.totalMovies,
    required this.totalViews,
    required this.brokenStreams,
    required this.iptvChannelsTotal,
    required this.iptvChannelsEnabled,
    required this.iptvPortals,
    required this.iptvVodsTotal,
    required this.dbSize,
    required this.topMovies,
    required this.recentMovies,
    required this.brokenMovies,
    this.languageDistribution = const {},
    this.genreDistribution = const {},
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalMovies: json['total_movies'] ?? 0,
      totalViews: json['total_views'] ?? 0,
      brokenStreams: json['total_broken'] ?? 0,
      iptvChannelsTotal: json['iptv_channels_total'] ?? 0,
      iptvChannelsEnabled: json['iptv_channels_enabled'] ?? 0,
      iptvPortals: json['iptv_portals'] ?? 0,
      iptvVodsTotal: json['iptv_vods_total'] ?? 0,
      dbSize: (json['db_size'] as num?)?.toDouble() ?? 0.0,
      topMovies: (json['top_movies'] as List?)?.map((e) => Movie.fromJson(e)).toList() ?? [],
      recentMovies: (json['recent_movies'] as List?)?.map((e) => Movie.fromJson(e)).toList() ?? [],
      brokenMovies: (json['broken_movies'] as List?)?.map((e) => Movie.fromJson(e)).toList() ?? [],
    );
  }

  int get avgViews => totalMovies > 0 ? (totalViews / totalMovies).round() : 0;
  
  double get brokenPercentage => totalMovies > 0 ? (brokenStreams / totalMovies) : 0;
  
  double get iptvEnabledPercentage => iptvChannelsTotal > 0 ? (iptvChannelsEnabled / iptvChannelsTotal) : 0;
}

class LanguageStats {
  final String name;
  final int views;

  LanguageStats({required this.name, required this.views});

  factory LanguageStats.fromJson(Map<String, dynamic> json) {
    return LanguageStats(
      name: json['name'] ?? '',
      views: json['views'] ?? 0,
    );
  }
}

class GenreStats {
  final String genre;
  final int views;

  GenreStats({required this.genre, required this.views});

  factory GenreStats.fromJson(Map<String, dynamic> json) {
    return GenreStats(
      genre: json['genre'] ?? '',
      views: json['views'] ?? 0,
    );
  }
}
