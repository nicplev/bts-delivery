import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:bts_delivery_app/firebase_options.dart';

/// Script to set a user as admin in Firestore
///
/// Usage:
/// 1. Update the userEmail constant below with your email
/// 2. Run: dart scripts/set_admin.dart
///    OR: flutter run -t scripts/set_admin.dart
///
/// This will find the user by email and set their role to 'admin'

// ignore_for_file: avoid_print

const String userEmail = 'nicxplev@gmail.com'; // UPDATE THIS WITH YOUR EMAIL

Future<void> main() async {
  print('=== Set Admin Role Script ===\n');

  // Initialize Firebase
  print('Initializing Firebase...');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('✓ Firebase initialized\n');

  final firestore = FirebaseFirestore.instance;

  try {
    // Search for user by email
    print('Searching for user with email: $userEmail');
    final usersQuery = await firestore
        .collection('users')
        .where('email', isEqualTo: userEmail)
        .get();

    if (usersQuery.docs.isEmpty) {
      print('✗ No user found with email: $userEmail');
      print('\nAvailable users:');

      // List all users
      final allUsers = await firestore.collection('users').get();
      for (var doc in allUsers.docs) {
        final data = doc.data();
        print('  - ${doc.id}: ${data['email']} (role: ${data['role']})');
      }
      return;
    }

    // Update user role to admin
    final userDoc = usersQuery.docs.first;
    final userId = userDoc.id;
    final currentData = userDoc.data();

    print('✓ Found user: ${currentData['email']}');
    print('  User ID: $userId');
    print('  Current role: ${currentData['role']}');
    print('\nUpdating role to admin...');

    await firestore.collection('users').doc(userId).update({
      'role': 'admin',
    });

    print('✓ Successfully updated user role to admin!');
    print('\nUser details:');
    print('  Email: ${currentData['email']}');
    print('  UID: $userId');
    print('  Role: admin');
    print('\nYou can now log in as an admin with this account.');

  } catch (e) {
    print('✗ Error: $e');
  }

  print('\n=== Script Complete ===');
}
