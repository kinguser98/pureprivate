import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../../models/cloud_account_model.dart';
import '../../services/cloud_auth_service.dart';
import '../../utils/drawer_helper.dart';
import '../../widgets/cloud/oauth_webview_dialog.dart';

class CloudAccountsScreen extends StatefulWidget {
  const CloudAccountsScreen({super.key});

  @override
  State<CloudAccountsScreen> createState() => _CloudAccountsScreenState();
}

class _CloudAccountsScreenState extends State<CloudAccountsScreen> {
  List<CloudAccount> _accounts = [];
  bool _isLoading = true;
  String _executionMode = 'client';
  final TextEditingController _serverWorkerController = TextEditingController();
  bool _isTestingWorker = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _serverWorkerController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final accounts = await CloudAuthService.getAccounts();
    final mode = await CloudAuthService.getExecutionMode();
    final workerUrl = await CloudAuthService.getServerWorkerUrl();
    if (mounted) {
      setState(() {
        _accounts = accounts;
        _executionMode = mode;
        if (workerUrl != null) {
          _serverWorkerController.text = workerUrl;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _testWorkerConnection() async {
    final url = _serverWorkerController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your Server Worker URL')),
      );
      return;
    }

    setState(() => _isTestingWorker = true);
    try {
      final pingUrl = url.contains('?') ? '$url&action=ping' : '$url?action=ping';
      final res = await http.get(Uri.parse(pingUrl)).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        await CloudAuthService.setServerWorkerUrl(url);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text('✅ Connected! Server: ${data['server'] ?? 'PHP Server'} (PHP ${data['php_version'] ?? ''})'),
            ),
          );
        }
      } else {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('❌ Connection failed: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTestingWorker = false);
    }
  }

