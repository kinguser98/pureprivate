import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freebuff_core/services/telegram/telegram_service.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

class TelegramLoginScreen extends StatefulWidget {
  const TelegramLoginScreen({super.key});

  @override
  State<TelegramLoginScreen> createState() => _TelegramLoginScreenState();
}

class _TelegramLoginScreenState extends State<TelegramLoginScreen> {
  int _step = 0;
  bool _busy = false;
  String? _status;
  String? _error;

  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    TelegramService.instance.status.addListener(_onStatusChanged);
    TelegramService.instance.statusMessage.addListener(_onStatusMessageChanged);
    TelegramService.instance.init();
  }

  @override
  void dispose() {
    TelegramService.instance.status.removeListener(_onStatusChanged);
    TelegramService.instance.statusMessage
        .removeListener(_onStatusMessageChanged);
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  void _onStatusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onStatusMessageChanged() {
    if (!mounted) return;
    setState(() {
      _status = TelegramService.instance.statusMessage.value;
    });
  }

  Future<void> _next() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_step == 0) {
        await TelegramService.instance.startAuth(_phoneCtrl.text.trim());
        if (mounted) setState(() => _step = 1);
      } else if (_step == 1) {
        await TelegramService.instance.signIn(_codeCtrl.text.trim());
        // If 2FA needed the service moves to awaitingPassword.
        final st = TelegramService.instance.status.value;
        if (mounted) {
          setState(() {
            _step = st == TelegramStatus.awaitingPassword ? 2 : 3;
          });
        }
      } else if (_step == 2) {
        await TelegramService.instance.completePassword(_pwdCtrl.text);
        if (mounted) setState(() => _step = 3);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshIndex() async {
    setState(() => _busy = true);
    try {
      await TelegramService.instance.loadSavedMessages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Telegram Server refreshed.'),
          backgroundColor: Color(0xFF22C55E),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refresh failed: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _stepLabel(int step) {
    switch (step) {
      case 0:
        return 'Step 1 of 3 • Phone number';
      case 1:
        return 'Step 2 of 3 • Verification code';
      case 2:
        return 'Step 3 of 3 • Two-factor password';
      case 3:
        return 'Connected';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'Telegram',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildBanner(),
                  const SizedBox(height: 16),
                  _buildStepIndicator(),
                  const SizedBox(height: 12),
                  _buildActiveStep(),
                  const SizedBox(height: 24),
                  if (_step < 3) _buildActions() else _buildSuccessActions(),
                  const SizedBox(height: 24),
                  _buildFooter(),
                ],
              ),
            ),
          ),
          if (_busy)
            Container(
              color: Colors.black.withValues(alpha: 0.45),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.accentBright.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.accentBright.withValues(alpha: 0.4),
            ),
          ),
          child: Icon(
            Icons.send_rounded,
            color: AppColors.accentBright,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connect Telegram',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Index video files from your Telegram Server and surface them as stream sources on movie pages.',
                style: GoogleFonts.outfit(
                  color: Colors.white54,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBanner() {
    if (_error == null && _status == null) return const SizedBox.shrink();
    final isError = _error != null;
    final text = _error ?? _status ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError
            ? const Color(0x33EF4444)
            : AppColors.accentBright.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isError
              ? const Color(0x55EF4444)
              : AppColors.accentBright.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            color: isError ? const Color(0xFFEF4444) : AppColors.accentBright,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.outfit(
                color: Colors.white70,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        _stepLabel(_step),
        style: GoogleFonts.outfit(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildActiveStep() {
    if (_step == 0) return _buildPhoneStep();
    if (_step == 1) return _buildCodeStep();
    if (_step == 2) return _buildPasswordStep();
    return _buildSuccessStep();
  }

  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone number',
          style: GoogleFonts.outfit(
            color: Colors.white70,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Telegram will send a code to your Telegram app (not SMS).',
          style: GoogleFonts.outfit(
            color: Colors.white38,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +()-]'))],
          decoration: _decoration(hint: '+91 90000 00000'),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verification code',
          style: GoogleFonts.outfit(
            color: Colors.white70,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter the 5-digit code Telegram sent to your device.',
          style: GoogleFonts.outfit(
            color: Colors.white38,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 7,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 22,
            letterSpacing: 8,
          ),
          decoration: _decoration(hint: '• • • • •'),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Two-factor password',
          style: GoogleFonts.outfit(
            color: Colors.white70,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your account is protected by 2FA. Enter the cloud password.',
          style: GoogleFonts.outfit(
            color: Colors.white38,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pwdCtrl,
          obscureText: true,
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
          decoration: _decoration(hint: '••••••••'),
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentBright.withValues(alpha: 0.18),
            ),
            child: Icon(
              Icons.check_circle_rounded,
              color: AppColors.accentBright,
              size: 76,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            'Connected to Telegram',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Open any movie detail page to see Saved-Message files appear as stream sources.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white54,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _decoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.outfit(color: Colors.white30),
      filled: true,
      fillColor: Colors.white10,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _buildActions() {
    final isLast = _step == 2;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _busy ? null : _next,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentBright,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              isLast ? 'Submit' : 'Continue',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessActions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _refreshIndex,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: AppColors.accentBright.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Sync Telegram Server',
                  style: GoogleFonts.outfit(
                    color: AppColors.accentBright,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentBright,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Done',
                  style: GoogleFonts.outfit(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Text(
        'Powered by your own Telegram account • Session stays on device',
        style: GoogleFonts.outfit(
          color: Colors.white30,
          fontSize: 11,
        ),
      ),
    );
  }
}
