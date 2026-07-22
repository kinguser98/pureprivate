import 'package:flutter/material.dart';
import 'package:private_cinema_ios/models/movie.dart';

abstract final class MockCatalog {
  static const demoMp4Video =
      'https://useful-shandie-redinfinity-84f5dec0.koyeb.app/d/OneDrive/Public/HDmovie99.My-Thai.Massage.Resmi-Uncut99.Com.mp4';

  static const demoMkvVideo =
      'https://useful-shandie-redinfinity-84f5dec0.koyeb.app/d/OneDrive/Public/Movies/%40CC_New.A1.Accused.No.1.2019.Tamil.HDTVRip.x264.500MB.mkv';

  static List<Movie> allMovies = <Movie>[
    _detail(
      id: 'houses-dragons',
      title: 'HOUSES & DRAGONS',
      genre: 'Fantasy',
      rating: 8.9,
      poster: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=600&auto=format&fit=crop',
      backdrop: 'https://images.unsplash.com/photo-1599733589046-9b8308b5b50d?w=1200&auto=format&fit=crop',
      color: const Color(0xFF5A1A1A),
      year: 2029,
      runtime: '1h',
      language: 'English',
      videoSource: demoMp4Video,
      trailerUrl: 'https://www.youtube.com/watch?v=DotnJ7tTA34',
      ottName: 'Amazon Prime',
      ottLogo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/Amazon_Prime_Video_logo.svg/185px-Amazon_Prime_Video_logo.svg.png',
    ),
    _detail(
      id: 'last-of-us',
      title: 'THE LAST OF US',
      genre: 'Drama',
      rating: 8.8,
      poster: 'https://images.unsplash.com/photo-1536440136628-849c177e76a1?w=600&auto=format&fit=crop',
      backdrop: 'https://images.unsplash.com/photo-1448375240586-882707db888b?w=1200&auto=format&fit=crop',
      color: const Color(0xFF3D4F3A),
      year: 2023,
      runtime: '1h 20m',
      language: 'English',
      videoSource: demoMkvVideo,
      trailerUrl: 'https://www.youtube.com/watch?v=uLtkt8BonwM',
      ottName: 'JioHotstar',
      ottLogo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/1/1e/Disney%2B_Hotstar_logo.svg/185px-Disney%2B_Hotstar_logo.svg.png',
    ),
    _detail(
      id: 'premalu',
      title: 'PREMALU',
      genre: 'Romance',
      rating: 8.5,
      poster: 'https://images.unsplash.com/photo-1512820790803-83ca734da794?w=600&auto=format&fit=crop',
      backdrop: 'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=1200&auto=format&fit=crop',
      color: const Color(0xFF6B4226),
      year: 2024,
      runtime: '2h 36m',
      language: 'Malayalam',
      videoSource: demoMp4Video,
      trailerUrl: 'https://www.youtube.com/watch?v=r8Z5Lue_g2U',
      ottName: 'Netflix',
      ottLogo: 'https://assets.nflxext.com/us/ffe/siteui/common/icons/nficon2016.png',
    ),
    _detail(
      id: 'manjummel-boys',
      title: 'MANJUMMEL BOYS',
      genre: 'Thriller',
      rating: 8.8,
      poster: 'https://images.unsplash.com/photo-1501555088652-021faa106b9b?w=600&auto=format&fit=crop',
      backdrop: 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=1200&auto=format&fit=crop',
      color: const Color(0xFF1B3B32),
      year: 2024,
      runtime: '2h 15m',
      language: 'Malayalam',
      videoSource: demoMp4Video,
      trailerUrl: 'https://www.youtube.com/watch?v=Y81i_j5CszE',
      ottName: 'SonyLiv',
      ottLogo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/58/SonyLIV_logo.svg/185px-SonyLIV_logo.svg.png',
    ),
    _detail(
      id: 'vikram',
      title: 'VIKRAM',
      genre: 'Action',
      rating: 8.7,
      poster: 'https://images.unsplash.com/photo-1509198397868-475647b2a1e5?w=600&auto=format&fit=crop',
      backdrop: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=1200&auto=format&fit=crop',
      color: const Color(0xFF2E4053),
      year: 2022,
      runtime: '2h 55m',
      language: 'Tamil',
      videoSource: demoMp4Video,
      ottName: 'SunNxt',
      ottLogo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a2/Sun_NXT_logo.png/185px-Sun_NXT_logo.png',
    ),
    _detail(
      id: 'leo',
      title: 'LEO',
      genre: 'Action',
      rating: 8.4,
      poster: 'https://images.unsplash.com/photo-1536440136628-849c177e76a1?w=600&auto=format&fit=crop',
      backdrop: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=1200&auto=format&fit=crop',
      color: const Color(0xFF2E4053),
      year: 2023,
      runtime: '2h 44m',
      language: 'Tamil',
      videoSource: demoMp4Video,
      ottName: 'Zee5',
      ottLogo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5a/ZEE5_logo.svg/185px-ZEE5_logo.svg.png',
    ),
  ];

  static List<Movie> recentlyReleased = allMovies;
  static List<Movie> trending = allMovies;
  static List<Movie> topRated = allMovies;

  static void populateCatalog({
    required List<Movie> all,
    required List<Movie> recent,
    required List<Movie> trend,
    required List<Movie> rated,
  }) {
    allMovies = all;
    recentlyReleased = recent;
    trending = trend;
    topRated = rated;
  }

  static Movie _detail({
    required String id,
    required String title,
    required String genre,
    required double rating,
    required String poster,
    required String backdrop,
    required Color color,
    required int year,
    required String runtime,
    required String language,
    String? videoSource,
    String? trailerUrl,
    String? ottName,
    String? ottLogo,
  }) {
    final actualVideoSource = videoSource ?? demoMp4Video;
    return Movie(
      id: id,
      title: title,
      genre: genre,
      rating: rating,
      posterUrl: poster,
      backdropUrl: backdrop,
      posterColor: color,
      year: year,
      runtime: runtime,
      contentRating: 'TV-MA',
      tags: [genre],
      description:
          'Epic storytelling with cinematic visuals. Perfect for your private library — drop an .mp4 or .mkv file to play your own copy.',
      cast: const ['Robert Downey Jr.', 'Scarlett Johansson'],
      castMembers: const [
        CastMember(name: 'Robert Downey Jr.', profileUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150'),
        CastMember(name: 'Scarlett Johansson', profileUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150'),
      ],
      director: 'Featured Director',
      videoSource: actualVideoSource,
      trailerUrl: trailerUrl,
      language: language,
      ottName: ottName,
      ottLogo: ottLogo,
      streamSources: [StreamSource(name: 'Default Server', url: actualVideoSource)],
    );
  }
}
