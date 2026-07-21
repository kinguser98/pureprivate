class Movie {
  final int id;
  final String title;
  final String posterUrl;
  final int views;
  final String? language;
  final String? genre;

  Movie({required this.id, required this.title, required this.posterUrl, required this.views, this.language, this.genre});

  factory Movie.fromJson(Map<String, dynamic> json) => Movie(
        id: json['id'] as int,
        title: json['title'] as String,
        posterUrl: json['poster_url'] as String,
        views: json['views'] as int,
        language: json['language'] as String?,
        genre: json['genre'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'poster_url': posterUrl,
        'views': views,
        if (language != null) 'language': language,
        if (genre != null) 'genre': genre,
      };
}
