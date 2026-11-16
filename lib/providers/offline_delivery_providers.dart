import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/offline/offline_delivery_service.dart';
import '../services/offline/connectivity_service.dart';
import '../models/offline/offline_models.dart';

/// Provider for offline delivery service
final offlineDeliveryServiceProvider = Provider<OfflineDeliveryService>((ref) {
  final connectivity = ref.watch(connectivityServiceProvider);
  return OfflineDeliveryService(connectivity);
});

/// Provider for pending delivery completions
final pendingDeliveryCompletionsProvider = StreamProvider<List<PendingDeliveryCompletion>>((ref) async* {
  final service = ref.watch(offlineDeliveryServiceProvider);

  // Initial load
  yield await service.getPendingCompletions();

  // Refresh every 5 seconds to catch updates
  while (true) {
    await Future.delayed(const Duration(seconds: 5));
    yield await service.getPendingCompletions();
  }
});

/// Provider for pending count
final pendingDeliveryCountProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(offlineDeliveryServiceProvider);
  return await service.getPendingCount();
});

/// Provider for storage size
final pendingStorageSizeProvider = FutureProvider<String>((ref) async {
  final service = ref.watch(offlineDeliveryServiceProvider);
  final bytes = await service.getPendingStorageSize();
  return service.formatStorageSize(bytes);
});

/// Provider to check if specific delivery has pending completion
final hasPendingCompletionProvider = FutureProvider.family<bool, String>((ref, deliveryId) async {
  final service = ref.watch(offlineDeliveryServiceProvider);
  return await service.hasPendingCompletion(deliveryId);
});
