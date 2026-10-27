import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Supabase project settings. Release builds take them from
/// `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
/// (as the CI build does); when a define is missing or empty the values
/// below are used. The anon key is public by design — access is controlled
/// by the database's row-level security and function checks.
///
/// The admin can point a device at another server (Server settings, 27 Oct
/// 2026): if Supabase is ever gone, the shop moves to a new server restored
/// from its backup the same day, without waiting for a new app version.
class SupabaseConfig {
  static const String _urlDefine = String.fromEnvironment('SUPABASE_URL');
  static const String _keyDefine = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const String supabaseUrl = _urlDefine == '' ? 'https://hrlciruepdstrvtsuoyr.supabase.co' : _urlDefine;
  static const String supabaseAnonKey = _keyDefine == ''
      ? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhybGNpcnVlcGRzdHJ2dHN1b3lyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMDA4MjgsImV4cCI6MjA5ODY3NjgyOH0.-FqYflyY-0333oNlC5clOpcOm_E60R6e9WULp_xZHEo'
      : _keyDefine;

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  // ---- the server this device uses (built-in unless the admin changed it)
  static const _urlPref = 'server_url_override';
  static const _keyPref = 'server_key_override';
  static String? _urlOverride;
  static String? _keyOverride;

  static String get url => _urlOverride ?? supabaseUrl;
  static String get anonKey => _keyOverride ?? supabaseAnonKey;
  static bool get usingOtherServer => _urlOverride != null;

  /// Read once at start, before Supabase is set up.
  static Future<void> loadOverride() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final u = prefs.getString(_urlPref);
      final k = prefs.getString(_keyPref);
      if (u != null && k != null && check(u, k) == null) {
        _urlOverride = u;
        _keyOverride = k;
      }
    } catch (_) {
      // settings unreadable: the built-in server
    }
  }

  /// Takes effect when the app starts again.
  static Future<void> saveOverride(String url, String key) async {
    final problem = check(url, key);
    if (problem != null) throw Exception(problem);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlPref, _cleanUrl(url));
    await prefs.setString(_keyPref, key.trim());
  }

  /// Back to the built-in server (when the app starts again).
  static Future<void> clearOverride() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_urlPref);
    await prefs.remove(_keyPref);
  }

  static String _cleanUrl(String url) => url.trim().replaceAll(RegExp(r'/+$'), '');

  /// Why [url] / [key] cannot be used, or null when they look right. The
  /// secret service-role key is refused: it must never be in the app.
  static String? check(String url, String key) {
    final u = Uri.tryParse(_cleanUrl(url));
    if (u == null || u.scheme != 'https' || u.host.isEmpty) {
      return 'The server address must start with https://';
    }
    final k = key.trim();
    if (k.startsWith('sb_secret_')) return 'That is the secret key. Use the public (anon / publishable) key.';
    if (k.startsWith('sb_publishable_') && k.length > 20) return null;
    final parts = k.split('.');
    if (!k.startsWith('eyJ') || parts.length != 3) return 'That does not look like a Supabase public key.';
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (payload is Map && payload['role'] == 'service_role') {
        return 'That is the secret service-role key. Use the anon (public) key.';
      }
    } catch (_) {
      return 'That does not look like a Supabase public key.';
    }
    return null;
  }

  /// Can this device reach [url] with [key]? Null when it can.
  static Future<String?> testConnection(
    String url,
    String key, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final problem = check(url, key);
    if (problem != null) return problem;
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse('${_cleanUrl(url)}/auth/v1/health')).timeout(timeout);
      req.headers.set('apikey', key.trim());
      final res = await req.close().timeout(timeout);
      await res.drain<void>();
      if (res.statusCode == 200) return null;
      if (res.statusCode == 401 || res.statusCode == 403)
        return 'The server answered but refused the key (${res.statusCode}).';
      return 'The server answered with an error (${res.statusCode}).';
    } on SocketException {
      return 'Cannot reach that server. Check the address and the internet.';
    } on HandshakeException {
      return 'The server\'s security certificate could not be checked.';
    } catch (e) {
      return 'Cannot reach that server: $e';
    } finally {
      client.close(force: true);
    }
  }
}
