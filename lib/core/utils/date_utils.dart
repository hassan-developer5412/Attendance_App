import 'package:intl/intl.dart';

/// Date/time formatting helpers used throughout the app.
class AppDateUtils {
 
  AppDateUtils._();

  /// Canonical key used to store dates in the DB, e.g. 2025-01-31.
  static String dateKey(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date);

  static DateTime todayDateOnly() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static String formatFullDate(DateTime date) =>
      DateFormat('EEE, d MMM yyyy').format(date);

  static String formatShortDate(DateTime date) =>
      DateFormat('d MMM yyyy').format(date);

  static String formatTime(DateTime time) => DateFormat('hh:mm a').format(time);

  static String formatMonthYear(DateTime date) =>
      DateFormat('MMMM yyyy').format(date);

  static DateTime parseDateKey(String key) => DateFormat('yyyy-MM-dd').parse(key);

  static int daysInMonth(int year, int month) {
    final beginningNextMonth = (month < 12)
        ? DateTime(year, month + 1, 1)
        : DateTime(year + 1, 1, 1);
    return beginningNextMonth.subtract(const Duration(days: 1)).day;
  }
}