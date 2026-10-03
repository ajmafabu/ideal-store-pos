import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Tells a genuine "could not reach the server" failure apart from a
/// server that answered with an error (validation, permission, constraint).
///
/// Only network failures may be queued for offline retry; a server
/// rejection must be shown to the user, because retrying it later can
/// never succeed and queuing it used to hide the error (#5, #6, #7).
bool isNetworkError(Object e) {
  if (e is SocketException || e is TimeoutException || e is HttpException) {
    return true;
  }
  if (e is PostgrestException) {
    // PostgREST answered: the request reached the database.
    return false;
  }
  if (e is AuthException) return false;
  final msg = e.toString().toLowerCase();
  const markers = [
    'socketexception',
    'clientexception',
    'connection timeout',
    'connection refused',
    'connection reset',
    'connection closed',
    'failed host lookup',
    'network is unreachable',
    'no address associated',
    'timeoutexception',
    'handshakeexception',
    'xmlhttprequest error',
  ];
  return markers.any(msg.contains);
}

/// Unique-key violation: the row already exists on the server. Used to make
/// offline replays idempotent (the first attempt may have committed).
bool isDuplicateKey(Object e) =>
    e is PostgrestException && (e.code == '23505' || e.message.contains('duplicate key'));

/// The message the database raised for a business rule, e.g. "Payment 150 is
/// more than the amount due (100)". Falls back to [fallback] for technical errors.
String serverMessage(Object e, {String fallback = 'Something went wrong. Please try again.'}) {
  if (e is PostgrestException) {
    const businessCodes = {'P0001', 'P0002', '42501', '23514'};
    if (businessCodes.contains(e.code) || e.code == null) {
      final m = e.message.trim();
      if (m.isNotEmpty && m.length < 300) return m;
    }
    if (e.code == '23505') return 'This record already exists.';
    if (e.code == '23503') return 'This item is referenced by other records.';
    return fallback;
  }
  if (isNetworkError(e)) return 'No connection to the server. Please check the internet.';
  final s = e.toString();
  return s.length > 200 ? fallback : s.replaceFirst('Exception: ', '');
}
