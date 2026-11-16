import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../services/result.dart';
import '../models/staff.dart';

/// Repository for managing staff members and their calendar subscriptions
abstract class StaffRepository {
  Future<Result<Staff>> getStaffById(String staffId);
  Future<Result<List<Staff>>> getAllStaff();
  Future<Result<Staff>> updateStaff(Staff staff);
  Future<Result<String>> generateCalendarToken(String staffId);
  Future<Result<String>> regenerateCalendarToken(String staffId);
  Future<Result<Staff?>> getStaffByCalendarToken(String token);
  Future<Result<String>> getCalendarSubscriptionUrl(String staffId);
  Future<Result<String>> getCalendarHttpsUrl(String staffId);
}

class FirebaseStaffRepository implements StaffRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  @override
  Future<Result<Staff>> getStaffById(String staffId) async {
    try {
      final doc = await _firestore.collection('staff').doc(staffId).get();

      if (!doc.exists) {
        return const Result.failure('Staff member not found');
      }

      final staff = Staff.fromJson({
        'id': doc.id,
        ...doc.data()!,
      });

      return Result.success(staff);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting staff by ID: $e');
      }
      return Result.failure('Failed to get staff: $e');
    }
  }

  @override
  Future<Result<List<Staff>>> getAllStaff() async {
    try {
      final snapshot = await _firestore
          .collection('staff')
          .orderBy('name')
          .get();

      final staffList = snapshot.docs.map((doc) {
        return Staff.fromJson({
          'id': doc.id,
          ...doc.data(),
        });
      }).toList();

      return Result.success(staffList);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting all staff: $e');
      }
      return Result.failure('Failed to get staff list: $e');
    }
  }

  @override
  Future<Result<Staff>> updateStaff(Staff staff) async {
    try {
      final data = staff.toJson();
      data.remove('id'); // Don't store ID in the document

      await _firestore.collection('staff').doc(staff.id).update(data);

      // Sync role to users collection if staff is linked to a user account
      if (staff.uid != null) {
        try {
          await _firestore.collection('users').doc(staff.uid).update({
            'role': staff.role,
          });
          if (kDebugMode) {
            debugPrint('Synced role to users collection for staff ${staff.id}');
          }
        } catch (e) {
          // Log but don't fail the update if user sync fails
          if (kDebugMode) {
            debugPrint('Warning: Failed to sync role to users collection: $e');
          }
        }
      }

      return Result.success(staff);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error updating staff: $e');
      }
      return Result.failure('Failed to update staff: $e');
    }
  }

  @override
  Future<Result<String>> generateCalendarToken(String staffId) async {
    try {
      final staffDoc = await _firestore.collection('staff').doc(staffId).get();

      if (!staffDoc.exists) {
        return const Result.failure('Staff member not found');
      }

      final staff = Staff.fromJson({
        'id': staffDoc.id,
        ...staffDoc.data()!,
      });

      // If staff already has a token, return it
      if (staff.hasCalendarToken) {
        return Result.success(staff.calendarToken!);
      }

      // Generate new token
      final token = _uuid.v4();

      await _firestore.collection('staff').doc(staffId).update({
        'calendarToken': token,
      });

      if (kDebugMode) {
        debugPrint('Generated calendar token for staff $staffId');
      }

      return Result.success(token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error generating calendar token: $e');
      }
      return Result.failure('Failed to generate calendar token: $e');
    }
  }

  @override
  Future<Result<String>> regenerateCalendarToken(String staffId) async {
    try {
      final staffDoc = await _firestore.collection('staff').doc(staffId).get();

      if (!staffDoc.exists) {
        return const Result.failure('Staff member not found');
      }

      // Generate new token (this will revoke the old one)
      final token = _uuid.v4();

      await _firestore.collection('staff').doc(staffId).update({
        'calendarToken': token,
      });

      // Also delete the old calendar metadata
      await _firestore.collection('calendar_metadata').doc(staffId).delete();

      if (kDebugMode) {
        debugPrint('Regenerated calendar token for staff $staffId');
      }

      return Result.success(token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error regenerating calendar token: $e');
      }
      return Result.failure('Failed to regenerate calendar token: $e');
    }
  }

  @override
  Future<Result<Staff?>> getStaffByCalendarToken(String token) async {
    try {
      final query = await _firestore
          .collection('staff')
          .where('calendarToken', isEqualTo: token)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return const Result.success(null);
      }

      final doc = query.docs.first;
      final staff = Staff.fromJson({
        'id': doc.id,
        ...doc.data(),
      });

      return Result.success(staff);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting staff by calendar token: $e');
      }
      return Result.failure('Failed to get staff by token: $e');
    }
  }

  /// Generate calendar tokens for all staff members who don't have one
  /// This is useful for migrating existing staff to the new calendar system
  Future<Result<int>> generateTokensForAllStaff() async {
    try {
      // Get all staff without calendar tokens
      final snapshot = await _firestore.collection('staff').get();

      int count = 0;
      final batch = _firestore.batch();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (!data.containsKey('calendarToken') || data['calendarToken'] == null) {
          final token = _uuid.v4();
          batch.update(doc.reference, {'calendarToken': token});
          count++;
        }
      }

      await batch.commit();

      if (kDebugMode) {
        debugPrint('Generated calendar tokens for $count staff members');
      }

      return Result.success(count);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error generating tokens for all staff: $e');
      }
      return Result.failure('Failed to generate tokens: $e');
    }
  }

  /// Get calendar subscription URL for a staff member
  /// Returns webcal:// URL that can be subscribed to
  @override
  Future<Result<String>> getCalendarSubscriptionUrl(String staffId) async {
    try {
      final staffDoc = await _firestore.collection('staff').doc(staffId).get();

      if (!staffDoc.exists) {
        return const Result.failure('Staff member not found');
      }

      final staff = Staff.fromJson({
        'id': staffDoc.id,
        ...staffDoc.data()!,
      });

      if (!staff.hasCalendarToken) {
        // Generate token if doesn't exist
        final tokenResult = await generateCalendarToken(staffId);
        if (tokenResult.isFailure) {
          return Result.failure(tokenResult.errorOrNull ?? 'Failed to generate token');
        }

        final token = tokenResult.dataOrNull!;
        const baseUrl = 'https://us-central1-bts-delivery-app.cloudfunctions.net/calendar';
        return Result.success('webcals://${baseUrl.replaceFirst('https://', '')}/$token.ics');
      }

      const baseUrl = 'https://us-central1-bts-delivery-app.cloudfunctions.net/calendar';
      final webcalUrl = 'webcals://${baseUrl.replaceFirst('https://', '')}/${staff.calendarToken}.ics';

      return Result.success(webcalUrl);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting calendar subscription URL: $e');
      }
      return Result.failure('Failed to get subscription URL: $e');
    }
  }

  /// Get HTTPS version of calendar subscription URL
  @override
  Future<Result<String>> getCalendarHttpsUrl(String staffId) async {
    final webcalResult = await getCalendarSubscriptionUrl(staffId);

    if (webcalResult.isFailure) {
      return webcalResult;
    }

    final httpsUrl = webcalResult.dataOrNull!.replaceFirst('webcals://', 'https://');
    return Result.success(httpsUrl);
  }
}
