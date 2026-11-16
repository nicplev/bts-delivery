import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bts_delivery_app/models/staff.dart';

void main() {
  group('Staff Model Tests', () {
    test('should create staff with correct properties', () {
      final now = DateTime.now();
      final staff = Staff(
        id: '1',
        name: 'John Doe',
        uid: 'auth-uid',
        role: 'manager',
        createdAt: now,
      );

      expect(staff.id, '1');
      expect(staff.name, 'John Doe');
      expect(staff.uid, 'auth-uid');
      expect(staff.role, 'manager');
      expect(staff.isManager, true);
      expect(staff.hasManagerAccess, true);
      expect(staff.createdAt, now);
    });

    test('should have manager access when role is manager', () {
      final staff = Staff(
        id: '1',
        name: 'Manager User',
        role: 'manager',
        createdAt: DateTime.now(),
      );

      expect(staff.hasManagerAccess, true);
      expect(staff.isManager, true);
    });

    test('should have manager access when role is admin', () {
      final staff = Staff(
        id: '1',
        name: 'Admin User',
        role: 'admin',
        createdAt: DateTime.now(),
      );

      expect(staff.hasManagerAccess, true);
      expect(staff.isAdmin, true);
    });

    test('should not have manager access when neither flag is set', () {
      final staff = Staff(
        id: '1',
        name: 'Regular User',
        createdAt: DateTime.now(),
      );

      expect(staff.hasManagerAccess, false);
    });

    test('should serialize to JSON correctly', () {
      final now = DateTime.now();
      final timestamp = Timestamp.fromDate(now);

      final staff = Staff(
        id: '1',
        name: 'John Doe',
        uid: 'auth-uid',
        role: 'staff',
        createdAt: now,
      );

      final json = staff.toJson();

      expect(json['name'], 'John Doe');
      expect(json['uid'], 'auth-uid');
      expect(json['role'], 'staff');
      expect(json['createdAt'], timestamp);
    });

    test('should deserialize from JSON correctly', () {
      final now = DateTime.now();
      final timestamp = Timestamp.fromDate(now);

      final json = {
        'id': '1',
        'name': 'Jane Smith',
        'uid': 'auth-uid-2',
        'role': 'manager',
        'createdAt': timestamp,
      };

      final staff = Staff.fromJson(json);

      expect(staff.id, '1');
      expect(staff.name, 'Jane Smith');
      expect(staff.uid, 'auth-uid-2');
      expect(staff.role, 'manager');
      expect(staff.isManager, true);
      expect(staff.createdAt, now);
      expect(staff.hasManagerAccess, true);
    });
  });
}
