import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import '../../models/cloud_account_model.dart';
import '../../services/cloud_auth_service.dart';
import '../../services/download_manager_service.dart';
import '../../screens/cloud_accounts/cloud_accounts_screen.dart';

enum DownloadDestinationType {
  local,
  googleDrive,
  onedrive,
  telegram,
}

class AddDownloadBottomSheet extends StatefulWidget {
  final String url;
  final String? suggestedFilename;
  final int? contentLength;
  final Map<String, String>? headers;

  const AddDownloadBottomSheet({
    super.key,
    required this.url,
    this.suggestedFilename,
    this.contentLength,
    this.headers,
  });

  static Future<void> show(
    BuildContext context, {
    required String url,
    String? suggestedFilename,
    int? contentLength,
    Map<String, String>? headers,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddDownloadBottomSheet(
        url: url,
        suggestedFilename: suggestedFilename,
        contentLength: contentLength,
        headers: headers,
      ),
    );
  }

  @override
  State<AddDownloadBottomSheet> createState() => _AddDownloadBottomSheetState();
}

class _AddDownloadBottomSheetState extends State<AddDownloadBottomSheet> {
  late final TextEditingController _nameController;
  DownloadDestinationType _selectedDestination = DownloadDestinationType.local;
  List<CloudAccount> _allCloudAccounts = [];
  String? _selectedAccountId;
  bool _isServerSide = false;

  @override
  void initState() {
    super.initState();
    String initialName = widget.suggestedFilename ?? '';
    if (initialName.isEmpty) {
      try {
        final uri = Uri.parse(widget.url);
        final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (seg.isNotEmpty) {
          initialName = Uri.decodeComponent(seg.last);
        }
      } catch (_) {}
    }
    if (initialName.isEmpty) {
      initialName = 'download_${DateTime.now().millisecondsSinceEpoch}.mp4';
    }
    _nameController = TextEditingController(text: initialName);
    _loadCloudAccounts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadCloudAccounts() async {
    final accounts = await CloudAuthService.getAccounts();
    final defaultMode = await CloudAuthService.getExecutionMode();
    if (mounted) {
      setState(() {
        _allCloudAccounts = accounts;
        _isServerSide = defaultMode == 'server';
        _syncSelectedAccount();
      });
    }
  }

  void _syncSelectedAccount() {
    final matching = _getMatchingAccounts();
    if (matching.isNotEmpty) {
      if (_selectedAccountId == null || !matching.any((a) => a.id == _selectedAccountId)) {
        _selectedAccountId = matching.first.id;
      }
    } else {
      _selectedAccountId = null;
    }
  }

  List<CloudAccount> _getMatchingAccounts() {
    switch (_selectedDestination) {
      case DownloadDestinationType.googleDrive:
        return _allCloudAccounts.where((a) => a.provider == CloudProvider.gdrive).toList();
      case DownloadDestinationType.onedrive:
        return _allCloudAccounts.where((a) => a.provider == CloudProvider.onedrivePersonal || a.provider == CloudProvider.onedriveBusiness).toList();
      case DownloadDestinationType.telegram:
        return _allCloudAccounts.where((a) => a.provider == CloudProvider.telegramBot || a.provider == CloudProvider.telegramMtproto).toList();
      case DownloadDestinationType.local:
        return [];
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return 'Size Unknown';
    const mb = 1024 * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    } else if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
  }

  String _getFileExtension(String filename) {
    final ext = p.extension(filename).replaceAll('.', '').toUpperCase();
    return ext.isNotEmpty ? ext : 'FILE';
  }

  String _getDomain(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return 'Web Link';
    }
  }

