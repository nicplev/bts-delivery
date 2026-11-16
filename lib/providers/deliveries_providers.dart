import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/delivery.dart';
import '../../models/staff.dart';
import '../../repositories/deliveries_repository.dart';
import 'repository_providers.dart';
import 'auth_providers.dart';

final allDeliveriesProvider = StateProvider<bool>((ref) => false);

final todayDeliveriesProvider = StreamProvider.autoDispose<List<Delivery>>((ref) {
  final deliveriesRepository = ref.watch(deliveriesRepositoryProvider);
  final showAll = ref.watch(allDeliveriesProvider);
  final currentStaffAsync = ref.watch(currentStaffProvider);
  final isAdmin = ref.watch(isAdminProvider);

  return currentStaffAsync.when(
    loading: () => const Stream.empty(),
    error: (error, _) => Stream.error(error),
    data: (currentStaff) {
      // Admins can see all deliveries
      if (isAdmin) {
        return deliveriesRepository.watchTodayDeliveries();
      }

      if (currentStaff == null) {
        // User is not linked to a staff member, return empty stream
        return Stream.value(<Delivery>[]);
      }

      if (showAll && currentStaff.hasManagerAccess == true) {
        return deliveriesRepository.watchTodayDeliveries();
      } else {
        // Staff see deliveries for schools they're assigned to
        return deliveriesRepository.watchTodayDeliveries().map((deliveries) {
          return deliveries.where((delivery) {
            return currentStaff.assignedSchoolIds.contains(delivery.schoolId);
          }).toList();
        });
      }
    },
  );
});

final upcomingDeliveriesProvider = StreamProvider.autoDispose<List<Delivery>>((ref) {
  final deliveriesRepository = ref.watch(deliveriesRepositoryProvider);
  final showAll = ref.watch(allDeliveriesProvider);
  final currentStaffAsync = ref.watch(currentStaffProvider);
  final isAdmin = ref.watch(isAdminProvider);

  return currentStaffAsync.when(
    loading: () => const Stream.empty(),
    error: (error, _) => Stream.error(error),
    data: (currentStaff) {
      // Admins can see all deliveries
      if (isAdmin) {
        return deliveriesRepository.watchUpcomingDeliveries();
      }

      if (currentStaff == null) {
        // User is not linked to a staff member, return empty stream
        return Stream.value(<Delivery>[]);
      }

      if (showAll && currentStaff.hasManagerAccess == true) {
        return deliveriesRepository.watchUpcomingDeliveries();
      } else {
        // Staff see deliveries for schools they're assigned to
        return deliveriesRepository.watchUpcomingDeliveries().map((deliveries) {
          return deliveries.where((delivery) {
            return currentStaff.assignedSchoolIds.contains(delivery.schoolId);
          }).toList();
        });
      }
    },
  );
});

final pastDeliveriesProvider = StreamProvider.autoDispose<List<Delivery>>((ref) {
  final deliveriesRepository = ref.watch(deliveriesRepositoryProvider);
  final showAll = ref.watch(allDeliveriesProvider);
  final currentStaffAsync = ref.watch(currentStaffProvider);
  final isAdmin = ref.watch(isAdminProvider);

  return currentStaffAsync.when(
    loading: () => const Stream.empty(),
    error: (error, _) => Stream.error(error),
    data: (currentStaff) {
      // Admins can see all deliveries
      if (isAdmin) {
        return deliveriesRepository.watchPastDeliveries();
      }

      if (currentStaff == null) {
        // User is not linked to a staff member, return empty stream
        return Stream.value(<Delivery>[]);
      }

      if (showAll && currentStaff.hasManagerAccess == true) {
        return deliveriesRepository.watchPastDeliveries();
      } else {
        // Staff see deliveries for schools they're assigned to
        return deliveriesRepository.watchPastDeliveries().map((deliveries) {
          return deliveries.where((delivery) {
            return currentStaff.assignedSchoolIds.contains(delivery.schoolId);
          }).toList();
        });
      }
    },
  );
});

// Provider for all deliveries across all time periods (for calendar view)
final allDeliveriesListProvider = StreamProvider.autoDispose<List<Delivery>>((ref) {
  final deliveriesRepository = ref.watch(deliveriesRepositoryProvider);
  final showAll = ref.watch(allDeliveriesProvider);
  final currentStaffAsync = ref.watch(currentStaffProvider);
  final isAdmin = ref.watch(isAdminProvider);

  return currentStaffAsync.when(
    loading: () => const Stream.empty(),
    error: (error, _) => Stream.error(error),
    data: (currentStaff) {
      // Admins can see all deliveries
      if (isAdmin) {
        return deliveriesRepository.watchAllDeliveries();
      }

      if (currentStaff == null) {
        // User is not linked to a staff member, return empty stream
        return Stream.value(<Delivery>[]);
      }

      if (showAll && currentStaff.hasManagerAccess == true) {
        return deliveriesRepository.watchAllDeliveries();
      } else {
        // Staff see deliveries for schools they're assigned to
        return deliveriesRepository.watchAllDeliveries().map((deliveries) {
          return deliveries.where((delivery) {
            // Show deliveries for schools the staff has access to
            return currentStaff.assignedSchoolIds.contains(delivery.schoolId);
          }).toList();
        });
      }
    },
  );
});

final staffListProvider = FutureProvider<List<Staff>>((ref) async {
  final deliveriesRepository = ref.watch(deliveriesRepositoryProvider);
  final result = await deliveriesRepository.getAllStaff();
  return result.dataOrNull ?? [];
});

// Provider to get staff assigned to a specific school
final schoolStaffProvider = FutureProvider.family<List<Staff>, String>((ref, schoolId) async {
  final staffList = await ref.watch(staffListProvider.future);
  return staffList.where((staff) => staff.assignedSchoolIds.contains(schoolId)).toList();
});

final deliveryByIdProvider = FutureProvider.family<Delivery?, String>((ref, deliveryId) async {
  final deliveriesRepository = ref.watch(deliveriesRepositoryProvider);
  final result = await deliveriesRepository.getDeliveryById(deliveryId);
  return result.dataOrNull;
});

class DeliveriesNotifier extends StateNotifier<AsyncValue<void>> {
  DeliveriesNotifier(this._deliveriesRepository) : super(const AsyncValue.data(null));

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

final deliveriesNotifierProvider = StateNotifierProvider<DeliveriesNotifier, AsyncValue<void>>((ref) {
  final deliveriesRepository = ref.watch(deliveriesRepositoryProvider);
  return DeliveriesNotifier(deliveriesRepository);
});