import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/admin_api_client.dart';
import '../../utils/drawer_helper.dart';
import '../../widgets/common/glass_card.dart';
import '../../../screens/video_player_screen.dart';
import '../../../data/domain_service.dart';
import '../../../data/modular_source_service.dart';

class SourceModulesScreen extends ConsumerStatefulWidget {
  const SourceModulesScreen({super.key});

  @override
  ConsumerState<SourceModulesScreen> createState() => _SourceModulesScreenState();
}

class _SourceModulesScreenState extends ConsumerState<SourceModulesScreen> {
  bool _loading = true;
  bool _syncing = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _modules = [];

  // Default seed list for offline / instant display
  final List<Map<String, dynamic>> _defaultModules = [
    {
      'id': 'movieshunt',
      'name': 'MoviesHunt',
      'description': 'Fast Cloudflare R2 & 10Gbps dedicated MKV streams',
      'endpoint': 'https://ot.goprivate.fun/sources/movieshunt.php',
      'domain': 'https://movieshunt.monster',
      'enabled': true,
      'icon': 'film',
      'order': 1,
      'cache_ttl': 14400,
    },
    {
      'id': 'hdhub4u',
      'name': 'HDHub4u',
      'description': '4K, 1080p HEVC & Dolby 5.1 direct cloud streams',
      'endpoint': 'https://ot.goprivate.fun/sources/hdhub4u.php',
      'domain': 'https://new5.hdhub4u.cl',
      'enabled': true,
      'icon': 'hd',
      'order': 2,
      'cache_ttl': 14400,
    },
    {
      'id': 'moviesdrive',
      'name': 'MoviesDrive',
      'description': 'Multi-Audio 4K/1080p fast cloud links & mirrors',
      'endpoint': 'https://ot.goprivate.fun/sources/moviesdrive.php',
      'domain': 'https://new4.moviesdrive.christmas',
      'enabled': true,
      'icon': 'cloud',
      'order': 3,
      'cache_ttl': 14400,
    },
    {
      'id': 'vegamovies',
      'name': 'VegaMovies',
      'description': 'Direct high-speed VCloud & FastCloud servers',
      'endpoint': 'https://ot.goprivate.fun/sources/vegamovies.php',
      'domain': 'https://vegamovies.ist',
      'enabled': true,
      'icon': 'video',
      'order': 4,
      'cache_ttl': 14400,
    },
    {
      'id': 'cinejoy',
      'name': 'Cinejoy',
      'description': '1080p Full HD player & VidSrc fast mirror',
      'endpoint': 'https://ot.goprivate.fun/sources/cinejoy.php',
      'domain': 'https://cinejoy.to',
      'enabled': true,
      'icon': 'play',
      'order': 5,
      'cache_ttl': 86400,
    },
    {
      'id': 'filmu',
      'name': 'FilmU',
      'description': 'RiveStream high-bitrate multi-audio streams',
      'endpoint': 'https://ot.goprivate.fun/sources/filmu.php',
      'domain': 'https://rive.filmu.in',
      'enabled': true,
      'icon': 'sparkles',
      'order': 6,
      'cache_ttl': 14400,
    },
    {
      'id': 'istreamflare',
      'name': 'iStreamFlare',
      'description': 'HLS Multi-Quality Master Playlists with Auto Bitrate & Multi-Audio',
      'endpoint': 'https://ot.goprivate.fun/sources/istreamflare.php',
      'domain': 'https://istreamflare.top',
      'enabled': true,
      'icon': 'sparkles',
      'order': 7,
      'cache_ttl': 14400,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadModules();
  }

  Future<void> _loadModules() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await AdminApiClient.sharedDio.get('/modules.php?action=list');
      if (res.statusCode == 200 && res.data != null) {
        dynamic data = res.data;
        if (data is String) {
          try {
            data = jsonDecode(data);
          } catch (_) {}
        }
        if (data is Map && data['modules'] is List) {
          setState(() {
            _modules = List<Map<String, dynamic>>.from(data['modules']);
            _loading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('[SourceModulesScreen] Error loading modules: $e');
    }

    // Fallback to default modules if server request fails
    setState(() {
      if (_modules.isEmpty) {
        _modules = List<Map<String, dynamic>>.from(_defaultModules);
      }
      _loading = false;
    });
  }

  Future<void> _syncScrapersToServer() async {
    setState(() => _syncing = true);
    try {
      await AdminApiClient.sharedDio.get('/deploy_sources.php?json=1');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text('All 7 scraper modules synchronized to server!'),
              ],
            ),
            backgroundColor: Color(0xFF0F291E),
          ),
        );
      }
      _loadModules();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: $e'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _toggleModule(Map<String, dynamic> module) async {
    final id = module['id'];
    final currentStatus = module['enabled'] == true;
    final newStatus = !currentStatus;

