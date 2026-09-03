class BrowserBookmark {
  final String id;
  final String title;
  final String url;
  final String? faviconUrl;
  final DateTime createdAt;

  const BrowserBookmark({
    required this.id,
    required this.title,
    required this.url,
    this.faviconUrl,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'faviconUrl': faviconUrl,
    'createdAt': createdAt.toIso8601String(),
  };

  factory BrowserBookmark.fromJson(Map<String, dynamic> json) => BrowserBookmark(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Bookmark',
    url: json['url'] as String? ?? '',
    faviconUrl: json['faviconUrl'] as String?,
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
        : DateTime.now(),
  );
}

class BrowserHistoryItem {
  final String id;
  final String title;
  final String url;
  final DateTime visitedAt;

  const BrowserHistoryItem({
    required this.id,
    required this.title,
    required this.url,
    required this.visitedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'visitedAt': visitedAt.toIso8601String(),
  };

  factory BrowserHistoryItem.fromJson(Map<String, dynamic> json) => BrowserHistoryItem(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Page',
    url: json['url'] as String? ?? '',
    visitedAt: json['visitedAt'] != null
        ? DateTime.tryParse(json['visitedAt'] as String) ?? DateTime.now()
        : DateTime.now(),
  );
}
