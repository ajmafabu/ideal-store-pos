import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/logger.dart';

class VersionCheckService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Check if app needs forced update
  /// Returns true if update is required
  Future<bool> checkForUpdate() async {
    try {
      final response = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'min_version')
          .maybeSingle();

      if (response == null) return false;

      final minVersion = response['value'] as String;
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      return _isVersionBelow(currentVersion, minVersion);
    } catch (e) {
      Logger.error('VersionCheck', e);
      return false;
    }
  }

  /// Get minimum version string
  Future<String?> getMinVersion() async {
    try {
      final response = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'min_version')
          .maybeSingle();

      return response?['value'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Compare two semantic versions (e.g., "1.0.0" vs "1.0.1")
  bool _isVersionBelow(String current, String minimum) {
    final currentParts = current.split('.').map(int.parse).toList();
    final minimumParts = minimum.split('.').map(int.parse).toList();

    for (var i = 0; i < 3; i++) {
      final c = i < currentParts.length ? currentParts[i] : 0;
      final m = i < minimumParts.length ? minimumParts[i] : 0;
      if (c < m) return true;
      if (c > m) return false;
    }
    return false;
  }
}
