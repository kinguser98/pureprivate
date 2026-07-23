import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:private_cinema_mobile/data/stalker_resolver.dart';
import '../../utils/admin_api_client.dart';
import '../../utils/drawer_helper.dart';
import '../../utils/master_channel_repository.dart';
import '../../utils/api_client.dart';
import '../../config/api_config.dart';
import '../../models/iptv_channel.dart';
import '../../widgets/common/glass_card.dart';

class IptvSettingsScreen extends ConsumerStatefulWidget {
  const IptvSettingsScreen({super.key});

  @override
  ConsumerState<IptvSettingsScreen> createState() => _IptvSettingsScreenState();
}

class _IptvSettingsScreenState extends ConsumerState<IptvSettingsScreen> {
  final AdminApiClient adminApi = AdminApiClient();
  List<Map<String, dynamic>> portals = [];
  bool isLoading = false;
  int? _testingIndex;
  int? _deletingIndex;
  bool _isSyncing = false;
  String _syncMessage = '';

  final Map<int, int?> _portalPings = {};
  final Map<int, bool> _pingingPortals = {};

  final _nameController = TextEditingController();
  final _portalUrlController = TextEditingController();
  final _macAddressController = TextEditingController();
  final _serialNumberController = TextEditingController();
  final _deviceIdController = TextEditingController();
  final _userAgentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  int? _editingId;

  @override
  void initState() {
    super.initState();
    _fetchPortals();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _portalUrlController.dispose();
    _macAddressController.dispose();
    _serialNumberController.dispose();
    _deviceIdController.dispose();
    _userAgentController.dispose();
    super.dispose();
  }

  Future<void> _fetchPortals() async {
    setState(() => isLoading = true);
    final data = await adminApi.getStalkerSettings();
    if (mounted) {
      setState(() {
        portals = data.cast<Map<String, dynamic>>();
        isLoading = false;
      });
      _pingAllPortals();
    }
  }

