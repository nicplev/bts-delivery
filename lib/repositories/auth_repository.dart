import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/result.dart';
import '../services/staff_access_api.dart';
import '../services/switch_latest.dart';
import '../models/staff.dart';
import '../models/user.dart';

abstract class AuthRepository {
  Stream<User?> get authStateChanges;
  User? get currentUser;
  Future<Result<User>> signInWithEmailAndPassword(
      String email, String password);
  Future<Result<User>> createUserWithEmailAndPassword(
      String email, String password);
  Future<Result<void>> signOut();
  Future<Result<Staff>> linkToStaff(String code);
  Future<Result<Staff?>> getCurrentStaff();
  Stream<Staff?> watchCurrentStaff();
  Future<Result<AppUser?>> getCurrentUser();
  Stream<AppUser?> watchCurrentUser();
}

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Future<Result<User>> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update last login time in users collection
      unawaited(_recordLogin(credential.user!));

      return Result.success(credential.user!);
    } on FirebaseAuthException catch (e) {
      return Result.failure(_getAuthErrorMessage(e));
    } catch (e) {
      return Result.failure('An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<User>> createUserWithEmailAndPassword(
      String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create user document in users collection
      unawaited(_recordLogin(credential.user!));

      return Result.success(credential.user!);
    } on FirebaseAuthException catch (e) {
      return Result.failure(_getAuthErrorMessage(e));
    } catch (e) {
      return Result.failure('An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _auth.signOut();
      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to sign out: $e');
    }
  }

  @override
  Future<Result<Staff>> linkToStaff(String code) async {
    try {
      await callStaffAccess('redeemStaffInvite', {'code': code.trim()});
      final result = await getCurrentStaff();
      final staff = result.dataOrNull;
      return staff == null
          ? Result.failure(
              result.errorOrNull ?? 'Your staff link is still loading.')
          : Result.success(staff);
    } catch (e) {
      return Result.failure('Could not link your account: $e');
    }
  }

  @override
  Future<Result<Staff?>> getCurrentStaff() async {
    try {
      final user = currentUser;
      if (user == null) return const Result.success(null);

      final link =
          await _firestore.collection('staff_access').doc(user.uid).get();
      final staffId = link.data()?['staffId'] as String?;
      if (staffId == null || currentUser?.uid != user.uid) {
        return const Result.success(null);
      }
      final doc = await _firestore.collection('staff').doc(staffId).get();
      return Result.success(currentUser?.uid == user.uid
          ? _staff(doc, user, superAdmin: link.data()?['superAdmin'] == true)
          : null);
    } catch (e) {
      return Result.failure('Failed to get current staff: $e');
    }
  }

  @override
  Stream<Staff?> watchCurrentStaff() => switchLatest<User?, Staff?>(
        authStateChanges,
        (user) => user == null
            ? Stream<Staff?>.value(null)
            : switchLatest<DocumentSnapshot<Map<String, dynamic>>, Staff?>(
                _firestore.collection('staff_access').doc(user.uid).snapshots(),
                (link) {
                  final staffId = link.data()?['staffId'] as String?;
                  if (staffId == null) return Stream<Staff?>.value(null);
                  final superAdmin = link.data()?['superAdmin'] == true;
                  return _firestore
                      .collection('staff')
                      .doc(staffId)
                      .snapshots()
                      .map((doc) => _staff(doc, user, superAdmin: superAdmin));
                },
                reset: () => null,
              ),
        reset: () => null,
      );

  Staff? _staff(
    DocumentSnapshot<Map<String, dynamic>> doc,
    User user, {
    bool superAdmin = false,
  }) {
    final data = doc.data();
    if (data == null ||
        data['uid'] != user.uid ||
        !const ['admin', 'manager', 'staff'].contains(data['role'])) {
      return null;
    }
    return Staff.fromJson({...data, 'id': doc.id, 'superAdmin': superAdmin});
  }

  @override
  Future<Result<AppUser?>> getCurrentUser() async {
    try {
      final user = currentUser;
      if (user == null) return const Result.success(null);
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (currentUser?.uid != user.uid) return const Result.success(null);
      return Result.success(_profile(doc, user));
    } catch (e) {
      return Result.failure('Failed to get current user: $e');
    }
  }

  @override
  Stream<AppUser?> watchCurrentUser() => switchLatest<User?, AppUser?>(
        authStateChanges,
        (user) => user == null
            ? Stream<AppUser?>.value(null)
            : _firestore
                .collection('users')
                .doc(user.uid)
                .snapshots()
                .map((doc) => _profile(doc, user)),
        reset: () => null,
      );

  AppUser _profile(DocumentSnapshot<Map<String, dynamic>> doc, User user) {
    final data = doc.data();
    final createdAt = data?['createdAt'];
    final lastLoginAt = data?['lastLoginAt'];
    return AppUser(
      uid: user.uid,
      email: user.email ?? '',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      lastLoginAt: lastLoginAt is Timestamp ? lastLoginAt.toDate() : null,
    );
  }

  Future<void> _recordLogin(User user) async {
    final ref = _firestore.collection('users').doc(user.uid);
    try {
      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(ref);
        if (doc.exists) {
          transaction
              .update(ref, {'lastLoginAt': FieldValue.serverTimestamp()});
        } else {
          transaction.set(ref, {
            'uid': user.uid,
            'email': user.email,
            'createdAt': FieldValue.serverTimestamp(),
            'lastLoginAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } on FirebaseException catch (error) {
      debugPrint('Unable to record sign-in time: ${error.code}');
    }
  }

  String _getAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email address.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed login attempts. Please try again later.';
      default:
        return 'Authentication failed: ${e.message}';
    }
  }
}
