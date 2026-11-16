import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/delivery.dart';

/// Service for syncing deliveries with the device's native calendar (EventKit on iOS)
class CalendarSyncService {
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();

  static const String _calendarName = 'BTS Deliveries';
  static const int _calendarColor = 0xFF00AEEF; // KAKA Blue

  /// Request calendar permissions from the user
  Future<bool> requestPermissions() async {
    try {
      var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && (permissionsGranted.data ?? false)) {
        return true;
      }

      permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
      return permissionsGranted.isSuccess && (permissionsGranted.data ?? false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error requesting calendar permissions: $e');
      }
      return false;
    }
  }

  /// Check if calendar permissions are granted
  Future<bool> hasPermissions() async {
    try {
      final result = await _deviceCalendarPlugin.hasPermissions();
      return result.isSuccess && (result.data ?? false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking calendar permissions: $e');
      }
      return false;
    }
  }

  /// Get or create the BTS Deliveries calendar
  Future<String?> _getOrCreateCalendar() async {
    try {
      // Retrieve all calendars
      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (!calendarsResult.isSuccess || calendarsResult.data == null) {
        if (kDebugMode) {
          debugPrint('Failed to retrieve calendars');
        }
        return null;
      }

      // Check if our calendar already exists
      for (final cal in calendarsResult.data!) {
        if (cal.name == _calendarName && cal.id != null) {
          return cal.id;
        }
      }

      // Create new calendar
      final newCalendar = Calendar(
        name: _calendarName,
        color: _calendarColor,
        accountName: _calendarName,
        accountType: 'local',
      );

      final createResult = await _deviceCalendarPlugin.createCalendar(
        newCalendar.name!,
        calendarColor: Color(newCalendar.color ?? _calendarColor),
        localAccountName: newCalendar.accountName,
      );
      if (createResult.isSuccess && createResult.data != null) {
        return createResult.data;
      }

      if (kDebugMode) {
        debugPrint('Failed to create calendar: ${createResult.errors}');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting/creating calendar: $e');
      }
      return null;
    }
  }

  /// Sync a single delivery to the calendar
  Future<bool> syncDeliveryToCalendar(Delivery delivery) async {
    try {
      final hasPerms = await hasPermissions();
      if (!hasPerms) {
        final granted = await requestPermissions();
        if (!granted) return false;
      }

      final calendarId = await _getOrCreateCalendar();
      if (calendarId == null) return false;

      // Check if event already exists
      final existingEvent = await _getExistingEvent(calendarId, delivery.id);

      // Create event from delivery
      final event = Event(
        calendarId,
        eventId: existingEvent?.eventId,
        title: 'Delivery: ${delivery.schoolName}',
        description: _buildEventDescription(delivery),
        start: _buildEventStartTime(delivery),
        end: _buildEventEndTime(delivery),
        location: delivery.schoolName,
        allDay: delivery.time == null,
      );

      // Create or update the event
      final result = await _deviceCalendarPlugin.createOrUpdateEvent(event);

      if (result?.isSuccess ?? false) {
        if (kDebugMode) {
          debugPrint('Successfully synced delivery ${delivery.id} to calendar');
        }
        return true;
      } else {
        if (kDebugMode) {
          debugPrint('Failed to sync delivery: ${result?.errors}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error syncing delivery to calendar: $e');
      }
      return false;
    }
  }

  /// Sync multiple deliveries to the calendar
  Future<SyncResult> syncDeliveriesToCalendar(List<Delivery> deliveries) async {
    int successCount = 0;
    int failureCount = 0;

    for (final delivery in deliveries) {
      final success = await syncDeliveryToCalendar(delivery);
      if (success) {
        successCount++;
      } else {
        failureCount++;
      }
    }

    return SyncResult(
      totalCount: deliveries.length,
      successCount: successCount,
      failureCount: failureCount,
    );
  }

  /// Remove a delivery event from the calendar
  Future<bool> removeDeliveryFromCalendar(String deliveryId) async {
    try {
      final hasPerms = await hasPermissions();
      if (!hasPerms) return false;

      final calendarId = await _getOrCreateCalendar();
      if (calendarId == null) return false;

      final existingEvent = await _getExistingEvent(calendarId, deliveryId);
      if (existingEvent == null) return true; // Already removed

      final result = await _deviceCalendarPlugin.deleteEvent(
        calendarId,
        existingEvent.eventId!,
      );

      return result.isSuccess;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error removing delivery from calendar: $e');
      }
      return false;
    }
  }

  /// Clear all BTS Delivery events from the calendar
  Future<bool> clearAllDeliveries() async {
    try {
      final hasPerms = await hasPermissions();
      if (!hasPerms) return false;

      final calendarId = await _getOrCreateCalendar();
      if (calendarId == null) return false;

      // Get all events from the BTS Deliveries calendar
      final now = DateTime.now();
      final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(
          startDate: now.subtract(const Duration(days: 365)),
          endDate: now.add(const Duration(days: 365)),
        ),
      );

      if (!eventsResult.isSuccess || eventsResult.data == null) {
        return false;
      }

      // Delete all events
      for (final event in eventsResult.data!) {
        if (event.eventId != null) {
          await _deviceCalendarPlugin.deleteEvent(calendarId, event.eventId!);
        }
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error clearing all deliveries: $e');
      }
      return false;
    }
  }

  /// Get existing event for a delivery
  Future<Event?> _getExistingEvent(String calendarId, String deliveryId) async {
    try {
      final now = DateTime.now();
      final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(
          startDate: now.subtract(const Duration(days: 365)),
          endDate: now.add(const Duration(days: 365)),
        ),
      );

      if (!eventsResult.isSuccess || eventsResult.data == null) {
        return null;
      }

      // Find event with matching description containing delivery ID
      // We store the delivery ID in the description for matching
      for (final event in eventsResult.data!) {
        if (event.description?.contains('[ID:$deliveryId]') ?? false) {
          return event;
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting existing event: $e');
      }
      return null;
    }
  }

  /// Build event description from delivery
  String _buildEventDescription(Delivery delivery) {
    final buffer = StringBuffer();

    buffer.writeln('School: ${delivery.schoolName}');

    if (delivery.staffNames.isNotEmpty) {
      buffer.writeln('Staff: ${delivery.staffNames.join(", ")}');
    }

    if (delivery.notes?.isNotEmpty ?? false) {
      buffer.writeln('\nNotes: ${delivery.notes}');
    }

    buffer.writeln('\nManaged by BTS Delivery App');
    buffer.writeln('[ID:${delivery.id}]'); // Hidden ID for matching

    return buffer.toString();
  }

  /// Build event start time from delivery
  TZDateTime _buildEventStartTime(Delivery delivery) {
    if (delivery.time != null) {
      final dateTime = DateTime(
        delivery.date.year,
        delivery.date.month,
        delivery.date.day,
        delivery.time!.hour,
        delivery.time!.minute,
      );
      return TZDateTime.from(dateTime, TZDateTime.now(local).location);
    }

    // All-day event starts at midnight
    final dateTime = DateTime(
      delivery.date.year,
      delivery.date.month,
      delivery.date.day,
    );
    return TZDateTime.from(dateTime, TZDateTime.now(local).location);
  }

  /// Build event end time from delivery
  TZDateTime _buildEventEndTime(Delivery delivery) {
    if (delivery.time != null) {
      // Default to 1 hour duration for timed events
      final dateTime = DateTime(
        delivery.date.year,
        delivery.date.month,
        delivery.date.day,
        delivery.time!.hour,
        delivery.time!.minute,
      ).add(const Duration(hours: 1));
      return TZDateTime.from(dateTime, TZDateTime.now(local).location);
    }

    // All-day event ends at 11:59 PM
    final dateTime = DateTime(
      delivery.date.year,
      delivery.date.month,
      delivery.date.day,
      23,
      59,
    );
    return TZDateTime.from(dateTime, TZDateTime.now(local).location);
  }
}

/// Result of a calendar sync operation
class SyncResult {
  final int totalCount;
  final int successCount;
  final int failureCount;

  SyncResult({
    required this.totalCount,
    required this.successCount,
    required this.failureCount,
  });

  bool get hasFailures => failureCount > 0;
  bool get allSucceeded => failureCount == 0 && totalCount > 0;
  bool get allFailed => successCount == 0 && totalCount > 0;

  String get message {
    if (allSucceeded) {
      return 'Successfully synced $successCount ${successCount == 1 ? 'delivery' : 'deliveries'}';
    } else if (allFailed) {
      return 'Failed to sync deliveries';
    } else {
      return 'Synced $successCount of $totalCount deliveries';
    }
  }
}