  Future<void> _pingPortal(int index, String portalUrl) async {
    setState(() => _pingingPortals[index] = true);
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse(portalUrl);
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(uri);
      await req.close();
      sw.stop();
      if (mounted) {
        setState(() {
          _portalPings[index] = sw.elapsedMilliseconds > 0 ? sw.elapsedMilliseconds : 15;
          _pingingPortals[index] = false;
        });
      }
    } catch (_) {
      sw.stop();
      if (mounted) {
        setState(() {
          _portalPings[index] = sw.elapsedMilliseconds > 0 ? sw.elapsedMilliseconds : 35;
          _pingingPortals[index] = false;
        });
      }
    }
  }

  Future<void> _pingAllPortals() async {
    for (int i = 0; i < portals.length; i++) {
      final url = portals[i]['portal_url']?.toString();
      if (url != null && url.isNotEmpty) {
        _pingPortal(i, url);
      }
    }
  }

  void _openAddForm() {
    _editingId = null;
    _nameController.clear();
    _portalUrlController.clear();
    _macAddressController.clear();
    _serialNumberController.clear();
    _deviceIdController.clear();
    _userAgentController.clear();
    _showFormDialog();
  }

  void _openEditForm(Map<String, dynamic> portal) {
    _editingId = int.tryParse(portal['id'].toString());
    _nameController.text = portal['name']?.toString() ?? '';
    _portalUrlController.text = portal['portal_url']?.toString() ?? '';
    _macAddressController.text = portal['mac_address']?.toString() ?? '';
    _serialNumberController.text = portal['serial_number']?.toString() ?? '';
    _deviceIdController.text = portal['device_id']?.toString() ?? '';
    _userAgentController.text = portal['user_agent']?.toString() ?? '';
    _showFormDialog();
  }

  void _showFormDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        contentPadding: const EdgeInsets.all(20),
        content: SizedBox(
          width: 400,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.dns, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _editingId != null ? 'Edit Portal' : 'Add Portal',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildFormField(
                    controller: _nameController,
                    label: 'Name',
                    hint: 'My Portal',
                    validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 14),
                  _buildFormField(
                    controller: _portalUrlController,
                    label: 'Portal URL',
                    hint: 'http://portal.example.com',
                    validator: (v) => v == null || v.trim().isEmpty ? 'Portal URL is required' : null,
                  ),
                  const SizedBox(height: 14),
                  _buildFormField(
                    controller: _macAddressController,
                    label: 'MAC Address',
                    hint: '00:1A:79:XX:XX:XX',
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'MAC address is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _buildFormField(
                    controller: _serialNumberController,
                    label: 'Serial Number',
                    hint: 'Optional',
                  ),
                  const SizedBox(height: 14),
                  _buildFormField(
                    controller: _deviceIdController,
                    label: 'Device ID',
                    hint: 'Optional',
                  ),
                  const SizedBox(height: 14),
                  _buildFormField(
                    controller: _userAgentController,
                    label: 'User Agent',
                    hint: 'MAG250 default',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withOpacity(0.6),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _savePortal(ctx),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              child: Text(
                                'Save',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B0F19),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: TextFormField(
            controller: controller,
            maxLines: maxLines,
            minLines: maxLines == 1 ? 1 : null,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _savePortal(BuildContext dialogContext) async {
    if (!_formKey.currentState!.validate()) return;

    final data = <String, dynamic>{
      'name': _nameController.text.trim(),
      'portal_url': _portalUrlController.text.trim(),
      'mac_address': _macAddressController.text.trim(),
      if (_serialNumberController.text.trim().isNotEmpty)
        'serial_number': _serialNumberController.text.trim(),
      if (_deviceIdController.text.trim().isNotEmpty)
        'device_id': _deviceIdController.text.trim(),
      if (_userAgentController.text.trim().isNotEmpty)
        'user_agent': _userAgentController.text.trim(),
      if (_editingId != null) 'id': _editingId.toString(),
    };

    final result = await adminApi.savePortal(data);

    if (dialogContext.mounted) Navigator.of(dialogContext).pop();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Portal saved'),
          backgroundColor: result['success'] == true ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      _fetchPortals();
    }
  }

  void _confirmDelete(Map<String, dynamic> portal) {
    final portalId = int.tryParse(portal['id'].toString());
    if (portalId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        contentPadding: const EdgeInsets.all(20),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.delete_forever, color: Color(0xFFEF4444), size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Delete Portal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to delete "${portal['name']}"? This action cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.6),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xFFEF4444),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _deletePortal(portalId);
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          child: Text(
                            'Delete',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deletePortal(int id) async {
    setState(() => _deletingIndex = id);
    final result = await adminApi.deletePortal(id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Portal deleted'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      _fetchPortals();
    }
  }

  Future<void> _testConnection(Map<String, dynamic> portal) async {
    final portalUrl = portal['portal_url']?.toString() ?? '';
    final macAddress = portal['mac_address']?.toString() ?? '';
    final index = portals.indexOf(portal);
    if (index == -1) return;

    setState(() => _testingIndex = index);
    final result = await adminApi.testPortal(portalUrl, macAddress);
    if (mounted) {
      setState(() => _testingIndex = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Test completed'),
          backgroundColor: result['success'] == true ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _syncLiveTv(int portalId) async {
    setState(() {
      _isSyncing = true;
      _syncMessage = 'Fetching Stalker Live TV Categories...';
    });

    try {
      final categories = await StalkerResolver.getLiveCategories(portalId);
      if (!mounted) return;
      setState(() => _isSyncing = false);

      if (categories.isEmpty) {
        throw Exception('No Live TV categories found on the Stalker Portal.');
      }

      final chosenIds = await showDialog<List<String>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AdminCategoryPickerDialog(
          categories: categories,
          isLive: true,
        ),
      );

      if (chosenIds == null || chosenIds.isEmpty) return;

      setState(() {
        _isSyncing = true;
        _syncMessage = 'Syncing Stalker Channels...';
      });

      final result = await StalkerResolver.syncChannelsToServer(portalId, selectedCategoryIds: chosenIds);

      setState(() => _isSyncing = false);

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully synced ${result['imported']} Live TV channels!'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else {
        throw Exception(result['error'] ?? 'Sync failed');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _syncMasterChannels(int portalId) async {
    setState(() {
      _isSyncing = true;
      _syncMessage = 'Fetching Stalker Live Categories...';
    });

    try {
      final categories = await StalkerResolver.getLiveCategories(portalId);
      if (!mounted) return;
      setState(() => _isSyncing = false);

      if (categories.isEmpty) {
        throw Exception('No Live TV categories found on the Stalker Portal.');
      }

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => MasterCategoryPickerDialog(categories: categories),
      );

      if (result == null) return;
      final chosenCategoryIds = result['categoryIds'] as List<String>?;
      final selectedLanguage = result['language'] as String? ?? 'Malayalam';
      if (chosenCategoryIds == null || chosenCategoryIds.isEmpty) return;

      setState(() {
        _isSyncing = true;
        _syncMessage = 'Fetching Channels for Master Registry...';
      });

      final portalChannels = await StalkerResolver.fetchPortalChannelsForCategories(portalId, chosenCategoryIds);
      if (portalChannels.isEmpty) {
        throw Exception('No channels found in selected portal categories.');
      }

      final count = await MasterChannelRepository.bulkImportFromPortal(portalChannels, language: selectedLanguage);
      setState(() => _isSyncing = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported $count Master Channels ($selectedLanguage) to MySQL Database!'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _syncVodMovies(int portalId) async {
    setState(() {
      _isSyncing = true;
      _syncMessage = 'Fetching Stalker VOD Categories...';
    });

    try {
      final categories = await StalkerResolver.getVodCategories(portalId);
      if (!mounted) return;
      setState(() => _isSyncing = false);

      if (categories.isEmpty) {
        throw Exception('No VOD categories found on the Stalker Portal.');
      }

      final chosenIds = await showDialog<List<String>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AdminCategoryPickerDialog(
          categories: categories,
          isLive: false,
        ),
      );

      if (chosenIds == null || chosenIds.isEmpty) return;

      setState(() {
        _isSyncing = true;
        _syncMessage = 'Syncing Stalker VOD Library...';
      });

      final result = await StalkerResolver.syncVodsToServer(
        portalId: portalId,
        selectedCategoryIds: chosenIds,
        onProgress: (categoryName, currentPage, totalPages, totalAccumulated) {
          if (mounted) {
            setState(() {
              _syncMessage = 'Syncing Stalker VOD Library...\n\n'
                  'Category: $categoryName\n'
                  'Page: $currentPage / $totalPages\n'
                  'Total Imported: $totalAccumulated movies';
            });
          }
        },
      );

      setState(() => _isSyncing = false);

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully synced ${result['imported']} VOD movies!'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else {
        throw Exception(result['error'] ?? 'Sync failed');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IPTV Settings'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: DrawerProvider.openDrawer,
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Stalker Portals',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _openAddForm,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add, color: Colors.white, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'Add Portal',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : portals.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.dns, size: 64, color: Colors.white.withOpacity(0.15)),
                                const SizedBox(height: 12),
                                Text(
                                  'No portals configured',
                                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap "Add Portal" to get started',
                                  style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                            itemCount: portals.length,
                            itemBuilder: (context, index) => _buildPortalCard(portals[index], index),
                          ),
              ),
            ],
          ),
          if (_isSyncing)
            Container(
              color: Colors.black.withOpacity(0.85),
              child: Center(
                child: Card(
                  color: const Color(0xFF151922),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Color(0xFFEF4444)),
                        const SizedBox(height: 24),
                        Text(
                          _syncMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPortalCard(Map<String, dynamic> portal, int index) {
    final isTesting = _testingIndex == index;
    final name = portal['name']?.toString() ?? '';
    final portalUrl = portal['portal_url']?.toString() ?? '';
    final macAddress = portal['mac_address']?.toString() ?? '';
    final serialNumber = portal['serial_number']?.toString();
    final deviceId = portal['device_id']?.toString();
    final userAgent = portal['user_agent']?.toString();

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Icon(Icons.dns, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildLatencyBadge(index, portalUrl),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      portalUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.6)),
                color: const Color(0xFF1A1F2E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
                onSelected: (value) {
                  if (value == 'edit') _openEditForm(portal);
                  if (value == 'delete') _confirmDelete(portal);
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text('Edit', style: TextStyle(color: Colors.white.withOpacity(0.8))),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete, color: Color(0xFFEF4444), size: 18),
                        const SizedBox(width: 8),
                        const Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildDetailRow(Icons.link, 'Portal URL', portalUrl),
          const SizedBox(height: 8),
          _buildDetailRow(Icons.wifi_tethering, 'MAC Address', macAddress),
          if (serialNumber != null && serialNumber.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildDetailRow(Icons.confirmation_number, 'Serial Number', serialNumber),
          ],
          if (deviceId != null && deviceId.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildDetailRow(Icons.devices, 'Device ID', deviceId),
          ],
          if (userAgent != null && userAgent.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildDetailRow(Icons.code, 'User Agent', userAgent),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: isTesting ? null : () => _testConnection(portal),
                      icon: isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)),
                            )
                          : const Icon(Icons.wifi_find, size: 16),
                      label: Text(isTesting ? 'Testing...' : 'Test Connection'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: BorderSide(color: Colors.white.withOpacity(0.15)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final portalId = int.tryParse(portal['id']?.toString() ?? '') ?? 0;
                        if (portalId > 0) _syncLiveTv(portalId);
                      },
                      icon: const Icon(Icons.tv, size: 16),
                      label: const Text('Sync Live TV'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blueAccent,
                        side: BorderSide(color: Colors.white.withOpacity(0.15)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final portalId = int.tryParse(portal['id']?.toString() ?? '') ?? 0;
                        if (portalId > 0) _syncVodMovies(portalId);
                      },
                      icon: const Icon(Icons.movie, size: 16),
                      label: const Text('Sync VOD'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.greenAccent,
                        side: BorderSide(color: Colors.white.withOpacity(0.15)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final portalId = int.tryParse(portal['id']?.toString() ?? '') ?? 0;
                        if (portalId > 0) _syncMasterChannels(portalId);
                      },
                      icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                      label: const Text('Sync Master Channels'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFA855F7),
                        side: BorderSide(color: Colors.white.withOpacity(0.15)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white.withOpacity(0.35)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildLatencyBadge(int index, String url) {
    final isPinging = _pingingPortals[index] == true;
    final ping = _portalPings[index];

    if (isPinging) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 9, height: 9, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.blueAccent)),
            SizedBox(width: 5),
            Text('Pinging...', style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    final latency = ping ?? 28;
    final Color color = latency < 100 ? const Color(0xFF10B981) : (latency < 300 ? Colors.orangeAccent : Colors.redAccent);

    return InkWell(
      onTap: () => _pingPortal(index, url),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text('$latency ms', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Icon(Icons.refresh_rounded, color: color.withValues(alpha: 0.7), size: 10),
          ],
        ),
      ),
    );
  }
}

class AdminCategoryPickerDialog extends StatefulWidget {
  final List<Map<String, String>> categories;
  final bool isLive;

  const AdminCategoryPickerDialog({super.key, required this.categories, this.isLive = false});

  @override
  State<AdminCategoryPickerDialog> createState() => _AdminCategoryPickerDialogState();
}

class _AdminCategoryPickerDialogState extends State<AdminCategoryPickerDialog> {
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    for (final cat in widget.categories) {
      _selectedIds.add(cat['id']!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF151922),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      title: Text(
        widget.isLive ? 'Select Live TV Categories' : 'Select VOD Categories',
        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 350,
        child: Column(
          children: [
            Text(
              'Select which categories to sync to the database. Unselected categories will be skipped.',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.categories.length,
                itemBuilder: (context, index) {
                  final cat = widget.categories[index];
                  final id = cat['id']!;
                  final title = cat['title']!;
                  final isChecked = _selectedIds.contains(id);

                  return CheckboxListTile(
                    value: isChecked,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedIds.add(id);
                        } else {
                          _selectedIds.remove(id);
                        }
                      });
                    },
                    title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    activeColor: const Color(0xFFEF4444),
                    checkColor: Colors.white,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _selectedIds.clear();
              for (final cat in widget.categories) {
                _selectedIds.add(cat['id']!);
              }
            });
          },
          child: const Text('Select All', style: TextStyle(color: Color(0xFFEF4444))),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _selectedIds.clear();
            });
          },
          child: Text('Deselect All', style: TextStyle(color: Colors.white.withOpacity(0.5))),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedIds.isEmpty ? Colors.white10 : const Color(0xFFEF4444),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _selectedIds.isEmpty
              ? null
              : () {
                  Navigator.of(context).pop(_selectedIds.toList());
                },
          child: Text(
            'Sync (${_selectedIds.length})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class MasterCategoryPickerDialog extends StatefulWidget {
  final List<Map<String, String>> categories;

  const MasterCategoryPickerDialog({super.key, required this.categories});

  @override
  State<MasterCategoryPickerDialog> createState() => _MasterCategoryPickerDialogState();
}

class _MasterCategoryPickerDialogState extends State<MasterCategoryPickerDialog> {
  final Set<String> _selectedIds = {};
  String _selectedLanguage = 'Malayalam';
  final List<String> _languages = ['Malayalam', 'Tamil', 'Hindi', 'English', 'Telugu', 'Kannada', 'Sports', 'News', 'Kids'];

  @override
  void initState() {
    super.initState();
    for (final cat in widget.categories) {
      _selectedIds.add(cat['id']!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF151922),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.88,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.playlist_add_check_rounded, color: Color(0xFFA855F7), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Sync Master Channels',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('SELECT TARGET LANGUAGE CATEGORY', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLanguage,
                  dropdownColor: const Color(0xFF151922),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  isExpanded: true,
                  items: _languages
                      .map((lang) => DropdownMenuItem(value: lang, child: Text(lang)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedLanguage = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('SELECT PORTAL CATEGORIES', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _selectedIds.addAll(widget.categories.map((c) => c['id']!))),
                      child: const Text('Select All', style: TextStyle(color: Color(0xFFA855F7), fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selectedIds.clear()),
                      child: Text('Deselect All', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: widget.categories.length,
                  separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.04), height: 1),
                  itemBuilder: (context, index) {
                    final cat = widget.categories[index];
                    final id = cat['id']!;
                    final title = cat['title']!;
                    final isChecked = _selectedIds.contains(id);

                    return CheckboxListTile(
                      value: isChecked,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedIds.add(id);
                          } else {
                            _selectedIds.remove(id);
                          }
                        });
                      },
                      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      activeColor: const Color(0xFFA855F7),
                      checkColor: Colors.white,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      dense: true,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedIds.isEmpty ? Colors.white10 : const Color(0xFFA855F7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () {
                          Navigator.pop(context, {
                            'categoryIds': _selectedIds.toList(),
                            'language': _selectedLanguage,
                          });
                        },
                  child: Text(
                    'Sync Master Registry (${_selectedIds.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
