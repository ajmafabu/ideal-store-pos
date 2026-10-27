import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/config/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _jwt(Map<String, dynamic> payload) {
  String part(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(payload)}.signature';
}

/// Moving the shop to another server (27 Oct 2026).
void main() {
  group('what may be saved as the server', () {
    test('the built-in server and key pass', () {
      expect(SupabaseConfig.check(SupabaseConfig.supabaseUrl, SupabaseConfig.supabaseAnonKey), isNull);
    });

    test('https only', () {
      expect(SupabaseConfig.check('http://x.supabase.co', SupabaseConfig.supabaseAnonKey), contains('https'));
      expect(SupabaseConfig.check('not a url', SupabaseConfig.supabaseAnonKey), isNotNull);
    });

    test('the secret keys are refused: they must never be in the app', () {
      expect(SupabaseConfig.check('https://x.supabase.co', _jwt({'role': 'service_role'})), contains('secret'));
      expect(SupabaseConfig.check('https://x.supabase.co', 'sb_secret_abcdefghijklmnop'), contains('secret'));
    });

    test('public keys pass; anything else is refused', () {
      expect(SupabaseConfig.check('https://x.supabase.co', _jwt({'role': 'anon'})), isNull);
      expect(SupabaseConfig.check('https://x.supabase.co', 'sb_publishable_abcdefghijklmnop'), isNull);
      expect(SupabaseConfig.check('https://x.supabase.co', 'hello'), isNotNull);
    });
  });

  test('saved, read back at start, and cleared', () async {
    SharedPreferences.setMockInitialValues({});
    final key = _jwt({'role': 'anon'});
    await SupabaseConfig.saveOverride('https://new.example.co/', key);
    await SupabaseConfig.loadOverride();
    expect(SupabaseConfig.usingOtherServer, isTrue);
    expect(SupabaseConfig.url, 'https://new.example.co');
    expect(SupabaseConfig.anonKey, key);
    await SupabaseConfig.clearOverride();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('server_url_override'), isNull);
    expect(() => SupabaseConfig.saveOverride('https://x.co', 'sb_secret_abcdefghijklmnop'), throwsException);
  });

  test('a server that cannot be reached is reported before anything is saved', () async {
    final r = await SupabaseConfig.testConnection(
      'https://127.0.0.1:9',
      _jwt({'role': 'anon'}),
      timeout: const Duration(seconds: 3),
    );
    expect(r, isNotNull);
  });
}
