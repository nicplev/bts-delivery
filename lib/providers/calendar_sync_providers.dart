import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/calendar_sync_service.dart';
import '../services/calendar_subscription_service.dart';
import 'deliveries_providers.dart';
import 'staff_providers.dart';

/// Provider for the calendar sync service (legacy manual sync)
final calendarSyncServiceProvider = Provider<CalendarSyncService>((ref) {
  return CalendarSyncService();
});

/// Provider for the calendar subscription service (new auto-sync)
final calendarSubscriptionServiceProvider = Provider<CalendarSubscriptionService>((ref) {
  final staffRepository = ref.watch(staffRepositoryProvider);
  return CalendarSubscriptionService(staffRepository);
});

/// Provider to check if calendar permissions are granted
final hasCalendarPermissionsProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(calendarSyncServiceProvider);
  return await service.hasPermissions();
});

/// Provider to sync all deliveries to calendar
final syncAllDeliveriesProvider = FutureProvider.autoDispose<SyncResult>((ref) async {
  final service = ref.watch(calendarSyncServiceProvider);
  final deliveriesAsync = await ref.watch(allDeliveriesListProvider.future);

  return await service.syncDeliveriesToCalendar(deliveriesAsync);
});

/// Provider to track calendar sync state
final calendarSyncStateProvider = StateProvider<CalendarSyncState>((ref) {
  return CalendarSyncState.idle;
});

/// Enum for calendar sync state
enum CalendarSyncState {
  idle,
  syncing,
  success,
  error,
}
