import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class EmbedResolver {
  static bool _isValidVideoResource(Uri? uri) {
    if (uri == null) return false;
    final urlStr = uri.toString();
    final lower = urlStr.toLowerCase();
    
    // 1. Exclude common static assets by checking the URL path and extension
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
    
    // Also filter query parameters that might contain these extensions
    if (lower.contains('.js?') ||
        lower.contains('.css?') ||
        lower.contains('.png?') ||
        lower.contains('.jpg?') ||
        lower.contains('.jpeg?') ||
        lower.contains('.woff2?')) {
      return false;
    }
    
    // 2. Exclude typical ad networks, logs, trackers, and library names
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
    
    // 3. Match video stream patterns (includes master.txt from CloudStream's StreamHG extractor)
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
           lower.contains('master.txt') ||
           lower.contains('get_video') ||
           lower.contains('streamtape') ||
           lower.contains('strcloud.club') ||
           lower.contains('tpead.net');
  }

  /// Parses the 'headers' query parameter from the stream URL if it exists,
  /// returning a Map of HTTP headers. Merges with [fallbackHeaders] if provided.
  static Map<String, String> getHeadersForUrl(String url, {Map<String, String>? fallbackHeaders}) {
    final Map<String, String> result = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
    
    if (fallbackHeaders != null) {
      result.addAll(fallbackHeaders);
    }

    try {
      final uri = Uri.parse(url);
      final headersParam = uri.queryParameters['headers'];
      if (headersParam != null && headersParam.isNotEmpty) {
        final decodedJson = jsonDecode(headersParam);
        if (decodedJson is Map) {
          decodedJson.forEach((key, value) {
            final keyStr = key.toString();
            final valStr = value.toString();
            if (keyStr.toLowerCase() == 'referer') {
              result['Referer'] = valStr;
            } else if (keyStr.toLowerCase() == 'origin') {
              result['Origin'] = valStr;
            } else {
              result[keyStr] = valStr;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('EmbedResolver: Error parsing headers from URL: $e');
    }
    return result;
  }

  /// Resolves an embed page URL to its direct media streaming URL (.m3u8 or .mp4)
  /// using a background InAppWebView to intercept network requests.
  static Future<String?> resolve(BuildContext context, String embedUrl) async {
    final completer = Completer<String?>();
    bool dismissed = false;

    // Show a loading dialog during link resolution
    showDialog<void>(
      context: context,
      barrierDismissible: true, // Allow user to tap outside to cancel
      builder: (dialogContext) {
        return WillPopScope(
          onWillPop: () async {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
            dismissed = true;
            return true;
          },
          child: AlertDialog(
            backgroundColor: const Color(0xFF16161A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            title: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Color(0xFFFF2E93),
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'RESOLVING STREAM LINK',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Solve Cloudflare challenge if prompted...',
                        style: TextStyle(color: Colors.white38, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: Container(
              width: 320,
              height: 260,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(embedUrl),
                  headers: {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  },
                ),
                onWebViewCreated: (controller) {
                  controller.addJavaScriptHandler(
                    handlerName: 'videoFound',
                    callback: (args) {
                      if (args.isNotEmpty) {
                        final String urlStr = args[0].toString();
                        debugPrint('EmbedResolver: Video URL reported by JS handler: $urlStr');
                        if (!completer.isCompleted) {
                          completer.complete(urlStr);
                          if (!dismissed) {
                            Navigator.of(dialogContext).pop(); // Close dialog
                            dismissed = true;
                          }
                        }
                      }
                    },
                  );
                },
                initialUserScripts: UnmodifiableListView<UserScript>([
                  UserScript(
                    source: """
                      (function() {
                        console.log("EmbedResolver JS Injected into: " + window.location.href);
                        
                        function simulateClick(el) {
                          try {
                            el.focus();
                            var eventTypes = ['mousedown', 'mouseup', 'click'];
                            eventTypes.forEach(function(type) {
                              var e = new MouseEvent(type, {
                                bubbles: true,
                                cancelable: true,
                                view: window,
                                clientX: el.getBoundingClientRect().left + el.clientWidth / 2,
                                clientY: el.getBoundingClientRect().top + el.clientHeight / 2
                              });
                              el.dispatchEvent(e);
                            });
                          } catch(e) {}
                        }

                        // Remove overlay ads
                        function removeAdOverlays() {
                          try {
                            var divs = document.querySelectorAll('div');
                            divs.forEach(function(div) {
                              var style = window.getComputedStyle(div);
                              if (style.position === 'absolute' || style.position === 'fixed') {
                                var zIndex = parseInt(style.zIndex);
                                if (zIndex > 100 && (style.width === '100%' || div.clientWidth > window.innerWidth * 0.9)) {
                                  div.style.display = 'none';
                                }
                              }
                            });
                          } catch(e) {}
                        }

                        // DOM checker for video tags
                        var checkVideo = setInterval(function() {
                          try {
                            var vids = document.querySelectorAll('video');
                            vids.forEach(function(v) {
                              var src = v.src;
                              if (src && src.startsWith('http') && !src.startsWith('blob:')) {
                                clearInterval(checkVideo);
                                window.flutter_inappwebview.callHandler('videoFound', src);
                              }
                              var sources = v.querySelectorAll('source');
                              sources.forEach(function(srcEl) {
                                if (srcEl.src && srcEl.src.startsWith('http') && !srcEl.src.startsWith('blob:')) {
                                  clearInterval(checkVideo);
                                  window.flutter_inappwebview.callHandler('videoFound', srcEl.src);
                                }
                              });
                            });
                          } catch(e) {}
                        }, 500);

                        var count = 0;
                        var interval = setInterval(function() {
                          count++;
                          if (count > 40) {
                            clearInterval(interval);
                            return;
                          }

                          removeAdOverlays();

                          // 1. Click common play selectors
                          var selectors = [
                            '.vjs-big-play-button',
                            '.jw-display-icon-container',
                            '.play-button',
                            '.play-icon',
                            '#play-button',
                            '#play',
                            '.play',
                            '.watch-btn',
                            '.click-to-play',
                            '[class*="play"]',
                            '[id*="play"]',
                            '.vjs-tech',
                            'button',
                            'svg'
                          ];
                          selectors.forEach(function(sel) {
                            try {
                              var els = document.querySelectorAll(sel);
                              els.forEach(function(el) {
                                simulateClick(el);
                              });
                            } catch(e) {}
                          });

                          // 2. Click the center of the page
                          try {
                            var x = window.innerWidth / 2;
                            var y = window.innerHeight / 2;
                            var el = document.elementFromPoint(x, y);
                            if (el && el.tagName !== 'HTML' && el.tagName !== 'BODY') {
                              simulateClick(el);
                            }
                          } catch(e) {}
                        }, 400);
                      })();
                    """,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                    forMainFrameOnly: false,
                  )
                ]),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  javaScriptCanOpenWindowsAutomatically: false,
                  supportMultipleWindows: false,
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                ),
                onLoadStop: (controller, url) async {
                  debugPrint('EmbedResolver: Frame loaded: $url');
                  // Re-inject JS script execution to guarantee clicker runs on dynamic page modifications
                  await controller.evaluateJavascript(source: """
                    (function() {
                      console.log("EmbedResolver onLoadStop injected manually.");
                      
                      function simulateClick(el) {
                        try {
                          el.focus();
                          var eventTypes = ['mousedown', 'mouseup', 'click'];
                          eventTypes.forEach(function(type) {
                            var e = new MouseEvent(type, {
                              bubbles: true,
                              cancelable: true,
                              view: window,
                              clientX: el.getBoundingClientRect().left + el.clientWidth / 2,
                              clientY: el.getBoundingClientRect().top + el.clientHeight / 2
                            });
                            el.dispatchEvent(e);
                          });
                        } catch(e) {}
                      }

                      // Remove overlay ads
                      function removeAdOverlays() {
                        try {
                          var divs = document.querySelectorAll('div');
                          divs.forEach(function(div) {
                            var style = window.getComputedStyle(div);
                            if (style.position === 'absolute' || style.position === 'fixed') {
                              var zIndex = parseInt(style.zIndex);
                              if (zIndex > 100 && (style.width === '100%' || div.clientWidth > window.innerWidth * 0.9)) {
                                div.style.display = 'none';
                              }
                            }
                          });
                        } catch(e) {}
                      }

                      removeAdOverlays();

                      // Click common play selectors
                      var selectors = [
                        '.vjs-big-play-button',
                        '.jw-display-icon-container',
                        '.play-button',
                        '.play-icon',
                        '#play-button',
                        '#play',
                        '.play',
                        '.watch-btn',
                        '.click-to-play',
                        '[class*="play"]',
                        '[id*="play"]',
                        '.vjs-tech',
                        'button',
                        'svg'
                      ];
                      selectors.forEach(function(sel) {
                        try {
                          var els = document.querySelectorAll(sel);
                          els.forEach(function(el) {
                            simulateClick(el);
                          });
                        } catch(e) {}
                      });

                      // Click center
                      try {
                        var x = window.innerWidth / 2;
                        var y = window.innerHeight / 2;
                        var el = document.elementFromPoint(x, y);
                        if (el && el.tagName !== 'HTML' && el.tagName !== 'BODY') {
                          simulateClick(el);
                        }
                      } catch(e) {}
                    })();
                  """);
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  // Allow sub-frame navigation (like inside player iframes) to prevent "Network error - All servers failed"
                  if (!navigationAction.isForMainFrame) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  final url = navigationAction.request.url?.toString() ?? '';
                  final host = navigationAction.request.url?.host ?? '';
                  
                  final originalUri = WebUri(embedUrl);
                  final originalHost = originalUri.host;
                  
                  final lower = url.toLowerCase();
                  if (lower.contains('adserver') || 
                      lower.contains('adsystem') || 
                      lower.contains('popads') || 
                      lower.contains('onclick') || 
                      lower.contains('exoclick') || 
                      lower.contains('adsterra') ||
                      lower.contains('/ads/') ||
                      lower.contains('redirect')) {
                    debugPrint('EmbedResolver: Blocked ad URL in navigation: $url');
                    return NavigationActionPolicy.CANCEL;
                  }
                  
                  if (host == originalHost || 
                      host.isEmpty || 
                      host.contains('vidsrc') || 
                      host.contains('vidsrcme') ||
                      host.contains('orchestranova') ||
                      host.contains('vaplayer') ||
                      host.contains('vidplay') ||
                      host.contains('mcloud') ||
                      host.contains('rcpcdn') ||
                      host.contains('streamimdb') ||
                      host.contains('playimdb') ||
                      host.contains('streamtape') ||
                      host.contains('strcloud.club') ||
                      host.contains('tpead.net') ||
                      host.contains('hglink') ||
                      host.contains('hgcloud') ||
                      host.contains('cavanhabg') ||
                      host.contains('cavanha') ||
                      host.contains('tryzendm') ||
                      host.contains('vidhidepro') ||
                      host.contains('filemoon') ||
                      url.startsWith('data:')) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  
                  debugPrint('EmbedResolver: Blocked ad redirect to $url');
                  return NavigationActionPolicy.CANCEL;
                },
                onCreateWindow: (controller, createWindowAction) async {
                  debugPrint('EmbedResolver: Blocked popup window');
                  return true;
                },
                onLoadResource: (controller, resource) {
                  final urlStr = resource.url?.toString() ?? '';
                  debugPrint('EmbedResolver Intercepted: $urlStr');
                  
                  if (_isValidVideoResource(resource.url)) {
                    debugPrint('EmbedResolver: Found direct video URL: $urlStr');
                    if (!completer.isCompleted) {
                      completer.complete(urlStr);
                      if (!dismissed) {
                        Navigator.of(dialogContext).pop(); // Close dialog
                        dismissed = true;
                      }
                    }
                  }
                },
              ),
            ),
          ),
        );
      },
    ).then((_) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    // Enforce a 25-second timeout (HGCloud pages need more time to load m3u8)
    return completer.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        return null;
      },
    );
  }
}

