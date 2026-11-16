import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/result.dart';
import '../models/checklist_item.dart';

abstract class ChecklistRepository {
  Stream<List<ChecklistItem>> watchChecklistItems();
  Future<Result<ChecklistItem>> createChecklistItem(ChecklistItem item);
  Future<Result<ChecklistItem>> updateChecklistItem(ChecklistItem item);
  Future<Result<void>> deleteChecklistItem(String itemId);
  Future<Result<void>> reorderChecklistItems(List<ChecklistItem> items);
  Future<Result<void>> initializeDefaultItems();
}

class ChecklistRepositoryImpl implements ChecklistRepository {
  final FirebaseFirestore _firestore;

  ChecklistRepositoryImpl(this._firestore);

  @override
  Stream<List<ChecklistItem>> watchChecklistItems() {
    return _firestore
        .collection('checklist_items')
        .orderBy('order')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return ChecklistItem.fromJson(data);
      }).toList();
    });
  }

  @override
  Future<Result<ChecklistItem>> createChecklistItem(ChecklistItem item) async {
    try {
      // Get the next order number
      final snapshot = await _firestore
          .collection('checklist_items')
          .orderBy('order', descending: true)
          .limit(1)
          .get();

      int nextOrder = 1;
      if (snapshot.docs.isNotEmpty) {
        final lastItem = ChecklistItem.fromJson({
          ...snapshot.docs.first.data(),
          'id': snapshot.docs.first.id,
        });
        nextOrder = lastItem.order + 1;
      }

      final itemWithOrder = item.copyWith(
        id: '', // Will be set by Firestore
        order: nextOrder,
        createdAt: DateTime.now(),
      );

      final docRef = await _firestore
          .collection('checklist_items')
          .add(itemWithOrder.toJson()..remove('id'));

      final createdItem = itemWithOrder.copyWith(id: docRef.id);
      return Result.success(createdItem);
    } catch (e) {
      return Result.failure('Failed to create checklist item: $e');
    }
  }

  @override
  Future<Result<ChecklistItem>> updateChecklistItem(ChecklistItem item) async {
    try {
      final updateData = item.toJson()
        ..['updatedAt'] = Timestamp.now()
        ..remove('id');

      await _firestore
          .collection('checklist_items')
          .doc(item.id)
          .update(updateData);

      return Result.success(item.copyWith(updatedAt: DateTime.now()));
    } catch (e) {
      return Result.failure('Failed to update checklist item: $e');
    }
  }

  @override
  Future<Result<void>> deleteChecklistItem(String itemId) async {
    try {
      await _firestore.collection('checklist_items').doc(itemId).delete();

      // Reorder remaining items
      final snapshot = await _firestore
          .collection('checklist_items')
          .orderBy('order')
          .get();

      final batch = _firestore.batch();
      int order = 1;
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'order': order});
        order++;
      }
      await batch.commit();

      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete checklist item: $e');
    }
  }

  @override
  Future<Result<void>> reorderChecklistItems(List<ChecklistItem> items) async {
    try {
      final batch = _firestore.batch();

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        batch.update(
          _firestore.collection('checklist_items').doc(item.id),
          {'order': i + 1, 'updatedAt': Timestamp.now()},
        );
      }

      await batch.commit();
      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to reorder checklist items: $e');
    }
  }

  @override
  Future<Result<void>> initializeDefaultItems() async {
    try {
      // Check if there are any existing items
      final snapshot = await _firestore
          .collection('checklist_items')
          .limit(1)
          .get();

      // If items already exist, don't initialize
      if (snapshot.docs.isNotEmpty) {
        return const Result.success(null);
      }

      // Default checklist items
      final defaultItems = [
        ChecklistItem(
          id: '',
          title: 'Extra supplies delivered to office',
          subtitle: '(i.e. L/H Scissors)',
          order: 1,
          isActive: true,
          createdAt: DateTime.now(),
          createdBy: 'system',
        ),
        ChecklistItem(
          id: '',
          title: 'Envelopes delivered',
          subtitle: null,
          order: 2,
          isActive: true,
          createdAt: DateTime.now(),
          createdBy: 'system',
        ),
        ChecklistItem(
          id: '',
          title: 'Classrooms locked',
          subtitle: null,
          order: 3,
          isActive: true,
          createdAt: DateTime.now(),
          createdBy: 'system',
        ),
      ];

      // Add all items in a batch
      final batch = _firestore.batch();
      for (final item in defaultItems) {
        final docRef = _firestore.collection('checklist_items').doc();
        batch.set(docRef, item.toJson()..remove('id'));
      }
      await batch.commit();

      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to initialize default checklist items: $e');
    }
  }
}