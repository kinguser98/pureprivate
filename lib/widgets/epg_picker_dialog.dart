import 'package:flutter/material.dart';
import '../data/epg_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class EpgPickerDialog extends StatefulWidget {
  final String? initialEpgId;

  const EpgPickerDialog({super.key, this.initialEpgId});

  static Future<String?> show(BuildContext context, {String? initialEpgId}) {
    return showDialog<String>(
      context: context,
      builder: (context) => EpgPickerDialog(initialEpgId: initialEpgId),
    );
  }

  @override
  State<EpgPickerDialog> createState() => _EpgPickerDialogState();
}

class _EpgPickerDialogState extends State<EpgPickerDialog> {
  final _searchCtrl = TextEditingController();
  List<String> _allIds = [];
  List<String> _filteredIds = [];
  String _selectedSource = 'ALL';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEpgData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEpgData() async {
    if (!EpgService.isLoaded) {
      await EpgService.loadEpg();
    }
    _allIds = EpgService.availableEpgChannelIds;
    _applyFilter();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    final namesMap = EpgService.channelDisplayNames;
    final sourceMap = EpgService.channelSourceNames;

    _filteredIds = _allIds.where((id) {
      // 1. Source filter
      if (_selectedSource != 'ALL') {
        final sources = sourceMap[id];
        if (sources == null || !sources.contains(_selectedSource)) {
          return false;
        }
      }

      // 2. Query filter
      if (q.isNotEmpty) {
        final idMatch = id.toLowerCase().contains(q);
        final displayName = namesMap[id]?.toLowerCase() ?? '';
        final nameMatch = displayName.contains(q);
        return idMatch || nameMatch;
      }
      return true;
    }).toList();
  }

  void _onSearchChanged(String _) {
    setState(() {
      _applyFilter();
    });
  }

  void _onSourceSelected(String source) {
    if (_selectedSource == source) return;
    setState(() {
      _selectedSource = source;
      _applyFilter();
    });
  }

  Color _getSourceColor(String source) {
    if (source.contains('AIO')) return const Color(0xFF8B5CF6);
    if (source.contains('Jio')) return const Color(0xFF06B6D4);
    if (source.contains('Tata')) return const Color(0xFFF59E0B);
    if (source.contains('EPGShare')) return const Color(0xFF10B981);
    return const Color(0xFF94A3B8);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.88,
        height: MediaQuery.of(context).size.height * 0.78,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.live_tv_rounded, color: Color(0xFF8B5CF6), size: 20),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Link Built-in EPG Channel',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Search Bar
            TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search EPG channel (e.g. Asianet Movies, Surya TV, 459)...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // EPG Source Filter Chips
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: EpgService.availableSources.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final source = EpgService.availableSources[index];
                  final isSelected = _selectedSource == source;
                  final chipColor = _getSourceColor(source);

                  return InkWell(
                    onTap: () => _onSourceSelected(source),
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? chipColor.withValues(alpha: 0.22)
                            : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? chipColor : Colors.white.withValues(alpha: 0.1),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (source != 'ALL') ...[
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: chipColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            source,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),

            // Channel count summary bar
            Row(
              children: [
                Text(
                  _isLoading
                      ? 'Loading EPG guides...'
                      : '${_filteredIds.length} channels available',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const Spacer(),
                if (_selectedSource != 'ALL')
                  Text(
                    'Filtered by: $_selectedSource',
                    style: TextStyle(color: _getSourceColor(_selectedSource), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Channel List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
                  : _filteredIds.isEmpty
                      ? const Center(
                          child: Text(
                            'No EPG channels found',
                            style: TextStyle(color: Colors.white38, fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _filteredIds.length,
                          separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
                          itemBuilder: (context, index) {
                            final epgId = _filteredIds[index];
                            final logoUrl = EpgService.getChannelLogo(epgId, epgId);
                            final isSelected = widget.initialEpgId == epgId;
                            final displayName = EpgService.channelDisplayNames[epgId] ?? epgId;
                            final sources = EpgService.channelSourceNames[epgId] ?? {};

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: logoUrl != null && logoUrl.startsWith('http')
                                    ? CachedNetworkImage(
                                        imageUrl: logoUrl,
                                        width: 36,
                                        height: 36,
                                        fit: BoxFit.contain,
                                        errorWidget: (context, url, error) => const Icon(Icons.tv, color: Colors.white38, size: 20),
                                      )
                                    : Container(
                                        width: 36,
                                        height: 36,
                                        color: const Color(0xFF1E293B),
                                        child: const Icon(Icons.tv, color: Colors.white38, size: 20),
                                      ),
                              ),
                              title: Text(
                                displayName,
                                style: TextStyle(
                                  color: isSelected ? const Color(0xFF8B5CF6) : Colors.white,
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                              subtitle: Row(
                                children: [
                                  Text(
                                    'ID: $epgId',
                                    style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                                  ),
                                  const SizedBox(width: 8),
                                  ...sources.take(2).map((s) {
                                    final col = _getSourceColor(s);
                                    return Container(
                                      margin: const EdgeInsets.only(right: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: col.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: col.withValues(alpha: 0.3), width: 0.8),
                                      ),
                                      child: Text(
                                        s,
                                        style: TextStyle(color: col, fontSize: 9, fontWeight: FontWeight.bold),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle_rounded, color: Color(0xFF8B5CF6), size: 20)
                                  : null,
                              onTap: () => Navigator.pop(context, epgId),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
