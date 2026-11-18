import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/staff.dart';
import '../services/result.dart';
import '../services/staff_access_api.dart';

abstract class StaffRepository {
  Future<Result<Staff>> getStaffById(String staffId);
  Future<Result<List<Staff>>> getAllStaff();
  Future<Result<Staff>> createStaff(Staff staff);
  Future<Result<Staff>> updateStaff(Staff staff);
  Future<Result<void>> deleteStaff(String staffId);
  Future<Result<void>> setSchoolAssignments(
    String schoolId,
    Map<String, bool> changes,
  );
  Future<Result<String>> issueInvite(String staffId);
  Future<Result<String>> generateCalendarToken(String staffId);
  Future<Result<String>> regenerateCalendarToken(String staffId);
  Future<Result<String>> getCalendarSubscriptionUrl(String staffId);
  Future<Result<String?>> getExistingCalendarHttpsUrl(String staffId);

  // Team control — super admins only; the server refuses anyone else.
  Future<Result<TeamDirectory>> getTeamAccounts();

  /// Creates a sign-in for [email]. Pass [staffId] to give an existing
  /// person a sign-in, or [name] and [role] to add someone new.
  Future<Result<String>> createTeamAccount({
    required String email,
    String? staffId,
    String? name,
    String? role,
  });
  Future<Result<void>> setTeamSuperAdmin(String staffId, bool superAdmin);
  Future<Result<void>> setTeamSignIn(String staffId, bool enabled);
  Future<Result<void>> deleteTeamMember(String staffId);

  /// Emails [email] a link to choose a new password.
  Future<Result<void>> sendPasswordReset(String email);
}

/// Sign-in details for one person, visible to super admins.
class TeamAccount {
  const TeamAccount({
    required this.staffId,
    required this.hasLogin,
    this.email,
    this.signInEnabled = false,
    this.superAdmin = false,
    this.lastSignInAt,
  });

  factory TeamAccount.fromJson(Map<String, dynamic> json) => TeamAccount(
        staffId: json['staffId'] as String,
        hasLogin: json['hasLogin'] == true,
        email: json['email'] as String?,
        signInEnabled: json['signInEnabled'] == true,
        superAdmin: json['superAdmin'] == true,
        lastSignInAt: json['lastSignInAt'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (json['lastSignInAt'] as num).toInt())
            : null,
      );

  final String staffId;
  final bool hasLogin;
  final String? email;
  final bool signInEnabled;
  final bool superAdmin;
  final DateTime? lastSignInAt;
}

class TeamDirectory {
  const TeamDirectory({required this.callerStaffId, required this.accounts});

  final String callerStaffId;
  final Map<String, TeamAccount> accounts;
}

class FirebaseStaffRepository implements StaffRepository {
  final _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _staff =>
      _firestore.collection('staff');

  @override
  Future<Result<Staff>> getStaffById(String staffId) async {
    try {
      final doc = await _staff.doc(staffId).get();
      final data = doc.data();
      if (data == null) return const Result.failure('Staff member not found');
      // Super admin comes only from the server-owned access link.
      return Result.success(
          Staff.fromJson({...data, 'id': doc.id, 'superAdmin': false}));
    } catch (e) {
      return Result.failure('Failed to get staff: $e');
    }
  }

  @override
  Future<Result<List<Staff>>> getAllStaff() async {
    try {
      final result = await callStaffAccess('listStaffDirectory', {});
      final staff = (result['staff'] as List).map((entry) {
        final data = Map<String, dynamic>.from(entry as Map);
        data['createdAt'] = Timestamp.fromMillisecondsSinceEpoch(
          (data['createdAt'] as num).toInt(),
        );
        return Staff.fromJson(data);
      }).toList();
      return Result.success(staff);
    } catch (e) {
      return Result.failure('Failed to get the staff directory: $e');
    }
  }

  @override
  Future<Result<Staff>> createStaff(Staff staff) async {
    try {
      final doc = await _staff.add({
        'name': staff.name,
        'role': staff.role,
        'assignedSchoolIds': staff.assignedSchoolIds,
        'createdAt': Timestamp.fromDate(staff.createdAt),
      });
      return Result.success(staff.copyWith(id: doc.id));
    } catch (e) {
      return Result.failure('Failed to add staff: $e');
    }
  }

  @override
  Future<Result<Staff>> updateStaff(Staff staff) async {
    try {
      await _staff.doc(staff.id).update({
        'name': staff.name,
        'role': staff.role,
      });
      return Result.success(staff);
    } catch (e) {
      return Result.failure('Failed to update staff: $e');
    }
  }

