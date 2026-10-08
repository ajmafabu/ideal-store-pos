import 'package:hive_ce/hive.dart';

import '../config/hive_adapter.dart';
import '../models/profile.dart';

/// The signed-in user's profile, kept in the encrypted local store so the
/// app opens (and the till unlocks) after a restart without internet.
class ProfileCache {
  static const _key = 'profile';

  static Box<Map>? get _box =>
      Hive.isBoxOpen(HiveAdapter.cachedProfileBox) ? Hive.box<Map>(HiveAdapter.cachedProfileBox) : null;

  static Future<void> save(Profile profile) async => _box?.put(_key, profile.toJson());

  static Future<void> clear() async => _box?.delete(_key);

  /// The saved profile, only if it belongs to [userId].
  static Profile? read(String? userId) {
    final raw = _box?.get(_key);
    if (userId == null || raw == null || raw['id'] != userId) return null;
    try {
      return Profile.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }
}
