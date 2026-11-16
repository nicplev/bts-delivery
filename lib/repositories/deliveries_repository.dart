import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/result.dart';
import '../services/date_utils.dart';
import '../models/delivery.dart';
import '../models/staff.dart';
import 'scoped_query_stream.dart';
import 'staff_repository.dart';

abstract class DeliveriesRepository {
  Stream<List<Delivery>> watchTodayDeliveries({
    String? staffId,
    List<String>? schoolIds,
  });
  Stream<List<Delivery>> watchUpcomingDeliveries({
    String? staffId,
    List<String>? schoolIds,
  });
  Stream<List<Delivery>> watchPastDeliveries({
    String? staffId,
    List<String>? schoolIds,
  });
  Stream<List<Delivery>> watchAllDeliveries({
    String? staffId,
    List<String>? schoolIds,
  });
  Stream<List<Delivery>> watchDeliveriesByDateRange(
    DateTime start,
    DateTime end, {
    List<String>? schoolIds,
  });
  Future<Result<List<Delivery>>> getDeliveriesByDateRange(
      DateTime start, DateTime end,
      {String? staffId});
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
  Stream<List<Delivery>> watchTodayDeliveries({
    String? staffId,
    List<String>? schoolIds,
  }) {
    final start = DateTimeUtils.todayStart;
    final end = DateTime(start.year, start.month, start.day + 1);
    return _watchDeliveries(
      start: start,
      end: end,
      staffId: staffId,
      schoolIds: schoolIds,
    ).map((deliveries) => [...deliveries]..sort(compareDeliveryTimes));
  }

  @override
  Stream<List<Delivery>> watchUpcomingDeliveries({
    String? staffId,
    List<String>? schoolIds,
  }) {
    return _watchDeliveries(
      start: DateTimeUtils.tomorrowStart,
      staffId: staffId,
      schoolIds: schoolIds,
    );
  }

  @override
  Stream<List<Delivery>> watchPastDeliveries({
    String? staffId,
    List<String>? schoolIds,
  }) {
    return _watchDeliveries(
      end: DateTimeUtils.todayStart,
      staffId: staffId,
      schoolIds: schoolIds,
    ).map((deliveries) => deliveries.reversed.toList());
  }

  @override
  Stream<List<Delivery>> watchAllDeliveries({
    String? staffId,
    List<String>? schoolIds,
  }) {
    return _watchDeliveries(staffId: staffId, schoolIds: schoolIds);
  }

  @override
  Stream<List<Delivery>> watchDeliveriesByDateRange(
    DateTime start,
    DateTime end, {
    List<String>? schoolIds,
  }) {
    return _watchDeliveries(start: start, end: end, schoolIds: schoolIds);
  }

  Stream<List<Delivery>> _watchDeliveries({
    DateTime? start,
    DateTime? end,
    String? staffId,
    List<String>? schoolIds,
  }) {
    var query = _firestore.collection('deliveries').orderBy('date');
    if (start != null) {
      query = query.where('date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start));
    }
    if (end != null) {
      query = query.where('date', isLessThan: Timestamp.fromDate(end));
    }
    if (staffId != null) {
      query = query.where('staffIds', arrayContains: staffId);
    }

    Stream<List<Delivery>> watch(Query<Map<String, dynamic>> scopedQuery) {
      return scopedQuery.snapshots().map((snapshot) {
        return [
          for (final doc in snapshot.docs)
            Delivery.fromJson({...doc.data(), 'id': doc.id}),
        ];
      });
    }

    if (schoolIds == null) return watch(query);
    return watchInChunks(
      schoolIds,
      (ids) => watch(query.where('schoolId', whereIn: ids)),
    ).map((deliveries) {
      return [...deliveries]..sort((a, b) => a.date.compareTo(b.date));
    });
  }

  @override
  Future<Result<List<Delivery>>> getDeliveriesByDateRange(
      DateTime start, DateTime end,
      {String? staffId}) async {
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
      final deliveries = snapshot.docs
          .map((doc) => Delivery.fromJson({
                'id': doc.id,
                ...doc.data() as Map<String, dynamic>,
              }))
          .toList();

      return Result.success(deliveries);
    } catch (e) {
      return Result.failure('Failed to get deliveries: $e');
    }
  }

  @override
  Future<Result<Delivery>> getDeliveryById(String deliveryId) async {
    try {
      final doc =
          await _firestore.collection('deliveries').doc(deliveryId).get();

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

  final _staffRepository = FirebaseStaffRepository();

  @override
  Future<Result<List<Staff>>> getAllStaff() => _staffRepository.getAllStaff();

  @override
  Future<Result<Staff>> createStaff(Staff staff) =>
      _staffRepository.createStaff(staff);

  @override
  Future<Result<Staff>> updateStaff(Staff staff) =>
      _staffRepository.updateStaff(staff);

  @override
  Future<Result<void>> deleteStaff(String staffId) =>
      _staffRepository.deleteStaff(staffId);
}

int compareDeliveryTimes(Delivery a, Delivery b) {
  if (a.time == null && b.time == null) {
    return a.schoolName.compareTo(b.schoolName);
  }
  if (a.time == null) return 1;
  if (b.time == null) return -1;
  return a.time!.compareTo(b.time!);
}