  @override
  Future<Result<void>> setSchoolAssignments(
    String schoolId,
    Map<String, bool> changes,
  ) async {
    try {
      if (changes.isEmpty) return const Result.success(null);
      final batch = _firestore.batch();
      changes.forEach((staffId, isAssigned) {
        batch.update(_staff.doc(staffId), {
          'assignedSchoolIds': isAssigned
              ? FieldValue.arrayUnion([schoolId])
              : FieldValue.arrayRemove([schoolId]),
        });
      });
      await batch.commit();
      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to save staff assignments: $e');
    }
  }

  @override
  Future<Result<void>> deleteStaff(String staffId) async {
    try {
      await _staff.doc(staffId).delete();
      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete staff: $e');
    }
  }

  @override
  Future<Result<String>> issueInvite(String staffId) async {
    try {
      final data =
          await callStaffAccess('issueStaffInvite', {'staffId': staffId});
      return Result.success(data['code'] as String);
    } catch (e) {
      return Result.failure('Failed to issue an invitation: $e');
    }
  }

  @override
  Future<Result<TeamDirectory>> getTeamAccounts() async {
    try {
      final result = await callStaffAccess('listTeamAccounts', {});
      final accounts = [
        for (final entry in result['accounts'] as List)
          TeamAccount.fromJson(Map<String, dynamic>.from(entry as Map)),
      ];
      return Result.success(TeamDirectory(
        callerStaffId: result['callerStaffId'] as String,
        accounts: {for (final account in accounts) account.staffId: account},
      ));
    } catch (e) {
      return Result.failure('Could not load sign-in details: $e');
    }
  }

  @override
  Future<Result<String>> createTeamAccount({
    required String email,
    String? staffId,
    String? name,
    String? role,
  }) async {
    try {
      final result = await callStaffAccess('createTeamAccount', {
        'email': email,
        if (staffId != null) 'staffId': staffId,
        if (name != null) 'name': name,
        if (role != null) 'role': role,
      });
      return Result.success(result['staffId'] as String);
    } catch (e) {
      return Result.failure('Could not create the sign-in: $e');
    }
  }

  @override
  Future<Result<void>> setTeamSuperAdmin(String staffId, bool superAdmin) =>
      _teamCall(
          'setTeamSuperAdmin',
          {'staffId': staffId, 'superAdmin': superAdmin},
          'Could not change super admin access');

  @override
  Future<Result<void>> setTeamSignIn(String staffId, bool enabled) => _teamCall(
      'setTeamSignIn',
      {'staffId': staffId, 'enabled': enabled},
      'Could not change sign-in');

  @override
  Future<Result<void>> deleteTeamMember(String staffId) => _teamCall(
      'deleteTeamMember', {'staffId': staffId}, 'Could not delete this person');

  Future<Result<void>> _teamCall(
    String function,
    Map<String, dynamic> data,
    String failure,
  ) async {
    try {
      await callStaffAccess(function, data);
      return const Result.success(null);
    } catch (e) {
      return Result.failure('$failure: $e');
    }
  }

  @override
  Future<Result<void>> sendPasswordReset(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      return const Result.success(null);
    } catch (e) {
      return Result.failure('Could not send the password reset email: $e');
    }
  }

  @override
  Future<Result<String>> generateCalendarToken(String staffId) =>
      _calendarToken(staffId, rotate: false);

  @override
  Future<Result<String>> regenerateCalendarToken(String staffId) =>
      _calendarToken(staffId, rotate: true);

  Future<Result<String>> _calendarToken(
    String staffId, {
    required bool rotate,
  }) async {
    try {
      final result = await callStaffAccess('calendarSubscriptionToken', {
        'staffId': staffId,
        'rotate': rotate,
      });
      return Result.success(result['token'] as String);
    } catch (e) {
      return Result.failure('Failed to get a calendar link: $e');
    }
  }

  @override
  Future<Result<String>> getCalendarSubscriptionUrl(String staffId) async {
    return (await generateCalendarToken(staffId)).when(
      success: (token) => Result.success(calendarUrl(token, scheme: 'webcals')),
      failure: (message, error) => Result.failure(message, error),
    );
  }

  @override
  Future<Result<String?>> getExistingCalendarHttpsUrl(String staffId) async {
    try {
      final result = await callStaffAccess('calendarSubscriptionToken', {
        'staffId': staffId,
        'existingOnly': true,
      });
      final token = result['token'] as String?;
      return Result.success(token == null ? null : calendarUrl(token));
    } catch (e) {
      return Result.failure('Failed to check the calendar link: $e');
    }
  }
}

String calendarUrl(String token, {String scheme = 'https'}) {
  if (firebaseEmulatorHost.isNotEmpty) {
    return Uri(
      scheme: 'http',
      host: firebaseEmulatorHost,
      port: 5001,
      path: '/$firebaseDemoProject/us-central1/calendar/$token.ics',
    ).toString();
  }
  final projectId = Firebase.app().options.projectId;
  return Uri(
    scheme: scheme,
    host: 'us-central1-$projectId.cloudfunctions.net',
    path: '/calendar/$token.ics',
  ).toString();
}
