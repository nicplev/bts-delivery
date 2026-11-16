import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// One-time script to fix deliveries and consumables that have empty IDs in Firestore
///
/// This script finds all deliveries and consumables where the 'id' field is an empty string
/// and removes that field from the document. The document ID (from Firestore)
/// will be used as the ID when the app reads the data.
///
/// Run this from the app by calling: await fixDeliveryIds();
Future<String> fixDeliveryIds() async {
  final firestore = FirebaseFirestore.instance;
  final log = StringBuffer();

  void logMessage(String message) {
    debugPrint(message);
    log.writeln(message);
  }

  logMessage('Starting delivery ID fix...');

  try {
    // Get all deliveries
    final snapshot = await firestore.collection('deliveries').get();

    logMessage('Found ${snapshot.docs.length} deliveries');

    int fixedCount = 0;
    int errorCount = 0;

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        final storedId = data['id'] as String?;

        // Check if the stored ID is empty or doesn't match the document ID
        if (storedId == null || storedId.isEmpty || storedId != doc.id) {
          logMessage('Fixing delivery ${doc.id}: stored id = "$storedId"');

          // Remove the 'id' field from the document
          await doc.reference.update({
            'id': FieldValue.delete(),
          });

          fixedCount++;
          logMessage('  ✓ Fixed delivery ${doc.id}');
        }
      } catch (e) {
        logMessage('  ✗ Error fixing delivery ${doc.id}: $e');
        errorCount++;
      }
    }

    logMessage('\n=== Deliveries Migration Complete ===');
    logMessage('Fixed: $fixedCount deliveries');
    logMessage('Errors: $errorCount deliveries');
    logMessage('Skipped: ${snapshot.docs.length - fixedCount - errorCount} deliveries (already correct)');

    // Now fix consumables
    logMessage('\n\n=== Starting Consumables Migration ===');

    // Get all schools
    final schoolsSnapshot = await firestore.collection('schools').get();
    logMessage('Found ${schoolsSnapshot.docs.length} schools');

    int consumablesFixed = 0;
    int consumablesErrors = 0;
    int totalConsumables = 0;

    for (final schoolDoc in schoolsSnapshot.docs) {
      try {
        // Get consumables for this school
        final consumablesSnapshot = await schoolDoc.reference
            .collection('consumables')
            .get();

        totalConsumables += consumablesSnapshot.docs.length;

        for (final consumableDoc in consumablesSnapshot.docs) {
          try {
            final data = consumableDoc.data();
            final storedId = data['id'] as String?;

            if (storedId == null || storedId.isEmpty || storedId != consumableDoc.id) {
              logMessage('Fixing consumable ${consumableDoc.id} in school ${schoolDoc.id}');

              await consumableDoc.reference.update({
                'id': FieldValue.delete(),
              });

              consumablesFixed++;
            }
          } catch (e) {
            logMessage('  ✗ Error fixing consumable ${consumableDoc.id}: $e');
            consumablesErrors++;
          }
        }
      } catch (e) {
        logMessage('Error processing school ${schoolDoc.id}: $e');
      }
    }

    logMessage('\n=== Consumables Migration Complete ===');
    logMessage('Fixed: $consumablesFixed consumables');
    logMessage('Errors: $consumablesErrors consumables');
    logMessage('Skipped: ${totalConsumables - consumablesFixed - consumablesErrors} consumables (already correct)');

    logMessage('\n=== Overall Migration Complete ===');
    logMessage('Total deliveries fixed: $fixedCount');
    logMessage('Total consumables fixed: $consumablesFixed');

    return log.toString();
  } catch (e) {
    logMessage('Migration failed: $e');
    rethrow;
  }
}
