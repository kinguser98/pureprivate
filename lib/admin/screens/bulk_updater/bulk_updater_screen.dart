import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/admin_api_client.dart';
import '../../utils/drawer_helper.dart';
import '../../widgets/common/glass_card.dart';

class BulkUpdaterScreen extends ConsumerStatefulWidget {
  const BulkUpdaterScreen({super.key});

  @override
  ConsumerState<BulkUpdaterScreen> createState() => _BulkUpdaterScreenState();
}

class _BulkUpdaterScreenState extends ConsumerState<BulkUpdaterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  final adminApi = AdminApiClient();
  bool _dryRun = true;
  bool _loading = false;
  String? _resultMessage;
  String? _responseHtml;
  bool? _success;
  int? _matchCount;

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  Future<void> _runUpdate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final result = await adminApi.bulkUpdate(
        _findController.text.trim(),
        _replaceController.text.trim(),
        _dryRun,
      );
      setState(() {
        _success = result['success'] as bool? ?? false;
        _resultMessage = result['message'] as String? ?? 'Operation completed';
        _responseHtml = result['html'] as String?;
        _matchCount = _tryParseMatchCount(_responseHtml);
      });
    } catch (e) {
      setState(() {
        _success = false;
        _resultMessage = 'Error: $e';
        _responseHtml = null;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  int? _tryParseMatchCount(String? html) {
    if (html == null) return null;
    final match = RegExp(r'(\d+)\s*matches?\s*found', caseSensitive: false).firstMatch(html);
    if (match != null) return int.tryParse(match.group(1)!);
    final rowMatch = RegExp(r'<tr[^>]*>', caseSensitive: false).allMatches(html);
    if (rowMatch.length > 1) return rowMatch.length - 1;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk Updater'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: DrawerProvider.openDrawer,
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F1923), Color(0xFF1A1F2E)],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Find & Replace URLs',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _findController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Find',
                          hintText: 'e.g. old-cdn.example.com',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                          filled: true,
                          fillColor: const Color(0xFF1A1F2E).withOpacity(0.6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFEF4444)),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.red.withOpacity(0.5)),
                          ),
                          prefixIcon: const Icon(Icons.search, color: Color(0xFFEF4444)),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Find text is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _replaceController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Replace',
                          hintText: 'e.g. new-cdn.example.com',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                          filled: true,
                          fillColor: const Color(0xFF1A1F2E).withOpacity(0.6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFEF4444)),
                          ),
                          prefixIcon: const Icon(Icons.swap_horiz, color: Color(0xFFEF4444)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            'Dry Run',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Switch(
                            value: _dryRun,
                            onChanged: (value) => setState(() => _dryRun = value),
                            activeColor: const Color(0xFFEF4444),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _runUpdate,
                          icon: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(_dryRun ? Icons.preview : Icons.play_arrow),
                          label: Text(_loading ? 'Running...' : (_dryRun ? 'Preview Update' : 'Run Update')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFEF4444).withOpacity(0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_resultMessage != null) ...[
                const SizedBox(height: 20),
                _buildResultBanner(),
              ],
              if (_matchCount != null) ...[
                const SizedBox(height: 12),
                _buildMatchCountBadge(),
              ],
              if (_responseHtml != null && _responseHtml!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildResponseHtmlCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultBanner() {
    final isSuccess = _success ?? false;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderColor: isSuccess ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle : Icons.error,
            color: isSuccess ? Colors.green : Colors.red,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _resultMessage ?? '',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchCountBadge() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
          ),
          child: Text(
            '$_matchCount match${_matchCount == 1 ? '' : 'es'} found',
            style: const TextStyle(
              color: Color(0xFFEF4444),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        if (_dryRun)
          Text(
            'Dry Run — No changes applied',
            style: TextStyle(
              color: Colors.orange.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
      ],
    );
  }

  Widget _buildResponseHtmlCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.code, size: 18, color: Colors.white.withOpacity(0.6)),
              const SizedBox(width: 8),
              Text(
                'Server Response',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117).withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                _responseHtml!,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
