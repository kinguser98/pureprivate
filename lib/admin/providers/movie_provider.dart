import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../utils/api_client.dart';
import '../utils/storage.dart';
import '../config/api_config.dart';
import 'auth_provider.dart';

final movieProvider = StateNotifierProvider<MovieNotifier, MovieState>((ref) {
  return MovieNotifier(ref.read(apiClientProvider));
});

class MovieState {
  final List<Movie> movies;
  final bool isLoading;
  final String? error;
  final bool isLoadingMore;
  final bool hasMore;
  final int currentPage;

  const MovieState({
    this.movies = const [],
    this.isLoading = false,
    this.error,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.currentPage = 1,
  });

  MovieState copyWith({
    List<Movie>? movies,
    bool? isLoading,
    String? error,
    bool? isLoadingMore,
    bool? hasMore,
    int? currentPage,
  }) {
    return MovieState(
      movies: movies ?? this.movies,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
    );
  }

  List<Movie> get topMovies {
    final sorted = List<Movie>.from(movies);
    sorted.sort((a, b) => b.views.compareTo(a.views));
    return sorted.take(10).toList();
  }

  List<Movie> get recentMovies {
    final sorted = List<Movie>.from(movies);
    sorted.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    return sorted.take(10).toList();
  }

  List<Movie> get brokenMovies => movies.where((m) => m.isBroken).toList();
}

class MovieNotifier extends StateNotifier<MovieState> {
  final ApiClient _apiClient;

  MovieNotifier(this._apiClient) : super(const MovieState()) {
    _loadCachedMovies();
  }

  Future<void> _loadCachedMovies() async {
    try {
      final cached = await Storage.getCachedMovies();
      if (cached.isNotEmpty && state.movies.isEmpty) {
        state = state.copyWith(movies: cached, isLoading: false);
      }
    } catch (_) {}
  }

  Future<void> fetchMovies({bool refresh = false}) async {
    if (refresh) {
      state = state.copyWith(isLoading: true, error: null, currentPage: 1);
    }

    try {
      final data = await _apiClient.get(ApiConfig.movies, queryParams: {
        'limit': 500,
      });

      final moviesRaw = data['movies'] ?? <dynamic>[];
      final movies = (moviesRaw as List)
          .map((e) => Movie.fromJson(e as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        movies: movies,
        isLoading: false,
        error: null,
      );

      // Cache movies
      try {
        await Storage.cacheMovies(movies);
      } catch (_) {}
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  List<Movie> searchMovies(String query) {
    if (query.isEmpty) return state.movies;
    final lowerQuery = query.toLowerCase();
    return state.movies.where((movie) {
      return movie.title.toLowerCase().contains(lowerQuery) ||
          movie.genre.toLowerCase().contains(lowerQuery) ||
          (movie.cast?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  List<Movie> filterByLanguage(int languageId) {
    if (languageId == 0) return state.movies;
    return state.movies.where((movie) => movie.languageId == languageId).toList();
  }

  List<Movie> filterByGenre(String genre) {
    if (genre.isEmpty) return state.movies;
    return state.movies.where((movie) {
      return movie.genre.toLowerCase().contains(genre.toLowerCase());
    }).toList();
  }

}
