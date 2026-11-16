import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/checklist_item.dart';
import '../repositories/checklist_repository.dart';

// Provider for checklist repository
final checklistRepositoryProvider = Provider<ChecklistRepository>((ref) {
  return ChecklistRepositoryImpl(FirebaseFirestore.instance);
});

// Stream provider for watching checklist items
final checklistItemsProvider = StreamProvider<List<ChecklistItem>>((ref) {
  final repository = ref.watch(checklistRepositoryProvider);
  return repository.watchChecklistItems();
});

// Stream provider for active checklist items only
final activeChecklistItemsProvider = StreamProvider<List<ChecklistItem>>((ref) {
  final repository = ref.watch(checklistRepositoryProvider);
  return repository.watchChecklistItems().map((items) =>
      items.where((item) => item.isActive).toList());
});

// StateNotifier for managing checklist operations
class ChecklistNotifier extends StateNotifier<AsyncValue<void>> {
  ChecklistNotifier(this._repository) : super(const AsyncValue.data(null));

  final ChecklistRepository _repository;

  Future<bool> createChecklistItem(ChecklistItem item) async {
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

  Future<bool> updateChecklistItem(ChecklistItem item) async {
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

  Future<bool> reorderChecklistItems(List<ChecklistItem> items) async {
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
}

// Provider for checklist notifier
final checklistNotifierProvider =
    StateNotifierProvider<ChecklistNotifier, AsyncValue<void>>((ref) {
  final repository = ref.watch(checklistRepositoryProvider);
  return ChecklistNotifier(repository);
});

// Provider to initialize default checklist items on first run
final initializeChecklistProvider = FutureProvider<void>((ref) async {
  final repository = ref.watch(checklistRepositoryProvider);
  await repository.initializeDefaultItems();
});