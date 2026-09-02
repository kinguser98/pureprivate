import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/browser_tab_model.dart';
import '../../services/adblock_filter_engine.dart';
import '../../services/media_sniffer_service.dart';
import '../../services/browser_history_service.dart';
import '../../services/download_manager_service.dart';
import '../../widgets/browser/add_download_bottom_sheet.dart';
import '../../widgets/browser/media_grabber_bottom_sheet.dart';
import '../../widgets/browser/bookmarks_history_bottom_sheet.dart';
import '../../widgets/browser/image_context_menu_bottom_sheet.dart';
import '../../widgets/browser/url_suggestion_overlay.dart';
import '../downloads/download_manager_screen.dart';

class BrowserScreen extends StatefulWidget {
  final String? initialUrl;

  const BrowserScreen({super.key, this.initialUrl});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final List<BrowserTab> _tabs = [];
  int _activeTabIndex = 0;
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  final _downloadService = DownloadManagerService();
  bool _isTabSwitcherOpen = false;
  bool _isCurrentUrlBookmarked = false;
  bool _showSuggestions = false;

  BrowserTab get _currentTab => _tabs.isNotEmpty ? _tabs[_activeTabIndex] : _tabs.first;

  @override
  void initState() {
    super.initState();
    _downloadService.addListener(_onDownloadServiceUpdate);
    _urlFocusNode.addListener(() {
      setState(() {
        _showSuggestions = _urlFocusNode.hasFocus && _urlController.text.trim().isNotEmpty;
      });
    });
    _urlController.addListener(() {
      if (_urlFocusNode.hasFocus) {
        setState(() {
          _showSuggestions = _urlController.text.trim().isNotEmpty;
        });
      }
    });
    _initInitialUrl();
  }

  Future<void> _initInitialUrl() async {
    String startUrl = widget.initialUrl ?? '';
    if (startUrl.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      startUrl = prefs.getString('goxio_last_browser_url') ?? 'https://www.google.com';
    }
    _addNewTab(url: startUrl);
  }

