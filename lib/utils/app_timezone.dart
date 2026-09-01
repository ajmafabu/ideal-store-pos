import 'package:intl/intl.dart';

class AppTimezone {
  /// Device's local timezone offset (detected from system)
  static Duration get _localOffset {
    final now = DateTime.now();
    return now.timeZoneOffset;
  }

  /// Public accessor for the device's timezone offset
  static Duration get localOffset => _localOffset;

  static DateTime nowUtc() => DateTime.now().toUtc();

  static DateTime nowIst() => DateTime.now().toUtc().add(_localOffset);

  static DateTime todayStartUtc() {
    final now = nowIst();
    return DateTime.utc(now.year, now.month, now.day).subtract(_localOffset);
  }

  static DateTime todayEndUtc() => todayStartUtc().add(const Duration(days: 1));

  static DateTime yesterdayStartUtc() =>
      todayStartUtc().subtract(const Duration(days: 1));

  static DateTime yesterdayEndUtc() => todayStartUtc();

  static DateTime monthStartUtc() {
    final now = nowIst();
    return DateTime.utc(now.year, now.month, 1).subtract(_localOffset);
  }

  static DateTime monthEndUtc() {
    final now = nowIst();
    return DateTime.utc(now.year, now.month + 1, 1).subtract(_localOffset);
  }

  static DateTime todayStartIst() {
    final now = nowIst();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime todayEndIst() => todayStartIst().add(const Duration(days: 1));

  static DateTime yesterdayStartIst() =>
      todayStartIst().subtract(const Duration(days: 1));

  static DateTime yesterdayEndIst() => todayStartIst();

  static DateTime monthStartIst() {
    final now = nowIst();
    return DateTime(now.year, now.month, 1);
  }

  static DateTime monthEndIst() {
    final now = nowIst();
    return DateTime(now.year, now.month + 1, 1);
  }

  static DateTime toIst(DateTime utcDate) => utcDate.toUtc().add(_localOffset);

  static DateTime toUtc(DateTime istDate) {
    if (istDate.isUtc) return istDate;
    return DateTime.utc(
      istDate.year,
      istDate.month,
      istDate.day,
      istDate.hour,
      istDate.minute,
      istDate.second,
      istDate.millisecond,
      istDate.microsecond,
    ).subtract(_localOffset);
  }

  static String formatDate(DateTime date) =>
      DateFormat('dd MMM yyyy').format(toIst(date));

  static String formatDateTime(DateTime date) =>
      DateFormat('dd MMM yyyy, hh:mm a').format(toIst(date));

  static String formatTime(DateTime date) =>
      DateFormat('hh:mm a').format(toIst(date));

  static String formatShortDate(DateTime date) =>
      DateFormat('dd MMM').format(toIst(date));
}
