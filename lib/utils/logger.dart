import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class Logger {
  static const String _tag = 'IdealStorePOS';

  /// `developer.log` prints nothing in release builds, so shop phones had
  /// no error log at all (QA #7). Warnings and errors also go to the system
  /// log there (Android logcat), where `adb logcat` can read them.
  static void _release(String level, String message, [Object? error]) {
    if (!kReleaseMode) return;
    debugPrint('[$_tag] $level: $message${error != null ? ' — $error' : ''}');
  }

  static void info(String message) {
    developer.log(message, name: _tag, level: 800);
  }

  static void warning(String message) {
    developer.log(message, name: _tag, level: 900);
    _release('W', message);
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: _tag,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    _release('E', message, error);
  }

  static void debug(String message) {
    developer.log(message, name: _tag, level: 500);
  }
}
