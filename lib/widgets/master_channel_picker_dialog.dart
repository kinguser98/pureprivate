import 'package:flutter/material.dart';
import '../admin/models/master_channel.dart';
import '../admin/utils/master_channel_repository.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MasterChannelPickerDialog extends StatefulWidget {
  final String? initialMasterId;

  const MasterChannelPickerDialog({super.key, this.initialMasterId});

  static Future<MasterChannel?> show(BuildContext context, {String? initialMasterId}) {
    return showDialog<MasterChannel>(
      context: context,
      builder: (context) => MasterChannelPickerDialog(initialMasterId: initialMasterId),
    );
  }

  @override
  State<MasterChannelPickerDialog> createState() => _MasterChannelPickerDialogState();
}

class _MasterChannelPickerDialogState extends State<MasterChannelPickerDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _languages = ['Malayalam', 'Tamil', 'Hindi', 'English', 'Telugu', 'Kannada', 'Sports', 'News', 'Kids'];
  List<MasterChannel> _allChannels = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _languages.length, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final list = await MasterChannelRepository.getAll();
    if (mounted) {
      setState(() {
        _allChannels = list;
        _isLoading = false;
      });
    }
  }

  List<MasterChannel> _getFilteredChannels(String language) {
    return _allChannels.where((c) {
      final matchesLang = (c.language ?? 'Malayalam') == language;
      if (_searchQuery.isEmpty) return matchesLang;
      final q = _searchQuery.toLowerCase();
      final matchesQuery = c.displayName.toLowerCase().contains(q) || c.epgId.toLowerCase().contains(q);
      return matchesLang && matchesQuery;
    }).toList();
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
        width: MediaQuery.of(context).size.width * 0.88,
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.playlist_add_check_rounded, color: Color(0xFF8B5CF6), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Link to Master Channel',
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
            const SizedBox(height: 8),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: const Color(0xFF8B5CF6),
              labelColor: const Color(0xFF8B5CF6),
              unselectedLabelColor: Colors.white54,
              tabs: _languages.map((lang) => Tab(text: lang)).toList(),
            ),
            const SizedBox(height: 10),
            TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search master channel name or EPG ID...',
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
                  : TabBarView(
                      controller: _tabController,
                      children: _languages.map((lang) {
                        final channels = _getFilteredChannels(lang);
                        if (channels.isEmpty) {
                          return Center(
                            child: Text(
                              'No Master Channels in $lang',
                              style: const TextStyle(color: Colors.white38, fontSize: 13),
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: channels.length,
                          separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
                          itemBuilder: (context, index) {
                            final master = channels[index];
                            final isSelected = widget.initialMasterId == master.id;

                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: master.logoUrl.isNotEmpty && master.logoUrl.startsWith('http')
                                    ? CachedNetworkImage(
                                        imageUrl: master.logoUrl,
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
                                master.displayName,
                                style: TextStyle(
                                  color: isSelected ? const Color(0xFF8B5CF6) : Colors.white,
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                              subtitle: master.epgId.isNotEmpty
                                  ? Text('EPG: ${master.epgId}', style: const TextStyle(color: Colors.white38, fontSize: 10))
                                  : null,
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle_rounded, color: Color(0xFF8B5CF6), size: 20)
                                  : null,
                              onTap: () => Navigator.pop(context, master),
                            );
                          },
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
