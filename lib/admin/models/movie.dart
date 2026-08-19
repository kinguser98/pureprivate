import 'dart:convert';
import 'package:hive/hive.dart';

part 'movie.g.dart';

@HiveType(typeId: 0)
class Movie {
  @HiveField(0) final int id;
  @HiveField(1) final String title;
  @HiveField(2) final String posterUrl;
  @HiveField(3) final String? backdropUrl;
  @HiveField(4) final int views;
  @HiveField(5) final String genre;
  @HiveField(6) final String? releaseDate;
  @HiveField(7) final String? description;
  @HiveField(8) final String? streamUrl;
  @HiveField(9) final String? qualityTag;
  @HiveField(10) final int languageId;
  @HiveField(11) final String? cast;
  @HiveField(12) final String? director;
  @HiveField(13) final String? trailerUrl;
  @HiveField(14) final String? collection;
  @HiveField(15) final String? ottName;
  @HiveField(16) final String? ottLogo;
  @HiveField(17) final String? streamSources;
  @HiveField(18) final String? createdAt;
  @HiveField(19) final String? streamStatus;
  @HiveField(20) final String? lastChecked;
  @HiveField(21) final String? tmdbId;
  @HiveField(22) final String? imdbId;
  @HiveField(23) final String? castPhotos;
  @HiveField(24) final String? directorPhoto;
  @HiveField(25) final String? runtime;
  @HiveField(26) final int ottId;
  @HiveField(27) final String? logoUrl;

  Movie({
    required this.id,
    required this.title,
    required this.posterUrl,
    this.backdropUrl,
    this.views = 0,
    this.genre = '',
    this.releaseDate,
    this.description,
    this.streamUrl,
    this.qualityTag,
    this.languageId = 0,
    this.cast,
    this.director,
    this.trailerUrl,
    this.collection,
    this.ottName,
    this.ottLogo,
    this.streamSources,
    this.createdAt,
    this.streamStatus,
    this.lastChecked,
    this.tmdbId,
    this.imdbId,
    this.castPhotos,
    this.directorPhoto,
    this.runtime,
    this.ottId = 0,
    this.logoUrl,
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    int _parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    String _parseString(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      if (value is num || value is bool) return value.toString();
      if (value is List || value is Map) return value.toString();
      return '';
    }

    String _parseStreamSources(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      if (value is List) {
        try {
          return jsonEncode(value);
        } catch (_) {
          return value.toString();
        }
      }
      return value.toString();
    }

    return Movie(
      id: _parseInt(json['id']),
      title: _parseString(json['title']),
      posterUrl: _parseString(json['poster_url']),
      backdropUrl: _parseString(json['backdrop_url']),
      views: _parseInt(json['views']),
      genre: _parseString(json['genre']),
      releaseDate: _parseString(json['release_date']),
      description: _parseString(json['description']),
      streamUrl: _parseString(json['stream_url']),
      qualityTag: _parseString(json['quality_tag']),
      languageId: _parseInt(json['language_id']),
      cast: _parseString(json['cast']),
      director: _parseString(json['director']),
      trailerUrl: _parseString(json['trailer_url']),
      collection: _parseString(json['collection']),
      ottName: _parseString(json['ott_name']),
      ottLogo: _parseString(json['ott_logo']),
      streamSources: _parseStreamSources(json['stream_sources']),
      createdAt: _parseString(json['created_at']),
      streamStatus: _parseString(json['stream_status']),
      lastChecked: _parseString(json['last_checked']),
      tmdbId: _parseString(json['tmdb_id']),
      imdbId: _parseString(json['imdb_id']),
      castPhotos: _parseString(json['cast_photos']),
      directorPhoto: _parseString(json['director_photo']),
      runtime: _parseString(json['runtime']),
      ottId: _parseInt(json['ott_id']),
      logoUrl: _parseString(json['logo_url']),
    );
  }

  bool get isBroken => streamStatus == 'broken';

  @override
  String toString() => 'Movie(id: $id, title: $title)';
}
