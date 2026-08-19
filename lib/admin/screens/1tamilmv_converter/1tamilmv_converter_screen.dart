import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class OneTamilmvConverterScreen extends StatefulWidget {
  const OneTamilmvConverterScreen({super.key});

  @override
  State<OneTamilmvConverterScreen> createState() => _OneTamilmvConverterScreenState();
}

class _OneTamilmvConverterScreenState extends State<OneTamilmvConverterScreen> {
  InAppWebViewController? _webViewController;
  final TextEditingController _domainController = TextEditingController();
  final TextEditingController _findController = TextEditingController();

  String _currentDomain = '1tamilmv.ing';
  bool _isLoading = true;
  String _currentUrl = 'https://www.1tamilmv.ing/';
  String? _errorMessage;

  // Find In Page Search State
  bool _isSearchOpen = false;
  int _activeMatchOrdinal = 0;
  int _numberOfMatches = 0;

  final String _seedrToken = 'sdp_zfvS5fCde2VMajyFDIspqveYPkGFxkWPd1z5j93u8wjeKyWIEf1u2MbnUw3bHZpA';
  final String _stLogin = 'e4a49ef565d194df9617';
  final String _stKey = 'aGYRRB932LSJRp';

  // Conversion Progress State
  bool _isConverting = false;
  int _activeStep = 0; // 0: none, 1: copied, 2: seedr add, 3: seedr dl, 4: streamtape, 5: done
  String _step1Text = 'Waiting...';
  String _step2Text = 'Waiting...';
  String _step3Text = 'Waiting...';
  String _step4Text = 'Waiting...';
  double _step4Pct = 0.0;
  String _step4BytesText = '';
  
  String? _overLimitError;
  String? _overLimitMagnet;
  String? _finalLinkId;

  final List<String> _streamtapeDomains = [
    'streamtape.com',
    'tpead.net',
    'strcloud.link',
    'streamta.pe',
    'strtpe.link',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedDomain();
  }

  @override
  void dispose() {
    _domainController.dispose();
    _findController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedDomain() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('1tamilmv_domain');
    if (saved != null && saved.trim().isNotEmpty) {
      _currentDomain = saved.trim().replaceAll('http://', '').replaceAll('https://', '').replaceAll('/', '');
    }
    _currentUrl = 'https://www.$_currentDomain/';
    _fetchAndRenderPage(_currentUrl);
  }

  Future<void> _saveDomain(String newDomain) async {
    final clean = newDomain.trim().replaceAll('http://', '').replaceAll('https://', '').replaceAll('/', '');
    if (clean.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('1tamilmv_domain', clean);

    setState(() {
      _currentDomain = clean;
      _currentUrl = 'https://www.$_currentDomain/';
    });

    _fetchAndRenderPage(_currentUrl);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Domain updated to: $clean'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _fetchAndRenderPage(String targetUrl) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentUrl = targetUrl;
    });

