import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_cinema_mobile/data/playback_tracker.dart';
import 'package:private_cinema_mobile/screens/downloads_screen.dart';
import 'package:private_cinema_mobile/theme/app_colors.dart';
import 'package:private_cinema_mobile/data/stalker_resolver.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _deviceId = 'Loading...';
  late final TextEditingController _torrentioUrlController;
  late final TextEditingController _stravoUrlController;
  bool _isSyncing = false;
  String _syncMessage = '';

  @override
  void initState() {
    super.initState();
    _torrentioUrlController = TextEditingController();
    _stravoUrlController = TextEditingController();
    _loadDeviceId();
    _loadTorrentioUrl();
    _loadStravoUrl();
  }

  @override
  void dispose() {
    _torrentioUrlController.dispose();
    _stravoUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceId() async {
    final id = await PlaybackTracker.getOrCreateDeviceId();
    if (mounted) {
      setState(() {
        _deviceId = id;
      });
    }
  }

  Future<void> _loadTorrentioUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('torrentio_addon_url') ?? 'https://torrentio.strem.fun';
    _torrentioUrlController.text = url;
  }

  Future<void> _loadStravoUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('stravo_addon_url') ?? 'https://stravo-clfk.onrender.com/default';
    _stravoUrlController.text = url;
  }

  Future<void> _saveTorrentioUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('torrentio_addon_url', value.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrentio Addon URL saved successfully.')),
      );
    }
  }

  Future<void> _saveStravoUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stravo_addon_url', value.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stravo Addon URL saved successfully.')),
      );
    }
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Wipe App Data?',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will clear all watch history, progress tracking, downloads, and favorites stored locally. Proceed?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Wipe All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await _loadDeviceId();
      await _loadTorrentioUrl();
      await _loadStravoUrl();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App data and cache wiped successfully.')),
        );
      }
    }
  }

  void _copyDeviceId() {
    Clipboard.setData(ClipboardData(text: _deviceId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Device ID copied to clipboard.')),
    );
  }

  Future<void> _runStalkerSync(bool isVod) async {
    setState(() {
      _isSyncing = true;
      _syncMessage = isVod ? 'Fetching Stalker VOD Categories...' : 'Syncing Stalker Channels...';
    });

    List<String>? selectedCategoryIds;

    if (isVod) {
      try {
        final categories = await StalkerResolver.getVodCategories();
        if (mounted) {
          setState(() {
            _isSyncing = false;
          });
        }
        if (categories.isEmpty) {
          throw Exception('No VOD categories found on the Stalker Portal.');
        }

        if (mounted) {
          final chosenIds = await showDialog<List<String>>(
            context: context,
            barrierDismissible: false,
            builder: (context) => MobileCategoryPickerDialog(categories: categories),
          );

          if (chosenIds == null || chosenIds.isEmpty) {
            return;
          }
          selectedCategoryIds = chosenIds;
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isSyncing = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load VOD categories: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    }

    setState(() {
      _isSyncing = true;
      _syncMessage = isVod ? 'Syncing Stalker VOD Library...' : 'Syncing Stalker Channels...';
    });

    try {
      final Map<String, dynamic> result;
      if (isVod) {
        result = await StalkerResolver.syncVodsToServer(
          selectedCategoryIds: selectedCategoryIds,
          onProgress: (categoryName, currentPage, totalPages, totalAccumulated) {
            if (mounted) {
              setState(() {
                _syncMessage = 'Syncing Stalker VOD Library...\n\n'
                    'Category: $categoryName\n'
                    'Page: $currentPage / $totalPages\n'
                    'Total Imported: $totalAccumulated movies';
              });
            }
          },
        );
      } else {
        result = await StalkerResolver.syncChannelsToServer();
      }
      
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }

      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isVod
                  ? 'Successfully synced ${result['imported']} VOD movies!'
                  : 'Successfully synced ${result['imported']} Live TV channels!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(result['error'] ?? 'Sync failed');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            ValueListenableBuilder<CinemaTheme>(
              valueListenable: ThemeManager.notifier,
              builder: (context, currentTheme, _) {
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 110 + mediaQuery.padding.bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  // Title
                  Text(
                    'Settings',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 1. Theme Configuration
                  _buildSectionHeader('Appearance'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Theme Accent Color',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: CinemaTheme.values.map((theme) {
                            final isSelected = theme == currentTheme;
                            return GestureDetector(
                              onTap: () => ThemeManager.setTheme(theme),
                              child: Column(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: theme.accent,
                                      shape: BoxShape.circle,
                                      border: isSelected
                                          ? Border.all(color: Colors.white, width: 3.5)
                                          : Border.all(color: Colors.transparent),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: theme.accent.withValues(alpha: 0.5),
                                                blurRadius: 12,
                                                spreadRadius: 2,
                                              )
                                            ]
                                          : null,
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                                        : null,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    theme.displayName.split(' ').first,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white38,
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 2. Cloud Sync Device ID
                  _buildSectionHeader('Cloud Sync'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your Device ID',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _deviceId,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Consolas',
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, color: Colors.white70),
                              onPressed: _copyDeviceId,
                              tooltip: 'Copy Device ID',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 8),
                        const Text(
                          'Use this Device ID to sync your favorites list and resume playback progress across TV and mobile apps.',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 2.5. Torrent Settings
                  _buildSectionHeader('Stremio & Torrent Addons'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Torrentio Addon URL',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _torrentioUrlController,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontFamily: 'Consolas',
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'https://torrentio.strem.fun',
                                  hintStyle: TextStyle(color: Colors.white30),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onSubmitted: _saveTorrentioUrl,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.save_rounded, color: Colors.white70),
                              onPressed: () => _saveTorrentioUrl(_torrentioUrlController.text),
                              tooltip: 'Save URL',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Customize Torrentio stream provider URL, e.g. when configured with RealDebrid API keys.',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 16),
                        Text(
                          'Stravo Addon URL',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _stravoUrlController,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontFamily: 'Consolas',
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'https://stravo-clfk.onrender.com/default',
                                  hintStyle: TextStyle(color: Colors.white30),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onSubmitted: _saveStravoUrl,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.save_rounded, color: Colors.white70),
                              onPressed: () => _saveStravoUrl(_stravoUrlController.text),
                              tooltip: 'Save URL',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Customize Stravo stream provider base URL.',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 2.7. IPTV Sync Settings
                  _buildSectionHeader('IPTV & Stalker Portal'),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: const Icon(Icons.sync_rounded, color: Colors.greenAccent),
                          title: Text(
                            'Sync Stalker Live TV',
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text('Fetch and upload all live TV channels to your admin panel', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          onTap: () => _runStalkerSync(false),
                        ),
                        const Divider(color: Colors.white10, height: 1),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: const Icon(Icons.movie_filter_rounded, color: Colors.indigoAccent),
                          title: Text(
                            'Sync Stalker VOD Movies',
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text('Fetch and upload all portal VOD movies to your admin panel database', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          onTap: () => _runStalkerSync(true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 3. Maintenance & Storage Settings
                  _buildSectionHeader('Storage & Maintenance'),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: Icon(Icons.download_for_offline_rounded, color: AppColors.accentBright),
                          title: Text(
                            'Offline Downloads',
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text('Manage downloaded movies and watch offline', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const DownloadsScreen(),
                              ),
                            );
                          },
                        ),
                        const Divider(color: Colors.white10, height: 1),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                          title: Text(
                            'Wipe Local App Data',
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text('Reset watch records and local cache', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          onTap: _clearCache,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),

                  // About Branding
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'GOXIO MOBILE',
                          style: GoogleFonts.outfit(
                            color: Colors.white24,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Version 1.0.0 (Companion Mode)',
                          style: TextStyle(color: Colors.white12, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (_isSyncing)
          Container(
            color: Colors.black.withValues(alpha: 0.75),
            child: Center(
              child: Card(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.pinkAccent),
                      const SizedBox(height: 24),
                      Text(
                        _syncMessage,
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This may take a moment. Please do not close the app.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(
          color: Colors.white38,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class MobileCategoryPickerDialog extends StatefulWidget {
  final List<Map<String, String>> categories;

  const MobileCategoryPickerDialog({super.key, required this.categories});

  @override
  State<MobileCategoryPickerDialog> createState() => _MobileCategoryPickerDialogState();
}

class _MobileCategoryPickerDialogState extends State<MobileCategoryPickerDialog> {
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    for (final cat in widget.categories) {
      _selectedIds.add(cat['id']!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Select VOD Categories',
        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 350,
        child: Column(
          children: [
            const Text(
              'Select which categories to sync to the admin panel database. Unselected categories will be skipped.',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.categories.length,
                itemBuilder: (context, index) {
                  final cat = widget.categories[index];
                  final id = cat['id']!;
                  final title = cat['title']!;
                  final isChecked = _selectedIds.contains(id);

                  return CheckboxListTile(
                    value: isChecked,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedIds.add(id);
                        } else {
                          _selectedIds.remove(id);
                        }
                      });
                    },
                    title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    activeColor: Colors.pinkAccent,
                    checkColor: Colors.white,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _selectedIds.clear();
              for (final cat in widget.categories) {
                _selectedIds.add(cat['id']!);
              }
            });
          },
          child: const Text('Select All', style: TextStyle(color: Colors.pinkAccent)),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _selectedIds.clear();
            });
          },
          child: const Text('Deselect All', style: TextStyle(color: Colors.white60)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedIds.isEmpty ? Colors.white10 : Colors.pinkAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _selectedIds.isEmpty
              ? null
              : () {
                  Navigator.of(context).pop(_selectedIds.toList());
                },
          child: Text(
            'Sync (${_selectedIds.length})',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
