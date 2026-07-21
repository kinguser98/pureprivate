import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/movie_provider.dart';
import '../../widgets/common/glass_card.dart';
import '../../utils/drawer_helper.dart';

class LinkCheckerScreen extends ConsumerStatefulWidget {
  const LinkCheckerScreen({super.key});
  @override
  ConsumerState<LinkCheckerScreen> createState() => _LinkCheckerScreenState();
}

class _LinkCheckerScreenState extends ConsumerState<LinkCheckerScreen> {
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(movieProvider.notifier).fetchMovies(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final movieState = ref.watch(movieProvider);
    final allMovies = movieState.movies;
    final filtered = _filter == 'All' ? allMovies : (_filter == 'Active' ? allMovies.where((m) => !m.isBroken).toList() : allMovies.where((m) => m.isBroken).toList());
    final activeCount = allMovies.where((m) => !m.isBroken).length;
    final brokenCount = allMovies.where((m) => m.isBroken).length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: DrawerProvider.openDrawer),
        title: const Text('Link Checker'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  _badge('$activeCount Active', const Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  _badge('$brokenCount Broken', const Color(0xFFEF4444)),
                  const SizedBox(width: 8),
                  _badge('${allMovies.length} Total', Colors.white.withOpacity(0.5)),
                ]),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1F2E).withOpacity(0.45),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filter,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1A1F2E),
                      icon: Icon(Icons.filter_list, color: Colors.white.withOpacity(0.6)),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      items: ['All', 'Active', 'Broken'].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                      onChanged: (v) { if (v != null) setState(() => _filter = v); },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: movieState.isLoading && allMovies.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline, size: 48, color: Colors.white.withOpacity(0.2)),
                            const SizedBox(height: 12),
                            Text('No $_filter movies', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final movie = filtered[index];
                          return GlassCard(
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 10, height: 10,
                                  decoration: BoxDecoration(
                                    color: movie.isBroken ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(movie.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text('Last checked: ${movie.lastChecked ?? "Never"}', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (movie.isBroken ? const Color(0xFFEF4444) : const Color(0xFF10B981)).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(movie.isBroken ? 'Broken' : 'Active', style: TextStyle(color: movie.isBroken ? const Color(0xFFEF4444) : const Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                IconButton(
                                  icon: Icon(Icons.edit, color: Colors.white.withOpacity(0.5), size: 18),
                                  onPressed: () => context.go('/edit-movie?id=${movie.id}'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
