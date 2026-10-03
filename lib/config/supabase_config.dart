/// Supabase project settings. Release builds take them from
/// `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
/// (as the CI build does); when a define is missing or empty the values
/// below are used. The anon key is public by design — access is controlled
/// by the database's row-level security and function checks.
class SupabaseConfig {
  static const String _urlDefine = String.fromEnvironment('SUPABASE_URL');
  static const String _keyDefine = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const String supabaseUrl =
      _urlDefine == '' ? 'https://hrlciruepdstrvtsuoyr.supabase.co' : _urlDefine;
  static const String supabaseAnonKey = _keyDefine == ''
      ? 'https://hrlciruepdstrvtsuoyr.supabase.co'
      : _keyDefine;

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