  void _startDownload() {
    final filename = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'file_${DateTime.now().millisecondsSinceEpoch}';

    String? targetCloudId;
    String? targetCloudName;

    if (_selectedDestination != DownloadDestinationType.local) {
      final matching = _getMatchingAccounts();
      final acc = matching.where((a) => a.id == _selectedAccountId).firstOrNull ?? matching.firstOrNull;
      if (acc != null) {
        targetCloudId = acc.id;
        targetCloudName = acc.accountName;
      }
    }

    // Queue download task in background service
    final service = DownloadManagerService();
    service.startDownload(
      url: widget.url,
      filename: filename,
      headers: widget.headers,
      autoUploadCloudAccountId: targetCloudId,
      autoUploadCloudAccountName: targetCloudName,
      isServerSide: _isServerSide,
    );

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(
              targetCloudId != null ? Icons.cloud_upload_rounded : Icons.download_done_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                targetCloudId != null
                    ? 'Downloading "$filename" -> Auto-uploading to $targetCloudName'
                    : 'Downloading "$filename" in background',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ext = _getFileExtension(_nameController.text);
    final isVideo = ['MP4', 'MKV', 'WEBM', 'TS', 'AVI', 'MOV'].contains(ext);
    final isAudio = ['MP3', 'AAC', 'M4A', 'WAV', 'FLAC'].contains(ext);
    final isImage = ['JPG', 'JPEG', 'PNG', 'WEBP', 'GIF'].contains(ext);

    IconData typeIcon = Icons.insert_drive_file_rounded;
    Color badgeColor = const Color(0xFF38BDF8);
    if (isVideo) {
      typeIcon = Icons.movie_rounded;
      badgeColor = const Color(0xFFEF4444);
    } else if (isAudio) {
      typeIcon = Icons.audiotrack_rounded;
      badgeColor = const Color(0xFFA855F7);
    } else if (isImage) {
      typeIcon = Icons.image_rounded;
      badgeColor = const Color(0xFF10B981);
    }

    final matchingAccounts = _getMatchingAccounts();

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
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
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                ),
                child: Icon(typeIcon, color: badgeColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready to Download',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            ext,
                            style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatSize(widget.contentLength),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        const Text('•', style: TextStyle(color: Colors.white30)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _getDomain(widget.url),
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white60),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // File Name Input
          const Text('File Name', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear_rounded, color: Colors.white30, size: 18),
                onPressed: () => _nameController.clear(),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Destination Selector
          const Text('Save Destination', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildDestinationOption(
                type: DownloadDestinationType.local,
                icon: Icons.smartphone_rounded,
                label: 'Phone Storage',
                color: const Color(0xFF10B981),
              ),
              const SizedBox(width: 8),
              _buildDestinationOption(
                type: DownloadDestinationType.googleDrive,
                icon: Icons.storage_rounded,
                label: 'Google Drive',
                color: const Color(0xFF4285F4),
              ),
              const SizedBox(width: 8),
              _buildDestinationOption(
                type: DownloadDestinationType.onedrive,
                icon: Icons.cloud_rounded,
                label: 'OneDrive',
                color: const Color(0xFF0078D4),
              ),
              const SizedBox(width: 8),
              _buildDestinationOption(
                type: DownloadDestinationType.telegram,
                icon: Icons.send_rounded,
                label: 'Telegram',
                color: const Color(0xFF229ED9),
              ),
            ],
          ),

          // Connected Cloud Account Picker
          if (_selectedDestination != DownloadDestinationType.local) ...[
            const SizedBox(height: 14),
            if (matchingAccounts.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No ${_destinationName()} account connected yet.',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CloudAccountsScreen()),
                        );
                      },
                      child: const Text('Connect Now', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Select Target Account', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text(
                    '${matchingAccounts.length} account${matchingAccounts.length > 1 ? 's' : ''} available',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedAccountId ?? matchingAccounts.first.id,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E293B),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
                    items: matchingAccounts.map((acc) {
                      return DropdownMenuItem<String>(
                        value: acc.id,
                        child: Row(
                          children: [
                            Icon(
                              acc.provider == CloudProvider.gdrive
                                  ? Icons.storage_rounded
                                  : (acc.provider == CloudProvider.onedriveBusiness ? Icons.business_center_rounded : Icons.cloud_rounded),
                              color: const Color(0xFF38BDF8),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    acc.accountName,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (acc.email != null && acc.email!.isNotEmpty)
                                    Text(
                                      acc.email!,
                                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedAccountId = val);
                      }
                    },
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Execution Mode Switch (Client Side vs Server Side)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  Icon(
                    _isServerSide ? Icons.cloud_done_rounded : Icons.phone_android_rounded,
                    color: _isServerSide ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isServerSide ? 'Server-Side Cloud Stream (0% Mobile Data)' : 'Direct Phone Stream to Cloud (0 Phone Storage)',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        Text(
                          _isServerSide
                              ? 'Offloaded to Shared Hosting. Best for direct MP4/MKV & cloud links.'
                              : 'Streams in RAM directly to Cloud. 0 MB storage used. Works for Streamtape.',
                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isServerSide,
                    activeThumbColor: const Color(0xFFF59E0B),
                    onChanged: (v) => setState(() => _isServerSide = v),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 4,
                  ),
                  icon: Icon(
                    _selectedDestination != DownloadDestinationType.local ? Icons.cloud_upload_rounded : Icons.download_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: Text(
                    _selectedDestination != DownloadDestinationType.local ? 'Start & Upload' : 'Start Download',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  onPressed: _startDownload,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _destinationName() {
    switch (_selectedDestination) {
      case DownloadDestinationType.googleDrive:
        return 'Google Drive';
      case DownloadDestinationType.onedrive:
        return 'OneDrive';
      case DownloadDestinationType.telegram:
        return 'Telegram';
      case DownloadDestinationType.local:
        return 'Local';
    }
  }

  Widget _buildDestinationOption({
    required DownloadDestinationType type,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final isSelected = _selectedDestination == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedDestination = type;
            _syncSelectedAccount();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.2) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : Colors.white.withValues(alpha: 0.08),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? color : Colors.white54, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
