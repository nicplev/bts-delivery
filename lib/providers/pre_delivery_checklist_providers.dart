import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/offline/saved_edit.dart';
import '../repositories/classroom_edit.dart';
import '../services/result.dart';
import 'repository_providers.dart';
import 'saved_edit_providers.dart';
import '../models/pre_delivery_checklist_item.dart';
import '../models/pre_delivery_completion.dart';
import '../repositories/pre_delivery_checklist_repository.dart';

// Provider for pre-delivery checklist repository
final preDeliveryChecklistRepositoryProvider = Provider<PreDeliveryChecklistRepository>((ref) {
  return PreDeliveryChecklistRepositoryImpl(FirebaseFirestore.instance);
});

// Stream provider for watching checklist items
final preDeliveryChecklistItemsProvider = StreamProvider<List<PreDeliveryChecklistItem>>((ref) {
  final repository = ref.watch(preDeliveryChecklistRepositoryProvider);
  return repository.watchChecklistItems();
});

// Stream provider for active checklist items only
final activePreDeliveryChecklistItemsProvider = StreamProvider<List<PreDeliveryChecklistItem>>((ref) {
  final repository = ref.watch(preDeliveryChecklistRepositoryProvider);
  return repository.watchChecklistItems().map((items) =>
      items.where((item) => item.isActive).toList());
});

// StateNotifier for managing checklist operations
class PreDeliveryChecklistNotifier extends StateNotifier<AsyncValue<void>> {
  PreDeliveryChecklistNotifier(this._repository, this._ref) : super(const AsyncValue.data(null));

  final PreDeliveryChecklistRepository _repository;
  final Ref _ref;

  Future<bool> createChecklistItem(PreDeliveryChecklistItem item) async {
    state = const AsyncValue.loading();
    final result = await _repository.createChecklistItem(item);

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

  Future<bool> updateChecklistItem(PreDeliveryChecklistItem item) async {
    state = const AsyncValue.loading();
    final result = await _repository.updateChecklistItem(item);

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

  Future<bool> deleteChecklistItem(String itemId) async {
    state = const AsyncValue.loading();
    final result = await _repository.deleteChecklistItem(itemId);

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

  Future<bool> reorderChecklistItems(List<PreDeliveryChecklistItem> items) async {
    state = const AsyncValue.loading();
    final result = await _repository.reorderChecklistItems(items);

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

  Future<Result<ClassroomEditStatus>> saveCompletion({
    required String schoolId,
    required String deliveryId,
    required String itemId,
    required bool isCompleted,
    required String itemLabel,
    String? editId,
  }) async {
    final user = _ref.read(authRepositoryProvider).currentUser;
    if (user == null || user.email == null) {
      return const Result.failure('Sign in to save this checklist item.');
    }
    try {
      final edit = EditIntent(
        id: editId ?? const Uuid().v4(),
        rememberId: editId != null,
        ownerUid: user.uid,
        schoolId: schoolId,
        deliveryId: deliveryId,
        itemId: itemId,
        itemLabel: itemLabel,
        capturedAt: DateTime.now().toUtc(),
        updatedBy: '',
        kind: SavedEditKind.checklist,
        values: {
          'isCompleted': isCompleted,
          'completedBy': isCompleted ? user.email : null,
        },
      );
      final result = await _ref.read(savedEditRecoveryProvider).save(edit);
      return result.when(
        success: (receipt) => Result.success(receipt.status),
        failure: Result<ClassroomEditStatus>.failure,
      );
    } catch (_) {
      return const Result.failure('Could not save this checklist item.');
    }
  }

  Future<bool> updateCompletion(String deliveryId, String itemId, bool isCompleted, String? userEmail) async {
    final result = await _repository.updateCompletion(deliveryId, itemId, isCompleted, userEmail);

    return result.when(
      success: (_) => true,
      failure: (message, exception) => false,
    );
  }
}

// Provider for checklist notifier
final preDeliveryChecklistNotifierProvider =
    StateNotifierProvider<PreDeliveryChecklistNotifier, AsyncValue<void>>((ref) {
  final repository = ref.watch(preDeliveryChecklistRepositoryProvider);
  return PreDeliveryChecklistNotifier(repository, ref);
});

// Provider to initialize default checklist items on first run
final initializePreDeliveryChecklistProvider = FutureProvider<void>((ref) async {
  final repository = ref.watch(preDeliveryChecklistRepositoryProvider);
  await repository.initializeDefaultItems();
});

// Stream provider for watching delivery completions (per delivery)
final deliveryCompletionsProvider = StreamProvider.family<List<PreDeliveryCompletion>, String>((ref, deliveryId) {
  final repository = ref.watch(preDeliveryChecklistRepositoryProvider);
  return repository.watchDeliveryCompletions(deliveryId);
});

// Provider to check if all checklist items are completed for a delivery
final deliveryChecklistCompleteProvider = FutureProvider.family<bool, String>((ref, deliveryId) async {
  final repository = ref.watch(preDeliveryChecklistRepositoryProvider);
  return repository.getCompletionStatus(deliveryId);
});

// Combined provider that watches both active items and completions to determine completion status
final deliveryChecklistStatusProvider = Provider.family<AsyncValue<bool>, String>((ref, deliveryId) {
  final activeItemsAsync = ref.watch(activePreDeliveryChecklistItemsProvider);
  final completionsAsync = ref.watch(deliveryCompletionsProvider(deliveryId));

  return activeItemsAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (activeItems) {
      return completionsAsync.when(
        loading: () => const AsyncValue.loading(),
        error: (e, st) => AsyncValue.error(e, st),
        data: (completions) {
          if (activeItems.isEmpty) {
            return const AsyncValue.data(true); // No items = complete
          }

          final completedItemIds = completions
              .where((c) => c.isCompleted)
              .map((c) => c.itemId)
              .toSet();

          final allComplete = activeItems.every((item) => completedItemIds.contains(item.id));
          return AsyncValue.data(allComplete);
        },
      );
    },
  );
});
