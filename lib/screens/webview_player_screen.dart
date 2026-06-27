import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewPlayerScreen extends StatefulWidget {
  const WebViewPlayerScreen({
    super.key,
    required this.embedUrl,
    this.title,
    this.isEmbedOnly = false,
    this.backdropUrl,
  });

  final String embedUrl;
  final String? title;
  final bool isEmbedOnly;
  final String? backdropUrl;

  @override
  State<WebViewPlayerScreen> createState() => _WebViewPlayerScreenState();
}

class _WebViewPlayerScreenState extends State<WebViewPlayerScreen> {
  bool _isLoading = true;
  bool _isTorrentPlaying = false;
  InAppWebViewController? _webViewController;
  int _countdownSeconds = 25;
  Timer? _countdownTimer;

  bool get _isEmbedOnly => widget.isEmbedOnly || widget.embedUrl.startsWith('magnet:') || widget.embedUrl.contains('streamimdb');

  void _togglePlayPause() {
    _webViewController?.evaluateJavascript(source: """
      (function() {
        var video = document.querySelector('video') || document.querySelector('iframe')?.contentWindow?.document?.querySelector('video');
        if (video) {
          if (video.paused) {
            video.play().catch(function(e) {});
          } else {
            video.pause();
          }
        }
      })();
    """);
  }

  void _seek(int seconds) {
    _webViewController?.evaluateJavascript(source: """
      (function() {
        var video = document.querySelector('video') || document.querySelector('iframe')?.contentWindow?.document?.querySelector('video');
        if (video) {
          video.currentTime = Math.max(0, Math.min(video.duration, video.currentTime + ($seconds)));
        }
      })();
    """);
  }

  bool _isValidVideoResource(WebUri? uri) {
    if (uri == null) return false;
    final urlStr = uri.toString();
    final lower = urlStr.toLowerCase();
    
    final path = uri.path.toLowerCase();
    if (path.endsWith('.js') ||
        path.endsWith('.css') ||
        path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.gif') ||
        path.endsWith('.svg') ||
        path.endsWith('.ico') ||
        path.endsWith('.woff') ||
        path.endsWith('.woff2') ||
        path.endsWith('.ttf') ||
        path.endsWith('.otf') ||
        path.endsWith('.json') ||
        path.endsWith('.html') ||
        path.endsWith('.wasm') ||
        path.endsWith('.map') ||
        path.endsWith('.xml') ||
        path.endsWith('.txt')) {
      return false;
    }
    
    if (lower.contains('.js?') ||
        lower.contains('.css?') ||
        lower.contains('.png?') ||
        lower.contains('.jpg?') ||
        lower.contains('.jpeg?') ||
        lower.contains('.woff2?')) {
      return false;
    }
    
    if (lower.contains('analytics') ||
        lower.contains('doubleclick') ||
        lower.contains('googlesyndication') ||
        lower.contains('telemetry') ||
        lower.contains('log') ||
        lower.contains('hls.js') ||
        lower.contains('hls.min.js') ||
        lower.contains('video.js') ||
        lower.contains('video.min.js') ||
        lower.contains('/ads/') ||
        lower.contains('adserver') ||
        lower.contains('adsystem') ||
        lower.contains('adsterra') ||
        lower.contains('exoclick') ||
        lower.contains('popads') ||
        lower.contains('onclick') ||
        lower.contains('promo.mp4') ||
        lower.contains('ad.mp4') ||
        lower.contains('pre_roll') ||
        lower.contains('preroll') ||
        lower.contains('loading.mp4') ||
        lower.contains('placeholder')) {
      return false;
    }
    
    return lower.contains('.m3u8') ||
           lower.contains('.mp4') ||
           lower.contains('.mpd') ||
           lower.contains('/hls/') ||
           lower.contains('/stream/') ||
           lower.contains('.mkv') ||
           lower.contains('.webm') ||
           lower.contains('.avi') ||
           lower.contains('/playlist') ||
           lower.contains('/manifest') ||
           lower.contains('get_video') ||
           lower.contains('streamtape') ||
           lower.contains('strcloud.club') ||
           lower.contains('tpead.net');
  }

