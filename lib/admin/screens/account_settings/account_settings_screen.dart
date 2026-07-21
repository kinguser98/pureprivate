import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/admin_api_client.dart';
import '../../utils/drawer_helper.dart';
import '../../widgets/common/glass_card.dart';

class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController(text: 'Admin');
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _adminApi = AdminApiClient();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final result = await _adminApi.updateAccount(
        _usernameController.text.trim(),
        _currentPasswordController.text,
        newPassword: _newPasswordController.text,
        confirmPassword: _confirmPasswordController.text,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', _usernameController.text.trim());

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']?.toString() ?? 'Account updated'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']?.toString() ?? 'Update failed'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred: ${e.toString()}'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: DrawerProvider.openDrawer,
        ),
        title: const Text('Account Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)]),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              (_usernameController.text.isNotEmpty ? _usernameController.text[0] : 'U').toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Account', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('Manage your credentials', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildLabel('Username'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _usernameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Enter username',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        prefixIcon: Icon(Icons.person, color: Colors.white.withOpacity(0.5), size: 20),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Username is required' : null,
                    ),
                    const SizedBox(height: 20),
                    _buildLabel('Current Password'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _currentPasswordController,
                      obscureText: _obscureCurrent,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Enter current password',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        prefixIcon: Icon(Icons.lock_outline, color: Colors.white.withOpacity(0.5), size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility, color: Colors.white.withOpacity(0.5), size: 20),
                          onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                        ),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Current password is required' : null,
                    ),
                    const SizedBox(height: 20),
                    _buildLabel('New Password'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: _obscureNew,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Enter new password',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        prefixIcon: Icon(Icons.lock, color: Colors.white.withOpacity(0.5), size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility, color: Colors.white.withOpacity(0.5), size: 20),
                          onPressed: () => setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildLabel('Confirm Password'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Confirm new password',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        prefixIcon: Icon(Icons.lock, color: Colors.white.withOpacity(0.5), size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: Colors.white.withOpacity(0.5), size: 20),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (v) {
                        if (v != null && v.isNotEmpty && v != _newPasswordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveChanges,
                        child: _isSaving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}
