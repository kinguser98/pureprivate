import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:private_cinema_mobile/widgets/resolving_dialog.dart';
import 'package:private_cinema_mobile/data/dns_proxy.dart';

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
        lower.contains('placeholder') ||
        lower.contains('trailer') ||
        lower.contains('youtube') ||
        lower.contains('youtu.be') ||
        lower.contains('ytimg') ||
        lower.contains('googlevideo')) {
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
           lower.contains('pixeldrain.com/api/file') ||
           lower.contains('fsl.hubcloud') ||
           lower.contains('/download/file/') ||
           lower.contains('r2.dev') ||
           lower.contains('r2.cloudflarestorage.com') ||
           lower.contains('workers.dev') ||
           lower.contains('.s3.') ||
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
    final lower = embedUrl.toLowerCase();

    // 1. Direct video streams require no unpacking
    if (lower.contains('.r2.cloudflarestorage.com') ||
        lower.contains('cdn.') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.mp4') ||
        lower.contains('.mkv?') ||
        lower.contains('.mp4?') ||
        lower.contains('.m3u8')) {
      return embedUrl;
    }

    // 2. PixelDrain direct conversion
    if (lower.contains('pixeldrain.com/u/') || lower.contains('pixeldrain.dev/u/')) {
      final pxId = RegExp(r'pixeldrain\.(?:com|dev)/u/([A-Za-z0-9_-]+)').firstMatch(embedUrl)?.group(1);
      if (pxId != null) {
        return 'https://pixeldrain.com/api/file/$pxId';
      }
    }

    // 3. Fast pure-HTTP 3-hop HubDrive / HubCloud unpacking (completes in 300ms)
    if (lower.contains('hubdrive.') || lower.contains('hubcloud.') || lower.contains('mdrive.')) {
      try {
        final fastList = await _unpackFastHttp(embedUrl);
        if (fastList.isNotEmpty) {
          debugPrint('EmbedResolver: Fast HTTP unpacked ${fastList.first}');
          return fastList.first;
        }
      } catch (e) {
        debugPrint('EmbedResolver fast HTTP unpack error: $e');
      }
    }

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
        initialSize: const Size(1920, 1080),
        initialUrlRequest: URLRequest(
          url: WebUri(embedUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Referer': 'https://www.movy.bz/',
          },
        ),
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: """
              (function() {
                // 1. Mock standard desktop window and screen dimensions to bypass anti-devtool checks
                try {
                  Object.defineProperty(window, 'outerWidth', { get: function() { return 1920; }, configurable: true });
                  Object.defineProperty(window, 'outerHeight', { get: function() { return 1080; }, configurable: true });
                  Object.defineProperty(window, 'innerWidth', { get: function() { return 1920; }, configurable: true });
                  Object.defineProperty(window, 'innerHeight', { get: function() { return 1080; }, configurable: true });
                  Object.defineProperty(window, 'screen', {
                    get: function() {
                      return {
                        availWidth: 1920,
                        availHeight: 1080,
                        width: 1920,
                        height: 1080,
                        colorDepth: 24,
                        pixelDepth: 24
                      };
                    },
                    configurable: true
                  });
                } catch(e) {}

                // 2. Suppress anti-devtool redirection
                try {
                  var origSetHref = Object.getOwnPropertyDescriptor(window.location, 'href');
                  if (origSetHref && origSetHref.set) {
                    var oldSetter = origSetHref.set;
                    Object.defineProperty(window.location, 'href', {
                      set: function(val) {
                        if (val === 'about:blank' || (typeof val === 'string' && val.indexOf('about:') !== -1)) return;
                        oldSetter.call(window.location, val);
                      }
                    });
                  }
                } catch(e) {}

                // 3. Neutralize console.clear / debugger traps
                try {
                  console.clear = function() {};
                  window.debugger = function() {};
                } catch(e) {}
              })();
            """,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            forMainFrameOnly: false,
          ),
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
                  if (count > 30) {
                    clearInterval(interval);
                    return;
                  }

                  removeAdOverlays();

                  // Click dedicated play selectors during initial 3 seconds only
                  if (count <= 4) {
                    var selectors = [
                      '.vjs-big-play-button',
                      '.jw-display-icon-container',
                      '.play-button',
                      '.play-icon',
                      '#play-button',
                      '#play',
                      '.watch-btn',
                      '.click-to-play'
                    ];
                    selectors.forEach(function(sel) {
                      try {
                        var els = document.querySelectorAll(sel);
                        els.forEach(function(el) {
                          simulateClick(el);
                        });
                      } catch(e) {}
                    });
                  }

                  // HubCloud / FastCloud / GDFlix automated button clicking
                  try {
                    var hubButtons = document.querySelectorAll('a.btn, button.btn, .btn-success, .btn-primary, #download, .download-btn, a[href*="hubcloud"], a[href*="pixeldrain"], a[href*="fastcloud"]');
                    hubButtons.forEach(function(btn) {
                      var txt = (btn.textContent || '').toLowerCase();
                      if (txt.indexOf('generate') !== -1 ||
                          txt.indexOf('download') !== -1 ||
                          txt.indexOf('fast') !== -1 ||
                          txt.indexOf('fsl') !== -1 ||
                          txt.indexOf('pixeldrain') !== -1 ||
                          txt.indexOf('stream') !== -1 ||
                          txt.indexOf('proceed') !== -1 ||
                          txt.indexOf('link') !== -1) {
                        simulateClick(btn);
                      }
                    });
                  } catch(e) {}

                  // On Cinejoy specifically, if Server 1 is buffering, attempt Server 2 (Solara / VidSrc) after 3s
                  if (window.location.href.indexOf('cinejoy.to') !== -1 && count === 6) {
                    try {
                      var serverElements = document.querySelectorAll('button, div, li, span');
                      serverElements.forEach(function(el) {
                        var txt = (el.textContent || '').trim().toLowerCase();
                        if (txt === 'solara' || txt === 'server 2' || txt === 'athens' || txt === 'joy') {
                          simulateClick(el);
                        }
                      });
                    } catch(e) {}
                  }
                }, 500);
              })();
            """,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
            forMainFrameOnly: false,
          )
        ]),
        initialSettings: InAppWebViewSettings(
          userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          javaScriptEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          javaScriptCanOpenWindowsAutomatically: true,
          supportMultipleWindows: false,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          useOnLoadResource: true,
          useShouldInterceptAjaxRequest: true,
          useShouldInterceptFetchRequest: true,
          cacheEnabled: true,
        ),
        onConsoleMessage: (controller, consoleMessage) {
          debugPrint('EmbedResolver JS Console: [${consoleMessage.messageLevel}] ${consoleMessage.message}');
        },
        onReceivedError: (controller, request, error) {
          debugPrint('EmbedResolver Network Error: ${error.type} - ${error.description} on ${request.url}');
        },
        onReceivedHttpError: (controller, request, errorResponse) {
          debugPrint('EmbedResolver HTTP Error: ${errorResponse.statusCode} - ${errorResponse.reasonPhrase} on ${request.url}');
        },
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
              function clickElement(el) {
                if (!el) return;
                try {
                  el.focus();
                  ['mousedown', 'mouseup', 'click'].forEach(function(type) {
                    var ev = new MouseEvent(type, {
                      bubbles: true,
                      cancelable: true,
                      view: window,
                      clientX: (el.getBoundingClientRect ? el.getBoundingClientRect().left + 10 : 0),
                      clientY: (el.getBoundingClientRect ? el.getBoundingClientRect().top + 10 : 0)
                    });
                    el.dispatchEvent(ev);
                  });
                  if (typeof el.click === 'function') el.click();
                } catch(e) {}
              }

              // Click all standard play buttons
              var selectors = [
                '.vjs-big-play-button',
                '.jw-display-icon-container',
                '.play-button',
                '.play-icon',
                '#play-button',
                '#play',
                '.watch-btn',
                '.click-to-play',
                '.play',
                'button',
                'video'
              ];
              selectors.forEach(function(sel) {
                try {
                  document.querySelectorAll(sel).forEach(function(el) {
                    clickElement(el);
                  });
                } catch(e) {}
              });
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
            debugPrint('EmbedResolver: Found video resource: $urlStr');
            
            final lower = urlStr.toLowerCase();
            final bool isMaster = lower.contains('master.m3u8') ||
                lower.contains('playlist.m3u8') ||
                lower.contains('manifest.m3u8') ||
                lower.contains('all.m3u8') ||
                lower.contains('/master');

            void completeWithUrl(String targetUrl) {
              if (completer.isCompleted) return;
              try {
                final embedUri = Uri.parse(embedUrl);
                final refererHost = '${embedUri.scheme}://${embedUri.host}/';
                final originHost = '${embedUri.scheme}://${embedUri.host}';
                
                final headersMap = {
                  'Referer': refererHost,
                  'Origin': originHost,
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                };
                
                final videoUri = Uri.parse(targetUrl);
                final queryParams = Map<String, String>.from(videoUri.queryParameters);
                queryParams['headers'] = jsonEncode(headersMap);
                
                final resolvedWithHeaders = videoUri.replace(queryParameters: queryParams).toString();
                completer.complete(resolvedWithHeaders);
              } catch (e) {
                debugPrint('EmbedResolver: Error building headers query: $e');
                completer.complete(targetUrl);
              }
              
              if (!dismissed) {
                Navigator.of(context).pop(); // Close dialog
                dismissed = true;
              }
            }

            final isPeakstormVariant = RegExp(r'index-s(\d+p)-v(\d+)-a(\d+)\.m3u8').hasMatch(urlStr);
            if (isPeakstormVariant) {
              final directMaster = urlStr.replaceAll(RegExp(r'index-s\d+p-v\d+-a\d+\.m3u8'), 'master.m3u8');
              debugPrint('EmbedResolver: Using direct master HLS: $directMaster');
              completeWithUrl(directMaster);
              return;
            }

            if (isMaster) {
              debugPrint('EmbedResolver: Prioritizing master HLS playlist: $urlStr');
              completeWithUrl(urlStr);
            } else {
              // Non-master (variant / mp4): wait 400ms in case master playlist arrives
              Future.delayed(const Duration(milliseconds: 400), () {
                if (!completer.isCompleted) {
                  completeWithUrl(urlStr);
                }
              });
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

  static Future<List<String>> _unpackFastHttp(String initialUrl) async {
    final directUrls = <String>[];
    const headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
      'Cookie': 'xla=s4t',
    };

    try {
      String currentUrl = initialUrl;

      // Hop 1: HubDrive / mdrive -> HubCloud
      if (currentUrl.contains('hubdrive.') || currentUrl.contains('drive.') || currentUrl.contains('mdrive.')) {
        final res1 = await http.get(Uri.parse(currentUrl), headers: headers).timeout(const Duration(seconds: 4));
        final hubMatch = RegExp(r'href="(https?://[^"]*hubcloud[^"]*)"').firstMatch(res1.body);
        if (hubMatch != null) currentUrl = hubMatch.group(1)!;
      }

      // Hop 2: HubCloud -> Gateway
      if (currentUrl.contains('hubcloud.')) {
        final res2 = await http.get(Uri.parse(currentUrl), headers: {
          ...headers,
          'Referer': initialUrl,
        }).timeout(const Duration(seconds: 4));

        final targetMatch = RegExp(r"var\s+url\s*=\s*'([^']+)'").firstMatch(res2.body) ??
                            RegExp(r'id="download"[^>]*href="([^"]+)"').firstMatch(res2.body);
        if (targetMatch != null) currentUrl = targetMatch.group(1)!;
      }

      // Hop 3: Gateway -> Direct streams
      final res3 = await http.get(Uri.parse(currentUrl), headers: {
        ...headers,
        'Referer': 'https://hubcloud.cx/',
      }).timeout(const Duration(seconds: 4));

      final btnRegex = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)<\/a>', caseSensitive: false, dotAll: true);
      for (final m in btnRegex.allMatches(res3.body)) {
        final href = m.group(1) ?? '';
        final lowerHref = href.toLowerCase();

        if (lowerHref.contains('.r2.cloudflarestorage.com') ||
            lowerHref.contains('cdn.') ||
            lowerHref.endsWith('.mkv') ||
            lowerHref.endsWith('.mp4') ||
            lowerHref.contains('.mkv?') ||
            lowerHref.contains('.mp4?')) {
          directUrls.add(href);
        }
      }
    } catch (_) {}

    return directUrls;
  }
}

