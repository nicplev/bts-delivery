import 'package:intl/intl.dart';

class DateTimeUtils {
  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }
  
  static DateTime startOfTomorrow(DateTime date) {
    return startOfDay(date.add(const Duration(days: 1)));
  }
  
  static DateTime get todayStart => startOfDay(DateTime.now());
  static DateTime get tomorrowStart => startOfTomorrow(DateTime.now());
  
  static String formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }
  
  static String formatTime(DateTime date) {
    return DateFormat('h:mm a').format(date);
  }
  
  static String formatDateTime(DateTime date) {
    return DateFormat('MMM dd, yyyy h:mm a').format(date);
  }
}