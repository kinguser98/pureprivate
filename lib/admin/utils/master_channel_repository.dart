import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../../data/api_service.dart';
import '../models/master_channel.dart';
import '../models/iptv_channel.dart';

class MasterChannelRepository {
  static const String _boxName = 'master_channels_box';

  static Future<Box<MasterChannel>?> get _box async {
    try {
      if (!Hive.isAdapterRegistered(20)) {
        Hive.registerAdapter(MasterChannelAdapter());
      }
      if (Hive.isBoxOpen(_boxName)) {
        return Hive.box<MasterChannel>(_boxName);
      }
      return await Hive.openBox<MasterChannel>(_boxName);
    } catch (e) {
      debugPrint('MasterChannelRepository Hive _box error: $e');
      return null;
    }
  }

  /// Returns all stored master channels from PHP server (with local Hive fallback).
  static Future<List<MasterChannel>> getAll() async {
    try {
      final uri = Uri.parse('${ApiService.apiUrl}?action=get_master_channels');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List data = json.decode(res.body);
        final list = data.map((e) => MasterChannel.fromJson(e as Map<String, dynamic>)).toList();
        
        // Cache to Hive if available
        try {
          final box = await _box;
          if (box != null) {
            await box.clear();
            for (final m in list) {
              await box.put(m.id, m);
            }
          }
        } catch (_) {}
        return list;
      }
    } catch (e) {
      debugPrint('MasterChannelRepository getAll remote error: $e');
    }

    try {
      final box = await _box;
      if (box != null) {
        return box.values.toList();
      }
    } catch (e) {
      debugPrint('MasterChannelRepository getAll local error: $e');
    }
    return [];
  }

  /// Bulk import channels from a portal into the Master Registry (MySQL + local Hive).
  static Future<int> bulkImportFromPortal(List<IptvChannel> portalChannels, {String language = 'Malayalam'}) async {
    int importedCount = 0;
    try {
      final List<Map<String, dynamic>> channelList = [];
      for (final ch in portalChannels) {
        final normName = ch.name.trim();
        if (normName.isEmpty) continue;

        channelList.add({
          'id': 'master_${DateTime.now().microsecondsSinceEpoch}_${channelList.length}',
          'displayName': normName,
          'logoUrl': ch.logoUrl,
          'epgId': ch.stalkerId ?? normName,
          'categoryName': ch.categoryName,
          'aliases': [normName.toLowerCase()],
        });
      }

      if (channelList.isEmpty) return 0;

      final uri = Uri.parse('${ApiService.apiUrl}?action=bulk_import_master_channels');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'language': language,
          'channels': channelList,
        }),
      ).timeout(const Duration(seconds: 15));

      debugPrint('bulk_import_master_channels status: ${res.statusCode}, body: ${res.body}');

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true) {
          importedCount = data['imported'] ?? channelList.length;
        }
      }
    } catch (e) {
      debugPrint('MasterChannelRepository bulkImportFromPortal error: $e');
    }
    return importedCount;
  }

  /// Save or update a master channel entry (MySQL + Hive).
  static Future<void> save(MasterChannel channel) async {
    try {
      final uri = Uri.parse('${ApiService.apiUrl}?action=save_master_channel');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(channel.toJson()),
      ).timeout(const Duration(seconds: 10));

      debugPrint('save_master_channel response status: ${res.statusCode}, body: ${res.body}');

      try {
        final box = await _box;
        if (box != null) {
          await box.put(channel.id, channel);
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('MasterChannelRepository save error: $e');
    }
  }

  /// Delete a master channel entry (MySQL + Hive).
  static Future<void> delete(String masterId) async {
    try {
      final uri = Uri.parse('${ApiService.apiUrl}?action=delete_master_channel&master_id=$masterId');
      await http.get(uri).timeout(const Duration(seconds: 10));

      try {
        final box = await _box;
        if (box != null) {
          await box.delete(masterId);
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('MasterChannelRepository delete error: $e');
    }
  }
}
