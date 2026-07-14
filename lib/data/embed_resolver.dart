import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:private_cinema_ios/widgets/resolving_dialog.dart';

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
  /// using a background HeadlessInAppWebView to intercept network requests.
  static Future<String?> resolve(BuildContext context, String embedUrl) async {
    final completer = Completer<String?>();
    bool dismissed = false;
    HeadlessInAppWebView? headlessWebView;

    // Show a clean loading dialog during background link resolution
    showDialog<void>(
      context: context,
      barrierDismissible: true, // Allow user to tap outside to cancel
      builder: (dialogContext) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
            dismissed = true;
          },
          child: const ResolvingProgressDialog(
            title: 'RESOLVING STREAM LINK',
            subtitle: 'Extracting video source...',
          ),
        );
      },
    ).then((_) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    try {
      headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(embedUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ),
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: """
              (function() {
                console.log("HeadlessResolver JS Injected into: " + window.location.href);
                
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

                  // Click the center of the page
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
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: 'videoFound',
            callback: (args) {
              if (args.isNotEmpty) {
                final String urlStr = args[0].toString();
                debugPrint('EmbedResolver: Video URL found: $urlStr');
                if (!completer.isCompleted) {
                  completer.complete(urlStr);
                  if (!dismissed) {
                    Navigator.of(context).pop(); // Close dialog
                    dismissed = true;
                  }
                }
              }
            },
          );
        },
        onLoadStop: (controller, url) async {
          debugPrint('EmbedResolver: Headless frame loaded: $url');
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
          if (!navigationAction.isForMainFrame) {
            return NavigationActionPolicy.ALLOW;
          }

          final url = navigationAction.request.url?.toString() ?? '';
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
          
          // Allow all other redirections and player frames in background HeadlessWebView
          return NavigationActionPolicy.ALLOW;
        },
        onLoadResource: (controller, resource) {
          final urlStr = resource.url?.toString() ?? '';
          if (_isValidVideoResource(resource.url)) {
            debugPrint('EmbedResolver: Found direct video URL in background: $urlStr');
            if (!completer.isCompleted) {
              // Construct headers Map to prevent HTTP 403 Forbidden errors in VideoPlayerScreen
              try {
                final embedUri = Uri.parse(embedUrl);
                final refererHost = '${embedUri.scheme}://${embedUri.host}/';
                final originHost = '${embedUri.scheme}://${embedUri.host}';
                
                final headersMap = {
                  'Referer': refererHost,
                  'Origin': originHost,
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                };
                
                final videoUri = Uri.parse(urlStr);
                final queryParams = Map<String, String>.from(videoUri.queryParameters);
                queryParams['headers'] = jsonEncode(headersMap);
                
                final resolvedWithHeaders = videoUri.replace(queryParameters: queryParams).toString();
                completer.complete(resolvedWithHeaders);
              } catch (e) {
                debugPrint('EmbedResolver: Error building headers query: $e');
                completer.complete(urlStr);
              }
              
              if (!dismissed) {
                Navigator.of(context).pop(); // Close dialog
                dismissed = true;
              }
            }
          }
        },
      );

      await headlessWebView.run();

      final result = await completer.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () => null,
      );

      return result;
    } catch (e) {
      debugPrint('EmbedResolver background resolution error: $e');
      return null;
    } finally {
      await headlessWebView?.dispose();
    }
  }
}

