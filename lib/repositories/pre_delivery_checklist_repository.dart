import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/result.dart';
import '../models/pre_delivery_checklist_item.dart';
import '../models/pre_delivery_completion.dart';

abstract class PreDeliveryChecklistRepository {
  Stream<List<PreDeliveryChecklistItem>> watchChecklistItems();
  Future<Result<PreDeliveryChecklistItem>> createChecklistItem(PreDeliveryChecklistItem item);
  Future<Result<PreDeliveryChecklistItem>> updateChecklistItem(PreDeliveryChecklistItem item);
  Future<Result<void>> deleteChecklistItem(String itemId);
  Future<Result<void>> reorderChecklistItems(List<PreDeliveryChecklistItem> items);
  Future<Result<void>> initializeDefaultItems();

  // Completion tracking per delivery
  Stream<List<PreDeliveryCompletion>> watchDeliveryCompletions(String deliveryId);
  Future<Result<void>> updateCompletion(String deliveryId, String itemId, bool isCompleted, String? userEmail);
  Future<bool> getCompletionStatus(String deliveryId);
}

class PreDeliveryChecklistRepositoryImpl implements PreDeliveryChecklistRepository {
  final FirebaseFirestore _firestore;

  PreDeliveryChecklistRepositoryImpl(this._firestore);

  @override
  Stream<List<PreDeliveryChecklistItem>> watchChecklistItems() {
    return _firestore
        .collection('pre_delivery_checklist_items')
        .orderBy('order')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return PreDeliveryChecklistItem.fromJson(data);
      }).toList();
    });
  }

  @override
  Future<Result<PreDeliveryChecklistItem>> createChecklistItem(PreDeliveryChecklistItem item) async {
    try {
      // Get the next order number
      final snapshot = await _firestore
          .collection('pre_delivery_checklist_items')
          .orderBy('order', descending: true)
          .limit(1)
          .get();

      int nextOrder = 1;
      if (snapshot.docs.isNotEmpty) {
        final lastItem = PreDeliveryChecklistItem.fromJson({
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
          .collection('pre_delivery_checklist_items')
          .add(itemWithOrder.toJson()..remove('id'));

      final createdItem = itemWithOrder.copyWith(id: docRef.id);
      return Result.success(createdItem);
    } catch (e) {
      return Result.failure('Failed to create checklist item: $e');
    }
  }

  @override
  Future<Result<PreDeliveryChecklistItem>> updateChecklistItem(PreDeliveryChecklistItem item) async {
    try {
      final updateData = item.toJson()
        ..['updatedAt'] = Timestamp.now()
        ..remove('id');

      await _firestore
          .collection('pre_delivery_checklist_items')
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
      await _firestore.collection('pre_delivery_checklist_items').doc(itemId).delete();

      // Reorder remaining items
      final snapshot = await _firestore
          .collection('pre_delivery_checklist_items')
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
  Future<Result<void>> reorderChecklistItems(List<PreDeliveryChecklistItem> items) async {
    try {
      final batch = _firestore.batch();

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        batch.update(
          _firestore.collection('pre_delivery_checklist_items').doc(item.id),
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
          .collection('pre_delivery_checklist_items')
          .limit(1)
          .get();

      // If items already exist, don't initialize
      if (snapshot.docs.isNotEmpty) {
        return const Result.success(null);
      }

      // Default pre-delivery checklist items for van loading
      final defaultItems = [
        PreDeliveryChecklistItem(
          id: '',
          title: 'Tissues loaded',
          subtitle: 'Check all tissue boxes for delivery',
          order: 1,
          isActive: true,
          createdAt: DateTime.now(),
          createdBy: 'system',
        ),
        PreDeliveryChecklistItem(
          id: '',
          title: 'Headphones packed',
          subtitle: 'Verify headphone quantities match order',
          order: 2,
          isActive: true,
          createdAt: DateTime.now(),
          createdBy: 'system',
        ),
        PreDeliveryChecklistItem(
          id: '',
          title: 'Office supplies included',
          subtitle: 'Extra supplies for school office',
          order: 3,
          isActive: true,
          createdAt: DateTime.now(),
          createdBy: 'system',
        ),
        PreDeliveryChecklistItem(
          id: '',
          title: 'Delivery paperwork ready',
          subtitle: 'Printed delivery manifests',
          order: 4,
          isActive: true,
          createdAt: DateTime.now(),
          createdBy: 'system',
        ),
        PreDeliveryChecklistItem(
          id: '',
          title: 'Van inspection complete',
          subtitle: 'Fuel, tires, cleanliness checked',
          order: 5,
          isActive: true,
          createdAt: DateTime.now(),
          createdBy: 'system',
        ),
      ];

      // Add all items in a batch
      final batch = _firestore.batch();
      for (final item in defaultItems) {
        final docRef = _firestore.collection('pre_delivery_checklist_items').doc();
        batch.set(docRef, item.toJson()..remove('id'));
      }
      await batch.commit();

      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to initialize default checklist items: $e');
    }
  }

  @override
  Stream<List<PreDeliveryCompletion>> watchDeliveryCompletions(String deliveryId) {
    return _firestore
        .collection('deliveries')
        .doc(deliveryId)
        .collection('preDeliveryChecklist')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['itemId'] = doc.id;
        return PreDeliveryCompletion.fromJson(data);
      }).toList();
    });
  }

  @override
  Future<Result<void>> updateCompletion(
    String deliveryId,
    String itemId,
    bool isCompleted,
    String? userEmail,
  ) async {
    try {
      final docRef = _firestore
          .collection('deliveries')
          .doc(deliveryId)
          .collection('preDeliveryChecklist')
          .doc(itemId);

      if (isCompleted) {
        await docRef.set({
          'isCompleted': true,
          'completedBy': userEmail,
          'completedAt': Timestamp.now(),
        });
      } else {
        await docRef.set({
          'isCompleted': false,
          'completedBy': null,
          'completedAt': null,
        });
      }

      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to update completion: $e');
    }
  }

  @override
  Future<bool> getCompletionStatus(String deliveryId) async {
    try {
      // Get all active checklist items
      final itemsSnapshot = await _firestore
          .collection('pre_delivery_checklist_items')
          .where('isActive', isEqualTo: true)
          .get();

      if (itemsSnapshot.docs.isEmpty) {
        return true; // No items to complete
      }

      // Get completions for this delivery
      final completionsSnapshot = await _firestore
          .collection('deliveries')
          .doc(deliveryId)
          .collection('preDeliveryChecklist')
          .where('isCompleted', isEqualTo: true)
          .get();

      final completedItemIds = completionsSnapshot.docs.map((doc) => doc.id).toSet();
      final activeItemIds = itemsSnapshot.docs.map((doc) => doc.id).toSet();

      // Check if all active items are completed
      return activeItemIds.every((itemId) => completedItemIds.contains(itemId));
    } catch (e) {
      return false;
    }
  }
}