    try {
      final res = await http.get(
        Uri.parse(targetUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200 || res.statusCode == 301 || res.statusCode == 302) {
        String html = res.body;

        // 1. Strip external ad scripts & ad iframes from HTML string
        html = html
            .replaceAll(RegExp(r'<script[^>]*src="[^"]*(?:luluvdo|adsterra|popunder|exoclick|hilltop|topcpm|syndication)[^"]*"[^>]*></script>', caseSensitive: false), '')
            .replaceAll(RegExp(r'<iframe[^>]*src="[^"]*(?:luluvdo|adsterra|popunder)[^"]*"[^>]*></iframe>', caseSensitive: false), '');

        final baseTag = '<base href="$targetUrl">';
        final customJs = '''
          <script>
            (function() {
              window.open = function() { return null; };

              function nukeAdsAndInterceptMagnets() {
                // Intercept magnet clicks
                document.querySelectorAll('a[href^="magnet:"]').forEach(function(a) {
                  a.onclick = function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    if (window.flutter_inappwebview) {
                      window.flutter_inappwebview.callHandler('onMagnetClick', a.href);
                    }
                    return false;
                  };
                });

                // Strip invisible ad overlays covering screen
                document.querySelectorAll('div, a, iframe').forEach(function(el) {
                  var style = window.getComputedStyle(el);
                  if ((style.position === 'fixed' || style.position === 'absolute') && parseInt(style.zIndex) > 99) {
                    if (!el.innerText || el.innerText.trim().length === 0 || el.outerHTML.includes('luluvdo') || el.outerHTML.includes('ad')) {
                      el.remove();
                    }
                  }
                });

                // Remove ad banners
                document.querySelectorAll('iframe[src*="luluvdo"], iframe[src*="ad"], .ipsWidget_horizontal, a[href*="luluvdo"], a[href*="bet"], a[href*="casino"]').forEach(function(el) {
                  el.remove();
                });
              }

              setInterval(nukeAdsAndInterceptMagnets, 500);
              document.addEventListener("DOMContentLoaded", nukeAdsAndInterceptMagnets);
            })();
          </script>
        ''';

        String cleanHtml = html;
        if (cleanHtml.contains('<head>')) {
          cleanHtml = cleanHtml.replaceFirst('<head>', '<head>$baseTag');
        } else {
          cleanHtml = baseTag + cleanHtml;
        }
        cleanHtml = cleanHtml.replaceFirst('</body>', '$customJs</body>');

        if (_webViewController != null) {
          await _webViewController!.loadData(
            data: cleanHtml,
            baseUrl: WebUri(targetUrl),
            mimeType: 'text/html',
            encoding: 'utf-8',
          );
        }
      } else {
        setState(() {
          _errorMessage = 'HTTP ${res.statusCode}: Could not reach site. Try changing domain.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error: $e';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleMagnetIntercepted(String magnetUrl) {
    final dnMatch = RegExp(r'dn=([^&]+)').firstMatch(magnetUrl);
    final xlMatch = RegExp(r'xl=(\d+)').firstMatch(magnetUrl);

    final name = dnMatch != null ? Uri.decodeComponent(dnMatch.group(1)!) : '1TamilMV Quality Release';
    double sizeMb = 0;
    if (xlMatch != null) {
      sizeMb = (int.tryParse(xlMatch.group(1)!) ?? 0) / (1024 * 1024);
    } else {
      final gbMatch = RegExp(r'(\d+(?:\.\d+)?)\s*GB', caseSensitive: false).firstMatch(name);
      final mbMatch = RegExp(r'(\d+)\s*MB', caseSensitive: false).firstMatch(name);
      if (gbMatch != null) {
        sizeMb = (double.tryParse(gbMatch.group(1)!) ?? 0) * 1024;
      } else if (mbMatch != null) {
        sizeMb = (double.tryParse(mbMatch.group(1)!) ?? 0);
      }
    }

    final isOver4Gb = sizeMb > 4096;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.cloud_upload_rounded, color: Colors.redAccent, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Convert Source?', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('Upload to Seedr → Streamtape', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('File Size:', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11)),
                      Text(sizeMb > 0 ? '${(sizeMb / 1024).toStringAsFixed(1)} GB' : 'Unknown Size',
                          style: GoogleFonts.outfit(color: isOver4Gb ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            if (isOver4Gb) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Files > 4GB exceed Seedr account limit.', style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('CANCEL', style: GoogleFonts.outfit(color: Colors.white54, fontWeight: FontWeight.bold)),
          ),
          if (isOver4Gb) ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _copyToClipboard(magnetUrl, 'Magnet link copied!');
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text('COPY MAGNET', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            ),
          ] else ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _startConversionProcess(magnetUrl, name, sizeMb);
              },
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: Text('CONFIRM UPLOAD', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _clearSeedrAccount() async {
    try {
      final res = await http.get(
        Uri.parse('https://v2.seedr.cc/api/v0.1/p/fs/folder/0/contents'),
        headers: {'Authorization': 'Bearer $_seedrToken', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final folders = data['folders'] as List? ?? [];
        final files = data['files'] as List? ?? [];
        final tasks = data['tasks'] as List? ?? [];

        for (final t in tasks) {
          if (t['id'] != null) {
            try {
              await http.delete(
                Uri.parse('https://v2.seedr.cc/api/v0.1/p/tasks/${t['id']}'),
                headers: {'Authorization': 'Bearer $_seedrToken'},
              ).timeout(const Duration(seconds: 5));
            } catch (_) {}
          }
        }

        for (final f in folders) {
          if (f['id'] != null) {
            try {
              await http.delete(
                Uri.parse('https://v2.seedr.cc/api/v0.1/p/fs/folder/${f['id']}'),
                headers: {'Authorization': 'Bearer $_seedrToken'},
              ).timeout(const Duration(seconds: 5));
            } catch (_) {}
          }
        }

        final fileIds = files.map((f) => f['id']).whereType<int>().toList();
        if (fileIds.isNotEmpty) {
          try {
            await http.post(
              Uri.parse('https://v2.seedr.cc/api/v0.1/p/fs/batch/delete'),
              headers: {
                'Authorization': 'Bearer $_seedrToken',
                'Content-Type': 'application/json',
              },
              body: json.encode({'ids': fileIds}),
            ).timeout(const Duration(seconds: 5));
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Seedr auto-clear error: $e');
    }
  }

  Future<void> _startConversionProcess(String magnet, String name, double sizeMb) async {
    setState(() {
      _isConverting = true;
      _activeStep = 1;
      _step1Text = magnet.substring(0, magnet.length > 50 ? 50 : magnet.length) + '...';
      _step2Text = 'Waiting...';
      _step3Text = 'Waiting...';
      _step4Text = 'Waiting...';
      _step4Pct = 0.0;
      _step4BytesText = '';
      _overLimitError = null;
      _overLimitMagnet = null;
      _finalLinkId = null;
    });

    if (sizeMb > 4096) {
      setState(() {
        _isConverting = false;
        _activeStep = 0;
        _overLimitError = 'Files above 4GB are not supported on Seedr (Size: ${(sizeMb / 1024).toStringAsFixed(1)} GB)';
        _overLimitMagnet = magnet;
      });
      return;
    }

    await Future.delayed(const Duration(milliseconds: 400));

    setState(() {
      _activeStep = 2;
      _step2Text = 'Clearing old Seedr files & sending magnet...';
    });

    await _clearSeedrAccount();

    try {
      final addRes = await http.post(
        Uri.parse('https://v2.seedr.cc/api/v0.1/p/tasks'),
        headers: {
          'Authorization': 'Bearer $_seedrToken',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {'torrent_magnet': magnet},
      ).timeout(const Duration(seconds: 15));

      final addJson = json.decode(addRes.body);
      if (addRes.statusCode != 200 || addJson['success'] != true) {
        setState(() {
          _isConverting = false;
          _step2Text = 'Seedr add failed: ${addJson['reason_phrase'] ?? 'Error'}';
        });
        return;
      }

      setState(() {
        _step2Text = 'Torrent task queued in Seedr ✓';
      });
    } catch (e) {
      setState(() {
        _isConverting = false;
        _step2Text = 'Error adding to Seedr: $e';
      });
      return;
    }

    setState(() {
      _activeStep = 3;
      _step3Text = 'Seedr caching torrent to cloud...';
    });

    String? seedrDirectUrl;
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(seconds: 3));
      try {
        final rootRes = await http.get(
          Uri.parse('https://v2.seedr.cc/api/v0.1/p/fs/folder/0/contents'),
          headers: {'Authorization': 'Bearer $_seedrToken', 'Accept': 'application/json'},
        );
        if (rootRes.statusCode == 200) {
          final rootData = json.decode(rootRes.body);
          final folders = rootData['folders'] as List? ?? [];
          final files = rootData['files'] as List? ?? [];

          int? targetFileId;
          if (folders.isNotEmpty) {
            final fId = folders[0]['id'];
            final subRes = await http.get(
              Uri.parse('https://v2.seedr.cc/api/v0.1/p/fs/folder/$fId/contents'),
              headers: {'Authorization': 'Bearer $_seedrToken', 'Accept': 'application/json'},
            );
            if (subRes.statusCode == 200) {
              final subData = json.decode(subRes.body);
              final subFiles = subData['files'] as List? ?? [];
              if (subFiles.isNotEmpty) targetFileId = subFiles[0]['id'];
            }
          } else if (files.isNotEmpty) {
            targetFileId = files[0]['id'];
          }

          if (targetFileId != null) {
            final dlRes = await http.get(
              Uri.parse('https://v2.seedr.cc/api/v0.1/p/download/file/$targetFileId/url'),
              headers: {'Authorization': 'Bearer $_seedrToken', 'Accept': 'application/json'},
            );
            if (dlRes.statusCode == 200) {
              final dlData = json.decode(dlRes.body);
              seedrDirectUrl = dlData['url']?.toString();
              if (seedrDirectUrl != null && seedrDirectUrl.isNotEmpty) {
                setState(() {
                  _step3Text = 'Seedr Download Completed ✓';
                });
                break;
              }
            }
          }
        }
      } catch (_) {}
    }

    if (seedrDirectUrl == null) {
      setState(() {
        _isConverting = false;
        _step3Text = 'Seedr download timeout';
      });
      return;
    }

    setState(() {
      _activeStep = 4;
      _step4Text = 'Initiating Streamtape cloud transfer...';
    });

    String? remoteId;
    try {
      final stAddRes = await http.get(
        Uri.parse('https://api.strcloud.club/remotedl/add?login=$_stLogin&key=$_stKey&url=${Uri.encodeComponent(seedrDirectUrl)}'),
      );
      final stAddJson = json.decode(stAddRes.body);
      remoteId = stAddJson['result']?['id']?.toString();

      if (remoteId == null) {
        setState(() {
          _isConverting = false;
          _step4Text = 'Streamtape remote upload add failed';
        });
        return;
      }
    } catch (e) {
      setState(() {
        _isConverting = false;
        _step4Text = 'Streamtape API error: $e';
      });
      return;
    }

    String? finalLinkId;
    for (int j = 0; j < 120; j++) {
      await Future.delayed(const Duration(seconds: 3));
      try {
        final stStatusRes = await http.get(
          Uri.parse('https://api.strcloud.club/remotedl/status?login=$_stLogin&key=$_stKey&id=$remoteId'),
        );
        if (stStatusRes.statusCode == 200) {
          final stData = json.decode(stStatusRes.body);
          final task = stData['result']?[remoteId];
          if (task != null) {
            final loaded = (task['bytes_loaded'] as num?)?.toDouble() ?? 0;
            final total = (task['bytes_total'] as num?)?.toDouble() ?? 1;
            final pct = (loaded / (total == 0 ? 1 : total)).clamp(0.0, 1.0);
            final status = task['status']?.toString();

            String? linkId;
            if (task['url'] != null && task['url'].toString().contains('/v/')) {
              final match = RegExp(r'/v/([a-zA-Z0-9_-]+)').firstMatch(task['url'].toString());
              if (match != null) linkId = match.group(1);
            }
            if (linkId == null || linkId.isEmpty || linkId == 'false' || linkId == 'null') {
              linkId = task['linkid']?.toString() ?? task['extid']?.toString();
            }

            final isDone = (status == 'completed' || status == 'finished') || (loaded > 0 && total > 0 && loaded >= total);

            setState(() {
              _step4Pct = isDone ? 1.0 : pct;
              _step4BytesText = '${(loaded / (1024 * 1024)).toStringAsFixed(1)} MB / ${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
              _step4Text = isDone ? 'Streamtape transfer completed ✓' : 'Cloud transfer in progress... (${(pct * 100).toStringAsFixed(1)}%)';
            });

            if (isDone && linkId != null && linkId.isNotEmpty && linkId != 'false' && linkId != 'null') {
              finalLinkId = linkId;
              break;
            }
          }
        }
      } catch (_) {}
    }

    if (finalLinkId != null) {
      setState(() {
        _isConverting = false;
        _activeStep = 5;
        _finalLinkId = finalLinkId;
      });
    } else {
      setState(() {
        _isConverting = false;
        _step4Text = 'Streamtape transfer timeout';
      });
    }
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
            const SizedBox(width: 10),
            Text(message, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyAllDomains() {
    if (_finalLinkId == null) return;
    final allLinks = _streamtapeDomains.map((domain) => 'https://$domain/v/$_finalLinkId/').join('\n');
    _copyToClipboard(allLinks, 'Copied all ${_streamtapeDomains.length} Streamtape mirror links!');
  }

  void _showDomainDialog() {
    _domainController.text = _currentDomain;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.domain_rounded, color: Colors.redAccent, size: 22),
            const SizedBox(width: 10),
            Text('1TamilMV Domain Setting', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update domain if site extension changes (e.g. 1tamilmv.fi):', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 14),
            TextField(
              controller: _domainController,
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: 'https://www.',
                prefixStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
                filled: true,
                fillColor: Colors.black.withOpacity(0.4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('CANCEL', style: GoogleFonts.outfit(color: Colors.white54, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _saveDomain(_domainController.text),
            child: Text('SAVE DOMAIN', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F17),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.block_rounded, color: Colors.redAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1TamilMV Ad-Free Browser', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                Text(_currentDomain, style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isSearchOpen ? Icons.search_off_rounded : Icons.search_rounded, color: _isSearchOpen ? Colors.redAccent : Colors.white70),
            onPressed: () {
              setState(() {
                _isSearchOpen = !_isSearchOpen;
                if (!_isSearchOpen) {
                  _findController.clear();
                  _webViewController?.clearMatches();
                  _numberOfMatches = 0;
                  _activeMatchOrdinal = 0;
                }
              });
            },
            tooltip: 'Find in Page',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: () => _fetchAndRenderPage(_currentUrl),
            tooltip: 'Reload Page',
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: Colors.white70),
            onPressed: _showDomainDialog,
            tooltip: 'Change Domain',
          ),
        ],
      ),
      body: Column(
        children: [
          // FIND IN PAGE SEARCH BAR BAR
          if (_isSearchOpen)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF1E293B),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _findController,
                      autofocus: true,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Search text on page...',
                        hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.4),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                      onChanged: (val) {
                        if (val.trim().isEmpty) {
                          _webViewController?.clearMatches();
                          setState(() {
                            _numberOfMatches = 0;
                            _activeMatchOrdinal = 0;
                          });
                        } else {
                          _webViewController?.findAllAsync(find: val.trim());
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$_activeMatchOrdinal/$_numberOfMatches', style: GoogleFonts.outfit(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white70, size: 20),
                    onPressed: () => _webViewController?.findNext(forward: false),
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 20),
                    onPressed: () => _webViewController?.findNext(forward: true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                    onPressed: () {
                      _findController.clear();
                      _webViewController?.clearMatches();
                      setState(() {
                        _isSearchOpen = false;
                        _numberOfMatches = 0;
                        _activeMatchOrdinal = 0;
                      });
                    },
                  ),
                ],
              ),
            ),

          if (_isLoading)
            const LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.redAccent, minHeight: 3),

          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.redAccent.withOpacity(0.2),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_errorMessage!, style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 11))),
                  TextButton(
                    onPressed: () => _fetchAndRenderPage(_currentUrl),
                    child: Text('RETRY', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
            ),

          // LIVE AD-FREE WEBVIEW PREVIEW
          Expanded(
            child: Stack(
              children: [
                InAppWebView(
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    databaseEnabled: true,
                    cacheEnabled: true,
                    thirdPartyCookiesEnabled: true,
                    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
                    javaScriptCanOpenWindowsAutomatically: false,
                    supportMultipleWindows: false,
                    useShouldOverrideUrlLoading: true,
                    transparentBackground: false,
                    mediaPlaybackRequiresUserGesture: true,
                  ),
                  onReceivedServerTrustAuthRequest: (controller, challenge) async {
                    return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
                  },
                  onFindResultReceived: (controller, activeMatchOrdinal, numberOfMatches, isDoneCounting) {
                    if (isDoneCounting) {
                      setState(() {
                        _activeMatchOrdinal = activeMatchOrdinal + 1;
                        _numberOfMatches = numberOfMatches;
                      });
                    }
                  },
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                    controller.addJavaScriptHandler(
                      handlerName: 'onMagnetClick',
                      callback: (args) {
                        if (args.isNotEmpty) {
                          final magUrl = args[0].toString();
                          _handleMagnetIntercepted(magUrl);
                        }
                      },
                    );
                    _fetchAndRenderPage(_currentUrl);
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final uri = navigationAction.request.url;
                    if (uri != null) {
                      final urlStr = uri.toString();
                      if (urlStr.startsWith('magnet:')) {
                        _handleMagnetIntercepted(urlStr);
                        return NavigationActionPolicy.CANCEL;
                      }
                      if (urlStr.contains(_currentDomain) ||
                          urlStr.contains('1tamilmv') ||
                          urlStr.startsWith('data:') ||
                          urlStr.startsWith('about:')) {
                        return NavigationActionPolicy.ALLOW;
                      }
                    }
                    // HARD CANCEL ALL AD REDIRECTS & EXTERNAL WEBSITES
                    return NavigationActionPolicy.CANCEL;
                  },
                ),

                // OVER-LIMIT BADGE OVERLAY (> 4GB)
                if (_overLimitError != null)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('4GB Limit Reached', style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                                onPressed: () => setState(() => _overLimitError = null),
                              ),
                            ],
                          ),
                          Text(_overLimitError!, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 10),
                          if (_overLimitMagnet != null)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                                onPressed: () => _copyToClipboard(_overLimitMagnet!, 'Magnet link copied!'),
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: Text('COPY MAGNET LINK', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // CONVERSION PROGRESS BOTTOM SHEET / CARD
          if (_isConverting || _activeStep > 0)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
                boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Conversion Progress Tracker', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      if (!_isConverting)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                          onPressed: () => setState(() => _activeStep = 0),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  _buildStepRow(1, '1. Magnet Intercepted', _step1Text, _activeStep >= 1),
                  const SizedBox(height: 6),
                  _buildStepRow(2, '2. Added to Seedr', _step2Text, _activeStep >= 2),
                  const SizedBox(height: 6),
                  _buildStepRow(3, '3. Downloaded to Seedr', _step3Text, _activeStep >= 3),
                  const SizedBox(height: 6),

                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _activeStep == 4 ? Colors.amber.withOpacity(0.1) : (_activeStep > 4 ? Colors.green.withOpacity(0.1) : Colors.white.withOpacity(0.03)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _activeStep == 4 ? Colors.amber.withOpacity(0.3) : (_activeStep > 4 ? Colors.green.withOpacity(0.3) : Colors.white10)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('4. Uploading to Streamtape', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            if (_step4BytesText.isNotEmpty)
                              Text(_step4BytesText, style: GoogleFonts.outfit(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: _step4Pct,
                            backgroundColor: Colors.white10,
                            color: _activeStep > 4 ? Colors.greenAccent : Colors.amberAccent,
                            minHeight: 5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(_step4Text, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 10)),
                      ],
                    ),
                  ),

                  if (_finalLinkId != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Streamtape Links Ready!', style: GoogleFonts.outfit(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                onPressed: _copyAllDomains,
                                icon: const Icon(Icons.copy_all_rounded, size: 14),
                                label: Text('COPY ALL LINKS', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 10)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ..._streamtapeDomains.map((domain) {
                            final mirrorUrl = 'https://$domain/v/$_finalLinkId/';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Expanded(child: Text(mirrorUrl, style: GoogleFonts.outfit(color: Colors.white, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  IconButton(
                                    icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 16),
                                    onPressed: () => _copyToClipboard(mirrorUrl, 'Copied $domain link!'),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepRow(int step, String title, String desc, bool isDone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDone ? Colors.green.withOpacity(0.1) : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDone ? Colors.green.withOpacity(0.3) : Colors.white10),
      ),
      child: Row(
        children: [
          Icon(isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
               color: isDone ? Colors.greenAccent : Colors.white38, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                Text(desc, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
