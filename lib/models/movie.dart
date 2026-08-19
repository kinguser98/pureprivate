import 'package:flutter/material.dart';

class CastMember {
  const CastMember({required this.name, required this.profileUrl});
  final String name;
  final String profileUrl;
}

class StreamSource {
  const StreamSource({
    required this.name,
    required this.url,
    this.seeders,
    this.peers,
    this.headers,
    this.quality,
    this.qualityBadgeColor,
    this.qualityBadgeText,
  });
  final String name;
  final String url;
  final int? seeders;
  final int? peers;
  final Map<String, String>? headers;
  final String? quality;
  final Color? qualityBadgeColor;
  final String? qualityBadgeText;
}

class Movie {
  const Movie({
    required this.id,
    required this.title,
    required this.genre,
    required this.rating,
    required this.posterUrl,
    this.backdropUrl,
    this.description,
    this.watchProgress,
    this.posterColor,
    this.year,
    this.runtime,
    this.contentRating,
    this.tags = const [],
    this.cast = const [],
    this.director,
    this.directorPhoto,
    this.videoSource,
    this.trailerUrl,
    this.castMembers = const [],
    this.language,
    this.tmdbId,
    this.imdbId,
    this.streamSources = const [],
    this.collection,
    this.isNew = false,
    // OTT provider fields
    this.ottName,
    this.ottLogo,
    this.ottId,
    this.logoUrl,
  });

  final String id;
  final String title;
  final String genre;
  final double rating;
  final String posterUrl;
  final String? backdropUrl;
  final String? description;
  final double? watchProgress;
  final Color? posterColor;
  final int? year;
  final String? runtime;
  final String? contentRating;
  final List<String> tags;
  final List<String> cast;
  final String? director;
  final String? directorPhoto;
  final String? videoSource;
  final String? trailerUrl;
  final List<CastMember> castMembers;
  final String? language;
  final String? tmdbId;
  final String? imdbId;
  final List<StreamSource> streamSources;
  final String? collection;
  final bool isNew;
  
  // OTT provider fields
  final String? ottName;
  final String? ottLogo;
  final int? ottId;
  final String? logoUrl;

  String get displayBackdrop => backdropUrl ?? posterUrl;
}
