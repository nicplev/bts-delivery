import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/delivery.dart';
import '../models/staff.dart';
import '../repositories/deliveries_repository.dart';
import '../services/date_utils.dart';
import 'repository_providers.dart';
import 'auth_providers.dart';

final allDeliveriesProvider = StateProvider<bool>((ref) => false);

final deliveryTodayProvider = Provider.autoDispose<DateTime>((ref) {
  final now = DateTime.now();
  final today = DateTimeUtils.startOfDay(now);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final timer = Timer(tomorrow.difference(now), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return today;
});

final todayDeliveriesProvider =
    StreamProvider.autoDispose<List<Delivery>>((ref) {
  final deliveryDate = ref.watch(deliveryTodayProvider);
  final tomorrow = DateTime(
    deliveryDate.year,
    deliveryDate.month,
    deliveryDate.day + 1,
  );
  final repository = ref.watch(deliveriesRepositoryProvider);
  return _watchVisibleDeliveries(ref, (schoolIds) {
    return repository.watchDeliveriesByDateRange(
      deliveryDate,
      tomorrow,
      schoolIds: schoolIds,
    );
  }).map((deliveries) => [...deliveries]..sort(compareDeliveryTimes));
});

typedef DeliveryDateRange = ({DateTime start, DateTime end});

final calendarDeliveriesProvider =
    StreamProvider.autoDispose.family<List<Delivery>, DeliveryDateRange>(
  (ref, range) {
    final repository = ref.watch(deliveriesRepositoryProvider);
    return _watchVisibleDeliveries(ref, (schoolIds) {
      return repository.watchDeliveriesByDateRange(
        range.start,
        range.end,
        schoolIds: schoolIds,
      );
    });
  },
);

final upcomingDeliveriesProvider = StreamProvider.autoDispose<List<Delivery>>(
  (ref) {
    final repository = ref.watch(deliveriesRepositoryProvider);
    return _watchVisibleDeliveries(ref, (schoolIds) {
      return repository.watchUpcomingDeliveries(schoolIds: schoolIds);
    });
  },
);

final pastDeliveriesProvider = StreamProvider.autoDispose<List<Delivery>>(
  (ref) {
    final repository = ref.watch(deliveriesRepositoryProvider);
    return _watchVisibleDeliveries(ref, (schoolIds) {
      return repository.watchPastDeliveries(schoolIds: schoolIds);
    });
  },
);

// Full history is fetched only for explicit legacy calendar sync.
final allDeliveriesListProvider = StreamProvider.autoDispose<List<Delivery>>(
  (ref) {
    final repository = ref.watch(deliveriesRepositoryProvider);
    return _watchVisibleDeliveries(ref, (schoolIds) {
      return repository.watchAllDeliveries(schoolIds: schoolIds);
    });
  },
);

Stream<List<Delivery>> _watchVisibleDeliveries(
  Ref ref,
  Stream<List<Delivery>> Function(List<String>? schoolIds) watch,
) {
  if (ref.watch(isAdminProvider)) return watch(null);

  final showAll = ref.watch(allDeliveriesProvider);
  return ref.watch(currentStaffProvider).when(
        loading: () => const Stream.empty(),
        error: Stream.error,
        data: (staff) {
          if (staff == null ||
              (!staff.hasManagerAccess && staff.assignedSchoolIds.isEmpty)) {
            return Stream.value(const <Delivery>[]);
          }
          return watch(showAll && staff.hasManagerAccess
              ? null
              : staff.assignedSchoolIds);
        },
      );
}

final staffListProvider = FutureProvider<List<Staff>>((ref) async {
  final deliveriesRepository = ref.watch(deliveriesRepositoryProvider);
  final result = await deliveriesRepository.getAllStaff();
  return result.when(
    success: (staff) => staff,
    failure: (message, exception) => throw exception ?? StateError(message),
  );
});

// Provider to get staff assigned to a specific school
final schoolStaffProvider = FutureProvider.autoDispose
    .family<List<Staff>, String>((ref, schoolId) async {
  final staffList = await ref.watch(staffListProvider.future);
  return staffList
      .where((staff) => staff.assignedSchoolIds.contains(schoolId))
      .toList();
});

final deliveryByIdProvider =
    FutureProvider.family<Delivery?, String>((ref, deliveryId) async {
  final deliveriesRepository = ref.watch(deliveriesRepositoryProvider);
  final result = await deliveriesRepository.getDeliveryById(deliveryId);
  return result.dataOrNull;
});

class DeliveriesNotifier extends StateNotifier<AsyncValue<void>> {
  DeliveriesNotifier(this._deliveriesRepository)
      : super(const AsyncValue.data(null));

  final DeliveriesRepository _deliveriesRepository;

  Future<bool> createDelivery(Delivery delivery) async {
    state = const AsyncValue.loading();
    final result = await _deliveriesRepository.createDelivery(delivery);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> updateDelivery(Delivery delivery) async {
    state = const AsyncValue.loading();
    final result = await _deliveriesRepository.updateDelivery(delivery);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteDelivery(String deliveryId) async {
    state = const AsyncValue.loading();
    final result = await _deliveriesRepository.deleteDelivery(deliveryId);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }
}

final deliveriesNotifierProvider =
    StateNotifierProvider<DeliveriesNotifier, AsyncValue<void>>((ref) {
  final deliveriesRepository = ref.watch(deliveriesRepositoryProvider);
  return DeliveriesNotifier(deliveriesRepository);
});