  @override
  void dispose() {
    _downloadService.removeListener(_onDownloadServiceUpdate);
    _urlFocusNode.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onDownloadServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _addNewTab({String url = 'https://www.google.com'}) {
    final newTab = BrowserTab(
      id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
      url: url,
      title: 'New Tab',
    );
    setState(() {
      _tabs.add(newTab);
      _activeTabIndex = _tabs.length - 1;
      _urlController.text = url;
    });
    _checkBookmarkStatus(url);
  }

  Future<void> _checkBookmarkStatus(String url) async {
    final isBm = await BrowserHistoryService.isBookmarked(url);
    if (mounted) setState(() => _isCurrentUrlBookmarked = isBm);
  }

  Future<void> _toggleBookmark() async {
    await BrowserHistoryService.toggleBookmark(
      title: _currentTab.title,
      url: _currentTab.url,
      faviconUrl: _currentTab.faviconUrl,
    );
    await _checkBookmarkStatus(_currentTab.url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isCurrentUrlBookmarked ? 'Bookmark added!' : 'Bookmark removed!'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _showBookmarksHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BookmarksHistoryBottomSheet(
        onSelectUrl: (url) {
          _loadUrl(url);
        },
      ),
    );
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) {
      _currentTab.webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri('https://www.google.com')));
      setState(() {
        _currentTab.sniffedMedia.clear();
      });
      return;
    }

    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
      _urlController.text = _currentTab.url;
    });
    _checkBookmarkStatus(_currentTab.url);
  }

  void _loadUrl(String input) {
    String target = input.trim();
    if (target.isEmpty) return;

    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      if (target.contains('.') && !target.contains(' ')) {
        target = 'https://$target';
      } else {
        target = 'https://www.google.com/search?q=${Uri.encodeComponent(target)}';
      }
    }

    setState(() => _showSuggestions = false);
    _urlController.text = target;
    _currentTab.webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
    _urlFocusNode.unfocus();
  }

  void _onMediaDetected(String url, String type, String title) {
    final item = MediaSnifferService.createItemFromDetection(
      url: url,
      pageTitle: title.isNotEmpty ? title : _currentTab.title,
      explicitType: type,
      headers: {
        if (_currentTab.url.isNotEmpty && !_currentTab.url.startsWith('about:'))
          'Referer': _currentTab.url,
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
      },
    );

    if (item != null) {
      final exists = _currentTab.sniffedMedia.any((m) => m.url == item.url);
      if (!exists && mounted) {
        setState(() {
          _currentTab.sniffedMedia.add(item);
        });
      }
    }
  }

  void _showMediaGrabber() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MediaGrabberBottomSheet(
        mediaItems: _currentTab.sniffedMedia,
        onClear: () {
          setState(() {
            _currentTab.sniffedMedia.clear();
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _toggleDesktopMode() {
    setState(() {
      _currentTab.isDesktopMode = !_currentTab.isDesktopMode;
    });
    final customUA = _currentTab.isDesktopMode
        ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        : '';
    _currentTab.webViewController?.setSettings(
      settings: InAppWebViewSettings(
        userAgent: customUA,
        preferredContentMode: _currentTab.isDesktopMode ? UserPreferredContentMode.DESKTOP : UserPreferredContentMode.MOBILE,
      ),
    );
    _currentTab.webViewController?.reload();
  }

  void _toggleAdBlock() {
    setState(() {
      _currentTab.adBlockEnabled = !_currentTab.adBlockEnabled;
    });
    _currentTab.webViewController?.setSettings(
      settings: InAppWebViewSettings(
        contentBlockers: _currentTab.adBlockEnabled ? AdblockFilterEngine.contentBlockers : [],
      ),
    );
    _currentTab.webViewController?.reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_currentTab.adBlockEnabled ? 'Ad-Shield Enabled' : 'Ad-Shield Disabled'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _handleBackPress() async {
    if (_showSuggestions) {
      setState(() => _showSuggestions = false);
      _urlFocusNode.unfocus();
      return;
    }

    if (_isTabSwitcherOpen) {
      setState(() => _isTabSwitcherOpen = false);
      return;
    }

    final controller = _currentTab.webViewController;
    if (controller != null) {
      final canGoBack = await controller.canGoBack();
      if (canGoBack) {
        await controller.goBack();
        return;
      }

      // Fallback for client-side routing / SPA history
      try {
        final jsLength = await controller.evaluateJavascript(source: 'window.history.length');
        if (jsLength != null && jsLength is int && jsLength > 1) {
          await controller.evaluateJavascript(source: 'window.history.back()');
          return;
        }
      } catch (_) {}
    }

    // Never exit on system back swipe - prompt user to use Exit button
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('At start of history. Tap top-left "✕" to return to Admin.'),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'Exit Now',
            textColor: const Color(0xFFEF4444),
            onPressed: _exitBrowser,
          ),
        ),
      );
    }
  }

  Future<void> _exitBrowser() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Exit Browser?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Do you want to exit the Power Browser and return to the Admin Panel?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit Browser', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (shouldExit == true && mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        context.go('/dashboard');
      }
    }
  }

  void _openDownloadManager() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DownloadManagerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeDownloads = _downloadService.activeDownloadCount;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F19),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildAddressBar(activeDownloads),
                  if (_currentTab.isLoading)
                    LinearProgressIndicator(
                      value: _currentTab.progress > 0 ? _currentTab.progress : null,
                      color: const Color(0xFFEF4444),
                      backgroundColor: Colors.transparent,
                      minHeight: 2.5,
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: _activeTabIndex,
                      children: _tabs.map((tab) => _buildWebViewForTab(tab)).toList(),
                    ),
                  ),
                  _buildBottomToolbar(),
                ],
              ),

              // Live Omnibox Auto-Suggestions Overlay
              if (_showSuggestions)
                Positioned(
                  top: 56,
                  left: 0,
                  right: 0,
                  child: UrlSuggestionOverlay(
                    query: _urlController.text,
                    onSelect: _loadUrl,
                  ),
                ),

              // Floating Media Sniffer Badge
              if (_currentTab.sniffedMedia.isNotEmpty && !_isTabSwitcherOpen)
                Positioned(
                  right: 16,
                  bottom: 74,
                  child: FloatingActionButton.extended(
                    backgroundColor: const Color(0xFFF59E0B),
                    elevation: 8,
                    icon: const Icon(Icons.bolt_rounded, color: Colors.black, size: 20),
                    label: Text(
                      '${_currentTab.sniffedMedia.length} Media',
                      style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: _showMediaGrabber,
                  ),
                ),

              // Tab Switcher Overlay
              if (_isTabSwitcherOpen) _buildTabSwitcherOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddressBar(int activeDownloads) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
            tooltip: 'Exit Browser',
            onPressed: _exitBrowser,
          ),
          Expanded(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Icon(
                    _currentTab.url.startsWith('https') ? Icons.lock_rounded : Icons.public_rounded,
                    color: _currentTab.url.startsWith('https') ? Colors.greenAccent : Colors.white54,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      focusNode: _urlFocusNode,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Search or enter address',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      onSubmitted: _loadUrl,
                    ),
                  ),
                  // Bookmark Star Button
                  GestureDetector(
                    onTap: _toggleBookmark,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        _isCurrentUrlBookmarked ? Icons.star_rounded : Icons.star_border_rounded,
                        color: _isCurrentUrlBookmarked ? Colors.amber : Colors.white38,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  if (_currentTab.isLoading)
                    GestureDetector(
                      onTap: () => _currentTab.webViewController?.stopLoading(),
                      child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                    )
                  else
                    GestureDetector(
                      onTap: () => _currentTab.webViewController?.reload(),
                      child: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            icon: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.shield_rounded,
                  color: _currentTab.adBlockEnabled ? const Color(0xFF10B981) : Colors.white30,
                  size: 22,
                ),
              ],
            ),
            tooltip: 'Toggle Ad-Shield',
            onPressed: _toggleAdBlock,
          ),
          const SizedBox(width: 2),
          // Download Manager Quick Access Icon with Badge
          IconButton(
            icon: Badge(
              isLabelVisible: activeDownloads > 0,
              label: Text('$activeDownloads', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFF10B981),
              child: const Icon(Icons.download_rounded, color: Colors.white70, size: 22),
            ),
            tooltip: 'Download Manager',
            onPressed: _openDownloadManager,
          ),
        ],
      ),
    );
  }

  Widget _buildWebViewForTab(BrowserTab tab) {
    return InAppWebView(
      key: ValueKey(tab.id),
      initialUrlRequest: URLRequest(url: WebUri(tab.url)),
      initialUserScripts: UnmodifiableListView([
        UserScript(source: AdblockFilterEngine.antiPopupUserScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
        UserScript(source: AdblockFilterEngine.mediaSnifferUserScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
      ]),
      initialSettings: InAppWebViewSettings(
        contentBlockers: tab.adBlockEnabled ? AdblockFilterEngine.contentBlockers : [],
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        useShouldOverrideUrlLoading: true,
        useOnLoadResource: true,
        useOnDownloadStart: true,
        saveFormData: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        thirdPartyCookiesEnabled: true,
        safeBrowsingEnabled: true,
        preferredContentMode: tab.isDesktopMode ? UserPreferredContentMode.DESKTOP : UserPreferredContentMode.MOBILE,
      ),
      onWebViewCreated: (controller) {
        tab.webViewController = controller;

        // JS Handler for Media Detection
        controller.addJavaScriptHandler(
          handlerName: 'onMediaDetected',
          callback: (args) {
            if (args.isNotEmpty && args[0] is Map) {
              final data = args[0] as Map;
              final url = data['url']?.toString() ?? '';
              final type = data['type']?.toString() ?? 'video';
              final pageTitle = data['pageTitle']?.toString() ?? '';
              _onMediaDetected(url, type, pageTitle);
            }
          },
        );

        // JS Handler for Intercepted Popups
        controller.addJavaScriptHandler(
          handlerName: 'onInterceptedPopup',
          callback: (args) {
            debugPrint('Blocked rogue popup: $args');
          },
        );
      },
      // Direct file download click handler via AddDownloadBottomSheet
      onDownloadStartRequest: (controller, downloadStartRequest) async {
        final urlStr = downloadStartRequest.url.toString();
        final rawTitle = downloadStartRequest.suggestedFilename;
        final contentLength = downloadStartRequest.contentLength;

        if (mounted) {
          AddDownloadBottomSheet.show(
            context,
            url: urlStr,
            suggestedFilename: rawTitle,
            contentLength: contentLength > 0 ? contentLength : null,
          );
        }
      },
      onLongPressHitTestResult: (controller, hitTestResult) {
        final extra = hitTestResult.extra;
        if (extra != null && extra.isNotEmpty) {
          final isImage = hitTestResult.type == InAppWebViewHitTestResultType.IMAGE_TYPE ||
              hitTestResult.type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE ||
              extra.endsWith('.jpg') || extra.endsWith('.png') || extra.endsWith('.webp') || extra.endsWith('.gif');

          if (isImage) {
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (_) => ImageContextMenuBottomSheet(
                imageUrl: extra,
                pageTitle: tab.title,
              ),
            );
          }
        }
      },
      onUpdateVisitedHistory: (controller, uri, isReload) async {
        final canBack = await controller.canGoBack();
        final canForward = await controller.canGoForward();
        if (mounted) {
          setState(() {
            tab.canGoBack = canBack;
            tab.canGoForward = canForward;
            if (uri != null) {
              tab.url = uri.toString();
              if (tab.id == _currentTab.id && !_urlFocusNode.hasFocus) {
                _urlController.text = tab.url;
              }
            }
          });
        }
      },
      onLoadStart: (controller, uri) {
        if (mounted && uri != null) {
          setState(() {
            tab.isLoading = true;
            tab.url = uri.toString();
            if (tab.id == _currentTab.id && !_urlFocusNode.hasFocus) {
              _urlController.text = tab.url;
            }
          });
        }
      },
      onLoadStop: (controller, uri) async {
        final title = await controller.getTitle();
        final canBack = await controller.canGoBack();
        final canForward = await controller.canGoForward();
        if (mounted) {
          setState(() {
            tab.isLoading = false;
            tab.title = title ?? 'Webpage';
            tab.canGoBack = canBack;
            tab.canGoForward = canForward;
          });
          if (uri != null && !uri.toString().startsWith('about:')) {
            _checkBookmarkStatus(uri.toString());
            await BrowserHistoryService.addHistoryItem(title: tab.title, url: uri.toString());
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('goxio_last_browser_url', uri.toString());
          }
        }
      },
      onProgressChanged: (controller, progress) {
        if (mounted) {
          setState(() {
            tab.progress = progress / 100;
          });
        }
      },
      onLoadResource: (controller, resource) {
        final resUrl = resource.url.toString();
        _onMediaDetected(resUrl, 'resource', tab.title);
      },
      shouldOverrideUrlLoading: (controller, navAction) async {
        final uri = navAction.request.url;
        if (uri == null) return NavigationActionPolicy.CANCEL;

        final urlStr = uri.toString();
        if (urlStr.startsWith('intent://') || urlStr.startsWith('market://') || urlStr.startsWith('tg:join')) {
          return NavigationActionPolicy.CANCEL;
        }

        return NavigationActionPolicy.ALLOW;
      },
    );
  }

  Widget _buildBottomToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_rounded, color: _currentTab.canGoBack ? Colors.white : Colors.white24, size: 18),
            onPressed: _currentTab.canGoBack ? () => _currentTab.webViewController?.goBack() : null,
          ),
          IconButton(
            icon: Icon(Icons.arrow_forward_ios_rounded, color: _currentTab.canGoForward ? Colors.white : Colors.white24, size: 18),
            onPressed: _currentTab.canGoForward ? () => _currentTab.webViewController?.goForward() : null,
          ),
          IconButton(
            icon: const Icon(Icons.home_rounded, color: Colors.white70, size: 22),
            onPressed: () => _currentTab.webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri('https://www.google.com'))),
          ),
          // Tab Switcher Button
          InkWell(
            onTap: () => setState(() => _isTabSwitcherOpen = !_isTabSwitcherOpen),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white70, width: 1.8),
              ),
              child: Text(
                '${_tabs.length}',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (val) {
              if (val == 'downloads') _openDownloadManager();
              if (val == 'desktop') _toggleDesktopMode();
              if (val == 'share') Share.share(_currentTab.url);
              if (val == 'new_tab') _addNewTab();
              if (val == 'bookmarks_history') _showBookmarksHistory();
              if (val == 'clear_cache') {
                InAppWebViewController.clearAllCache();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Browser Cache Cleared!')));
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'new_tab',
                child: Row(
                  children: const [
                    Icon(Icons.add_rounded, color: Colors.white70, size: 18),
                    SizedBox(width: 10),
                    Text('New Tab', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'downloads',
                child: Row(
                  children: const [
                    Icon(Icons.download_rounded, color: Color(0xFF10B981), size: 18),
                    SizedBox(width: 10),
                    Text('Download Manager', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'bookmarks_history',
                child: Row(
                  children: const [
                    Icon(Icons.bookmark_border_rounded, color: Colors.white70, size: 18),
                    SizedBox(width: 10),
                    Text('Bookmarks & History', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'desktop',
                child: Row(
                  children: [
                    Icon(_currentTab.isDesktopMode ? Icons.phone_android_rounded : Icons.desktop_windows_rounded, color: Colors.white70, size: 18),
                    const SizedBox(width: 10),
                    Text(_currentTab.isDesktopMode ? 'Mobile View' : 'Desktop View', style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: Row(
                  children: const [
                    Icon(Icons.share_rounded, color: Colors.white70, size: 18),
                    SizedBox(width: 10),
                    Text('Share Page', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear_cache',
                child: Row(
                  children: const [
                    Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                    SizedBox(width: 10),
                    Text('Clear Cache', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcherOverlay() {
    return Container(
      color: const Color(0xFF0B0F19),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Open Tabs (${_tabs.length})', style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
                      tooltip: 'New Tab',
                      onPressed: () {
                        setState(() => _isTabSwitcherOpen = false);
                        _addNewTab();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 24),
                      onPressed: () => setState(() => _isTabSwitcherOpen = false),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: _tabs.length,
              itemBuilder: (ctx, idx) {
                final tab = _tabs[idx];
                final isSelected = idx == _activeTabIndex;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _activeTabIndex = idx;
                      _urlController.text = tab.url;
                      _isTabSwitcherOpen = false;
                    });
                    _checkBookmarkStatus(tab.url);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFEF4444) : Colors.white.withValues(alpha: 0.08),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tab.title,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _closeTab(idx),
                                child: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Colors.white12),
                        Expanded(
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.public_rounded, color: Colors.white30, size: 36),
                                const SizedBox(height: 8),
                                Text(
                                  tab.url,
                                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
