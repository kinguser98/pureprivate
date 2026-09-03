import 'package:flutter/material.dart';
import '../../services/browser_history_service.dart';

enum SuggestionType {
  bookmark,
  history,
  search,
}

class UrlSuggestionItem {
  final SuggestionType type;
  final String title;
  final String url;

  UrlSuggestionItem({
    required this.type,
    required this.title,
    required this.url,
  });
}

class UrlSuggestionOverlay extends StatefulWidget {
  final String query;
  final Function(String url) onSelect;

  const UrlSuggestionOverlay({
    super.key,
    required this.query,
    required this.onSelect,
  });

  @override
  State<UrlSuggestionOverlay> createState() => _UrlSuggestionOverlayState();
}

class _UrlSuggestionOverlayState extends State<UrlSuggestionOverlay> {
  List<UrlSuggestionItem> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _fetchSuggestions();
  }

  @override
  void didUpdateWidget(covariant UrlSuggestionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _fetchSuggestions();
    }
  }

  Future<void> _fetchSuggestions() async {
    final q = widget.query.trim().toLowerCase();
    if (q.isEmpty) {
      if (mounted) setState(() => _suggestions = []);
      return;
    }

    final bookmarks = await BrowserHistoryService.getBookmarks();
    final history = await BrowserHistoryService.getHistory();
    final List<UrlSuggestionItem> results = [];

    // 1. Search Bookmarks
    for (final bm in bookmarks) {
      if (bm.title.toLowerCase().contains(q) || bm.url.toLowerCase().contains(q)) {
        results.add(UrlSuggestionItem(type: SuggestionType.bookmark, title: bm.title, url: bm.url));
        if (results.length >= 5) break;
      }
    }

    // 2. Search History
    if (results.length < 5) {
      for (final h in history) {
        if (!results.any((r) => r.url == h.url)) {
          if (h.title.toLowerCase().contains(q) || h.url.toLowerCase().contains(q)) {
            results.add(UrlSuggestionItem(type: SuggestionType.history, title: h.title, url: h.url));
            if (results.length >= 5) break;
          }
        }
      }
    }

    // 3. Fallback Google Search suggestion if less than 5
    if (results.length < 5) {
      results.add(UrlSuggestionItem(
        type: SuggestionType.search,
        title: 'Search for "$q"',
        url: 'https://www.google.com/search?q=${Uri.encodeComponent(widget.query.trim())}',
      ));
    }

    if (mounted) {
      setState(() => _suggestions = results.take(5).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_suggestions.isEmpty || widget.query.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
          itemBuilder: (ctx, i) {
            final item = _suggestions[i];
            IconData icon;
            Color iconColor;
            switch (item.type) {
              case SuggestionType.bookmark:
                icon = Icons.star_rounded;
                iconColor = Colors.amber;
                break;
              case SuggestionType.history:
                icon = Icons.history_rounded;
                iconColor = const Color(0xFF38BDF8);
                break;
              case SuggestionType.search:
                icon = Icons.search_rounded;
                iconColor = Colors.white54;
                break;
            }

            return ListTile(
              dense: true,
              leading: Icon(icon, color: iconColor, size: 20),
              title: Text(
                item.title,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                item.url,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => widget.onSelect(item.url),
            );
          },
        ),
      ),
    );
  }
}
