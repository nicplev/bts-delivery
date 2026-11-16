import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/result.dart';
import '../models/staff.dart';
import '../models/user.dart';

abstract class AuthRepository {
  Stream<User?> get authStateChanges;
  User? get currentUser;
  Future<Result<User>> signInWithEmailAndPassword(String email, String password);
  Future<Result<User>> createUserWithEmailAndPassword(String email, String password);
  Future<Result<void>> signOut();
  Future<Result<Staff>> linkToStaff(String staffId);
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
  Future<Result<User>> signInWithEmailAndPassword(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update last login time in users collection
      await _updateUserLoginTime(credential.user!);

      return Result.success(credential.user!);
    } on FirebaseAuthException catch (e) {
      return Result.failure(_getAuthErrorMessage(e));
    } catch (e) {
      return Result.failure('An unexpected error occurred: $e');
    }
  }
  
  @override
  Future<Result<User>> createUserWithEmailAndPassword(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Create user document in users collection
      await _createUserDocument(credential.user!);
      
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
  Future<Result<Staff>> linkToStaff(String staffId) async {
    try {
      final user = currentUser;
      if (user == null) {
        return const Result.failure('No user signed in');
      }

      final staffDoc = _firestore.collection('staff').doc(staffId);
      await staffDoc.update({'uid': user.uid});

      final doc = await staffDoc.get();
      if (!doc.exists) {
        return const Result.failure('Staff member not found');
      }

      final staff = Staff.fromJson({
        'id': doc.id,
        ...doc.data()!,
      });

      // Update user document role to match the staff member's role
      await _firestore.collection('users').doc(user.uid).update({
        'role': staff.role,
      });

      return Result.success(staff);
    } catch (e) {
      return Result.failure('Failed to link to staff: $e');
    }
  }
  
  @override
  Future<Result<Staff?>> getCurrentStaff() async {
    try {
      final user = currentUser;
      if (user == null) {
        return const Result.success(null);
      }
      
      final query = await _firestore
          .collection('staff')
          .where('uid', isEqualTo: user.uid)
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
      return Result.failure('Failed to get current staff: $e');
    }
  }
  
  @override
  Stream<Staff?> watchCurrentStaff() {
    return authStateChanges.asyncMap((user) async {
      if (user == null) return null;
      
      final result = await getCurrentStaff();
      return result.dataOrNull;
    });
  }
  
  @override
  Future<Result<AppUser?>> getCurrentUser() async {
    try {
      final user = currentUser;
      if (user == null) {
        return const Result.success(null);
      }

      final docRef = _firestore.collection('users').doc(user.uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        // Create user document if it doesn't exist (legacy users)
        await _createUserDocument(user);
        return Result.success(AppUser(
          uid: user.uid,
          email: user.email!,
          role: 'staff',
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
        ));
      }

      final data = doc.data()!;

      // IMPORTANT: getCurrentUser() should NEVER write to Firestore
      // Any writes trigger stream updates which cause infinite loops
      // Field fixes should only happen during sign-in via _updateUserLoginTime

      // Build the AppUser with proper error handling for timestamps
      DateTime createdAt;
      DateTime lastLoginAt;

      try {
        if (data['createdAt'] is Timestamp) {
          createdAt = (data['createdAt'] as Timestamp).toDate();
        } else {
          createdAt = DateTime.now();
        }
      } catch (e) {
        debugPrint('Error parsing createdAt timestamp: $e');
        createdAt = DateTime.now();
      }

      try {
        if (data['lastLoginAt'] is Timestamp) {
          lastLoginAt = (data['lastLoginAt'] as Timestamp).toDate();
        } else {
          lastLoginAt = DateTime.now();
        }
      } catch (e) {
        debugPrint('Error parsing lastLoginAt timestamp: $e');
        lastLoginAt = DateTime.now();
      }

      final appUser = AppUser(
        uid: user.uid,
        email: data['email'] ?? user.email!,
        role: data['role'] ?? 'staff',
        createdAt: createdAt,
        lastLoginAt: lastLoginAt,
      );

      return Result.success(appUser);
    } catch (e) {
      debugPrint('Error getting current user: $e');
      return Result.failure('Failed to get current user: $e');
    }
  }
  
  @override
  Stream<AppUser?> watchCurrentUser() {
    // Cache the last known user ID to prevent unnecessary re-subscriptions
    String? lastUserId;

    return authStateChanges.asyncExpand((user) {
      // Only switch streams when the user ID actually changes
      if (user?.uid == lastUserId) {
        return const Stream.empty();
      }

      lastUserId = user?.uid;

      if (user == null) {
        return Stream.value(null);
      }

      // Watch the Firestore document directly instead of calling getCurrentUser
      // This prevents infinite loops from auth state changes
      return _firestore.collection('users').doc(user.uid).snapshots().map((doc) {
        if (!doc.exists) {
          return null;
        }

        final data = doc.data()!;

        // Parse timestamps safely
        DateTime createdAt = DateTime.now();
        DateTime lastLoginAt = DateTime.now();

        try {
          if (data['createdAt'] is Timestamp) {
            createdAt = (data['createdAt'] as Timestamp).toDate();
          }
        } catch (e) {
          // Use default
        }

        try {
          if (data['lastLoginAt'] is Timestamp) {
            lastLoginAt = (data['lastLoginAt'] as Timestamp).toDate();
          }
        } catch (e) {
          // Use default
        }

        return AppUser(
          uid: user.uid,
          email: data['email'] ?? user.email!,
          role: data['role'] ?? 'staff',
          createdAt: createdAt,
          lastLoginAt: lastLoginAt,
        );
      });
    });
  }
  
  Future<void> _createUserDocument(User user) async {
    final userDoc = AppUser(
      uid: user.uid,
      email: user.email!,
      role: 'staff', // Default role
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
    );
    
    await _firestore.collection('users').doc(user.uid).set(userDoc.toJson());
  }
  
  Future<void> _updateUserLoginTime(User user) async {
    try {
      final docRef = _firestore.collection('users').doc(user.uid);
      final doc = await docRef.get();
      
      if (!doc.exists) {
        // Create new document with all required fields
        await _createUserDocument(user);
      } else {
        // Check and fix document structure
        final data = doc.data()!;
        final updates = <String, dynamic>{
          'lastLoginAt': Timestamp.fromDate(DateTime.now()),
        };
        
        // Ensure all required fields exist
        if (!data.containsKey('uid')) {
          updates['uid'] = user.uid;
        }
        if (!data.containsKey('email')) {
          updates['email'] = user.email;
        }
        if (!data.containsKey('role')) {
          updates['role'] = 'staff'; // Default role
        }
        if (!data.containsKey('createdAt')) {
          updates['createdAt'] = Timestamp.fromDate(DateTime.now());
        }
        
        // Remove any fields that shouldn't be in users collection
        if (data.containsKey('isManager') || data.containsKey('name')) {
          // Need to rewrite the document without these fields
          await docRef.set({
            'uid': user.uid,
            'email': data['email'] ?? user.email,
            'role': data['role'] ?? 'staff',
            'createdAt': data['createdAt'] ?? Timestamp.fromDate(DateTime.now()),
            'lastLoginAt': Timestamp.fromDate(DateTime.now()),
          });
        } else {
          // Just update the necessary fields
          await docRef.update(updates);
        }
      }
    } catch (e) {
      // If any error, create a fresh document
      await _createUserDocument(user);
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