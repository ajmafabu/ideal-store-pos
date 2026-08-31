import 'dart:developer' as developer;

class Logger {
  static const String _tag = 'IdealStorePOS';

  static void info(String message) {
    developer.log(message, name: _tag, level: 800);
  }

  static void warning(String message) {
    developer.log(message, name: _tag, level: 900);
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: _tag,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void debug(String message) {
    developer.log(message, name: _tag, level: 500);
  }
}
