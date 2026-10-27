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
  // the login server could not be reached or failed (5xx): the session is
  // kept by the library; the cached profile is used meanwhile
  if (e is AuthRetryableFetchException) return true;
  if (e is PostgrestException) {
    // the server answered: a refusal, unless it only said "not now"
    return isServerUnavailable(e);
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

/// The server answered only to say it cannot work right now: Supabase down
/// or overloaded, a gateway error page (502/503/504, Cloudflare 52x), the
/// database unreachable. Until 25 Oct 2026 these counted as refusals, so a
/// bill made while Supabase had trouble was rejected instead of kept, and
/// queued bills were moved to Sync Issues after a few tries. Retrying later
/// is safe: every document carries its own id.
bool isServerUnavailable(PostgrestException e) {
  final code = (e.code ?? '').trim().toUpperCase();
  // a non-JSON answer (gateway page): the code is the HTTP status
  // (three digits only: 42501, 23514 … are database refusals, not HTTP)
  final status = code.length == 3 ? int.tryParse(code) : null;
  if (status != null && ((status >= 500 && status <= 599) || status == 408 || status == 429)) return true;
  const postgrest = {'PGRST000', 'PGRST001', 'PGRST002', 'PGRST003'}; // database not reachable
  const postgres = {
    '08000', '08001', '08003', '08004', '08006', // connection lost
    '53300', // too many connections
    '57P01', '57P02', '57P03', // server shutting down / starting
    '57014', // statement cancelled (timeout): nothing was saved
  };
  if (postgrest.contains(code) || postgres.contains(code)) return true;
  final m = e.message.toLowerCase();
  return m.contains('<html') ||
      m.contains('bad gateway') ||
      m.contains('service unavailable') ||
      m.contains('gateway time') ||
      m.contains('upstream connect');
}

const serverTroubleMessage =
    'The server is having a problem right now. Saved on this device; it will be sent automatically.';

/// Server trouble rather than no internet (for the wording shown).
bool isServerTrouble(Object e) =>
    (e is PostgrestException && isServerUnavailable(e)) ||
    (e is AuthRetryableFetchException && (int.tryParse(e.statusCode ?? '') ?? 0) >= 500);

/// Unique-key violation: the row already exists on the server. Used to make
/// offline replays idempotent (the first attempt may have committed).
bool isDuplicateKey(Object e) => e is PostgrestException && (e.code == '23505' || e.message.contains('duplicate key'));

/// The message the database raised for a business rule, e.g. "Payment 150 is
/// more than the amount due (100)". Falls back to [fallback] for technical errors.
String serverMessage(Object e, {String fallback = 'Something went wrong. Please try again.'}) {
  if (isServerTrouble(e)) {
    return serverTroubleMessage;
  }
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

/// Remembers for a minute that the server just failed, so the next bills
/// are saved on the device at once instead of each waiting for a time-out
/// at a busy counter (25 Oct 2026). A successful sync clears it.
class ServerHealth {
  static DateTime? _downUntil;
  static const pause = Duration(minutes: 1);

  static bool get likelyDown => _downUntil != null && DateTime.now().isBefore(_downUntil!);

  static void markDown() => _downUntil = DateTime.now().add(pause);

  static void markUp() => _downUntil = null;
}
