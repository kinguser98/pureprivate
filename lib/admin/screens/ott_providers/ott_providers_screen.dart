import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/admin_api_client.dart';
import '../../utils/drawer_helper.dart';
import '../../widgets/common/glass_card.dart';

class OttProvidersScreen extends ConsumerStatefulWidget {
  const OttProvidersScreen({super.key});
  @override
  ConsumerState<OttProvidersScreen> createState() => _OttProvidersScreenState();
}

class _OttProvidersScreenState extends ConsumerState<OttProvidersScreen> {
  final _nameCtrl = TextEditingController();
  final _logoCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _adminApi = AdminApiClient();
  List<Map<String, dynamic>> _providers = [];
  bool _loading = true;
  bool _saving = false;
  int? _editId;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _logoCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final list = await _adminApi.fetchOttProviderList();
    if (mounted) setState(() { _providers = list; _loading = false; });
  }

  void _resetForm() { _editId = null; _nameCtrl.clear(); _logoCtrl.clear(); _formKey.currentState?.reset(); setState(() {}); }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    if (_editId != null) {
      await _adminApi.saveOttProvider(_nameCtrl.text.trim(), _logoCtrl.text.trim(), id: _editId);
    } else {
      await _adminApi.saveOttProvider(_nameCtrl.text.trim(), _logoCtrl.text.trim());
    }
    _resetForm();
    await _fetch();
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Provider saved'), backgroundColor: Color(0xFF22C55E)));
    }
  }

  Future<void> _delete(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Provider', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _adminApi.deleteOttProvider(id);
      _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: DrawerProvider.openDrawer),
        title: const Text('OTT Providers'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                GlassCard(padding: const EdgeInsets.all(20), child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(_editId != null ? Icons.edit : Icons.add, color: const Color(0xFFEF4444), size: 20),
                    const SizedBox(width: 8),
                    Text(_editId != null ? 'Edit Provider' : 'Add Provider', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (_editId != null) TextButton(onPressed: _resetForm, child: Text('Cancel', style: TextStyle(color: Colors.white54, fontSize: 13))),
                  ]),
                  const SizedBox(height: 16),
                  Container(decoration: BoxDecoration(color: const Color(0xFF0B0F19), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
                    child: TextFormField(controller: _nameCtrl, style: const TextStyle(color: Colors.white, fontSize: 14),
                      validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                      decoration: InputDecoration(labelText: 'Provider Name', labelStyle: TextStyle(color: Colors.white54, fontSize: 13), hintText: 'e.g. Netflix', hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                        prefixIcon: Icon(Icons.business, color: Colors.white.withOpacity(0.4), size: 20), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)))),
                  const SizedBox(height: 12),
                  Container(decoration: BoxDecoration(color: const Color(0xFF0B0F19), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
                    child: TextFormField(controller: _logoCtrl, style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(labelText: 'Logo URL', labelStyle: TextStyle(color: Colors.white54, fontSize: 13), hintText: 'https://...', hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                        prefixIcon: Icon(Icons.image, color: Colors.white.withOpacity(0.4), size: 20), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)))),
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, height: 48, child: ElevatedButton(onPressed: _saving ? null : _submit,
                    child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_editId != null ? 'Update' : 'Add'))),
                ]))),
                const SizedBox(height: 24),
                Text('Providers (${_providers.length})', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_providers.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 48), child: Center(
                    child: Column(children: [
                      Icon(Icons.tv, size: 64, color: Colors.white.withOpacity(0.2)),
                      const SizedBox(height: 16),
                      Text('No providers found on server', style: TextStyle(color: Colors.white54, fontSize: 15)),
                    ]),
                  )),
                ..._providers.asMap().entries.map((e) => GlassCard(padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 8), child: Row(children: [
                  Container(width: 36, height: 36, decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)]), borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)))),
                  const SizedBox(width: 12),
                  Expanded(child: Text(e.value['name']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
                  IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.white60), onPressed: () {
                    _editId = e.value['id'] as int?;
                    _nameCtrl.text = e.value['name']?.toString() ?? '';
                    _logoCtrl.text = e.value['logo_url']?.toString() ?? '';
                    setState(() {});
                  }),
                  IconButton(icon: const Icon(Icons.delete, size: 20, color: Color(0xFFEF4444)), onPressed: () {
                    final id = e.value['id'] as int?;
                    if (id != null) _delete(id);
                  }),
                ]))),
              ]),
            ),
    );
  }
}