  Future<void> _deleteAccount(CloudAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Disconnect Account?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to remove "${account.accountName}"? You can reconnect it anytime.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await CloudAuthService.removeAccount(account.id);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${account.accountName}')),
        );
      }
    }
  }

  void _showAddAccountModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Connect Cloud Storage',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Link personal or business accounts to upload media directly.',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 20),
            _providerTile(
              icon: Icons.storage_rounded,
              color: const Color(0xFF4285F4),
              title: 'Google Drive',
              subtitle: 'Connect Personal or Workspace Google Account',
              onTap: () {
                Navigator.pop(ctx);
                _showGoogleDriveDialog();
              },
            ),
            const SizedBox(height: 12),
            _providerTile(
              icon: Icons.cloud_rounded,
              color: const Color(0xFF0078D4),
              title: 'OneDrive (Personal)',
              subtitle: 'Microsoft Account (@outlook, @hotmail, etc.)',
              onTap: () {
                Navigator.pop(ctx);
                _showOneDriveDialog(isBusiness: false);
              },
            ),
            const SizedBox(height: 12),
            _providerTile(
              icon: Icons.business_center_rounded,
              color: const Color(0xFF00A4EF),
              title: 'OneDrive (Work / School / 365)',
              subtitle: 'Office 365 / Azure AD Business Account',
              onTap: () {
                Navigator.pop(ctx);
                _showOneDriveDialog(isBusiness: true);
              },
            ),
            const SizedBox(height: 12),
            _providerTile(
              icon: Icons.send_rounded,
              color: const Color(0xFF2AABEE),
              title: 'Telegram Storage',
              subtitle: 'Upload to Saved Messages or a Channel via Bot / MTProto',
              onTap: () {
                Navigator.pop(ctx);
                _showTelegramDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 16),
          ],
        ),
      ),
    );
  }

  void _showOneDriveDialog({required bool isBusiness}) {
    final codeController = TextEditingController();
    final nameController = TextEditingController(text: isBusiness ? 'Work OneDrive' : 'Personal OneDrive');
    final tenantController = TextEditingController(text: isBusiness ? 'organizations' : 'consumers');
    final clientIdController = TextEditingController(text: CloudAuthService.msClientId);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(isBusiness ? Icons.business_center_rounded : Icons.cloud_rounded, color: const Color(0xFF0078D4), size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isBusiness ? 'Connect OneDrive Business' : 'Connect OneDrive Personal',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // One-Tap In-App Login Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0078D4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.login_rounded, color: Colors.white, size: 20),
                  label: Text(
                    isBusiness ? 'Sign In with Work / Office 365' : 'Sign In with Microsoft',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    final authUrl = CloudAuthService.getOneDriveAuthUrl(
                      isBusiness: isBusiness,
                      customTenant: tenantController.text.trim().isNotEmpty ? tenantController.text.trim() : null,
                      customClientId: clientIdController.text.trim().isNotEmpty ? clientIdController.text.trim() : null,
                    );
                    showDialog(
                      context: context,
                      builder: (_) => OAuthWebViewDialog(
                        initialUrl: authUrl,
                        title: isBusiness ? 'Microsoft 365 Login' : 'Microsoft Account Login',
                        redirectPrefix: 'https://login.microsoftonline.com/common/oauth2/nativeclient',
                        onRedirectMatched: (redirectedUrl) async {
                          final uri = Uri.parse(redirectedUrl);
                          final code = uri.queryParameters['code'];
                          if (code != null) {
                            final acc = await CloudAuthService.handleOneDriveAuthCode(
                              code: code,
                              isBusiness: isBusiness,
                              customTenant: tenantController.text.trim().isNotEmpty ? tenantController.text.trim() : null,
                              customClientId: clientIdController.text.trim().isNotEmpty ? clientIdController.text.trim() : null,
                            );
                            if (acc != null && mounted) {
                              _loadData();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Connected ${acc.accountName} successfully!'), backgroundColor: Colors.green),
                              );
                            }
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              // MS Graph Explorer Helper Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF0078D4).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.vpn_key_rounded, color: Color(0xFF0078D4), size: 16),
                        SizedBox(width: 6),
                        Text('Instant Token (MS Graph Explorer)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '1. Open Microsoft Graph Explorer\n'
                      '2. Sign in with your Work 365 or Personal Account\n'
                      '3. Tap "Access token" tab & copy the Bearer Token below:',
                      style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'https://developer.microsoft.com/en-us/graph/graph-explorer',
                              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontFamily: 'monospace'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 14, color: Colors.white70),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Copy Link',
                            onPressed: () {
                              Clipboard.setData(const ClipboardData(text: 'https://developer.microsoft.com/en-us/graph/graph-explorer'));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('MS Graph Explorer link copied!')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0078D4),
                          side: const BorderSide(color: Color(0xFF0078D4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                        label: const Text('Open in Chrome', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          launchUrl(
                            Uri.parse('https://developer.microsoft.com/en-us/graph/graph-explorer'),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: const [
                  Expanded(child: Divider(color: Colors.white24)),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('CONFIG & MANUAL TOKEN', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold))),
                  Expanded(child: Divider(color: Colors.white24)),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Account Nickname', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  hintText: 'e.g. Work 365 Drive',
                  hintStyle: const TextStyle(color: Colors.white30),
                ),
              ),
              if (isBusiness) ...[
                const SizedBox(height: 12),
                const Text('Azure App Client ID (Optional for Org Tenants)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: clientIdController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    hintText: 'Your Azure App Registration ID',
                    hintStyle: const TextStyle(color: Colors.white30),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Tenant ID (Default: organizations)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: tenantController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    hintText: 'organizations or your tenant-id',
                    hintStyle: const TextStyle(color: Colors.white30),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Paste Bearer Token', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.paste_rounded, size: 14, color: Color(0xFF0078D4)),
                    label: const Text('Paste', style: TextStyle(fontSize: 11, color: Color(0xFF0078D4))),
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        codeController.text = data!.text!.trim();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: codeController,
                maxLines: 2,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  hintText: 'Bearer token from MS Graph Explorer',
                  hintStyle: const TextStyle(color: Colors.white30),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0078D4)),
            onPressed: () async {
              final val = codeController.text.trim();
              if (val.isEmpty) return;
              Navigator.pop(ctx);
              final directAcc = CloudAccount(
                id: 'onedrive_${DateTime.now().millisecondsSinceEpoch}',
                provider: isBusiness ? CloudProvider.onedriveBusiness : CloudProvider.onedrivePersonal,
                accountName: nameController.text.trim().isNotEmpty ? nameController.text.trim() : 'OneDrive Account',
                email: isBusiness ? 'Business Account' : 'Personal Account',
                accessToken: val,
                tenantId: tenantController.text.trim(),
                connectedAt: DateTime.now(),
              );
              await CloudAuthService.addOrUpdateAccount(directAcc);
              _loadData();
            },
            child: const Text('Save Token', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showGoogleDriveDialog() {
    final nameController = TextEditingController(text: 'Google Drive');
    final emailController = TextEditingController();
    final tokenController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.storage_rounded, color: Color(0xFF4285F4), size: 24),
            const SizedBox(width: 10),
            Text('Connect Google Drive', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Token Playground Helper Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF4285F4).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.vpn_key_rounded, color: Color(0xFF4285F4), size: 16),
                        SizedBox(width: 6),
                        Text('Guaranteed Token (Google Playground)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '1. Open Google OAuth Playground\n'
                      '2. Select "Drive API v3" -> authorize\n'
                      '3. Tap "Exchange code" & copy the Access Token below:',
                      style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'https://developers.google.com/oauthplayground',
                              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontFamily: 'monospace'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 14, color: Colors.white70),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Copy Link',
                            onPressed: () {
                              Clipboard.setData(const ClipboardData(text: 'https://developers.google.com/oauthplayground'));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Google OAuth Playground link copied!')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4285F4),
                          side: const BorderSide(color: Color(0xFF4285F4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                        label: const Text('Open in Chrome', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          launchUrl(
                            Uri.parse('https://developers.google.com/oauthplayground'),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('Account Nickname', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  hintText: 'e.g. My GDrive',
                  hintStyle: const TextStyle(color: Colors.white30),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Google Email', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: emailController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  hintText: 'yourname@gmail.com',
                  hintStyle: const TextStyle(color: Colors.white30),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('OAuth Access Token / API Token', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.paste_rounded, size: 14, color: Color(0xFF4285F4)),
                    label: const Text('Paste', style: TextStyle(fontSize: 11, color: Color(0xFF4285F4))),
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        tokenController.text = data!.text!.trim();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: tokenController,
                maxLines: 2,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  hintText: 'Paste Google Drive OAuth Token',
                  hintStyle: const TextStyle(color: Colors.white30),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4285F4)),
            onPressed: () async {
              if (tokenController.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await CloudAuthService.connectGoogleDriveManual(
                accountName: nameController.text.trim(),
                email: emailController.text.trim(),
                accessToken: tokenController.text.trim(),
              );
              _loadData();
            },
            child: const Text('Save Manual', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showTelegramDialog() {
    final botTokenController = TextEditingController();
    final chatIdController = TextEditingController();
    final nameController = TextEditingController(text: 'My Telegram');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.send_rounded, color: Color(0xFF2AABEE), size: 24),
            const SizedBox(width: 10),
            Text('Connect Telegram Storage', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nickname', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  hintText: 'e.g. My Telegram Backup',
                  hintStyle: const TextStyle(color: Colors.white30),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Bot Token (from @BotFather)', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: botTokenController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  hintText: '123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11',
                  hintStyle: const TextStyle(color: Colors.white30),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Target Chat ID (Channel or User ID)', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: chatIdController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  hintText: 'e.g. -1001234567890 or @channelusername',
                  hintStyle: const TextStyle(color: Colors.white30),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white60))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2AABEE)),
            onPressed: () async {
              final token = botTokenController.text.trim();
              final chat = chatIdController.text.trim();
              if (token.isEmpty || chat.isEmpty) return;
              Navigator.pop(ctx);
              await CloudAuthService.connectTelegramBot(
                botToken: token,
                chatId: chat,
                accountName: nameController.text.trim(),
              );
              _loadData();
            },
            child: const Text('Connect Telegram', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F19),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
          onPressed: () => DrawerProvider.scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text('Cloud Storages', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFEF4444),
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Connect Account', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
        onPressed: _showAddAccountModal,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFEF4444)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                // Execution Mode Switcher Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF0F172A)]),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.memory_rounded, color: Color(0xFF8B5CF6), size: 20),
                          const SizedBox(width: 8),
                          Text('Download Execution Pipeline', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Choose whether downloads stream directly through your phone or offload to your server.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _modeOptionTile(
                              title: 'Client-Side (Phone)',
                              subtitle: 'Direct mobile data transfer',
                              selected: _executionMode == 'client',
                              onTap: () async {
                                setState(() => _executionMode = 'client');
                                await CloudAuthService.setExecutionMode('client');
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _modeOptionTile(
                              title: 'Server-Side (Fast)',
                              subtitle: 'VPS cloud offload relay',
                              selected: _executionMode == 'server',
                              onTap: () async {
                                setState(() => _executionMode = 'server');
                                await CloudAuthService.setExecutionMode('server');
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Shared Hosting Server Worker Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.dns_rounded, color: Color(0xFF06B6D4), size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Shared Hosting / Server Worker', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                const Text('0% Phone Bandwidth • Datacenter speed', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Drop "cloud_worker.php" into your shared hosting (cPanel / Hostinger public_html) and paste the URL here:',
                        style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _serverWorkerController,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          hintText: 'https://yourdomain.com/cloud_worker.php',
                          hintStyle: const TextStyle(color: Colors.white30),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF06B6D4),
                                side: const BorderSide(color: Color(0xFF06B6D4)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              icon: _isTestingWorker
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06B6D4)))
                                  : const Icon(Icons.network_check_rounded, size: 16),
                              label: const Text('Test & Save', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: _isTestingWorker ? null : _testWorkerConnection,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Connected Accounts (${_accounts.length})', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                if (_accounts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.cloud_off_rounded, color: Colors.white.withValues(alpha: 0.3), size: 48),
                        const SizedBox(height: 14),
                        const Text('No Cloud Accounts Connected', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        const Text('Link Google Drive, OneDrive (Personal or Business), or Telegram to enable cloud downloads.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                          icon: const Icon(Icons.add, size: 18, color: Colors.white),
                          label: const Text('Add Account', style: TextStyle(color: Colors.white)),
                          onPressed: _showAddAccountModal,
                        ),
                      ],
                    ),
                  )
                else
                  ..._accounts.map((acc) => _accountCard(acc)),
              ],
            ),
    );
  }

  Widget _modeOptionTile({required String title, required String subtitle, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF8B5CF6).withValues(alpha: 0.15) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? const Color(0xFF8B5CF6) : Colors.white.withValues(alpha: 0.05), width: selected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: selected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _accountCard(CloudAccount account) {
    IconData icon;
    Color color;

    switch (account.provider) {
      case CloudProvider.gdrive:
        icon = Icons.storage_rounded;
        color = const Color(0xFF4285F4);
        break;
      case CloudProvider.onedrivePersonal:
        icon = Icons.cloud_rounded;
        color = const Color(0xFF0078D4);
        break;
      case CloudProvider.onedriveBusiness:
        icon = Icons.business_center_rounded;
        color = const Color(0xFF00A4EF);
        break;
      case CloudProvider.telegramMtproto:
      case CloudProvider.telegramBot:
        icon = Icons.send_rounded;
        color = const Color(0xFF2AABEE);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.accountName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  '${account.provider.displayName} • ${account.email}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
            onPressed: () => _deleteAccount(account),
          ),
        ],
      ),
    );
  }
}
