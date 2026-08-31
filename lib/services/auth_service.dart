import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';
import '../utils/pin_auth.dart';
import '../utils/logger.dart';
import 'audit_service.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Future<Profile?> getCurrentProfile() async {
    if (currentUser == null) return null;

    try {
      final response = await _client
          .from('profiles')
          .select('id, name, role, pin, shop_id, active, gstin, shop_name, shop_address, shop_phone')
          .eq('id', currentUser!.id);

      if (response.isEmpty) {
        // Profile doesn't exist yet — this happens if the Supabase
        // on_auth_user_created trigger hasn't fired or was removed.
        // Return null and let the UI handle it (login screen shows error).
        Logger.warning('No profile found for user ${currentUser!.id}');
        return null;
      }
      return Profile.fromJson(response.first);
    } catch (e) {
      Logger.error('getCurrentProfile', e);
      return null;
    }
  }

  /// Sign up with email + password (for admin initial setup)
  Future<void> signUp({
    required String email,
    required String password,
    required String name,
    String role = 'staff',
    String? pin,
  }) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name, 'role': role},
    );

    // Store PIN hash if provided
    if (pin != null && pin.isNotEmpty) {
      final user = _client.auth.currentUser;
      if (user != null) {
        // Retry until profile exists (DB trigger creates it)
        for (int i = 0; i < 10; i++) {
          try {
            await _client
                .from('profiles')
                .update({'pin': PinAuth.hashPin(pin)})
                .eq('id', user.id);
            break;
          } catch (e) {
            Logger.warning('PIN update attempt failed (signIn): $e');
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
      }
    }
  }

  /// Sign up with email + PIN (for staff — derives strong password from PIN)
  Future<void> signUpWithPin({
    required String email,
    required String pin,
    required String name,
    String role = 'staff',
  }) async {
    final derivedPassword = PinAuth.derivePassword(email, pin);

    await _client.auth.signUp(
      email: email,
      password: derivedPassword,
      data: {'name': name, 'role': role},
    );

    // Store PIN hash with retry
    final user = _client.auth.currentUser;
    if (user != null) {
      for (int i = 0; i < 10; i++) {
        try {
          await _client
              .from('profiles')
              .update({'pin': PinAuth.hashPin(pin)})
              .eq('id', user.id);
          break;
        } catch (e) {
          Logger.warning('PIN update attempt failed (signUp): $e');
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }
  }

  /// Sign in with email + password (direct password login)
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email,
      password: password,
    ).timeout(const Duration(seconds: 20), onTimeout: () {
      throw Exception('Connection timed out. Check your internet and try again.');
    });

    AuditService().log(
      action: 'sign_in',
      entityType: 'auth',
      description: 'Signed in with password: $email',
    );
  }

  /// Sign in with email + PIN (derives strong password from PIN)
  Future<void> signInWithPin({
    required String email,
    required String pin,
  }) async {
    final derivedPassword = PinAuth.derivePassword(email, pin);

    await _client.auth.signInWithPassword(
      email: email,
      password: derivedPassword,
    );

    AuditService().log(
      action: 'sign_in',
      entityType: 'auth',
      description: 'Signed in with PIN: $email',
    );

    // After successful auth, verify PIN hash matches
    final user = _client.auth.currentUser;
    if (user != null) {
      try {
        final profileRes = await _client
            .from('profiles')
            .select('pin')
            .eq('id', user.id)
            .maybeSingle();

        if (profileRes != null) {
          final storedPin = profileRes['pin'] as String?;
          if (storedPin != null && !PinAuth.verifyPin(pin, storedPin)) {
            await _client.auth.signOut();
            throw Exception('Invalid PIN');
          }
        }
      } catch (e) {
        if (e.toString().contains('Invalid PIN')) rethrow;
      }
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();

    AuditService().log(
      action: 'sign_out',
      entityType: 'auth',
      description: 'User signed out',
    );
  }

  Future<void> updateProfile({
    required String name,
    String? gstin,
    String? shopName,
    String? shopAddress,
    String? shopPhone,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Not logged in');

    await _client.from('profiles').update({
      'name': name,
      'gstin': gstin,
      'shop_name': shopName,
      'shop_address': shopAddress,
      'shop_phone': shopPhone,
    }).eq('id', user.id);
  }

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
}
