import 'package:hive/hive.dart';

part 'master_channel.g.dart';

@HiveType(typeId: 20)
class MasterChannel {
  @HiveField(0)
  final String id; // Unique Master ID e.g. "master_hbo_hd"

  @HiveField(1)
  final String displayName;

  @HiveField(2)
  final String logoUrl;

  @HiveField(3)
  final String epgId;

  @HiveField(4)
  final String categoryName;

  @HiveField(5)
  final List<String> aliases;

  @HiveField(6)
  final DateTime updatedAt;

  @HiveField(7)
  final String language;

  MasterChannel({
    required this.id,
    required this.displayName,
    required this.logoUrl,
    required this.epgId,
    required this.categoryName,
    this.language = 'Malayalam',
    this.aliases = const [],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  MasterChannel copyWith({
    String? id,
    String? displayName,
    String? logoUrl,
    String? epgId,
    String? categoryName,
    String? language,
    List<String>? aliases,
    DateTime? updatedAt,
  }) {
    return MasterChannel(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      logoUrl: logoUrl ?? this.logoUrl,
      epgId: epgId ?? this.epgId,
      categoryName: categoryName ?? this.categoryName,
      language: language ?? this.language,
      aliases: aliases ?? this.aliases,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'master_id': id,
        'displayName': displayName,
        'logoUrl': logoUrl,
        'epgId': epgId,
        'categoryName': categoryName,
        'language': language,
        'aliases': aliases,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory MasterChannel.fromJson(Map<String, dynamic> json) {
    final mId = json['master_id']?.toString() ?? json['id']?.toString() ?? '';
    return MasterChannel(
      id: mId.isNotEmpty ? mId : 'master_${DateTime.now().millisecondsSinceEpoch}',
      displayName: json['displayName']?.toString() ?? json['display_name']?.toString() ?? '',
      logoUrl: json['logoUrl']?.toString() ?? json['logo_url']?.toString() ?? '',
      epgId: json['epgId']?.toString() ?? json['epg_id']?.toString() ?? '',
      categoryName: json['categoryName']?.toString() ?? json['category_name']?.toString() ?? 'General',
      language: json['language']?.toString() ?? 'Malayalam',
      aliases: (json['aliases'] is List
          ? json['aliases'] as List
          : (json['aliases']?.toString().split(',') ?? []))
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
