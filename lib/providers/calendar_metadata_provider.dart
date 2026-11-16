import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/calendar_metadata.dart';

/// Provider to fetch calendar metadata for a specific staff member
final calendarMetadataProvider =
    FutureProvider.family<CalendarMetadata?, String>((ref, staffId) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('calendar_metadata')
        .doc(staffId)
        .get();

    if (doc.data()?['subscriptionActive'] != true) {
      return null;
    }

    return CalendarMetadata.fromJson({
      ...doc.data()!,
      'staffId': doc.id,
      'token': '',
    });
  } catch (e) {
    // Return null if there's an error (metadata might not exist yet)
    return null;
  }
});

/// Provider to watch calendar metadata in real-time
final calendarMetadataStreamProvider =
    StreamProvider.family<CalendarMetadata?, String>((ref, staffId) {
  return FirebaseFirestore.instance
      .collection('calendar_metadata')
      .doc(staffId)
      .snapshots()
      .map((doc) {
    if (doc.data()?['subscriptionActive'] != true) {
      return null;
    }

    return CalendarMetadata.fromJson({
      ...doc.data()!,
      'staffId': doc.id,
      'token': '',
    });
  });
});
