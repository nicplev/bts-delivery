import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:uuid/uuid.dart';

/// Migration script to add calendar tokens to all existing staff members
///
/// Usage:
///   dart run scripts/migrate_calendar_tokens.dart
///
/// This script will:
/// 1. Connect to Firestore
/// 2. Find all staff members without a calendarToken
/// 3. Generate a unique token for each
/// 4. Update the staff documents
///
/// Prerequisites:
/// - Firebase project must be configured
/// - Must have admin access to Firestore
/// - Run from project root directory

void main() async {
  print('=== Calendar Token Migration Script ===\n');

  try {
    // Initialize Firebase
    print('Initializing Firebase...');
    await Firebase.initializeApp();
    print('✓ Firebase initialized\n');

    final firestore = FirebaseFirestore.instance;
    const uuid = Uuid();

    // Get all staff members
    print('Fetching all staff members...');
    final staffSnapshot = await firestore.collection('staff').get();
    print('✓ Found ${staffSnapshot.docs.length} staff members\n');

    if (staffSnapshot.docs.isEmpty) {
      print('No staff members found. Exiting.');
      exit(0);
    }

    // Filter staff without calendar tokens
    final staffWithoutTokens = staffSnapshot.docs.where((doc) {
      final data = doc.data();
      return !data.containsKey('calendarToken') ||
          data['calendarToken'] == null ||
          data['calendarToken'] == '';
    }).toList();

    print(
        'Staff members without calendar tokens: ${staffWithoutTokens.length}');

    if (staffWithoutTokens.isEmpty) {
      print('\n✓ All staff members already have calendar tokens!');
      exit(0);
    }

    // Ask for confirmation
    print(
        '\nThis will generate calendar tokens for ${staffWithoutTokens.length} staff members.');
    print('Staff members to update:');
    for (final doc in staffWithoutTokens) {
      final data = doc.data();
      print('  - ${data['name']} (${doc.id})');
    }

    print('\nDo you want to continue? (y/n): ');
    final input = stdin.readLineSync();

    if (input?.toLowerCase() != 'y' && input?.toLowerCase() != 'yes') {
      print('Migration cancelled.');
      exit(0);
    }

    // Perform migration
    print('\nStarting migration...\n');

    final batch = firestore.batch();
    int count = 0;

    for (final doc in staffWithoutTokens) {
      final token = uuid.v4();
      batch.update(doc.reference, {'calendarToken': token});
      count++;

      final data = doc.data();
      print(
          '  [$count/${staffWithoutTokens.length}] Generated token for ${data['name']}');
    }

    // Commit the batch
    print('\nCommitting changes to Firestore...');
    await batch.commit();

    print('\n✓ Migration completed successfully!');
    print('  Total staff updated: $count');
    print(
        '\nAll staff members now have calendar tokens and can subscribe to their calendars.');
  } catch (e, stackTrace) {
    print('\n✗ Error during migration:');
    print(e);
    print('\nStack trace:');
    print(stackTrace);
    exit(1);
  }
}
