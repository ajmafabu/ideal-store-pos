class ErrorMessages {
  /// Parse a raw exception into a user-friendly message
  static String parse(Object error) {
    final msg = error.toString();

    // Network errors
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return 'No internet connection. Please check your network.';
    }
    if (msg.contains('TimeoutException') || msg.contains('timeout')) {
      return 'Request timed out. Please try again.';
    }

    // Supabase/PostgREST errors
    if (msg.contains('PostgrestException')) {
      if (msg.contains('23503')) return 'This item is referenced by other records and cannot be deleted.';
      if (msg.contains('23505')) return 'This record already exists.';
      if (msg.contains('42P01')) return 'Database configuration error. Contact support.';
      if (msg.contains('permission denied') || msg.contains('42501')) return 'You do not have permission for this action.';
      return 'Database error. Please try again.';
    }

    // Auth errors
    if (msg.contains('AuthException') || msg.contains('Invalid login')) {
      return 'Invalid credentials. Please check your email and password.';
    }

    // Hive errors
    if (msg.contains('HiveError') || msg.contains('Box not found')) {
      return 'Local storage error. Please restart the app.';
    }

    // Generic fallback
    if (msg.length > 100) return 'Something went wrong. Please try again.';
    return msg;
  }
}
