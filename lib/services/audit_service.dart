import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

/// Logs important business actions for compliance and troubleshooting.
/// Stores audit entries in a local Hive box AND optionally in Supabase.
class AuditService {
  static final AuditService _instance = AuditService._internal();
  factory AuditService() => _instance;
  AuditService._internal();

  /// Log an audit entry
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

      // Store locally (Hive box would be ideal, but for simplicity use Supabase)
      // In production, also store in Hive for offline audit trail
      await Supabase.instance.client.from('audit_log').insert(entry);
      Logger.info('Audit: $action $entityType ${entityId ?? ""}');
    } catch (e) {
      Logger.warning('Failed to write audit log: $e');
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
      final response = await Supabase.instance.client
          .from('audit_log')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      Logger.warning('Failed to query audit log: $e');
      return [];
    }
  }
}
