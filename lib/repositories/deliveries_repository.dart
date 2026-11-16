import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/result.dart';
import '../services/date_utils.dart';
import '../models/delivery.dart';
import '../models/staff.dart';

abstract class DeliveriesRepository {
  Stream<List<Delivery>> watchTodayDeliveries({String? staffId});
  Stream<List<Delivery>> watchUpcomingDeliveries({String? staffId});
  Stream<List<Delivery>> watchPastDeliveries({String? staffId});
  Stream<List<Delivery>> watchAllDeliveries({String? staffId});
  Future<Result<List<Delivery>>> getDeliveriesByDateRange(DateTime start, DateTime end, {String? staffId});
  Future<Result<Delivery>> getDeliveryById(String deliveryId);
  Future<Result<Delivery>> createDelivery(Delivery delivery);
  Future<Result<Delivery>> updateDelivery(Delivery delivery);
  Future<Result<void>> deleteDelivery(String deliveryId);
  Future<Result<List<Staff>>> getAllStaff();
  Future<Result<Staff>> createStaff(Staff staff);
  Future<Result<Staff>> updateStaff(Staff staff);
  Future<Result<void>> deleteStaff(String staffId);
}

class FirebaseDeliveriesRepository implements DeliveriesRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  @override
  Stream<List<Delivery>> watchTodayDeliveries({String? staffId}) {
    final start = DateTimeUtils.todayStart;
    final end = DateTimeUtils.tomorrowStart;
    
    Query query = _firestore
        .collection('deliveries')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end));
    
    if (staffId != null) {
      query = query.where('staffIds', arrayContains: staffId);
    }
    
    return query.snapshots().map((snapshot) {
      final deliveries = snapshot.docs.map((doc) => Delivery.fromJson({
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      })).toList();
      
      // Sort by time, with null times at the end
      deliveries.sort((a, b) {
        if (a.time == null && b.time == null) return 0;
        if (a.time == null) return 1;
        if (b.time == null) return -1;
        return a.time!.compareTo(b.time!);
      });
      
      return deliveries;
    });
  }
  
  @override
  Stream<List<Delivery>> watchUpcomingDeliveries({String? staffId}) {
    final tomorrow = DateTimeUtils.tomorrowStart;
    
    Query query = _firestore
        .collection('deliveries')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(tomorrow))
        .orderBy('date');
    
    if (staffId != null) {
      query = query.where('staffIds', arrayContains: staffId);
    }
    
    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Delivery.fromJson({
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      })).toList();
    });
  }
  
  @override
  Stream<List<Delivery>> watchPastDeliveries({String? staffId}) {
    final today = DateTimeUtils.todayStart;

    Query query = _firestore
        .collection('deliveries')
        .where('date', isLessThan: Timestamp.fromDate(today))
        .orderBy('date', descending: true);

    if (staffId != null) {
      query = query.where('staffIds', arrayContains: staffId);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Delivery.fromJson({
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      })).toList();
    });
  }

  @override
  Stream<List<Delivery>> watchAllDeliveries({String? staffId}) {
    Query query = _firestore
        .collection('deliveries')
        .orderBy('date', descending: false);

    if (staffId != null) {
      query = query.where('staffIds', arrayContains: staffId);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Delivery.fromJson({
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      })).toList();
    });
  }
  
  @override
  Future<Result<List<Delivery>>> getDeliveriesByDateRange(DateTime start, DateTime end, {String? staffId}) async {
    try {
      Query query = _firestore
          .collection('deliveries')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThan: Timestamp.fromDate(end))
          .orderBy('date');

      if (staffId != null) {
        query = query.where('staffIds', arrayContains: staffId);
      }

      final snapshot = await query.get();
      final deliveries = snapshot.docs.map((doc) => Delivery.fromJson({
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      })).toList();

      return Result.success(deliveries);
    } catch (e) {
      return Result.failure('Failed to get deliveries: $e');
    }
  }

  @override
  Future<Result<Delivery>> getDeliveryById(String deliveryId) async {
    try {
      final doc = await _firestore.collection('deliveries').doc(deliveryId).get();

      if (!doc.exists) {
        return const Result.failure('Delivery not found');
      }

      final delivery = Delivery.fromJson({
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      });

      return Result.success(delivery);
    } catch (e) {
      return Result.failure('Failed to get delivery: $e');
    }
  }

  @override
  Future<Result<Delivery>> createDelivery(Delivery delivery) async {
    try {
      // Don't include the id field when creating a new document
      final json = delivery.toJson();
      json.remove('id');

      final docRef = await _firestore.collection('deliveries').add(json);
      final createdDelivery = delivery.copyWith(id: docRef.id);
      return Result.success(createdDelivery);
    } catch (e) {
      return Result.failure('Failed to create delivery: $e');
    }
  }
  
  @override
  Future<Result<Delivery>> updateDelivery(Delivery delivery) async {
    try {
      if (delivery.id.isEmpty) {
        return const Result.failure('Cannot update delivery: ID is empty');
      }

      // Don't include the id field in the update data
      final json = delivery.toJson();
      json.remove('id');

      await _firestore.collection('deliveries').doc(delivery.id).update(json);
      return Result.success(delivery);
    } catch (e) {
      return Result.failure('Failed to update delivery: $e');
    }
  }
  
  @override
  Future<Result<void>> deleteDelivery(String deliveryId) async {
    try {
      await _firestore.collection('deliveries').doc(deliveryId).delete();
      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete delivery: $e');
    }
  }
  
  @override
  Future<Result<List<Staff>>> getAllStaff() async {
    try {
      final snapshot = await _firestore.collection('staff').orderBy('name').get();
      final staff = snapshot.docs
          .where((doc) => doc.id.isNotEmpty) // Filter out any invalid docs
          .map((doc) {
            final data = doc.data();
            // Remove 'id' from data if it exists to avoid conflict
            data.remove('id');
            return Staff.fromJson({
              'id': doc.id, // Use Firestore document ID
              ...data,
            });
          }).toList();

      return Result.success(staff);
    } catch (e) {
      return Result.failure('Failed to get staff: $e');
    }
  }
  
  @override
  Future<Result<Staff>> createStaff(Staff staff) async {
    try {
      // Don't store the ID in the document - Firestore provides it
      final staffData = staff.toJson();
      staffData.remove('id'); // Remove empty ID from being stored

      final docRef = await _firestore.collection('staff').add(staffData);
      final createdStaff = staff.copyWith(id: docRef.id);
      return Result.success(createdStaff);
    } catch (e) {
      return Result.failure('Failed to create staff: $e');
    }
  }
  
  @override
  Future<Result<Staff>> updateStaff(Staff staff) async {
    try {
      if (staff.id.isEmpty) {
        return const Result.failure('Cannot update staff: ID is empty');
      }

      // Don't store the ID in the document - it's the document ID
      final staffData = staff.toJson();
      staffData.remove('id');

      await _firestore.collection('staff').doc(staff.id).update(staffData);

      // If staff is linked to a user account, sync the role to the user document
      if (staff.uid != null && staff.uid!.isNotEmpty) {
        await _firestore.collection('users').doc(staff.uid).update({
          'role': staff.role,
        });
      }

      return Result.success(staff);
    } catch (e) {
      return Result.failure('Failed to update staff: $e');
    }
  }

  @override
  Future<Result<void>> deleteStaff(String staffId) async {
    try {
      if (staffId.isEmpty) {
        return const Result.failure('Cannot delete staff: ID is empty');
      }
      await _firestore.collection('staff').doc(staffId).delete();
      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete staff: $e');
    }
  }
}