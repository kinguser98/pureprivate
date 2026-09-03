import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';

class OAuthWebViewDialog extends StatefulWidget {
  final String initialUrl;
  final String title;
  final String redirectPrefix;
  final Function(String redirectedUrl) onRedirectMatched;

  const OAuthWebViewDialog({
    super.key,
    required this.initialUrl,
    required this.title,
    required this.redirectPrefix,
    required this.onRedirectMatched,
  });

  @override
  State<OAuthWebViewDialog> createState() => _OAuthWebViewDialogState();
}

class _OAuthWebViewDialogState extends State<OAuthWebViewDialog> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  double _progress = 0.0;
  bool _hasCaptured = false;

  void _checkUrl(WebUri? uri) {
    if (uri == null || _hasCaptured) return;
    final urlStr = uri.toString();

    if (urlStr.startsWith(widget.redirectPrefix) ||
        urlStr.contains('code=') ||
        urlStr.contains('access_token=') ||
        urlStr.contains('approvalCode=')) {
      _hasCaptured = true;
      widget.onRedirectMatched(urlStr);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: double.infinity,
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFF1E293B),
                child: Row(
                  children: [
                    const Icon(Icons.security_rounded, color: Colors.greenAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              if (_isLoading)
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  color: const Color(0xFFEF4444),
                  backgroundColor: Colors.transparent,
                  minHeight: 3,
                ),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    userAgent: 'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                    thirdPartyCookiesEnabled: true,
                    domStorageEnabled: true,
                  ),
                  onWebViewCreated: (c) => _controller = c,
                  onLoadStart: (c, uri) {
                    if (mounted) setState(() => _isLoading = true);
                    _checkUrl(uri);
                  },
                  onLoadStop: (c, uri) {
                    if (mounted) setState(() => _isLoading = false);
                    _checkUrl(uri);
                  },
                  onProgressChanged: (c, p) {
                    if (mounted) setState(() => _progress = p / 100);
                  },
                  shouldOverrideUrlLoading: (c, action) async {
                    final uri = action.request.url;
                    _checkUrl(uri);
                    return NavigationActionPolicy.ALLOW;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
