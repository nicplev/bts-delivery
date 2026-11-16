import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notification event types
enum NotificationType {
  signOffCleared,
  success,
  error,
  info,
}

/// Notification event model
class NotificationEvent {
  final NotificationType type;
  final String message;
  final DateTime timestamp;

  NotificationEvent({
    required this.type,
    required this.message,
  }) : timestamp = DateTime.now();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationEvent &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          message == message &&
          timestamp == other.timestamp;

  @override
  int get hashCode => type.hashCode ^ message.hashCode ^ timestamp.hashCode;
}

/// Notification state notifier
class NotificationNotifier extends StateNotifier<NotificationEvent?> {
  NotificationNotifier() : super(null);

  void showSignOffCleared() {
    state = NotificationEvent(
      type: NotificationType.signOffCleared,
      message: 'Sign-off cleared due to data changes',
    );
  }

  void showSuccess(String message) {
    state = NotificationEvent(
      type: NotificationType.success,
      message: message,
    );
  }

  void showError(String message) {
    state = NotificationEvent(
      type: NotificationType.error,
      message: message,
    );
  }

  void showInfo(String message) {
    state = NotificationEvent(
      type: NotificationType.info,
      message: message,
    );
  }

  void clear() {
    state = null;
  }
}

/// Global notification provider
final notificationProvider =
    StateNotifierProvider<NotificationNotifier, NotificationEvent?>((ref) {
  return NotificationNotifier();
});
