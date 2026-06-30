import 'dart:convert';
import 'dart:io';
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
  late final TextEditingController _netmirrorDomainsController;
  bool _isSyncing = false;
  String _syncMessage = '';

  @override
  void initState() {
    super.initState();
    _torrentioUrlController = TextEditingController();
    _stravoUrlController = TextEditingController();
    _netmirrorDomainsController = TextEditingController();
    _loadDeviceId();
    _loadTorrentioUrl();
    _loadStravoUrl();
    _loadNetmirrorDomains();
  }

  @override
  void dispose() {
    _torrentioUrlController.dispose();
    _stravoUrlController.dispose();
    _netmirrorDomainsController.dispose();
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

  Future<void> _loadNetmirrorDomains() async {
    final prefs = await SharedPreferences.getInstance();
    final domains = prefs.getString('netmirror_domains') ?? '';
    _netmirrorDomainsController.text = domains;
  }

  Future<void> _saveNetmirrorDomains(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('netmirror_domains', value.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NetMirror domains saved successfully.')),
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

  Future<void> _testPortalConnectivity() async {
    setState(() {
      _isSyncing = true;
      _syncMessage = 'Fetching portal list...';
    });

    try {
      final portals = await StalkerResolver.getAllPortals();
      if (portals.isEmpty) {
        if (mounted) {
          setState(() => _isSyncing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No portals configured'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }

      final results = <String>[];

      for (final portal in portals) {
        final id = portal['id']?.toString() ?? '?';
        final name = portal['name']?.toString() ?? 'Portal $id';
        final rawUrl = portal['portal_url']?.toString() ?? '';
        final mac = portal['mac_address']?.toString() ?? '';
        final serialNumber = portal['serial_number']?.toString() ?? '';
        var deviceId = portal['device_id']?.toString() ?? '';
        if (deviceId.contains(' ')) {
          deviceId = deviceId.split(' ').last.trim();
        }
        final userAgent = portal['user_agent']?.toString().isNotEmpty == true
            ? portal['user_agent'].toString()
            : 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG250 stbapp ver: 2 rev: 250 Safari/533.3';

        results.add('═══ Portal $id: $name ═══');
        results.add('URL: $rawUrl');
        results.add('MAC: $mac');

        if (rawUrl.isEmpty || mac.isEmpty) {
          results.add('❌ SKIP: URL or MAC is empty');
          results.add('');
          continue;
        }

        // Build handshake URL
        var portalUrl = rawUrl.trim();
        if (portalUrl.endsWith('/')) portalUrl = portalUrl.substring(0, portalUrl.length - 1);
        portalUrl = portalUrl.replaceAll(RegExp(r'/c$'), '/server/load.php');
        portalUrl = portalUrl.replaceAll(RegExp(r'/c/$'), '/server/load.php');
        if (!portalUrl.contains('portal.php') && !portalUrl.contains('load.php')) {
          portalUrl = '$portalUrl/server/load.php';
        }

        var hsUrl = '$portalUrl?type=stb&action=handshake&js=true';
        var cookies = 'mac=$mac; stb_lang=en; timezone=GMT';
        if (deviceId.isNotEmpty) {
          cookies += '; device_id=$deviceId; device_id2=$deviceId';
          hsUrl += '&device_id=${Uri.encodeComponent(deviceId)}&device_id2=${Uri.encodeComponent(deviceId)}';
        }

        setState(() => _syncMessage = 'Testing Portal $id: $name...');

        try {
          // Use dart:io HttpClient for better cookie/redirect handling
          final ioClient = HttpClient();
          ioClient.userAgent = userAgent;
          ioClient.connectionTimeout = const Duration(seconds: 12);
          
          final Map<String, String> sessionCookies = {};
          
          void extractCookies(HttpClientResponse res) {
            final setCookies = res.headers[HttpHeaders.setCookieHeader];
            if (setCookies != null) {
              for (final header in setCookies) {
                final parts = header.split(';');
                if (parts.isNotEmpty) {
                  final pair = parts.first.split('=');
                  if (pair.length >= 2) {
                    sessionCookies[pair.first.trim()] = pair.sublist(1).join('=').trim();
                  }
                }
              }
            }
          }

          String getCookieHeader(String manualCookies) {
            final merged = <String, String>{};
            for (final part in manualCookies.split(';')) {
              final pair = part.split('=');
              if (pair.length >= 2) {
                merged[pair.first.trim()] = pair.sublist(1).join('=').trim();
              }
            }
            sessionCookies.forEach((key, val) {
              merged[key] = val;
            });
            return merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
          }

          final request = await ioClient.getUrl(Uri.parse(hsUrl));
          request.headers.set('Cookie', getCookieHeader(cookies));
          request.headers.set('X-User-Agent', 'Model: MAG250; Link: Ethernet');

          final response = await request.close().timeout(const Duration(seconds: 12));
          final body = await response.transform(utf8.decoder).join();
          extractCookies(response);

          results.add('HTTP Status: ${response.statusCode}');
          results.add('Handshake Set-Cookies: ${response.headers[HttpHeaders.setCookieHeader] ?? 'None'}');

          if (response.statusCode == 200) {
            // Try to parse token
            String token = '';
            try {
              final data = json.decode(body);
              token = data['js']?['token']?.toString() ?? '';
              if (token.isNotEmpty) {
                results.add('✅ Handshake Token: ${token.substring(0, token.length > 15 ? 15 : token.length)}...');
              } else {
                results.add('⚠️ 200 OK but no token. Body: ${body.substring(0, body.length > 200 ? 200 : body.length)}');
              }
            } catch (e) {
              results.add('⚠️ Handshake response not JSON. Error: $e. Body: ${body.substring(0, body.length > 250 ? 250 : body.length)}');
            }

            if (token.isNotEmpty) {
              // 2. Perform Profile Init
              results.add('--- Profile Init ---');
              final profileCookies = '$cookies; token=$token; Bearer=$token';
              var profileUrl = '$portalUrl?type=stb&action=get_profile&hd=1&ver=ImageDescription&num_err=0&mac=${Uri.encodeComponent(mac)}&sn=${Uri.encodeComponent(serialNumber)}';
              if (deviceId.isNotEmpty) {
                profileUrl += '&device_id=$deviceId&device_id2=$deviceId';
              }

              final profileReq = await ioClient.getUrl(Uri.parse(profileUrl));
              final mergedProfileCookies = getCookieHeader(profileCookies);
              profileReq.headers.set('Cookie', mergedProfileCookies);
              profileReq.headers.set('Authorization', 'Bearer $token');
              profileReq.headers.set('X-User-Agent', 'Model: MAG250; Link: Ethernet');

              results.add('Profile Cookies Sent: $mergedProfileCookies');

              final profileRes = await profileReq.close().timeout(const Duration(seconds: 8));
              final profileBody = await profileRes.transform(utf8.decoder).join();
              extractCookies(profileRes);
              
              results.add('Profile Status: ${profileRes.statusCode}');
              results.add('Profile Set-Cookies: ${profileRes.headers[HttpHeaders.setCookieHeader] ?? 'None'}');
              if (profileRes.statusCode == 200) {
                results.add('✅ Profile loaded');
              } else {
                results.add('❌ Profile failed: ${profileBody.substring(0, profileBody.length > 100 ? 100 : profileBody.length)}');
              }

              // 3. Get VOD Categories
              results.add('--- Fetching VOD Categories ---');
              var catsUrl = '$portalUrl?type=vod&action=get_categories';
              if (deviceId.isNotEmpty) {
                catsUrl += '&device_id=$deviceId&device_id2=$deviceId';
              }

              final catsReq = await ioClient.getUrl(Uri.parse(catsUrl));
              final mergedCatsCookies = getCookieHeader(profileCookies);
              catsReq.headers.set('Cookie', mergedCatsCookies);
              catsReq.headers.set('Authorization', 'Bearer $token');
              catsReq.headers.set('X-User-Agent', 'Model: MAG250; Link: Ethernet');

              final catsRes = await catsReq.close().timeout(const Duration(seconds: 8));
              final catsBody = await catsRes.transform(utf8.decoder).join();
              extractCookies(catsRes);

              results.add('VOD Categories Status: ${catsRes.statusCode}');
              dynamic firstCategory;
              if (catsRes.statusCode == 200 && !catsBody.contains('Authorization failed')) {
                try {
                  final catsData = json.decode(catsBody);
                  final rawList = catsData['js'] ?? catsData['result'] ?? [];
                  if (rawList is List && rawList.isNotEmpty) {
                    firstCategory = rawList.firstWhere(
                      (c) => c['id']?.toString() != 'All' && c['id']?.toString() != '*' && c['title']?.toString().toLowerCase() != 'all' && c['name']?.toString().toLowerCase() != 'all',
                      orElse: () => rawList.first,
                    );
                    results.add('✅ Found ${rawList.length} categories (First Selected: ${firstCategory['title'] ?? firstCategory['name']})');
                  } else {
                    results.add('⚠️ No categories returned or empty.');
                  }
                } catch (e) {
                  results.add('⚠️ VOD Categories parse failed. Error: $e. Body: ${catsBody.substring(0, catsBody.length > 250 ? 250 : catsBody.length)}');
                }
              } else {
                results.add('❌ Fetching categories failed. Body: $catsBody');
              }

              // 4. Get VOD Movie
              results.add('--- Fetching Sample VOD Movie ---');
              final catId = firstCategory != null ? (firstCategory['id']?.toString() ?? '') : '';
              var moviesUrl = '$portalUrl?type=vod&action=get_ordered_list&category=$catId&p=1';
              if (deviceId.isNotEmpty) {
                moviesUrl += '&device_id=$deviceId&device_id2=$deviceId';
              }

              final moviesReq = await ioClient.getUrl(Uri.parse(moviesUrl));
              moviesReq.headers.set('Cookie', getCookieHeader(profileCookies));
              moviesReq.headers.set('Authorization', 'Bearer $token');
              moviesReq.headers.set('X-User-Agent', 'Model: MAG250; Link: Ethernet');

              final moviesRes = await moviesReq.close().timeout(const Duration(seconds: 8));
              final moviesBody = await moviesRes.transform(utf8.decoder).join();
              extractCookies(moviesRes);
              
              results.add('Movies List Status: ${moviesRes.statusCode}');
              String cmd = '';
              String movieName = '';
              if (moviesRes.statusCode == 200 && !moviesBody.contains('Authorization failed')) {
                try {
                  final moviesData = json.decode(moviesBody);
                  final rawMovies = moviesData['js']?['data'] ?? moviesData['result']?['data'] ?? moviesData['js'] ?? moviesData['result'] ?? [];
                  if (rawMovies is List && rawMovies.isNotEmpty) {
                    final firstMovie = rawMovies.first;
                    cmd = firstMovie['cmd']?.toString() ?? '';
                    movieName = firstMovie['name']?.toString() ?? '';
                    results.add('✅ Movie: "$movieName", CMD: "$cmd"');
                  } else {
                    results.add('⚠️ No movies found.');
                  }
                } catch (e) {
                  results.add('⚠️ Movies response not JSON. Error: $e. Body: ${moviesBody.substring(0, moviesBody.length > 250 ? 250 : moviesBody.length)}');
                }
              } else {
                results.add('❌ Fetching movies failed. Body: $moviesBody');
              }

              // 5. Try Create Link
              if (cmd.isNotEmpty) {
                results.add('--- Trying Create Link ---');
                var linkUrl = '$portalUrl?type=vod&action=create_link&cmd=${Uri.encodeComponent(cmd)}&series=0&disable_ad=1&download=0&play_lite=0';
                if (deviceId.isNotEmpty) {
                  linkUrl += '&device_id=$deviceId&device_id2=$deviceId';
                }

                final linkReq = await ioClient.getUrl(Uri.parse(linkUrl));
                linkReq.headers.set('Cookie', getCookieHeader(profileCookies));
                linkReq.headers.set('Authorization', 'Bearer $token');
                linkReq.headers.set('X-User-Agent', 'Model: MAG250; Link: Ethernet');

                final linkRes = await linkReq.close().timeout(const Duration(seconds: 8));
                final linkBody = await linkRes.transform(utf8.decoder).join();
                extractCookies(linkRes);
                
                results.add('Create Link Status: ${linkRes.statusCode}');
                try {
                  final linkData = json.decode(linkBody);
                  final finalUrl = linkData['js']?['cmd']?.toString() ?? linkData['result']?.toString() ?? '';
                  if (finalUrl.isNotEmpty) {
                    results.add('✅ Stream URL: ${finalUrl.substring(0, finalUrl.length > 30 ? 30 : finalUrl.length)}...');
                  } else {
                    results.add('❌ Response: $linkBody');
                  }
                } catch (e) {
                  results.add('❌ Response (non-JSON). Error: $e. Body: ${linkBody.substring(0, linkBody.length > 250 ? 250 : linkBody.length)}');
                }
              }
            }
          } else if (response.statusCode == 403) {
            if (body.contains('Cloudflare') || body.contains('cloudflare')) {
              results.add('❌ CLOUDFLARE BLOCKED from this device');
            } else {
              results.add('❌ 403 Forbidden. Body: ${body.substring(0, body.length > 200 ? 200 : body.length)}');
            }
          } else {
            results.add('❌ Status ${response.statusCode}. Body: ${body.substring(0, body.length > 150 ? 150 : body.length)}');
          }
          ioClient.close();
        } catch (e) {
          results.add('❌ Error: $e');
        }
        results.add('');
      }

      setState(() => _isSyncing = false);

      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1a1a2e),
            title: Text('Portal Connectivity Test', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Text(
                results.join('\n'),
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: results.join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                },
                child: const Text('Copy', style: TextStyle(color: Colors.orangeAccent)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _isSyncing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _runStalkerSync(bool isVod) async {
    setState(() {
      _isSyncing = true;
      _syncMessage = isVod ? 'Fetching Stalker Portals list...' : 'Syncing Stalker Channels...';
    });

    List<Map<String, dynamic>> portals = [];
    try {
      portals = await StalkerResolver.getAllPortals();
    } catch (e) {
      debugPrint('Error getting portals: $e');
    }

    if (portals.isEmpty) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Stalker Portals configured on the backend. Please add one first in the admin panel.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    int? selectedPortalId;
    if (mounted) {
      setState(() => _isSyncing = false);
      selectedPortalId = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (context) => MobilePortalPickerDialog(portals: portals),
      );
    }

    if (selectedPortalId == null) {
      return; // Cancelled
    }

    setState(() {
      _isSyncing = true;
      _syncMessage = isVod ? 'Fetching Stalker VOD Categories...' : 'Syncing Stalker Channels...';
    });

    List<String>? selectedCategoryIds;

    if (isVod) {
      try {
        final categories = await StalkerResolver.getVodCategories(selectedPortalId);
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
          portalId: selectedPortalId,
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
        result = await StalkerResolver.syncChannelsToServer(selectedPortalId);
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
                        const SizedBox(height: 16),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 16),
                        Text(
                          'NetMirror Domains',
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
                                controller: _netmirrorDomainsController,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontFamily: 'Consolas',
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'e.g. https://mobiledetects.com, https://mobiledetect.app',
                                  hintStyle: TextStyle(color: Colors.white30),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onSubmitted: _saveNetmirrorDomains,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.save_rounded, color: Colors.white70),
                              onPressed: () => _saveNetmirrorDomains(_netmirrorDomainsController.text),
                              tooltip: 'Save Domains',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Comma-separated list of active NetMirror search fallback domains (overrides default domains list).',
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
                        const Divider(color: Colors.white10, height: 1),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: const Icon(Icons.network_check_rounded, color: Colors.orangeAccent),
                          title: Text(
                            'Test Portal Connectivity',
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text('Test handshake from this device for all portals', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          onTap: _testPortalConnectivity,
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

class MobilePortalPickerDialog extends StatelessWidget {
  final List<Map<String, dynamic>> portals;

  const MobilePortalPickerDialog({super.key, required this.portals});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Select Stalker Portal',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: portals.length,
          itemBuilder: (context, index) {
            final p = portals[index];
            final portalId = int.tryParse(p['id']?.toString() ?? '') ?? 0;
            final portalName = p['name']?.toString() ?? 'Stalker Portal';
            final portalUrl = p['portal_url']?.toString() ?? '';

            return Card(
              color: Colors.white.withValues(alpha: 0.05),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.settings_input_hdmi, color: Colors.pinkAccent),
                title: Text(portalName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(portalUrl, style: const TextStyle(color: Colors.white60, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.of(context).pop(portalId);
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
      ],
    );
  }
}