  @override
  void initState() {
    super.initState();
    // Force Landscape for video playback
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Safeguard: Dismiss loading overlay after 25 seconds to prevent infinite lock
    if (widget.embedUrl.startsWith('magnet:')) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            if (_countdownSeconds > 0) {
              _countdownSeconds--;
            } else {
              _countdownTimer?.cancel();
              if (!_isTorrentPlaying) {
                _isTorrentPlaying = true;
              }
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    // Reset orientations when exiting player
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.backspace ||
                  event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack) {
                final isAndroidOrIOS = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
                if (isAndroidOrIOS) {
                  return KeyEventResult.ignored; // Let system pop naturally
                } else {
                  Navigator.of(context).pop();
                  return KeyEventResult.handled;
                }
              }
              if (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space) {
                _togglePlayPause();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _seek(-10);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _seek(10);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            children: [
              // Full-screen WebView playing the embed source
              InAppWebView(
                initialUrlRequest: widget.embedUrl.startsWith('magnet:')
                    ? null
                    : URLRequest(
                        url: WebUri(widget.embedUrl),
                        headers: {
                          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                          if (widget.embedUrl.contains('youtube') || widget.embedUrl.contains('youtu.be')) ...{
                            'Referer': 'https://ott.redapp.space',
                            'Origin': 'https://ott.redapp.space',
                          } else ...{
                            'Referer': widget.embedUrl.startsWith('http') 
                                ? '${Uri.parse(widget.embedUrl).scheme}://${Uri.parse(widget.embedUrl).host}/'
                                : widget.embedUrl,
                            'Origin': widget.embedUrl.startsWith('http') 
                                ? '${Uri.parse(widget.embedUrl).scheme}://${Uri.parse(widget.embedUrl).host}'
                                : widget.embedUrl,
                          }
                        },
                      ),
              initialData: widget.embedUrl.startsWith('magnet:')
                  ? InAppWebViewInitialData(
                      data: """
<!DOCTYPE html>
<html>
<head>
    <title>Torrent Player</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
        body, html {
            margin: 0;
            padding: 0;
            width: 100%;
            height: 100%;
            background-color: #000;
            overflow: hidden;
        }
        #player {
            width: 100%;
            height: 100%;
        }
    </style>
</head>
<body>
    <div id="player" class="webtor"></div>
    <script>
        window.webtor = window.webtor || [];
        window.webtor.push({
            id: 'player',
            magnet: '${widget.embedUrl}',
            width: '100%',
            height: '100%',
            features: {
                title: true,
                settings: true,
                fullscreen: true,
                play: true,
            },
            autoplay: true,
        });

        function checkPlaying() {
            var video = document.querySelector('video');
            if (video && !video.paused && video.currentTime > 0) {
                if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('onVideoPlaying');
                }
            }
            setTimeout(checkPlaying, 500);
        }
        setTimeout(checkPlaying, 2000);
    </script>
    <script src="https://cdn.jsdelivr.net/npm/@webtor/embed-sdk-js/dist/index.min.js" charset="utf-8" async></script>
</body>
</html>
                      """,
                    )
                  : null,
              initialUserScripts: UnmodifiableListView<UserScript>([
                UserScript(
                  source: """
                    (function() {
                      // Pre-emptively disable common popup APIs
                      window.open = function() { return null; };
                      window.alert = function() {};
                      window.confirm = function() { return true; };
                      window.prompt = function() { return null; };
                      
                      // Prevent frame hijacking and target blank redirects
                      document.addEventListener('click', function(e) {
                        var target = e.target;
                        while (target && target.parentNode) {
                          if (target.tagName === 'A') break;
                          target = target.parentNode;
                        }
                        if (target && target.tagName === 'A') {
                          if (target.target === '_blank') {
                            target.target = '_self';
                          }
                        }
                      }, true);
                      
                      console.log('AdBlocker UserScript injected successfully.');

                      // Force YouTube quality to 720p automatically
                      if (window.location.href.indexOf('youtube.com') !== -1 || window.location.href.indexOf('youtu.be') !== -1) {
                        console.log('YouTube trailer detected, arming 720p auto-quality...');
                        function forceYouTube720p() {
                          var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                          if (player) {
                            var currentQuality = typeof player.getPlaybackQuality === 'function' ? player.getPlaybackQuality() : '';
                            if (currentQuality === 'hd720' || currentQuality === 'hd1080' || currentQuality === 'highres') {
                              console.log('Quality is already HD: ' + currentQuality);
                              window._forcedQualityClicked = true;
                              return;
                            }
                            
                            if (typeof player.setPlaybackQualityRange === 'function') {
                              player.setPlaybackQualityRange('hd720', 'hd720');
                            }
                            if (typeof player.setPlaybackQuality === 'function') {
                              player.setPlaybackQuality('hd720');
                            }
                            
                            try {
                              var settingsButton = document.querySelector('.ytp-settings-button');
                              if (settingsButton && !window._forcedQualityClicked) {
                                settingsButton.click();
                                setTimeout(function() {
                                  var menuItems = document.querySelectorAll('.ytp-menuitem');
                                  var qualityMenuItem = null;
                                  for (var i = 0; i < menuItems.length; i++) {
                                    var text = menuItems[i].innerText || '';
                                    if (text.indexOf('Quality') !== -1 || text.indexOf('质量') !== -1 || text.indexOf('화질') !== -1) {
                                      qualityMenuItem = menuItems[i];
                                      break;
                                    }
                                  }
                                  if (!qualityMenuItem && menuItems.length > 0) {
                                    qualityMenuItem = menuItems[menuItems.length - 1];
                                  }
                                  if (qualityMenuItem) {
                                    qualityMenuItem.click();
                                    setTimeout(function() {
                                      var qualityOptions = document.querySelectorAll('.ytp-menuitem');
                                      var optionClicked = false;
                                      for (var j = 0; j < qualityOptions.length; j++) {
                                        var qText = qualityOptions[j].innerText || '';
                                        if (qText.indexOf('720') !== -1 || qText.indexOf('720p') !== -1) {
                                          qualityOptions[j].click();
                                          optionClicked = true;
                                          console.log('Forced 720p via settings menu click');
                                          break;
                                        }
                                      }
                                      if (!optionClicked && qualityOptions.length > 0) {
                                        qualityOptions[0].click();
                                      }
                                      if (settingsButton) settingsButton.click();
                                      window._forcedQualityClicked = true;
                                    }, 100);
                                  } else {
                                    if (settingsButton) settingsButton.click();
                                  }
                                }, 100);
                              }
                            } catch (clickErr) {
                              console.error('Quality click error:', clickErr);
                            }
                          }
                        }
                        
                        var qTimer = setInterval(forceYouTube720p, 1000);
                        setTimeout(function() {
                          clearInterval(qTimer);
                        }, 15000);
                      }
                    })();
                  """,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
                UserScript(
                  source: """
                    (function() {
                      function findInShadows(selector, root) {
                        root = root || document;
                        var el = root.querySelector(selector);
                        if (el) return el;
                        var all = root.querySelectorAll('*');
                        for (var i = 0; i < all.length; i++) {
                          if (all[i].shadowRoot) {
                            var found = findInShadows(selector, all[i].shadowRoot);
                            if (found) return found;
                          }
                        }
                        return null;
                      }

                      function findAllInShadows(selector, root, results) {
                        root = root || document;
                        results = results || [];
                        var elements = root.querySelectorAll(selector);
                        for (var i = 0; i < elements.length; i++) {
                          results.push(elements[i]);
                        }
                        var all = root.querySelectorAll('*');
                        for (var j = 0; j < all.length; j++) {
                          if (all[j].shadowRoot) {
                            findAllInShadows(selector, all[j].shadowRoot, results);
                          }
                        }
                        return results;
                      }

                      function simulateClick(element) {
                        if (!element) return;
                        try {
                          element.click();
                        } catch(e) {}
                        try {
                          var event = new MouseEvent('click', {
                            view: window,
                            bubbles: true,
                            cancelable: true
                          });
                          element.dispatchEvent(event);
                        } catch(e) {}
                      }

                      function clickTextButtons(root) {
                        root = root || document;
                        var all = root.querySelectorAll('button, a, div[role="button"], span');
                        for (var i = 0; i < all.length; i++) {
                          var btn = all[i];
                          var text = (btn.innerText || btn.textContent || '').trim().toLowerCase();
                          if (text === 'play' || text === 'start' || text === 'stream' || text.indexOf('click to play') !== -1) {
                            simulateClick(btn);
                            console.log('Automated click triggered on text button: ' + text);
                          }
                        }
                        var allElements = root.querySelectorAll('*');
                        for (var j = 0; j < allElements.length; j++) {
                          if (allElements[j].shadowRoot) {
                            clickTextButtons(allElements[j].shadowRoot);
                          }
                        }
                      }

                      function isWebtorLoading() {
                        var text = (document.body ? (document.body.innerText || document.body.textContent || '') : '').toLowerCase();
                        return text.indexOf('checking magnet') !== -1 ||
                               text.indexOf('searching for stream') !== -1 ||
                               text.indexOf('retrieving') !== -1 ||
                               text.indexOf('probing') !== -1 ||
                               text.indexOf('transcoder') !== -1 ||
                               text.indexOf('buffering content') !== -1 ||
                               text.indexOf('loading opensubtitles') !== -1;
                      }

                      function isAnyVideoPlaying() {
                        var videos = [];
                        findAllInShadows('video', document, videos);
                        for (var i = 0; i < videos.length; i++) {
                          var v = videos[i];
                          if (v && !v.paused && v.currentTime > 0) {
                            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                              window.flutter_inappwebview.callHandler('onVideoPlaying');
                            }
                            return true;
                          }
                        }
                        return false;
                      }

                      function autoClickPlay() {
                        if (isWebtorLoading()) {
                          return;
                        }

                        if (isAnyVideoPlaying()) {
                          return;
                        }

                        var selectors = [
                          'button[data-plyr="play"]',
                          '.plyr__control--overlaid',
                          '.plyr__controls [data-plyr="play"]',
                          'button[aria-label="Play"]',
                          'button[aria-label="Play Video"]',
                          'button[title="Play"]',
                          '.webtor-play',
                          '.play-btn',
                          'div.plyr__video-wrapper'
                        ];

                        for (var i = 0; i < selectors.length; i++) {
                          var found = findAllInShadows(selectors[i]);
                          for (var j = 0; j < found.length; j++) {
                            simulateClick(found[j]);
                          }
                        }

                        var classIds = findAllInShadows('[class*="plyr__control--overlaid"]');
                        for (var k = 0; k < classIds.length; k++) {
                          simulateClick(classIds[k]);
                        }

                        clickTextButtons();
                      }
                      
                      setInterval(autoClickPlay, 800);
                    })();
                  """,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
              ]),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                useHybridComposition: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                useWideViewPort: true,
                loadWithOverviewMode: true,
                // Ad-blocking: Prevents popups and tab redirects from opening
                javaScriptCanOpenWindowsAutomatically: false,
                supportMultipleWindows: false,
                contentBlockers: widget.embedUrl.contains('youtube') || widget.embedUrl.contains('youtu.be')
                    ? []
                    : [
                        // Block common ad servers and popup redirects
                        ContentBlocker(
                          trigger: ContentBlockerTrigger(urlFilter: ".*(doubleclick|googleads|googlesyndication|popads|adsterra|exoclick|propellerads|onclickads|popcash|juicyads|exdynsrv|yepads|adbackgate|adbrau|addthis|adrta|adzerk|coinad|content-ad|histats|adrun|adservice|leadgeneration|mgid|outbrain|taboola|a.orola.net|clickadu|admaven|hilltopads).*"),
                          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
                        ),
                      ],
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'onVideoPlaying',
                  callback: (args) {
                    if (mounted && !_isTorrentPlaying) {
                      _countdownTimer?.cancel();
                      setState(() {
                        _isTorrentPlaying = true;
                      });
                    }
                  },
                );
              },
              onLoadStart: (controller, url) {
                setState(() {
                  _isLoading = true;
                });
              },
              onLoadStop: (controller, url) {
                setState(() {
                  _isLoading = false;
                });
              },
              onLoadResource: (controller, resource) {
                final urlStr = resource.url?.toString() ?? '';
                if (!_isEmbedOnly && _isValidVideoResource(resource.url)) {
                  debugPrint('WebViewPlayerScreen Intercepted Stream URL: $urlStr');
                  if (mounted && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop(urlStr);
                  }
                }
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                if (widget.embedUrl.startsWith('magnet:')) {
                  return NavigationActionPolicy.ALLOW;
                }
                // Allow sub-frame navigation (like inside player iframes) to prevent "Network error - All servers failed"
                if (!navigationAction.isForMainFrame) {
                  return NavigationActionPolicy.ALLOW;
                }

                // Allow auto-redirects (non-user gesture) to accommodate mirror CDNs
                if (navigationAction.hasGesture == false) {
                  return NavigationActionPolicy.ALLOW;
                }

                final url = navigationAction.request.url?.toString() ?? '';
                final host = navigationAction.request.url?.host ?? '';
                
                final originalUri = WebUri(widget.embedUrl);
                final originalHost = originalUri.host;
                
                // Allow original domain, trusted video partners, common video hosting, or internal schemas
                if (host == originalHost || 
                    host.isEmpty || 
                    host.contains('youtube') ||
                    host.contains('youtu.be') ||
                    host.contains('googlevideo') ||
                    host.contains('ytimg') ||
                    host.contains('vidsrc') || 
                    host.contains('vidsrcme') ||
                    host.contains('orchestranova') ||
                    host.contains('vaplayer') ||
                    host.contains('vidlink') ||
                    host.contains('streamimdb') ||
                    host.contains('playimdb') ||
                    host.contains('streamtape') ||
                    host.contains('strcloud.club') ||
                    host.contains('tpead.net') ||
                    host.contains('coreflix') ||
                    host.contains('embed.su') ||
                    host.contains('superembed') ||
                    host.contains('multiembed') ||
                    host.contains('showbox') ||
                    host.contains('vidbinge') ||
                    host.contains('autoembed') ||
                    host.contains('warezcdn') ||
                    host.contains('embedsu') ||
                    host.contains('vipr.im') ||
                    host.contains('stream') ||
                    url.startsWith('data:')) {
                  return NavigationActionPolicy.ALLOW;
                }
                
                debugPrint('WebViewPlayerScreen: Blocked ad redirect to $url');
                return NavigationActionPolicy.CANCEL;
              },
              onCreateWindow: (controller, createWindowAction) async {
                // Block popups by consuming the request and returning true
                return true;
              },
            ),
  
            // Loading spinner overlay
            if (widget.embedUrl.startsWith('magnet:') ? !_isTorrentPlaying : _isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: Stack(
                    children: [
                      if (widget.backdropUrl != null && widget.backdropUrl!.isNotEmpty)
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0.85,
                            child: Image.network(
                              widget.backdropUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: widget.backdropUrl != null ? 0.25 : 1.0),
                          ),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(
                              color: Color(0xFFFF2E93), // Neon pink spinner
                            ),
                            if (widget.embedUrl.startsWith('magnet:')) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Connecting to Peers & Loading Torrent...\nDismissing in $_countdownSeconds seconds',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Floating Back Button to exit the WebView player
            Positioned(
              top: 20,
              left: 20,
              child: SafeArea(
                child: ClipOval(
                  child: Material(
                    color: Colors.black54,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
