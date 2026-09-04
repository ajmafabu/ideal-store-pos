import 'dart:convert';
import 'package:hive_ce/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/hive_adapter.dart';
import '../utils/logger.dart';

/// Logs important business actions for compliance and troubleshooting.
/// Stores audit entries in a local Hive box AND in Supabase.
/// When offline, queues to Hive and syncs on next online connection.
class AuditService {
  static final AuditService _instance = AuditService._internal();
  factory AuditService() => _instance;
  AuditService._internal();

  Box<Map>? _auditBox;

  Future<Box<Map>> _getBox() async {
    if (_auditBox != null && _auditBox!.isOpen) return _auditBox!;
    final cipher = HiveAdapter.cipher;
    _auditBox = await Hive.openBox<Map>(HiveAdapter.pendingAuditBox, encryptionCipher: cipher);
    return _auditBox!;
  }

  /// Log an audit entry — queues to Hive if offline, writes to Supabase if online
  Future<void> log({
    required String action,
    required String entityType,
    String? entityId,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    String? description,
  }) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final entry = {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'old_data': oldData != null ? jsonEncode(oldData) : null,
        'new_data': newData != null ? jsonEncode(newData) : null,
        'description': description,
        'user_id': user?.id,
        'user_email': user?.email,
        'created_at': DateTime.now().toIso8601String(),
      };

      // Try Supabase first
      try {
        await Supabase.instance.client.from('audit_log').insert(entry);
        Logger.info('Audit: $action $entityType ${entityId ?? ""}');
      } catch (e) {
        // Offline — queue to Hive for later sync
        final box = await _getBox();
        await box.put(entry['id'], entry);
        Logger.info('Audit queued offline: $action $entityType ${entityId ?? ""}');
      }
    } catch (e) {
      Logger.warning('Failed to write audit log: $e');
    }
  }

  /// Sync queued audit logs from Hive to Supabase
  Future<void> syncPendingAuditLogs() async {
    try {
      final box = await _getBox();
      if (box.isEmpty) return;

      final keys = box.keys.toList();
      for (final key in keys) {
        final entry = box.get(key);
        if (entry == null) continue;
        try {
          await Supabase.instance.client.from('audit_log').insert(entry);
          await box.delete(key);
        } catch (_) {
          // Will retry on next sync
        }
      }
      if (keys.isNotEmpty) {
        Logger.info('Synced ${keys.length} audit logs');
      }
    } catch (e) {
      Logger.warning('Failed to sync audit logs: $e');
    }
  }

  /// Query audit log
  Future<List<Map<String, dynamic>>> getAuditLog({
    String? entityType,
    String? entityId,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    try {
      var query = Supabase.instance.client
          .from('audit_log')
          .select();
      if (entityType != null) {
        query = query.eq('entity_type', entityType);
      }
      if (entityId != null) {
        query = query.eq('entity_id', entityId);
      }
      if (from != null) {
        query = query.gte('created_at', from.toIso8601String());
      }
      if (to != null) {
        query = query.lte('created_at', to.toIso8601String());
      }
      final response = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      Logger.warning('Failed to query audit log: $e');
      return [];
    }
  }
}
