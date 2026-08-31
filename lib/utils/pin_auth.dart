import 'package:crypto/crypto.dart';
import 'dart:convert';

class PinAuth {
  static const String _salt = 'ideal_store_pos_v1';

  /// Derive a strong Supabase password from email + PIN.
  /// Returns a 64-char hex string that's cryptographically strong.
  static String derivePassword(String email, String pin) {
    final input = '$email:$pin:$_salt';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Hash PIN for storage in profiles table.
  static String hashPin(String pin) {
    final input = 'pin:$pin:$_salt';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify a PIN against a stored hash.
  static bool verifyPin(String pin, String storedHash) {
    return hashPin(pin) == storedHash;
  }
}
