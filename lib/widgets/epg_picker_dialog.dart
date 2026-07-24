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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEpgData();
  }

  Future<void> _loadEpgData() async {
    if (!EpgService.isLoaded) {
      await EpgService.loadEpg();
    }
    _allIds = EpgService.availableEpgChannelIds;
    _filteredIds = List.from(_allIds);
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filter(String query) {
    final q = query.trim().toLowerCase();
    final namesMap = EpgService.channelDisplayNames;
    setState(() {
      if (q.isEmpty) {
        _filteredIds = List.from(_allIds);
      } else {
        _filteredIds = _allIds.where((id) {
          final idMatch = id.toLowerCase().contains(q);
          final displayName = namesMap[id]?.toLowerCase() ?? '';
          final nameMatch = displayName.contains(q);
          return idMatch || nameMatch;
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.live_tv_rounded, color: Color(0xFF8B5CF6), size: 22),
                    SizedBox(width: 8),
                    Text(
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
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              onChanged: _filter,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search EPG channel name or ID (e.g. Surya TV, ts521)...',
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
            const SizedBox(height: 12),
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
                          separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
                          itemBuilder: (context, index) {
                            final epgId = _filteredIds[index];
                            final logoUrl = EpgService.getChannelLogo(epgId, epgId);
                            final isSelected = widget.initialEpgId == epgId;
                            final displayName = EpgService.channelDisplayNames[epgId];
                            final titleText = (displayName != null && displayName.isNotEmpty)
                                ? '$displayName ($epgId)'
                                : epgId;

                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: logoUrl != null && logoUrl.startsWith('http')
                                    ? CachedNetworkImage(
                                        imageUrl: logoUrl,
                                        width: 36,
                                        height: 36,
                                        fit: BoxFit.contain,
                                        errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white38, size: 20),
                                      )
                                    : Container(
                                        width: 36,
                                        height: 36,
                                        color: const Color(0xFF1E293B),
                                        child: const Icon(Icons.tv, color: Colors.white38, size: 20),
                                      ),
                              ),
                              title: Text(
                                titleText,
                                style: TextStyle(
                                  color: isSelected ? const Color(0xFF8B5CF6) : Colors.white,
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                ),
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
