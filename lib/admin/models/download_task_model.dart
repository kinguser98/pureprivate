enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  canceled,
}

class DownloadTask {
  final String id;
  String url;
  String filename;
  Map<String, String>? headers;
  DownloadStatus status;
  int receivedBytes;
  int totalBytes;
  double speedBytesPerSec;
  int? etaSeconds;
  String? savePath;
  String? errorMessage;
  String? autoUploadCloudAccountId;
  String? autoUploadCloudAccountName;
  bool isServerSide;
  DateTime createdAt;
  DateTime? completedAt;

  DownloadTask({
    required this.id,
    required this.url,
    required this.filename,
    this.headers,
    this.status = DownloadStatus.queued,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0.0,
    this.etaSeconds,
    this.savePath,
    this.errorMessage,
    this.autoUploadCloudAccountId,
    this.autoUploadCloudAccountName,
    this.isServerSide = false,
    required this.createdAt,
    this.completedAt,
  });

  double get progress {
    if (totalBytes <= 0) return 0.0;
    final p = receivedBytes / totalBytes;
    return p.clamp(0.0, 1.0);
  }

  String get speedFormatted {
    if (speedBytesPerSec <= 0) return '0 KB/s';
    if (speedBytesPerSec >= 1024 * 1024) {
      return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    }
    return '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
  }

  String get sizeFormatted {
    final rec = _formatBytes(receivedBytes);
    if (totalBytes <= 0) return rec;
    return '$rec / ${_formatBytes(totalBytes)}';
  }

  String get etaFormatted {
    if (etaSeconds == null || etaSeconds! <= 0) return '--';
    final duration = Duration(seconds: etaSeconds!);
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    }
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    }
    return '${duration.inSeconds}s';
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'filename': filename,
    'headers': headers,
    'status': status.name,
    'receivedBytes': receivedBytes,
    'totalBytes': totalBytes,
    'savePath': savePath,
    'errorMessage': errorMessage,
    'autoUploadCloudAccountId': autoUploadCloudAccountId,
    'autoUploadCloudAccountName': autoUploadCloudAccountName,
    'isServerSide': isServerSide,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
    id: json['id'] as String,
    url: json['url'] as String,
    filename: json['filename'] as String? ?? 'download',
    headers: json['headers'] != null ? Map<String, String>.from(json['headers'] as Map) : null,
    status: DownloadStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => DownloadStatus.queued,
    ),
    receivedBytes: json['receivedBytes'] as int? ?? 0,
    totalBytes: json['totalBytes'] as int? ?? 0,
    savePath: json['savePath'] as String?,
    errorMessage: json['errorMessage'] as String?,
    autoUploadCloudAccountId: json['autoUploadCloudAccountId'] as String?,
    autoUploadCloudAccountName: json['autoUploadCloudAccountName'] as String?,
    isServerSide: json['isServerSide'] as bool? ?? false,
    createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now() : DateTime.now(),
    completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'] as String) : null,
  );
}