    // Optimistic UI update
    setState(() {
      module['enabled'] = newStatus;
    });

    try {
      await AdminApiClient.sharedDio.post('/modules.php?action=toggle&id=$id', data: {});
    } catch (e) {
      // Revert on error
      setState(() {
        module['enabled'] = currentStatus;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to toggle module: $e')),
        );
      }
    }
  }

  void _openTestDialog(Map<String, dynamic> module) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ModuleTestSheet(module: module),
    );
  }

  void _openEditDomainDialog(Map<String, dynamic> module) {
    final id = module['id'] ?? '';
    final name = module['name'] ?? id;
    final currentDomain = module['domain'] ?? '';
    final ctrl = TextEditingController(text: currentDomain);
    bool saving = false;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.amberAccent.withOpacity(0.4)),
              ),
              title: Row(
                children: [
                  const Icon(Icons.public_rounded, color: Colors.amberAccent, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit Domain: $name',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Changing this domain updates the active scraper mirror immediately on both shared hosting and in-app extractors.',
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Active Mirror Domain',
                      labelStyle: GoogleFonts.outfit(color: Colors.amberAccent, fontSize: 12),
                      hintText: 'https://...',
                      hintStyle: GoogleFonts.outfit(color: Colors.white30, fontSize: 13),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.amberAccent, width: 1.5),
                      ),
                      prefixIcon: const Icon(Icons.link_rounded, color: Colors.amberAccent, size: 18),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white60)),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final newDomain = ctrl.text.trim().replaceAll(RegExp(r'/+$'), '');
                          if (newDomain.isEmpty) return;

                          setDialogState(() => saving = true);
                          try {
                            // 1. Persist to shared hosting JSON
                            await AdminApiClient.sharedDio.post(
                              '/modules.php?action=save_domain',
                              data: {'id': id, 'domain': newDomain},
                            );

                            // 2. Persist in app DomainService cache
                            await DomainService.setCustomDomain(id, newDomain);

                            // 3. Update local state
                            setState(() {
                              module['domain'] = newDomain;
                            });

                            if (mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text('Domain for $name updated to $newDomain!'),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: const Color(0xFF0F291E),
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to update domain: $e'),
                                  backgroundColor: Colors.red.shade900,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent.shade700,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(
                          'Save & Apply',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _syncModulesToAppSettings(List<Map<String, dynamic>> modules) async {
    try {
      final jsonStr = jsonEncode(modules);
      await AdminApiClient.sharedDio.post(
        '/api.php?action=bulk_save_app_settings',
        data: {'source_modules_json': jsonStr},
      );
      await ModularSourceService.fetchActiveModules(forceRefresh: true);
    } catch (e) {
      debugPrint('[SourceModulesScreen] Failed syncing to app_settings: $e');
    }
  }

  void _openModuleDialog({Map<String, dynamic>? moduleToEdit}) {
    final isEditing = moduleToEdit != null;
    final idCtrl = TextEditingController(text: moduleToEdit?['id'] ?? '');
    final nameCtrl = TextEditingController(text: moduleToEdit?['name'] ?? '');
    final endpointCtrl = TextEditingController(text: moduleToEdit?['endpoint'] ?? '');
    final domainCtrl = TextEditingController(text: moduleToEdit?['domain'] ?? '');
    final descCtrl = TextEditingController(text: moduleToEdit?['description'] ?? '');
    bool isEnabled = moduleToEdit?['enabled'] ?? true;
    bool saving = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.cyanAccent.withOpacity(0.4)),
              ),
              title: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded,
                    color: Colors.cyanAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit Module: ${moduleToEdit['name']}' : 'Add New Source Module',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configure a modular source provider. It will automatically integrate into the app settings, stream selectors, and priority list.',
                        style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: idCtrl,
                        enabled: !isEditing,
                        style: GoogleFonts.outfit(
                          color: isEditing ? Colors.white54 : Colors.white,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Module ID (unique, lowercase e.g. istreamflare)',
                          labelStyle: GoogleFonts.outfit(color: Colors.cyanAccent, fontSize: 12),
                          hintText: 'e.g. istreamflare',
                          hintStyle: GoogleFonts.outfit(color: Colors.white30, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Display Name',
                          labelStyle: GoogleFonts.outfit(color: Colors.cyanAccent, fontSize: 12),
                          hintText: 'e.g. iStreamFlare',
                          hintStyle: GoogleFonts.outfit(color: Colors.white30, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: endpointCtrl,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Scraper Endpoint URL',
                          labelStyle: GoogleFonts.outfit(color: Colors.cyanAccent, fontSize: 12),
                          hintText: 'https://ot.goprivate.fun/sources/istreamflare.php',
                          hintStyle: GoogleFonts.outfit(color: Colors.white30, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: domainCtrl,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Active Mirror Domain (optional)',
                          labelStyle: GoogleFonts.outfit(color: Colors.cyanAccent, fontSize: 12),
                          hintText: 'https://stream.neuroflare.de',
                          hintStyle: GoogleFonts.outfit(color: Colors.white30, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Description / Features',
                          labelStyle: GoogleFonts.outfit(color: Colors.cyanAccent, fontSize: 12),
                          hintText: 'Fast Cloudflare R2 & multi-audio streams',
                          hintStyle: GoogleFonts.outfit(color: Colors.white30, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Enable Module', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
                          Switch(
                            value: isEnabled,
                            onChanged: (val) => setDialogState(() => isEnabled = val),
                            activeColor: Colors.cyanAccent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final id = idCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
                          final name = nameCtrl.text.trim();
                          final endpoint = endpointCtrl.text.trim();
                          final domain = domainCtrl.text.trim();
                          final description = descCtrl.text.trim();

                          if (id.isEmpty || name.isEmpty || endpoint.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('ID, Name, and Endpoint are required.'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          setDialogState(() => saving = true);

                          try {
                            final res = await AdminApiClient.sharedDio.post(
                              '/modules.php?action=save_module',
                              data: {
                                'action': 'save_module',
                                'id': id,
                                'name': name,
                                'endpoint': endpoint,
                                'domain': domain,
                                'description': description,
                                'enabled': isEnabled,
                              },
                            );

                            if (domain.isNotEmpty) {
                              await DomainService.setCustomDomain(id, domain);
                            }

                            // Sync directly to app_settings as well
                            if (res.data is Map && res.data['modules'] is List) {
                              final List<Map<String, dynamic>> updatedMods = 
                                  (res.data['modules'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
                              await _syncModulesToAppSettings(updatedMods);
                            } else {
                              await ModularSourceService.fetchActiveModules(forceRefresh: true);
                            }

                            if (mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text('Module "$name" saved successfully!'),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: const Color(0xFF0F291E),
                                ),
                              );
                              _loadModules();
                            }
                          } catch (e) {
                            setDialogState(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to save module: $e'),
                                  backgroundColor: Colors.red.shade900,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06B6D4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          isEditing ? 'Update Module' : 'Add Module',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteModule(Map<String, dynamic> module) {
    final id = module['id'] ?? '';
    final name = module['name'] ?? id;
    bool deleting = false;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.redAccent.withOpacity(0.4)),
              ),
              title: Row(
                children: [
                  const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Delete Module: $name?',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Text(
                'Are you sure you want to delete module "$name"? It will be permanently removed from the server, scraper endpoints, and app source ordering.',
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: deleting ? null : () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: deleting
                      ? null
                      : () async {
                          setDialogState(() => deleting = true);
                          try {
                            final res = await AdminApiClient.sharedDio.post(
                              '/modules.php?action=delete_module',
                              data: {'action': 'delete_module', 'id': id},
                            );

                            // Clean up from app_settings as well
                            if (res.data is Map && res.data['modules'] is List) {
                              final List<Map<String, dynamic>> updatedMods = 
                                  (res.data['modules'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
                              await _syncModulesToAppSettings(updatedMods);
                            } else {
                              final current = List<Map<String, dynamic>>.from(_modules);
                              current.removeWhere((m) => m['id'] == id);
                              await _syncModulesToAppSettings(current);
                            }

                            if (mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text('Module "$name" deleted!'),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: const Color(0xFF0F291E),
                                ),
                              );
                              _loadModules();
                            }
                          } catch (e) {
                            setDialogState(() => deleting = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to delete module: $e'),
                                  backgroundColor: Colors.red.shade900,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: deleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Delete', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _modules.where((m) => m['enabled'] == true).length;

    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F19),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
          onPressed: DrawerProvider.openDrawer,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Source Modules',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              'Stremio-Style Zero-Rebuild Scrapers',
              style: GoogleFonts.outfit(fontSize: 11, color: Colors.cyanAccent.withOpacity(0.8)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Add Source Module',
            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.cyanAccent),
            onPressed: () => _openModuleDialog(),
          ),
          IconButton(
            tooltip: 'Sync Scrapers to Server',
            icon: _syncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                : const Icon(Icons.cloud_sync_rounded, color: Colors.cyanAccent),
            onPressed: _syncing ? null : _syncScrapersToServer,
          ),
          IconButton(
            tooltip: 'Refresh List',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _loadModules,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          : RefreshIndicator(
              onRefresh: _loadModules,
              color: Colors.cyanAccent,
              backgroundColor: const Color(0xFF0B0F19),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Top Stats Overview
                  _buildStatsBanner(activeCount, _modules.length),
                  const SizedBox(height: 16),

                  // Header section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'INSTALLED MODULES (${_modules.length})',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: Colors.white54,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _syncScrapersToServer,
                        icon: const Icon(Icons.flash_on_rounded, size: 14, color: Colors.cyanAccent),
                        label: Text(
                          'Re-Sync All',
                          style: GoogleFonts.outfit(fontSize: 12, color: Colors.cyanAccent),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // List of module cards
                  ..._modules.map((m) => _buildModuleCard(m)).toList(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openModuleDialog(),
        backgroundColor: const Color(0xFF06B6D4),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text('Add Module', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildStatsBanner(int active, int total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E1B4B).withOpacity(0.6),
            const Color(0xFF0F172A).withOpacity(0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total Modules', '$total', Icons.layers_rounded, Colors.indigoAccent),
          Container(width: 1, height: 40, color: Colors.white10),
          _buildStatItem('Active Remote', '$active', Icons.check_circle_outline_rounded, Colors.greenAccent),
          Container(width: 1, height: 40, color: Colors.white10),
          _buildStatItem('Zero Rebuild', 'Live', Icons.bolt_rounded, Colors.amberAccent),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.outfit(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }

  Widget _buildModuleCard(Map<String, dynamic> module) {
    final name = module['name'] ?? 'Unknown Module';
    final id = module['id'] ?? '';
    final description = module['description'] ?? '';
    final endpoint = module['endpoint'] ?? '';
    final domain = module['domain'] ?? '';
    final isEnabled = module['enabled'] == true;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      borderColor: isEnabled ? Colors.cyanAccent.withOpacity(0.18) : Colors.white.withOpacity(0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isEnabled
                        ? [const Color(0xFF06B6D4), const Color(0xFF3B82F6)]
                        : [Colors.grey.shade800, Colors.grey.shade900],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    _getModuleIcon(id),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isEnabled ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isEnabled ? Colors.greenAccent.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            isEnabled ? 'ACTIVE' : 'OFF',
                            style: GoogleFonts.outfit(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isEnabled ? Colors.greenAccent : Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: GoogleFonts.outfit(fontSize: 12, color: Colors.white60),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Switch(
                value: isEnabled,
                onChanged: (_) => _toggleModule(module),
                activeColor: Colors.cyanAccent,
                activeTrackColor: Colors.cyan.withOpacity(0.3),
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.white10,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Chips for endpoint & domain
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (domain.isNotEmpty)
                InkWell(
                  onTap: () => _openEditDomainDialog(module),
                  borderRadius: BorderRadius.circular(8),
                  child: _buildChip(Icons.public, domain, Colors.amberAccent, isEditable: true),
                ),
              if (endpoint.isNotEmpty)
                _buildChip(Icons.api_rounded, endpoint.replaceAll('https://', ''), Colors.blueAccent),
            ],
          ),
          const SizedBox(height: 12),

          // Actions
          Row(
            children: [
              Expanded(
                flex: 4,
                child: ElevatedButton.icon(
                  onPressed: () => _openTestDialog(module),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06B6D4).withOpacity(0.15),
                    foregroundColor: Colors.cyanAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.cyanAccent.withOpacity(0.4)),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 16),
                  label: Text(
                    'Test Live',
                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _openEditDomainDialog(module),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amberAccent,
                  side: BorderSide(color: Colors.amberAccent.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                ),
                icon: const Icon(Icons.public_rounded, size: 14),
                label: Text(
                  'Domain',
                  style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => _openModuleDialog(moduleToEdit: module),
                tooltip: 'Edit Module',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.white.withOpacity(0.12)),
                  ),
                ),
                icon: const Icon(Icons.edit_rounded, color: Colors.white70, size: 16),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => _confirmDeleteModule(module),
                tooltip: 'Delete Module',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                  ),
                ),
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChip(IconData icon, String label, Color color, {bool isEditable = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color.withOpacity(0.8)),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(fontSize: 10, color: Colors.white70),
          ),
          if (isEditable) ...[
            const SizedBox(width: 4),
            Icon(Icons.edit_rounded, size: 10, color: color.withOpacity(0.9)),
          ],
        ],
      ),
    );
  }

  IconData _getModuleIcon(String id) {
    switch (id) {
      case 'movieshunt':
        return Icons.movie_filter_rounded;
      case 'hdhub4u':
        return Icons.hd_rounded;
      case 'moviesdrive':
        return Icons.cloud_download_rounded;
      case 'vegamovies':
        return Icons.video_collection_rounded;
      case 'cinejoy':
        return Icons.play_circle_fill_rounded;
      case 'filmu':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.extension_rounded;
    }
  }
}

// -----------------------------------------------------------------------------
// Live Test Modal Sheet with Direct Play Support
// -----------------------------------------------------------------------------

class _ModuleTestSheet extends StatefulWidget {
  final Map<String, dynamic> module;
  const _ModuleTestSheet({required this.module});

  @override
  State<_ModuleTestSheet> createState() => _ModuleTestSheetState();
}

class _ModuleTestSheetState extends State<_ModuleTestSheet> {
  final _queryCtrl = TextEditingController(text: 'latest');
  final _yearCtrl = TextEditingController(text: '');

  bool _testing = false;
  Map<String, dynamic>? _testResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Auto-run test on open
    _runTest();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  Future<void> _runTest() async {
    final id = widget.module['id'] ?? '';
    final q = _queryCtrl.text.trim().isEmpty ? 'latest' : _queryCtrl.text.trim();
    final y = _yearCtrl.text.trim();

    setState(() {
      _testing = true;
      _testResult = null;
      _error = null;
    });

    try {
      final url = '/modules.php?action=test&id=${Uri.encodeComponent(id)}&query=${Uri.encodeComponent(q)}&year=${Uri.encodeComponent(y)}';
      final res = await AdminApiClient.sharedDio.get(url);

      dynamic data = res.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }

      if (data is Map) {
        setState(() {
          _testResult = Map<String, dynamic>.from(data);
          _testing = false;
        });
      } else {
        setState(() {
          _error = 'Invalid response received from module.';
          _testing = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _testing = false;
      });
    }
  }

  String _cleanStreamName(String? rawName) {
    if (rawName == null || rawName.isEmpty) return 'Direct Stream';
    String cleaned = rawName
        .replaceAll(RegExp(r'\bMovies\s*Hunt\b[:\s-]*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bHDHub4u\b[:\s-]*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bMoviesDrive\b[:\s-]*', caseSensitive: false), '')
        .trim();
    if (cleaned.startsWith('•')) cleaned = cleaned.substring(1).trim();
    return cleaned.isEmpty ? 'Direct Stream' : cleaned;
  }

  void _playStreamDirectly(Map<String, dynamic> stream) {
    final streamUrl = stream['url']?.toString() ?? '';
    if (streamUrl.isEmpty) return;

    final streamName = _cleanStreamName(stream['name']?.toString());
    final rawHeaders = stream['headers'];
    final Map<String, String> headers = {};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) => headers[k.toString()] = v.toString());
    }

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoSource: streamUrl,
          title: streamName,
          headers: headers.isNotEmpty ? headers : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moduleName = widget.module['name'] ?? 'Module';

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF0D111A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        children: [
          // Sheet Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Test Module: $moduleName',
                        style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        'Live scraper query & direct stream testing',
                        style: GoogleFonts.outfit(fontSize: 11, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Quick selection chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _buildQuickChip('🔥 Latest Release', 'latest', ''),
                const SizedBox(width: 8),
                _buildQuickChip('Kalki 2898 AD', 'Kalki', '2024'),
                const SizedBox(width: 8),
                _buildQuickChip('Oppam', 'Oppam', '2016'),
                const SizedBox(width: 8),
                _buildQuickChip('Interstellar', 'Interstellar', '2014'),
              ],
            ),
          ),

          // Query & Year Input Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _queryCtrl,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Movie / Title (or "latest")',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.cyanAccent)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _yearCtrl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Year',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.cyanAccent)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _testing ? null : _runTest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06B6D4),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  icon: _testing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.flash_on_rounded, size: 16),
                  label: Text('Test', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 1),

          // Results Scroll Area
          Expanded(
            child: _buildResultsBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, String q, String y) {
    final isSelected = _queryCtrl.text == q;
    return GestureDetector(
      onTap: () {
        setState(() {
          _queryCtrl.text = q;
          _yearCtrl.text = y;
        });
        _runTest();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF06B6D4).withOpacity(0.2) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF06B6D4) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.cyanAccent : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildResultsBody() {
    if (_testing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.cyanAccent),
            const SizedBox(height: 16),
            Text(
              'Connecting to scraper module...',
              style: GoogleFonts.outfit(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              'Unpacking video streams & resolving direct links',
              style: GoogleFonts.outfit(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text('Test Request Failed', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
              const SizedBox(height: 8),
              Text(_error!, style: GoogleFonts.robotoMono(fontSize: 12, color: Colors.redAccent), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_testResult == null) {
      return const SizedBox();
    }

    final success = _testResult!['success'] == true;
    final httpCode = _testResult!['http_code'] ?? 200;
    final durationMs = _testResult!['duration_ms'] ?? 0;
    final parsed = _testResult!['parsed_data'] as Map<String, dynamic>? ?? {};
    final streams = (parsed['streams'] as List<dynamic>?) ?? [];
    final testedTitle = parsed['tested_title']?.toString() ??
        _testResult!['tested_title']?.toString() ??
        parsed['query']?.toString() ??
        'Latest Release';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: success ? const Color(0xFF064E3B).withOpacity(0.4) : const Color(0xFF7F1D1D).withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: success ? Colors.greenAccent.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(success ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 16, color: success ? Colors.greenAccent : Colors.redAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  success ? '✓ HTTP $httpCode OK in ${durationMs}ms' : '✗ Failed with HTTP $httpCode',
                  style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: success ? Colors.greenAccent : Colors.redAccent),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Tested Movie Title Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1B4B).withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.indigoAccent.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.movie_filter_rounded, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TESTED MOVIE (LIVE FROM SOURCE)',
                      style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.cyanAccent),
                    ),
                    Text(
                      testedTitle,
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Streams List
        if (streams.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Column(
              children: [
                const Icon(Icons.movie_outlined, size: 40, color: Colors.amberAccent),
                const SizedBox(height: 8),
                Text('No streams returned for this title.', style: GoogleFonts.outfit(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Try clicking "Latest Release" or searching another title like "Kalki".', style: GoogleFonts.outfit(fontSize: 12, color: Colors.white54)),
              ],
            ),
          )
        else ...[
          Text(
            'FOUND ${streams.length} DIRECT STREAM(S):',
            style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white54),
          ),
          const SizedBox(height: 8),
          ...streams.map((s) {
            final sm = s is Map<String, dynamic> ? s : Map<String, dynamic>.from(s as Map);
            return _buildStreamCard(sm);
          }),
        ],
      ],
    );
  }

  Widget _buildStreamCard(Map<String, dynamic> stream) {
    final name = _cleanStreamName(stream['name']?.toString());
    final url = stream['url']?.toString() ?? '';
    final quality = stream['quality']?.toString() ?? 'HD';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131A26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                ),
                child: Text(
                  quality,
                  style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    url,
                    style: GoogleFonts.robotoMono(fontSize: 10, color: Colors.white54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Stream URL copied to clipboard!'), duration: Duration(seconds: 1)),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.copy_rounded, size: 14, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _playStreamDirectly(stream),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(
                    'Direct Play Now',
                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
