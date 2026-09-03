import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class AdblockFilterEngine {
  /// Known aggressive ad networks and pop-under patterns
  static final List<String> adDomainFilters = [
    '.*doubleclick\\.net.*',
    '.*googlesyndication\\.com.*',
    '.*googleadservices\\.com.*',
    '.*popads\\.net.*',
    '.*popcash\\.net.*',
    '.*propellerads\\.com.*',
    '.*adcash\\.com.*',
    '.*exoclick\\.com.*',
    '.*juicyads\\.com.*',
    '.*adsterra\\.com.*',
    '.*monetag\\.com.*',
    '.*hilltopads\\.com.*',
    '.*clickadu\\.com.*',
    '.*onclickmega\\.com.*',
    '.*trafficjunky\\.com.*',
    '.*adnxs\\.com.*',
    '.*criteo\\.com.*',
    '.*taboola\\.com.*',
    '.*outbrain\\.com.*',
    '.*zeroredirect.*',
    '.*safelink.*',
    '.*redirect.*ad.*',
    '.*adsystem.*',
  ];

  /// Compiles ContentBlockers for InAppWebView
  static List<ContentBlocker> get contentBlockers {
    final List<ContentBlocker> blockers = [];
    for (final pattern in adDomainFilters) {
      blockers.add(
        ContentBlocker(
          trigger: ContentBlockerTrigger(
            urlFilter: pattern,
          ),
          action: ContentBlockerAction(
            type: ContentBlockerActionType.BLOCK,
          ),
        ),
      );
    }

    // Hide common ad containers via CSS injection
    blockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: '.*'),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector: '.ad, .ads, .adsbygoogle, .banner-ad, [class*="ad-banner"], [id*="google_ads"], '
              '[class*="pop-under"], .ad-container, #ad-wrapper, .floating-ad',
        ),
      ),
    );

    return blockers;
  }

  /// JavaScript injected at DOCUMENT_START to neuter popups, alert traps, and redirect loops
  static const String antiPopupUserScript = '''
    (function() {
      // 1. Neuter window.open and blank targets
      const origOpen = window.open;
      window.open = function(url, target, features) {
        if (!url || url === 'about:blank' || url.includes('javascript:')) {
          return null;
        }
        // Notify Flutter handler instead of opening rogue popups
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('onInterceptedPopup', url);
        }
        return null;
      };

      // 2. Disable annoying alert/confirm loops
      window.alert = function() {};
      window.confirm = function() { return true; };
      window.prompt = function() { return null; };

      // 3. Remove aggressive click-jackers on body
      document.addEventListener('DOMContentLoaded', () => {
        document.querySelectorAll('a[target="_blank"]').forEach(a => {
          a.setAttribute('target', '_self');
        });
      });
    })();
  ''';

  /// JavaScript injected to sniff media from HTML5 video tags, fetch, and XHR requests
  static const String mediaSnifferUserScript = '''
    (function() {
      function sendMediaToApp(url, type) {
        if (!url || typeof url !== 'string') return;
        if (url.startsWith('blob:') || url.startsWith('http://') || url.startsWith('https://')) {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler('onMediaDetected', {
              url: url,
              type: type,
              pageTitle: document.title || 'Web Video',
            });
          }
        }
      }

      // Hook HTMLMediaElement prototype
      const origPlay = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function() {
        if (this.src) sendMediaToApp(this.src, 'video');
        if (this.currentSrc) sendMediaToApp(this.currentSrc, 'video');
        return origPlay.apply(this, arguments);
      };

      // Hook HTMLVideoElement src assignment
      const origVideoSrc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
      if (origVideoSrc && origVideoSrc.set) {
        Object.defineProperty(HTMLMediaElement.prototype, 'src', {
          set: function(val) {
            sendMediaToApp(val, 'video');
            return origVideoSrc.set.apply(this, arguments);
          },
          get: origVideoSrc.get
        });
      }

      // Check DOM periodically for video/source elements
      setInterval(() => {
        document.querySelectorAll('video, source').forEach(el => {
          const s = el.src || el.getAttribute('src');
          if (s) sendMediaToApp(s, 'video');
        });
      }, 1500);
    })();
  ''';
}
