import 'package:intl/intl.dart';

/// Day arithmetic plus the app's single set of display formats (Australian):
/// dates `d MMM yyyy`, weekday dates `EEE d MMM yyyy`, times `h:mm a` and
/// date-times `d MMM yyyy, h:mm a`.
///
/// For on-screen text only: exports (Excel/CSV) and anything parsed back keep
/// their own fixed formats.
class DateTimeUtils {
  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime startOfTomorrow(DateTime date) {
    return startOfDay(date.add(const Duration(days: 1)));
  }

  static DateTime get todayStart => startOfDay(DateTime.now());
  static DateTime get tomorrowStart => startOfTomorrow(DateTime.now());

  /// "17 Nov 2026".
  static String formatDate(DateTime date) {
    return DateFormat('d MMM yyyy').format(date);
  }

  /// "Tue 17 Nov 2026".
  static String formatWeekdayDate(DateTime date) {
    return DateFormat('EEE d MMM yyyy').format(date);
  }

  /// "9:00 AM".
  static String formatTime(DateTime date) {
    return DateFormat('h:mm a').format(date);
  }

  /// "17 Nov 2026, 9:00 AM".
  static String formatDateTime(DateTime date) {
    return DateFormat('d MMM yyyy, h:mm a').format(date);
  }
}
