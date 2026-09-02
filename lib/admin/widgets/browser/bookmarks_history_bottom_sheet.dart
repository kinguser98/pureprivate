import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/browser_bookmark_model.dart';
import '../../services/browser_history_service.dart';

class BookmarksHistoryBottomSheet extends StatefulWidget {
  final Function(String url) onSelectUrl;

  const BookmarksHistoryBottomSheet({super.key, required this.onSelectUrl});

  @override
  State<BookmarksHistoryBottomSheet> createState() => _BookmarksHistoryBottomSheetState();
}

class _BookmarksHistoryBottomSheetState extends State<BookmarksHistoryBottomSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<BrowserBookmark> _bookmarks = [];
  List<BrowserHistoryItem> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final b = await BrowserHistoryService.getBookmarks();
    final h = await BrowserHistoryService.getHistory();
    if (mounted) {
      setState(() {
        _bookmarks = b;
        _history = h;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Bookmarks & History',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_tabController.index == 1 && _history.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await BrowserHistoryService.clearHistory();
                    _loadData();
                  },
                  child: const Text('Clear History', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFEF4444),
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: [
              Tab(text: 'Bookmarks (${_bookmarks.length})'),
              Tab(text: 'History (${_history.length})'),
            ],
            onTap: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFEF4444)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Bookmarks
                      _bookmarks.isEmpty
                          ? _emptyState(icon: Icons.star_border_rounded, text: 'No bookmarks yet.\nTap the star icon to save favorites.')
                          : ListView.separated(
                              itemCount: _bookmarks.length,
                              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                              itemBuilder: (ctx, idx) {
                                final bm = _bookmarks[idx];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                                  ),
                                  title: Text(bm.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(bm.url, style: const TextStyle(color: Colors.white38, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 18),
                                    onPressed: () async {
                                      await BrowserHistoryService.removeBookmark(bm.id);
                                      _loadData();
                                    },
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    widget.onSelectUrl(bm.url);
                                  },
                                );
                              },
                            ),

                      // History
                      _history.isEmpty
                          ? _emptyState(icon: Icons.history_rounded, text: 'Browsing history is clean.')
                          : ListView.separated(
                              itemCount: _history.length,
                              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                              itemBuilder: (ctx, idx) {
                                final item = _history[idx];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.public_rounded, color: Colors.white54, size: 20),
                                  ),
                                  title: Text(item.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(item.url, style: const TextStyle(color: Colors.white38, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.close_rounded, color: Colors.white24, size: 16),
                                    onPressed: () async {
                                      await BrowserHistoryService.removeHistoryItem(item.id);
                                      _loadData();
                                    },
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    widget.onSelectUrl(item.url);
                                  },
                                );
                              },
                            ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({required IconData icon, required String text}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}
