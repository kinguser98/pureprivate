import 'package:hive/hive.dart';

part 'iptv_channel.g.dart';

@HiveType(typeId: 1)
class IptvChannel {
  @HiveField(0)
  final int id;
  
  @HiveField(1)
  final String name;
  
  @HiveField(2)
  final String? customName;
  
  @HiveField(3)
  final String logoUrl;
  
  @HiveField(4)
  final String cmd;
  
  @HiveField(5)
  final String categoryName;
  
  @HiveField(6)
  final bool enabled;
  
  @HiveField(7)
  final int position;
  
  @HiveField(8)
  final int portalId;
  
  @HiveField(9)
  final String? portalName;
  
  @HiveField(10)
  final String? stalkerId;

  IptvChannel({
    required this.id,
    required this.name,
    this.customName,
    required this.logoUrl,
    required this.cmd,
    required this.categoryName,
    this.enabled = true,
    this.position = 0,
    this.portalId = 0,
    this.portalName,
    this.stalkerId,
  });

  factory IptvChannel.fromJson(Map<String, dynamic> json) {
    int _parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    String _parseString(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      return value.toString();
    }

    bool _parseBool(dynamic value) {
      if (value == null) return true;
      if (value is bool) return value;
      if (value is int) return value == 1;
      if (value is String) return value == '1' || value.toLowerCase() == 'true';
      return true;
    }

    return IptvChannel(
      id: _parseInt(json['id']),
      name: _parseString(json['name']),
      customName: _parseString(json['custom_name']),
      logoUrl: _parseString(json['logo_url']),
      cmd: _parseString(json['cmd']),
      categoryName: _parseString(json['category_name']),
      enabled: _parseBool(json['enabled']),
      position: _parseInt(json['position']),
      portalId: _parseInt(json['portal_id']),
      portalName: _parseString(json['portal_name']),
      stalkerId: _parseString(json['stalker_id']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'custom_name': customName,
      'logo_url': logoUrl,
      'cmd': cmd,
      'category_name': categoryName,
      'enabled': enabled ? 1 : 0,
      'position': position,
      'portal_id': portalId,
      'portal_name': portalName,
      'stalker_id': stalkerId,
    };
  }

  String get displayName => (customName == null || customName!.trim().isEmpty) ? name : customName!;
  
  @override
  String toString() => 'IptvChannel(id: $id, name: $name, enabled: $enabled)';
}
