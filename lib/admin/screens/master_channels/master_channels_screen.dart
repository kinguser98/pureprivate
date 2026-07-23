import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/master_channel.dart';
import '../../utils/master_channel_repository.dart';
import '../../utils/drawer_helper.dart';
import '../../../widgets/epg_picker_dialog.dart';
import '../../../data/epg_service.dart';
import 'package:google_fonts/google_fonts.dart';

class MasterChannelsScreen extends ConsumerStatefulWidget {
  const MasterChannelsScreen({super.key});

  @override
  ConsumerState<MasterChannelsScreen> createState() => _MasterChannelsScreenState();
}

class _MasterChannelsScreenState extends ConsumerState<MasterChannelsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _languages = ['Malayalam', 'Tamil', 'Hindi', 'English', 'Telugu', 'Kannada', 'Sports', 'News', 'Kids'];
  List<MasterChannel> _allChannels = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _languages.length, vsync: this);
    _loadMasterChannels();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMasterChannels() async {
    setState(() => _isLoading = true);
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

  void _openAddEditDialog([MasterChannel? channel]) {
    final nameCtrl = TextEditingController(text: channel?.displayName ?? '');
    final logoCtrl = TextEditingController(text: channel?.logoUrl ?? '');
    final epgCtrl = TextEditingController(text: channel?.epgId ?? '');
    final aliasCtrl = TextEditingController(text: channel?.aliases.join(', ') ?? '');
    String selectedLanguage = channel?.language ?? _languages[_tabController.index];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final logoUrlText = logoCtrl.text.trim();
            return Dialog(
              backgroundColor: const Color(0xFF131722),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.88,
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF8B5CF6).withOpacity(0.3), blurRadius: 10, spreadRadius: 1),
                              ],
                            ),
                            child: Icon(channel == null ? Icons.add_circle_outline : Icons.edit_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  channel == null ? 'New Master Channel' : 'Edit Master Channel',
                                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                                ),
                                Text(
                                  'Standardized Channel Template',
                                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text('DISPLAY NAME', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: TextField(
                          controller: nameCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            hintText: 'e.g. Asianet HD',
                            hintStyle: TextStyle(color: Colors.white30),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('EPG CHANNEL LINK', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                          InkWell(
                            onTap: () async {
                              final pickedEpg = await EpgPickerDialog.show(ctx, initialEpgId: epgCtrl.text);
                              if (pickedEpg != null && pickedEpg.isNotEmpty) {
                                final epgLogo = EpgService.getChannelLogo(pickedEpg, pickedEpg);
                                setDialogState(() {
                                  epgCtrl.text = pickedEpg;
                                  if (nameCtrl.text.trim().isEmpty) {
                                    nameCtrl.text = pickedEpg;
                                  }
                                  if (epgLogo != null && epgLogo.startsWith('http')) {
                                    logoCtrl.text = epgLogo;
                                  }
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.stars_rounded, color: Color(0xFF8B5CF6), size: 13),
                                  SizedBox(width: 4),
                                  Text('Pick from EPG', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: TextField(
                          controller: epgCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'EPG Channel ID...',
                            hintStyle: TextStyle(color: Colors.white30),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('LOGO URL', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                              ),
                              child: TextField(
                                controller: logoCtrl,
                                maxLines: 2,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: 'http://...',
                                  hintStyle: TextStyle(color: Colors.white30),
                                  border: InputBorder.none,
                                ),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: logoUrlText.startsWith('http')
                                  ? CachedNetworkImage(
                                      imageUrl: logoUrlText,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => const Icon(Icons.tv, size: 20, color: Colors.white30),
                                    )
                                  : const Icon(Icons.tv, size: 20, color: Colors.white30),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('TARGET LANGUAGE', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedLanguage,
                            dropdownColor: const Color(0xFF131722),
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            isExpanded: true,
                            items: _languages
                                .map((lang) => DropdownMenuItem(value: lang, child: Text(lang)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() => selectedLanguage = val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('ALIASES (SEARCH MATCH KEYWORDS)', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: TextField(
                          controller: aliasCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'asianet, asianethd, asianet tv',
                            hintStyle: TextStyle(color: Colors.white30),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B5CF6),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              elevation: 4,
                            ),
                            onPressed: () async {
                              if (nameCtrl.text.trim().isEmpty) return;
                              Navigator.pop(ctx);

                              final masterId = channel?.id ?? 'master_${DateTime.now().microsecondsSinceEpoch}';
                              final aliases = aliasCtrl.text
                                  .split(',')
                                  .map((s) => s.trim().toLowerCase())
                                  .where((s) => s.isNotEmpty)
                                  .toList();

                              final newMaster = MasterChannel(
                                id: masterId,
                                displayName: nameCtrl.text.trim(),
                                logoUrl: logoCtrl.text.trim(),
                                epgId: epgCtrl.text.trim(),
                                categoryName: channel?.categoryName ?? 'General',
                                language: selectedLanguage,
                                aliases: aliases,
                              );

                              await MasterChannelRepository.save(newMaster);
                              _loadMasterChannels();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Master channel saved to SQL database!'), backgroundColor: Color(0xFF22C55E)),
                                );
                              }
                            },
                            child: const Text('Save Master Channel', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDelete(MasterChannel channel) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Delete Master Channel', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${channel.displayName}" from MySQL database?', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await MasterChannelRepository.delete(channel.id);
              _loadMasterChannels();
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  void _toggleSelection(String masterId) {
    setState(() {
      if (_selectedIds.contains(masterId)) {
        _selectedIds.remove(masterId);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(masterId);
        _isSelectionMode = true;
      }
    });
  }

  void _selectAllCurrentTab(String language) {
    final channels = _getFilteredChannels(language);
    setState(() {
      _isSelectionMode = true;
      for (final ch in channels) {
        _selectedIds.add(ch.id);
      }
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  void _confirmBulkDelete() {
    if (_selectedIds.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1))),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 22),
            const SizedBox(width: 8),
            Text('Bulk Delete Master Channels', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedIds.length} selected master channels from your MySQL database?',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final idsToDelete = List<String>.from(_selectedIds);
              _deselectAll();
              setState(() => _isLoading = true);
              for (final id in idsToDelete) {
                await MasterChannelRepository.delete(id);
              }
              await _loadMasterChannels();
            },
            child: Text('Delete (${_selectedIds.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentLang = _languages[_tabController.index];
    final currentTabChannels = _getFilteredChannels(currentLang);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: Icon(_isSelectionMode ? Icons.close : Icons.menu, color: Colors.white),
          onPressed: () {
            if (_isSelectionMode) {
              _deselectAll();
            } else {
              DrawerProvider.openDrawer();
            }
          },
        ),
        title: Text(
          _isSelectionMode ? '${_selectedIds.length} Selected' : 'Master Channel Registry',
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_isSelectionMode) ...[
            TextButton(
              onPressed: () {
                if (_selectedIds.length >= currentTabChannels.length) {
                  _deselectAll();
                } else {
                  _selectAllCurrentTab(currentLang);
                }
              },
              child: Text(
                _selectedIds.length >= currentTabChannels.length ? 'Deselect' : 'Select All',
                style: const TextStyle(color: Color(0xFFA855F7), fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444)),
              onPressed: _confirmBulkDelete,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.select_all_rounded, color: Colors.white70),
              onPressed: () => _selectAllCurrentTab(currentLang),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              onPressed: _loadMasterChannels,
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFF8B5CF6),
          labelColor: const Color(0xFF8B5CF6),
          unselectedLabelColor: Colors.white54,
          tabs: _languages.map((lang) => Tab(text: lang)).toList(),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search Master Channels...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
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
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                        itemCount: channels.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final ch = channels[index];
                          final isSelected = _selectedIds.contains(ch.id);

                          return InkWell(
                            onLongPress: () => _toggleSelection(ch.id),
                            onTap: _isSelectionMode ? () => _toggleSelection(ch.id) : null,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF8B5CF6).withOpacity(0.18) : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF8B5CF6) : Colors.white.withOpacity(0.06),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: ListTile(
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isSelectionMode)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Icon(
                                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                          color: isSelected ? const Color(0xFF8B5CF6) : Colors.white38,
                                          size: 20,
                                        ),
                                      ),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: ch.logoUrl.isNotEmpty && ch.logoUrl.startsWith('http')
                                          ? CachedNetworkImage(
                                              imageUrl: ch.logoUrl,
                                              width: 42,
                                              height: 42,
                                              fit: BoxFit.contain,
                                              errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white38, size: 22),
                                            )
                                          : Container(
                                              width: 42,
                                              height: 42,
                                              color: const Color(0xFF0F172A),
                                              child: const Icon(Icons.tv, color: Colors.white38, size: 22),
                                            ),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  ch.displayName,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                subtitle: Row(
                                  children: [
                                    if (ch.epgId.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        margin: const EdgeInsets.only(top: 4, right: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF8B5CF6).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'EPG: ${ch.epgId}',
                                          style: const TextStyle(color: Color(0xFFA855F7), fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_rounded, color: Colors.white60, size: 18),
                                      onPressed: () => _openAddEditDialog(ch),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_rounded, color: Color(0xFFEF4444), size: 18),
                                      onPressed: () => _confirmDelete(ch),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B5CF6).withOpacity(0.4),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openAddEditDialog(),
            borderRadius: BorderRadius.circular(30),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text('Add Master Channel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
