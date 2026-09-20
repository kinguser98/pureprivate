import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:private_cinema_mobile/data/netmirror_ott_resolver.dart';

/// Opens NetMirror in a WebView so Cloudflare can be solved and session token extracted.
class NetmirrorOttVerifyScreen extends StatefulWidget {
  const NetmirrorOttVerifyScreen({super.key});

  @override
  State<NetmirrorOttVerifyScreen> createState() => _NetmirrorOttVerifyScreenState();
}

class _NetmirrorOttVerifyScreenState extends State<NetmirrorOttVerifyScreen> {
  InAppWebViewController? _controller;
  final TextEditingController _otpTextController = TextEditingController();
  bool   _solved      = false;
  bool   _extracting  = false;
  String _statusText  = 'Please wait / solve captcha if prompted...';
  double _progress    = 0;
  Timer? _autoPollTimer;

  @override
  void initState() {
    super.initState();
    // Auto-poll DOM every 1.5 seconds while active
    _autoPollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!_solved && !_extracting && _controller != null) {
        _extractOtpAndSave(_controller!, isAuto: true);
      }
    });
  }

  @override
  void dispose() {
    _autoPollTimer?.cancel();
    _otpTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        foregroundColor: Colors.white,
        title: const Text(
          'NetMirror OTT Verification',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Reload Page',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: () {
              _controller?.reload();
            },
          ),
          IconButton(
            tooltip: 'Sync from CloudStream',
            icon: const Icon(Icons.sync_rounded, color: Colors.cyanAccent),
            onPressed: _syncFromCloudStream,
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 1.0)
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              backgroundColor: Colors.grey[900],
              color: _solved ? Colors.greenAccent : Colors.blueAccent,
              minHeight: 3,
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            color: _solved
                ? Colors.green.withValues(alpha: 0.15)
                : const Color(0xFF1A1A2E),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _solved ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      color: _solved ? Colors.greenAccent : Colors.blueAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusText,
                        style: TextStyle(
                          color: _solved ? Colors.greenAccent : Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: _extracting ? null : () => _syncFromCloudStream(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Root Sync', style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                    ),
                    if (!_solved && _controller != null) ...[
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: _extracting ? null : () => _extractOtpAndSave(_controller!),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Verify Now', style: TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                      ),
                    ],
                  ],
                ),
                if (!_solved) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: TextField(
                            controller: _otpTextController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            style: const TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 2),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: 'Enter 6-digit OTP',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 0),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              filled: true,
                              fillColor: Colors.black45,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Colors.cyanAccent),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _extracting
                            ? null
                            : () {
                                final input = _otpTextController.text.trim();
                                if (input.length == 6) {
                                  _submitOtpCode(input);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyan[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: const Size(0, 36),
                        ),
                        child: const Text('Submit OTP', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  color: const Color(0xFF0D0D0D),
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri('https://netmirror.gg/tv'),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                      useHybridComposition: true,
                      transparentBackground: false,
                      underPageBackgroundColor: const Color(0xFF0D0D0D),
                      allowsInlineMediaPlayback: true,
                      isFraudulentWebsiteWarningEnabled: false,
                      allowsBackForwardNavigationGestures: true,
                      userAgent: Platform.isIOS
                          ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'
                          : 'Mozilla/5.0 (Linux; Android 13; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
                      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    ),
                    onWebViewCreated: (c) => _controller = c,
                    onProgressChanged: (controller, progress) {
                      if (mounted) setState(() => _progress = progress / 100.0);
                    },
                    onLoadStop: (controller, url) async {
                      if (_solved || _extracting) return;
                      await _extractOtpAndSave(controller);
                    },
                  ),
                ),
                if (_progress < 0.3 && !_solved)
                  Container(
                    color: const Color(0xFF0D0D0D),
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitOtpCode(String otp) async {
    if (_extracting || _solved) return;
    _extracting = true;
    if (mounted) setState(() => _statusText = 'Verifying OTP $otp...');

    try {
      bool gotAny = false;
      for (final ott in ['nf', 'pv', 'hs']) {
        final tok = await NetmirrorOttResolver.fetchUsertokenWithOtp(otp, ott: ott);
        if (tok != null && tok.length > 15 && tok.contains('::')) {
          gotAny = true;
        }
      }

      if (gotAny) {
        if (mounted) {
          setState(() {
            _solved     = true;
            _statusText = 'Token saved! Streams are now ready.';
          });
        }
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.pop(context, true);
        return;
      }
    } catch (_) {}

    _extracting = false;
    if (mounted) {
      setState(() => _statusText = 'Invalid OTP code. Please check and try again.');
    }
  }

  Future<void> _syncFromCloudStream() async {
    if (mounted) {
      setState(() => _statusText = 'Checking CloudStream session...');
    }
    final imported = await NetmirrorOttResolver.tryImportFromCloudStream(ott: 'nf');
    if (imported != null && imported.length > 15 && imported.contains('::')) {
      if (mounted) {
        setState(() {
          _solved = true;
          _statusText = 'Synced session token from CloudStream!';
        });
      }
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.pop(context, true);
      return;
    }
    if (mounted) {
      setState(() => _statusText = 'CloudStream session not found, please solve captcha below');
    }
  }

  Future<void> _extractOtpAndSave(InAppWebViewController controller, {bool isAuto = false}) async {
    if (_extracting || _solved) return;
    if (!isAuto && mounted) {
      setState(() => _statusText = 'Detecting session token...');
    }

    try {
      // Extract dynamic OTP array from HTML / scripts / text / DOM boxes
      final extractedOtp = await controller.evaluateJavascript(source: '''
        (function() {
          try {
            // 1. Check window.otp
            if (window.otp) {
              var wOtp = Array.isArray(window.otp) ? window.otp.join('') : String(window.otp);
              if (wOtp && wOtp.length >= 4) return wOtp;
            }

            // 2. Check innerText for 6 individual digits or 6 continuous digits
            var text = document.body ? document.body.innerText : '';
            var mSpace = text.match(/(\\d)\\s+(\\d)\\s+(\\d)\\s+(\\d)\\s+(\\d)\\s+(\\d)/);
            if (mSpace) {
              return mSpace[1] + mSpace[2] + mSpace[3] + mSpace[4] + mSpace[5] + mSpace[6];
            }

            var mDigits = text.match(/\\b([0-9]{6})\\b/);
            if (mDigits && mDigits[1] !== '109400' && mDigits[1] !== '000000') {
              return mDigits[1];
            }

            // 3. Scan DOM elements with single digit text
            var digitEls = document.querySelectorAll('div, span, p, h1, h2, h3, b');
            var collected = '';
            for (var i = 0; i < digitEls.length; i++) {
              var t = (digitEls[i].innerText || '').trim();
              if (/^\\d\$/.test(t)) {
                collected += t;
                if (collected.length === 6) return collected;
              } else if (collected.length > 0 && collected.length < 6 && t.length > 2) {
                collected = '';
              }
            }

            // 4. HTML script match
            var html = document.documentElement.innerHTML || '';
            var mScript = html.match(/const\\s+otp\\s*=\\s*\\[(.*?)\\]/);
            if (mScript && mScript[1]) {
              return mScript[1].replace(/[\\s,'"]/g, '');
            }
          } catch(e) {}
          return '';
        })();
      ''');

      final otpStr = (extractedOtp?.toString() ?? '').replaceAll('"', '').trim();
      
      if (otpStr.isNotEmpty && otpStr != 'null' && otpStr.length == 6) {
        if (mounted) {
          _otpTextController.text = otpStr;
        }
        await _submitOtpCode(otpStr);
        return;
      }

      if (!isAuto && mounted) {
        setState(() => _statusText = 'Please solve captcha / enter the 6-digit OTP above');
      }
    } catch (_) {
      if (!isAuto && mounted) {
        setState(() => _statusText = 'Please complete login / enter the 6-digit OTP above');
      }
    }
  }
}
