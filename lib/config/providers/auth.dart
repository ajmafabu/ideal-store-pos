import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/profile.dart';
import 'services.dart';

// ============================================
// PROFILE & AUTH
// ============================================

final profileProvider = FutureProvider<Profile?>((ref) async {
  final auth = ref.watch(authServiceProvider);
  final user = auth.currentUser;
  if (user == null) return null;
  try {
    return await auth.getCurrentProfile();
  } catch (e) {
    return null;
  }
});
