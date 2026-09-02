import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/cloud_account_model.dart';
import '../../models/browser_tab_model.dart';
import '../../services/cloud_auth_service.dart';
import '../../services/download_exporter_service.dart';

class DownloadDestinationDialog extends StatefulWidget {
  final SniffedMediaItem item;
  final String? localFilePath;

  const DownloadDestinationDialog({
    super.key,
    required this.item,
    this.localFilePath,
  });

  @override
  State<DownloadDestinationDialog> createState() => _DownloadDestinationDialogState();
}

class _DownloadDestinationDialogState extends State<DownloadDestinationDialog> {
  late TextEditingController _filenameController;
  List<CloudAccount> _accounts = [];
  String _selectedDestination = 'local'; // 'local', 'gdrive', 'onedrive', 'telegram'
  CloudAccount? _selectedAccount;
  String _executionMode = 'client'; // 'client' or 'server'
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    String safeTitle = widget.item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (safeTitle.isEmpty) safeTitle = 'media_download';
    _filenameController = TextEditingController(text: safeTitle);
    if (widget.localFilePath != null) {
      _selectedDestination = 'gdrive';
    }
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accs = await CloudAuthService.getAccounts();
    final mode = await CloudAuthService.getExecutionMode();
    if (mounted) {
      setState(() {
        _accounts = accs;
        _executionMode = mode;
      });
    }
  }

  List<CloudAccount> get _availableAccountsForSelectedDest {
    if (_selectedDestination == 'gdrive') {
      return _accounts.where((a) => a.provider == CloudProvider.gdrive).toList();
    }
    if (_selectedDestination == 'onedrive') {
      return _accounts.where((a) => a.provider == CloudProvider.onedrivePersonal || a.provider == CloudProvider.onedriveBusiness).toList();
    }
    if (_selectedDestination == 'telegram') {
      return _accounts.where((a) => a.provider == CloudProvider.telegramBot || a.provider == CloudProvider.telegramMtproto).toList();
    }
    return [];
  }

  Future<void> _startDownload() async {
    final filename = _filenameController.text.trim().isNotEmpty ? _filenameController.text.trim() : 'media_file';

    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusMessage = 'Initializing transfer...';
    });

    if (_selectedDestination == 'local') {
      setState(() => _statusMessage = 'Downloading to Device Storage...');
      final path = await DownloadExporterService.downloadToLocal(
        item: widget.item,
        customFilename: filename,
        onProgress: (rec, total) {
          if (total > 0 && mounted) {
            setState(() {
              _progress = rec / total;
              _statusMessage = '${(rec / (1024 * 1024)).toStringAsFixed(1)} MB / ${(total / (1024 * 1024)).toStringAsFixed(1)} MB (${(_progress * 100).toStringAsFixed(0)}%)';
            });
          }
        },
      );

      if (mounted) {
        setState(() => _isDownloading = false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(path != null ? 'Downloaded to Downloads folder!' : 'Download failed'),
            backgroundColor: path != null ? Colors.green : Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Cloud Destination
    final targetAccount = _selectedAccount ?? _availableAccountsForSelectedDest.firstOrNull;
    if (targetAccount == null) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select or connect a cloud account first.')),
        );
      }
      return;
    }

    if (_executionMode == 'server') {
      setState(() => _statusMessage = 'Dispatching job to Server Relay...');
      final ok = await DownloadExporterService.dispatchServerSideJob(
        account: targetAccount,
        item: widget.item,
        customFilename: filename,
      );
      if (mounted) {
        setState(() => _isDownloading = false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Server cloud upload started in background!' : 'Server dispatch failed.'),
            backgroundColor: ok ? Colors.green : Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Client-Side Cloud Upload
    setState(() => _statusMessage = 'Uploading to ${targetAccount.accountName}...');
    bool success = false;

    if (_selectedDestination == 'gdrive') {
      success = await DownloadExporterService.uploadToGoogleDrive(
        account: targetAccount,
        item: widget.item,
        customFilename: filename,
        localFilePath: widget.localFilePath,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusMessage = 'Uploading: ${(p * 100).toStringAsFixed(1)}%';
            });
          }
        },
      );
    } else if (_selectedDestination == 'onedrive') {
      success = await DownloadExporterService.uploadToOneDrive(
        account: targetAccount,
        item: widget.item,
        customFilename: filename,
        localFilePath: widget.localFilePath,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusMessage = 'Uploading: ${(p * 100).toStringAsFixed(1)}%';
            });
          }
        },
      );
    } else if (_selectedDestination == 'telegram') {
      success = await DownloadExporterService.uploadToTelegram(
        account: targetAccount,
        item: widget.item,
        customFilename: filename,
        localFilePath: widget.localFilePath,
      );
    }

    if (mounted) {
      setState(() => _isDownloading = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Successfully uploaded to ${targetAccount.accountName}!' : 'Upload failed.'),
          backgroundColor: success ? Colors.green : Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.download_rounded, color: Color(0xFFEF4444), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Export Media', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(widget.item.typeLabel, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text('Filename', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _filenameController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Destination', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _destChip('local', 'Local Storage', Icons.phone_android_rounded, const Color(0xFF10B981)),
                  _destChip('gdrive', 'Google Drive', Icons.storage_rounded, const Color(0xFF4285F4)),
                  _destChip('onedrive', 'OneDrive', Icons.cloud_rounded, const Color(0xFF0078D4)),
                  _destChip('telegram', 'Telegram', Icons.send_rounded, const Color(0xFF2AABEE)),
                ],
              ),
              if (_selectedDestination != 'local') ...[
                const SizedBox(height: 14),
                const Text('Select Account', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (_availableAccountsForSelectedDest.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No accounts connected for this provider. Add one in Admin -> Cloud Storages.',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonFormField<CloudAccount>(
                    value: _selectedAccount ?? _availableAccountsForSelectedDest.first,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    items: _availableAccountsForSelectedDest.map((acc) {
                      return DropdownMenuItem(
                        value: acc,
                        child: Text('${acc.accountName} (${acc.provider.displayName})', style: const TextStyle(color: Colors.white)),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedAccount = val),
                  ),
              ],
              const SizedBox(height: 16),
              if (_isDownloading) ...[
                LinearProgressIndicator(value: _progress > 0 ? _progress : null, color: const Color(0xFFEF4444), backgroundColor: Colors.white12),
                const SizedBox(height: 8),
                Text(_statusMessage, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 12),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isDownloading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: _isDownloading ? null : _startDownload,
                    child: Text(_isDownloading ? 'Transferring...' : 'Start Download', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _destChip(String key, String label, IconData icon, Color color) {
    final isSelected = _selectedDestination == key;
    return ChoiceChip(
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedDestination = key;
          _selectedAccount = null;
        });
      },
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : color),
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selectedColor: color.withValues(alpha: 0.8),
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isSelected ? color : Colors.white.withValues(alpha: 0.05))),
    );
  }
}
