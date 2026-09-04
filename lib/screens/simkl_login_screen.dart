import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_colors.dart';
import '../data/simkl_service.dart';

class SimklLoginScreen extends StatefulWidget {
  const SimklLoginScreen({super.key});

  @override
  State<SimklLoginScreen> createState() => _SimklLoginScreenState();
}

class _SimklLoginScreenState extends State<SimklLoginScreen> {
  SimklPinResponse? _pinResponse;
  bool _isLoading = true;
  Timer? _pollTimer;
  WebViewController? _webViewController;
  bool _showManualToken = false;
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _clientIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startPinAuth();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tokenController.dispose();
    _clientIdController.dispose();
    super.dispose();
  }

  Future<void> _startPinAuth() async {
    setState(() => _isLoading = true);
    final pin = await SimklService.generatePin();
    if (pin != null && mounted) {
      setState(() {
        _pinResponse = pin;
        _isLoading = false;
      });

      // Initialize WebView with verification URL
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0F172A))
        ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36',
        )
        ..loadRequest(Uri.parse(pin.verificationUrl));

      // Start polling for approval
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(Duration(seconds: pin.interval), (timer) async {
        final approved = await SimklService.checkPin(pin.userCode);
        if (approved && mounted) {
          timer.cancel();
          HapticFeedback.mediumImpact();
          Navigator.of(context).pop(true);
        }
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('🍿', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Text(
              'Connect SIMKL',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_showManualToken ? Icons.qr_code_rounded : Icons.vpn_key_rounded, color: Colors.amberAccent),
            tooltip: _showManualToken ? 'Web Login' : 'Enter Token / Client ID',
            onPressed: () => setState(() => _showManualToken = !_showManualToken),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.amberAccent),
                  SizedBox(height: 16),
                  Text('Connecting to SIMKL...', style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          : _showManualToken || _pinResponse == null
              ? _buildSetupView()
              : _buildPinWebView(),
    );
  }

  Widget _buildPinWebView() {
    return Column(
      children: [
        // PIN Header Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.amber.withOpacity(0.12),
          child: Row(
            children: [
              const Text('🍿', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Log in with Google below to authorize',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'PIN Code: ${_pinResponse!.userCode}',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amberAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _pinResponse!.userCode,
                  style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: WebViewWidget(controller: _webViewController!),
        ),
      ],
    );
  }

  Widget _buildSetupView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SIMKL App ID Setup Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.developer_mode_rounded, color: Colors.amberAccent, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Option 1: SIMKL App Client ID',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '1. Open simkl.com/settings/developer/new\n'
                  '2. Set Name: Private Cinema\n'
                  '3. Set Redirect URI: urn:ietf:wg:oauth:2.0:oob\n'
                  '4. Paste the 64-character Client ID below:',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.45),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amberAccent,
                    side: const BorderSide(color: Colors.amberAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                  label: const Text('Open simkl.com/settings/developer/new'),
                  onPressed: () {
                    launchUrl(Uri.parse('https://simkl.com/settings/developer/new/'), mode: LaunchMode.externalApplication);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _clientIdController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Client ID',
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                    hintText: 'Paste Client ID here...',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      final id = _clientIdController.text.trim();
                      if (id.isEmpty) return;
                      await SimklService.saveClientId(id);
                      _startPinAuth();
                    },
                    child: const Text('Save & Start Google Login', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Option 2: Direct Access Token
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.vpn_key_rounded, color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Option 2: Paste Access Token Directly',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Paste existing SIMKL access token...',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      final token = _tokenController.text.trim();
                      if (token.isEmpty) return;
                      final ok = await SimklService.setCustomToken(token);
                      if (ok && mounted) {
                        Navigator.of(context).pop(true);
                      }
                    },
                    child: const Text('Connect with Token', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
