import 'package:flutter_test/flutter_test.dart';
import 'package:bts_delivery_app/services/date_utils.dart';

void main() {
  group('DateTimeUtils Tests', () {
    test('should return start of day correctly', () {
      final date = DateTime(2024, 3, 15, 14, 30, 45);
      final startOfDay = DateTimeUtils.startOfDay(date);
      
      expect(startOfDay.year, 2024);
      expect(startOfDay.month, 3);
      expect(startOfDay.day, 15);
      expect(startOfDay.hour, 0);
      expect(startOfDay.minute, 0);
      expect(startOfDay.second, 0);
      expect(startOfDay.millisecond, 0);
    });

    test('should return start of tomorrow correctly', () {
      final date = DateTime(2024, 3, 15, 14, 30, 45);
      final startOfTomorrow = DateTimeUtils.startOfTomorrow(date);
      
      expect(startOfTomorrow.year, 2024);
      expect(startOfTomorrow.month, 3);
      expect(startOfTomorrow.day, 16);
      expect(startOfTomorrow.hour, 0);
      expect(startOfTomorrow.minute, 0);
      expect(startOfTomorrow.second, 0);
      expect(startOfTomorrow.millisecond, 0);
    });

    test('should handle month boundary correctly', () {
      final date = DateTime(2024, 3, 31, 23, 59, 59);
      final startOfTomorrow = DateTimeUtils.startOfTomorrow(date);
      
      expect(startOfTomorrow.year, 2024);
      expect(startOfTomorrow.month, 4);
      expect(startOfTomorrow.day, 1);
      expect(startOfTomorrow.hour, 0);
      expect(startOfTomorrow.minute, 0);
      expect(startOfTomorrow.second, 0);
    });

    test('should format date correctly', () {
      final date = DateTime(2024, 3, 15);
      final formatted = DateTimeUtils.formatDate(date);
      
      expect(formatted, 'Mar 15, 2024');
    });

    test('should format time correctly', () {
      final date = DateTime(2024, 3, 15, 14, 30);
      final formatted = DateTimeUtils.formatTime(date);
      
      expect(formatted, '2:30 PM');
    });

    test('should format datetime correctly', () {
      final date = DateTime(2024, 3, 15, 9, 15);
      final formatted = DateTimeUtils.formatDateTime(date);
      
      expect(formatted, 'Mar 15, 2024 9:15 AM');
    });
  });
}