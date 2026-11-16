import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../services/result.dart';
import '../models/offline/evidence_upload.dart';
import '../models/school.dart';
import '../models/delivery_visit.dart';
import '../models/signoff_snapshot.dart';
import '../models/school_timer.dart';
import 'scoped_query_stream.dart';
import 'classroom_edit.dart';
import 'signoff_snapshot_reader.dart';

abstract class SchoolsRepository {
  Stream<List<School>> watchSchools({List<String>? schoolIds});
  Future<Result<List<School>>> getSchools();
  Future<Result<School>> createSchool(School school);
  Future<Result<School>> updateSchool(School school);
  Future<Result<void>> deleteSchool(String schoolId);

  // Year Levels
  Stream<List<YearLevel>> watchYearLevels(String schoolId);
  Future<Result<YearLevel>> createYearLevel(
      String schoolId, YearLevel yearLevel);
  Future<Result<YearLevel>> updateYearLevel(
      String schoolId, YearLevel yearLevel);
  Future<Result<void>> deleteYearLevel(String schoolId, String yearLevelId);

  // Classrooms
  Stream<List<Classroom>> watchClassrooms(String schoolId, String yearLevelId);
  Future<Result<Classroom>> createClassroom(
      String schoolId, String yearLevelId, Classroom classroom);
  Future<Result<ClassroomEditReceipt>> updateClassroomName(
    String schoolId,
    String yearLevelId,
    String classroomId, {
    required String name,
    required String updatedBy,
  });
  Future<Result<ClassroomEditReceipt>> updateClassroomStatus(
    String schoolId,
    String yearLevelId,
    String classroomId, {
    required ClassroomCompletionStatus status,
    required int? actualPacksDelivered,
    required String updatedBy,
  });
  Future<Result<void>> deleteClassroom(
      String schoolId, String yearLevelId, String classroomId);

  // Year Level Breakdowns (for composite classes)
  Stream<List<YearLevelBreakdown>> watchYearLevelBreakdowns(
      String schoolId, String yearLevelId, String classroomId);
  Future<Result<YearLevelBreakdown>> createYearLevelBreakdown(
      String schoolId,
      String yearLevelId,
      String classroomId,
      YearLevelBreakdown breakdown);
  Future<Result<YearLevelBreakdown>> updateYearLevelBreakdown(
      String schoolId,
      String yearLevelId,
      String classroomId,
      YearLevelBreakdown breakdown);
  Future<Result<void>> deleteYearLevelBreakdown(String schoolId,
      String yearLevelId, String classroomId, String breakdownId);

  // Photos
  Stream<List<Photo>> watchClassroomPhotos(
    String schoolId, String yearLevelId, String classroomId, {String? deliveryId});
  Future<Result<Photo>> addClassroomPhoto(
    String schoolId, String yearLevelId, String classroomId, Photo photo, {String? deliveryId});
  Future<Result<void>> deleteClassroomPhoto(
    String schoolId, String yearLevelId, String classroomId, String photoId, {String? deliveryId});

  // Pack Totals
  Stream<PackTotal?> watchLatestPackTotal(
      String schoolId, String yearLevelId, String classroomId);
  Future<Result<PackTotal>> updatePackTotal(String schoolId, String yearLevelId,
      String classroomId, PackTotal packTotal);

  // School-wide Consumables
  Stream<List<Consumable>> watchConsumables(String schoolId);
  Future<Result<Consumable>> createConsumable(
      String schoolId, Consumable consumable);
  Future<Result<Consumable>> updateConsumable(
      String schoolId, Consumable consumable);
  Future<Result<void>> deleteConsumable(String schoolId, String consumableId);

  // Classroom Consumables
  Stream<List<Consumable>> watchClassroomConsumables(
      String schoolId, String yearLevelId, String classroomId);
  Future<Result<Consumable>> createClassroomConsumable(String schoolId,
      String yearLevelId, String classroomId, Consumable consumable);
  Future<Result<Consumable>> updateClassroomConsumable(String schoolId,
      String yearLevelId, String classroomId, Consumable consumable);
  Future<Result<void>> deleteClassroomConsumable(String schoolId,
      String yearLevelId, String classroomId, String consumableId);

  // Sign-off
  Future<SignOffSnapshot> readSignOffDraft(String schoolId, {required bool server, String? deliveryId});
  Stream<SignedEvidence?> watchSignedEvidence(String schoolId, String? deliveryId);
  Future<List<SignedEvidence>> readSignOffHistory(String schoolId, String? deliveryId);
  Future<void> persistQueuedSignOff(
    EvidenceUpload item, {
    required void Function() requireOwner,
  });
  Stream<SignOff?> watchSignOff(String schoolId);

  // Contacts
  Stream<List<Contact>> watchContacts(String schoolId);
  Future<Result<Contact>> createContact(String schoolId, Contact contact);
  Future<Result<Contact>> updateContact(String schoolId, Contact contact);
  Future<Result<void>> deleteContact(String schoolId, String contactId);

  // Maps
  Stream<List<MapAsset>> watchMapAssets(String schoolId);
  Future<Result<MapAsset>> createMapAsset(String schoolId, MapAsset mapAsset);
  Future<Result<void>> deleteMapAsset(String schoolId, String mapAssetId);

  // Notes
  Stream<List<Note>> watchNotes(String schoolId);
  Future<Result<Note>> createNote(String schoolId, Note note);
  Future<Result<void>> deleteNote(String schoolId, String noteId);

  // Classroom Notes
  Stream<List<Note>> watchClassroomNotes(
      String schoolId, String yearLevelId, String classroomId);
  Future<Result<Note>> createClassroomNote(
      String schoolId, String yearLevelId, String classroomId, Note note);
  Future<Result<Note>> updateClassroomNote(
      String schoolId, String yearLevelId, String classroomId, Note note);
  Future<Result<void>> deleteClassroomNote(
      String schoolId, String yearLevelId, String classroomId, String noteId);

  // Signed School Summaries
  Future<Result<SignedSchoolSummary?>> getSignedSchoolSummary(String schoolId);

  // Bulk Import
  Future<Result<BulkImportSummary>> bulkImportClassrooms(
      String schoolId, List<YearLevelImportData> yearLevels);

  // School Timers
  Stream<SchoolTimer?> watchActiveTimer(String schoolId);
  Stream<List<SchoolTimer>> watchTimerHistory(String schoolId, {int limit = 20});
  Future<Result<SchoolTimer>> startTimer(String schoolId, SchoolTimer timer);
  Future<Result<void>> stopTimer(
      String schoolId, String timerId, String stoppedByUid, String stoppedByName);

  // Timer History CRUD (admin only)
  Future<Result<void>> createTimerHistoryEntry(String schoolId, SchoolTimer timer);
  Future<Result<void>> updateTimerHistoryEntry(String schoolId, SchoolTimer timer);
  Future<Result<void>> deleteTimerHistoryEntry(String schoolId, String timerId);
}

/// Summary of bulk import operation
class BulkImportSummary {
  final int yearLevelsCreated;
  final int classroomsCreated;
  final int consumablesCreated;
  final int packsAllocated;

  BulkImportSummary({
    required this.yearLevelsCreated,
    required this.classroomsCreated,
    required this.consumablesCreated,
    required this.packsAllocated,
  });
}

/// Data for importing a year level
class YearLevelImportData {
  final String label;
  final List<ClassroomImportData> classrooms;

  YearLevelImportData({
    required this.label,
    required this.classrooms,
  });
}

/// Data for importing a classroom
class ClassroomImportData {
  final String name;
  final int packs;
  final List<ConsumableImportData> consumables;
  final List<StudentBreakdownImportData> studentBreakdowns;

  ClassroomImportData({
    required this.name,
    required this.packs,
    required this.consumables,
    this.studentBreakdowns = const [],
  });
}

/// Data for importing student breakdown by year level
class StudentBreakdownImportData {
  final String yearLevelLabel;
  final int studentCount;

  StudentBreakdownImportData({
    required this.yearLevelLabel,
    required this.studentCount,
  });
}

/// Data for importing a consumable
class ConsumableImportData {
  final String itemName;
  final int quantity;
  final String unit;

  ConsumableImportData({
    required this.itemName,
    required this.quantity,
    required this.unit,
  });
}

class FirebaseSchoolsRepository implements SchoolsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  FirebaseSchoolsRepository({DeliveryVisit? visit}) : _visit = visit;

  final DeliveryVisit? _visit;

  DocumentReference<Map<String, dynamic>> _recordsFor(String schoolId) {
    final visit = _visit;
    if (visit == null) return _firestore.collection('schools').doc(schoolId);
    if (schoolId != visit.schoolId) {
      throw ArgumentError.value(schoolId, 'schoolId', 'Invalid school for this delivery');
    }
    return _firestore.doc(visit.workspacePath);
  }

  // Helper method to update classroom's last modified metadata
  Future<void> _updateClassroomLastModified(
      String schoolId, String yearLevelId, String classroomId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      String updatedBy = 'Unknown';

      if (currentUser != null) {
        // First try to get staff name from Firestore
        try {
          final staffSnapshot = await _firestore
              .collection('staff')
              .doc(currentUser.uid)
              .get();

          if (staffSnapshot.exists) {
            updatedBy = staffSnapshot.data()?['name'] ?? currentUser.email?.split('@').first ?? 'Unknown';
          } else {
            // Fallback to email username
            updatedBy = currentUser.email?.split('@').first ?? 'Unknown';
          }
        } catch (_) {
          // Fallback to email username if staff lookup fails
          updatedBy = currentUser.email?.split('@').first ?? 'Unknown';
        }
      }

      await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .update({
        'lastUpdatedBy': updatedBy,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to update classroom last modified: $e');
      // Don't fail the main operation if updating metadata fails
    }
  }

  @override
  Stream<List<School>> watchSchools({List<String>? schoolIds}) {
    final collection = _firestore.collection('schools');

    Stream<List<School>> watch(Query<Map<String, dynamic>> query) {
      return query.snapshots().map((snapshot) {
        return [
          for (final doc in snapshot.docs)
            School.fromJson({...doc.data(), 'id': doc.id}),
        ];
      });
    }

    if (schoolIds == null) return watch(collection.orderBy('name'));
    return watchInChunks(
      schoolIds,
      (ids) => watch(collection.where(FieldPath.documentId, whereIn: ids)),
    ).map((schools) {
      return [...schools]..sort((a, b) => a.name.compareTo(b.name));
    });
  }

  @override
  Future<Result<List<School>>> getSchools() async {
    try {
      final snapshot =
          await _firestore.collection('schools').orderBy('name').get();
      final schools = snapshot.docs
          .map((doc) => School.fromJson({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();

      return Result.success(schools);
    } catch (e) {
      return Result.failure('Failed to get schools: $e');
    }
  }

  @override
  Future<Result<School>> createSchool(School school) async {
    try {
      final data = school.toJson();
      // Remove the id field as Firestore will generate it
      data.remove('id');

      final docRef = await _firestore.collection('schools').add(data);
      final createdSchool = school.copyWith(id: docRef.id);
      return Result.success(createdSchool);
    } catch (e) {
      return Result.failure('Failed to create school: $e');
    }
  }

  @override
  Future<Result<School>> updateSchool(School school) async {
    try {
      await _firestore
          .collection('schools')
          .doc(school.id)
          .update(school.toJson());
      return Result.success(school);
    } catch (e) {
      return Result.failure('Failed to update school: $e');
    }
  }

  @override
  Future<Result<void>> deleteSchool(String schoolId) async {
    try {
      await _firestore.collection('schools').doc(schoolId).delete();
      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete school: $e');
    }
  }

  // Year Levels
  @override
  Stream<List<YearLevel>> watchYearLevels(String schoolId) {
    return _recordsFor(schoolId)
        .collection('yearLevels')
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.where((doc) {
        final data = doc.data();
        // Check for either 'name' or 'label' field (name is legacy)
        final hasName = data['name'] != null || data['label'] != null;
        return hasName && data['createdAt'] != null;
      }).map((doc) {
        try {
          final data = doc.data();
          // Map 'name' field to 'label' for backwards compatibility
          final label = data['label'] ?? data['name'];

          final yearLevel = YearLevel.fromJson({
            'id': doc.id,
            'label': label,
            'createdAt': data['createdAt'],
          });
          return yearLevel;
        } catch (e) {
          // Log parsing errors but continue with other documents
          debugPrint('Error parsing year level ${doc.id}: $e');
          rethrow;
        }
      }).toList();
    });
  }

  @override
  Future<Result<YearLevel>> createYearLevel(
      String schoolId, YearLevel yearLevel) async {
    try {
      final data = yearLevel.toJson();
      // Remove the id field as Firestore will generate it
      data.remove('id');

      final docRef = await _recordsFor(schoolId)
          .collection('yearLevels')
          .add(data);
      final created = yearLevel.copyWith(id: docRef.id);


      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create year level: $e');
    }
  }

  @override
  Future<Result<YearLevel>> updateYearLevel(
      String schoolId, YearLevel yearLevel) async {
    try {
      await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevel.id)
          .update(yearLevel.toJson());


      return Result.success(yearLevel);
    } catch (e) {
      return Result.failure('Failed to update year level: $e');
    }
  }

  @override
  Future<Result<void>> deleteYearLevel(
      String schoolId, String yearLevelId) async {
    try {
      await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .delete();


      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete year level: $e');
    }
  }

  // Classrooms
  @override
  Stream<List<Classroom>> watchClassrooms(String schoolId, String yearLevelId) {
    return _recordsFor(schoolId)
        .collection('yearLevels')
        .doc(yearLevelId)
        .collection('classrooms')
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.where((doc) {
        final data = doc.data();
        // Filter out documents with missing required fields
        return data['name'] != null && data['createdAt'] != null;
      }).map((doc) {
        try {
          final data = doc.data();
          // Remove any id field from data to prevent overwriting
          data.remove('id');

          return Classroom.fromJson({
            'id': doc.id,
            ...data,
          });
        } catch (e) {
          // Log parsing errors but continue with other documents
          debugPrint('Error parsing classroom ${doc.id}: $e');
          rethrow;
        }
      }).toList();
    });
  }

  @override
  Future<Result<Classroom>> createClassroom(
      String schoolId, String yearLevelId, Classroom classroom) async {
    try {
      final data = classroom.toJson();
      // Remove the id field as Firestore will generate it
      data.remove('id');

      final docRef = await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .add(data);
      final created = classroom.copyWith(id: docRef.id);


      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create classroom: $e');
    }
  }

  @override
  Future<Result<ClassroomEditReceipt>> updateClassroomName(
    String schoolId,
    String yearLevelId,
    String classroomId, {
    required String name,
    required String updatedBy,
  }) {
    return _editClassroom(
      schoolId,
      yearLevelId,
      classroomId,
      () => ClassroomEdit.rename(name),
      updatedBy,
    );
  }

  @override
  Future<Result<ClassroomEditReceipt>> updateClassroomStatus(
    String schoolId,
    String yearLevelId,
    String classroomId, {
    required ClassroomCompletionStatus status,
    required int? actualPacksDelivered,
    required String updatedBy,
  }) {
    return _editClassroom(
      schoolId,
      yearLevelId,
      classroomId,
      () => ClassroomEdit.status(status, actualPacksDelivered),
      updatedBy,
    );
  }

  Future<Result<ClassroomEditReceipt>> _editClassroom(
    String schoolId,
    String yearLevelId,
    String classroomId,
    ClassroomEdit Function() edit,
    String updatedBy,
  ) async {
    try {
      final fields = edit().fields;
      final editId = const Uuid().v4();
      final classroom = _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId);

      final pendingEditIds = classroom
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) => snapshot.metadata.hasPendingWrites
              ? (snapshot.data()?['lastEditId'] as String?)
              : null);

      return await observeClassroomEdit(
        editId: editId,
        pendingEditIds: pendingEditIds,
        write: () => classroom.update({
          ...fields,
          'lastEditId': editId,
          'lastUpdatedBy': updatedBy,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        }),
      );
    } on ArgumentError catch (error) {
      return Result.failure(error.message?.toString() ?? 'Invalid classroom edit.');
    } catch (_) {
      return const Result.failure('Couldn’t submit the classroom edit.');
    }
  }

  @override
  Future<Result<void>> deleteClassroom(
      String schoolId, String yearLevelId, String classroomId) async {
    try {
      debugPrint(
          'Deleting classroom: schoolId=$schoolId, yearLevelId=$yearLevelId, classroomId=$classroomId');
      await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .delete();
      debugPrint('Classroom deleted successfully');


      return const Result.success(null);
    } catch (e) {
      debugPrint('Error deleting classroom: $e');
      return Result.failure('Failed to delete classroom: $e');
    }
  }

  // Year Level Breakdowns (for composite classes)
  @override
  Stream<List<YearLevelBreakdown>> watchYearLevelBreakdowns(
      String schoolId, String yearLevelId, String classroomId) {
    return _recordsFor(schoolId)
        .collection('yearLevels')
        .doc(yearLevelId)
        .collection('classrooms')
        .doc(classroomId)
        .collection('yearLevelBreakdowns')
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.where((doc) {
        final data = doc.data();
        return data['yearLevelId'] != null &&
            data['yearLevelLabel'] != null &&
            data['studentCount'] != null &&
            data['createdAt'] != null;
      }).map((doc) {
        try {
          final data = doc.data();
          data.remove('id');

          return YearLevelBreakdown.fromJson({
            'id': doc.id,
            ...data,
          });
        } catch (e) {
          debugPrint('Error parsing year level breakdown ${doc.id}: $e');
          rethrow;
        }
      }).toList();
    });
  }

  @override
  Future<Result<YearLevelBreakdown>> createYearLevelBreakdown(
      String schoolId,
      String yearLevelId,
      String classroomId,
      YearLevelBreakdown breakdown) async {
    try {
      final data = breakdown.toJson();
      data.remove('id');

      final docRef = await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('yearLevelBreakdowns')
          .add(data);
      final created = breakdown.copyWith(id: docRef.id);

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);


      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create year level breakdown: $e');
    }
  }

  @override
  Future<Result<YearLevelBreakdown>> updateYearLevelBreakdown(
      String schoolId,
      String yearLevelId,
      String classroomId,
      YearLevelBreakdown breakdown) async {
    try {
      await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('yearLevelBreakdowns')
          .doc(breakdown.id)
          .update(breakdown.toJson());

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);


      return Result.success(breakdown);
    } catch (e) {
      return Result.failure('Failed to update year level breakdown: $e');
    }
  }

  @override
  Future<Result<void>> deleteYearLevelBreakdown(String schoolId,
      String yearLevelId, String classroomId, String breakdownId) async {
    try {
      await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('yearLevelBreakdowns')
          .doc(breakdownId)
          .delete();

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);


      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete year level breakdown: $e');
    }
  }

  // Photos
  DocumentReference<Map<String, dynamic>> _photoClassroom(
    String schoolId,
    String yearLevelId,
    String classroomId,
    String? deliveryId,
  ) {
    final root = deliveryId == null
        ? _firestore.collection('schools').doc(schoolId)
        : _firestore.doc(DeliveryVisit(deliveryId: deliveryId, schoolId: schoolId).workspacePath);
    return root.collection('yearLevels').doc(yearLevelId)
        .collection('classrooms').doc(classroomId);
  }

  @override
  Stream<List<Photo>> watchClassroomPhotos(
      String schoolId, String yearLevelId, String classroomId, {String? deliveryId}) {
    return _photoClassroom(schoolId, yearLevelId, classroomId, deliveryId)
        .collection('photos')
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) {
            final data = doc.data();
            return Photo.fromJson({
              ...data,
              'id': doc.id,
            });
          })
          .toList();
    });
  }

  @override
  Future<Result<Photo>> addClassroomPhoto(
    String schoolId,
    String yearLevelId,
    String classroomId,
    Photo photo, {
    String? deliveryId,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || (photo.uploadedBy != null && photo.uploadedBy != user.uid)) {
        return const Result.failure('Sign in as the original photo owner');
      }
      final classroom = _photoClassroom(schoolId, yearLevelId, classroomId, deliveryId);
      final ref = classroom.collection('photos').doc(photo.id);
      final saved = photo.copyWith(uploadedBy: user.uid);

      await _firestore.runTransaction<void>((transaction) async {
        final existing = await transaction.get(ref);
        if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
          throw StateError('The authenticated user changed');
        }
        if (existing.exists) {
          final data = existing.data()!;
          if (data['storagePath'] != saved.storagePath ||
              data['uploadedBy'] != saved.uploadedBy) {
            throw StateError('Photo ID already belongs to other evidence');
          }
          return;
        }

        transaction.set(ref, saved.toJson());
        transaction.update(classroom, {
          'lastUpdatedBy': user.displayName ?? user.email?.split('@').first ?? 'Unknown',
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });
      }, timeout: const Duration(seconds: 30));
      return Result.success(saved);
    } on FirebaseException catch (error) {
      return Result.failure('Could not sync photo', error);
    } catch (_) {
      return const Result.failure('Could not sync photo');
    }
  }

  @override
  Future<Result<void>> deleteClassroomPhoto(String schoolId, String yearLevelId,
      String classroomId, String photoId, {String? deliveryId}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return const Result.failure('Sign in to remove the photo');

      final classroom =
          _photoClassroom(schoolId, yearLevelId, classroomId, deliveryId);
      final batch = _firestore.batch();
      // Signed snapshots can still reference the original Storage object.
      batch.delete(classroom.collection('photos').doc(photoId));
      batch.update(classroom, {
        'lastUpdatedBy':
            user.displayName ?? user.email?.split('@').first ?? 'Unknown',
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();

      return const Result.success(null);
    } on FirebaseException catch (error) {
      return Result.failure(
        'Could not remove the photo from the classroom',
        error,
      );
    }
  }

  // Pack Totals
  @override
  Stream<PackTotal?> watchLatestPackTotal(
      String schoolId, String yearLevelId, String classroomId) {
    return _recordsFor(schoolId)
        .collection('yearLevels')
        .doc(yearLevelId)
        .collection('classrooms')
        .doc(classroomId)
        .collection('packTotals')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      return PackTotal.fromJson({
        'id': doc.id,
        ...doc.data(),
      });
    });
  }

  @override
  Future<Result<PackTotal>> updatePackTotal(String schoolId, String yearLevelId,
      String classroomId, PackTotal packTotal) async {
    try {
      final docRef = await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('packTotals')
          .add(packTotal.toJson());
      final created = packTotal.copyWith(id: docRef.id);

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);


      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to update pack total: $e');
    }
  }

  // Consumables
  @override
  Stream<List<Consumable>> watchConsumables(String schoolId) {
    return _recordsFor(schoolId)
        .collection('consumables')
        .orderBy('itemName')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        // Remove any stored 'id' field to avoid conflicts
        data.remove('id');

        return Consumable.fromJson({
          'id': doc.id,
          ...data,
        });
      }).toList();
    });
  }

  @override
  Future<Result<Consumable>> createConsumable(
      String schoolId, Consumable consumable) async {
    try {
      // Don't include the id field when creating a new document
      final json = consumable.toJson();
      json.remove('id');

      final docRef = await _recordsFor(schoolId)
          .collection('consumables')
          .add(json);
      final created = consumable.copyWith(id: docRef.id);


      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create consumable: $e');
    }
  }

  @override
  Future<Result<Consumable>> updateConsumable(
      String schoolId, Consumable consumable) async {
    try {
      if (consumable.id.isEmpty) {
        return const Result.failure('Cannot update consumable: ID is empty');
      }

      // Don't include the id field in the update data
      final json = consumable.toJson();
      json.remove('id');

      await _recordsFor(schoolId)
          .collection('consumables')
          .doc(consumable.id)
          .update(json);


      return Result.success(consumable);
    } catch (e) {
      return Result.failure('Failed to update consumable: $e');
    }
  }

  @override
  Future<Result<void>> deleteConsumable(
      String schoolId, String consumableId) async {
    try {
      await _recordsFor(schoolId)
          .collection('consumables')
          .doc(consumableId)
          .delete();


      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete consumable: $e');
    }
  }

  // Classroom Consumables
  @override
  Stream<List<Consumable>> watchClassroomConsumables(
      String schoolId, String yearLevelId, String classroomId) {
    return _recordsFor(schoolId)
        .collection('yearLevels')
        .doc(yearLevelId)
        .collection('classrooms')
        .doc(classroomId)
        .collection('consumables')
        .orderBy('itemName')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data.remove('id');

        return Consumable.fromJson({
          'id': doc.id,
          ...data,
        });
      }).toList();
    });
  }

  @override
  Future<Result<Consumable>> createClassroomConsumable(String schoolId,
      String yearLevelId, String classroomId, Consumable consumable) async {
    try {
      final data = consumable.toJson();
      data.remove('id');

      final docRef = await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('consumables')
          .add(data);
      final created = consumable.copyWith(id: docRef.id);

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);


      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create classroom consumable: $e');
    }
  }

  @override
  Future<Result<Consumable>> updateClassroomConsumable(String schoolId,
      String yearLevelId, String classroomId, Consumable consumable) async {
    try {
      if (consumable.id.isEmpty) {
        return const Result.failure('Cannot update consumable: ID is empty');
      }

      // Don't include the id field in the update data
      final json = consumable.toJson();
      json.remove('id');

      await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('consumables')
          .doc(consumable.id)
          .update(json);

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);


      return Result.success(consumable);
    } catch (e) {
      return Result.failure('Failed to update classroom consumable: $e');
    }
  }

  @override
  Future<Result<void>> deleteClassroomConsumable(String schoolId,
      String yearLevelId, String classroomId, String consumableId) async {
    try {
      await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('consumables')
          .doc(consumableId)
          .delete();

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);


      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete classroom consumable: $e');
    }
  }

  // Sign-off
  @override
  Future<SignOffSnapshot> readSignOffDraft(
    String schoolId, {
    required bool server,
    String? deliveryId,
  }) {
    return readSignOffSnapshot(
      _firestore.collection('schools').doc(schoolId),
      server ? Source.server : Source.cache,
      workspace: deliveryId == null
          ? null
          : _firestore.doc(DeliveryVisit(deliveryId: deliveryId, schoolId: schoolId).workspacePath),
    );
  }

  @override
  Stream<SignedEvidence?> watchSignedEvidence(String schoolId, String? deliveryId) {
    final school = _firestore.collection('schools').doc(schoolId);
    return school
        .collection('signoffPointers')
        .doc(SignedEvidence.scopeKey(deliveryId))
        .snapshots()
        .asyncMap((pointer) async {
      final evidenceId = pointer.data()?['evidenceId'] as String?;
      if (evidenceId == null) return null;
      final ref = school.collection('signoffs').doc(evidenceId);
      final evidence = await ref.get();
      final data = evidence.data();
      if (data == null) throw StateError('Signed evidence unavailable');
      return SignedEvidence.fromDocument(data);
    });
  }

  @override
  Future<List<SignedEvidence>> readSignOffHistory(String schoolId, String? deliveryId) async {
    final history = _firestore.collection('schools').doc(schoolId).collection('signoffs');
    final query = deliveryId == null
        ? history.where('deliveryId', isNull: true)
        : history.where('deliveryId', isEqualTo: deliveryId);
    final snapshot = await query.orderBy('capturedAt', descending: true).limit(25).get();
    return snapshot.docs.map((doc) => SignedEvidence.fromDocument(doc.data())).toList();
  }

  @override
  Future<void> persistQueuedSignOff(
    EvidenceUpload item, {
    required void Function() requireOwner,
  }) async {
    final signed = SignedEvidence.fromUpload(item);
    final school = _firestore.collection('schools').doc(signed.schoolId);
    final evidence = school.collection('signoffs').doc(signed.id);
    final pointer = school.collection('signoffPointers')
        .doc(SignedEvidence.scopeKey(signed.deliveryId));
    requireOwner();
    await _firestore.runTransaction<void>((transaction) async {
      requireOwner();
      final existing = await transaction.get(evidence);
      requireOwner();
      if (existing.exists) {
        final previous = SignedEvidence.fromDocument(existing.data()!);
        if (!signed.matches(previous)) {
          throw StateError('Signature ID already belongs to different evidence');
        }
        return;
      }
      final latest = await transaction.get(pointer);
      requireOwner();
      transaction.set(evidence, signed.toDocument());
      final previousTime = latest.data()?['capturedAt'] as Timestamp?;
      if (previousTime == null || !signed.capturedAt.isBefore(previousTime.toDate())) {
        transaction.set(pointer, {
          'evidenceId': signed.id,
          'deliveryId': signed.deliveryId,
          'capturedAt': Timestamp.fromDate(signed.capturedAt),
        });
      }
    }, timeout: const Duration(seconds: 30));
  }

  @override
  Stream<SignOff?> watchSignOff(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('meta')
        .doc('signoff')
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return null;
      return SignOff.fromJson(snapshot.data()!);
    });
  }

  // Contacts
  @override
  Stream<List<Contact>> watchContacts(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('contacts')
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Contact.fromJson({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();
    });
  }

  @override
  Future<Result<Contact>> createContact(
      String schoolId, Contact contact) async {
    try {
      final docRef = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('contacts')
          .add(contact.toJson());
      final created = contact.copyWith(id: docRef.id);
      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create contact: $e');
    }
  }

  @override
  Future<Result<Contact>> updateContact(
      String schoolId, Contact contact) async {
    try {
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('contacts')
          .doc(contact.id)
          .update(contact.toJson());
      return Result.success(contact);
    } catch (e) {
      return Result.failure('Failed to update contact: $e');
    }
  }

  @override
  Future<Result<void>> deleteContact(String schoolId, String contactId) async {
    try {
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('contacts')
          .doc(contactId)
          .delete();
      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete contact: $e');
    }
  }

  // Maps
  @override
  Stream<List<MapAsset>> watchMapAssets(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('maps')
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MapAsset.fromJson({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();
    });
  }

  @override
  Future<Result<MapAsset>> createMapAsset(
      String schoolId, MapAsset mapAsset) async {
    try {
      final docRef = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('maps')
          .add(mapAsset.toJson());
      final created = mapAsset.copyWith(id: docRef.id);
      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create map asset: $e');
    }
  }

  @override
  Future<Result<void>> deleteMapAsset(
      String schoolId, String mapAssetId) async {
    try {
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('maps')
          .doc(mapAssetId)
          .delete();
      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete map asset: $e');
    }
  }

  // Notes
  @override
  Stream<List<Note>> watchNotes(String schoolId) {
    return _recordsFor(schoolId)
        .collection('notes')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Note.fromJson({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();
    });
  }

  @override
  Future<Result<Note>> createNote(String schoolId, Note note) async {
    try {
      final docRef = await _recordsFor(schoolId)
          .collection('notes')
          .add(note.toJson());
      final created = note.copyWith(id: docRef.id);


      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create note: $e');
    }
  }

  @override
  Future<Result<void>> deleteNote(String schoolId, String noteId) async {
    try {
      await _recordsFor(schoolId)
          .collection('notes')
          .doc(noteId)
          .delete();


      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete note: $e');
    }
  }

  // Classroom Notes
  @override
  Stream<List<Note>> watchClassroomNotes(
      String schoolId, String yearLevelId, String classroomId) {
    return _recordsFor(schoolId)
        .collection('yearLevels')
        .doc(yearLevelId)
        .collection('classrooms')
        .doc(classroomId)
        .collection('notes')
        .snapshots()
        .map((snapshot) {
      final notes = snapshot.docs.map((doc) {
        final data = doc.data();
        data.remove('id');

        return Note.fromJson({
          'id': doc.id,
          ...data,
        });
      }).toList();

      // Sort by createdAt in memory instead of using Firestore orderBy
      // This avoids needing a Firestore index
      notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return notes;
    });
  }

  @override
  Future<Result<Note>> createClassroomNote(
      String schoolId, String yearLevelId, String classroomId, Note note) async {
    try {
      final json = note.toJson();
      json.remove('id');

      final docRef = await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('notes')
          .add(json);
      final created = note.copyWith(id: docRef.id);

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);


      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create classroom note: $e');
    }
  }

  @override
  Future<Result<Note>> updateClassroomNote(
      String schoolId, String yearLevelId, String classroomId, Note note) async {
    try {
      if (note.id.isEmpty) {
        return const Result.failure('Cannot update note: ID is empty');
      }

      final json = note.toJson();
      json.remove('id');

      await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('notes')
          .doc(note.id)
          .update(json);

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);


      return Result.success(note);
    } catch (e) {
      return Result.failure('Failed to update classroom note: $e');
    }
  }

  @override
  Future<Result<void>> deleteClassroomNote(
      String schoolId, String yearLevelId, String classroomId, String noteId) async {
    try {
      await _recordsFor(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('notes')
          .doc(noteId)
          .delete();

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);


      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete classroom note: $e');
    }
  }

  // Signed School Summaries
  @override
  Future<Result<SignedSchoolSummary?>> getSignedSchoolSummary(String schoolId) async {
    try {
      final doc = await _firestore.collection('signed_school_summaries').doc(schoolId).get();
      final data = doc.data();
      return Result.success(data == null
          ? null
          : SignedSchoolSummary.fromJson({...data, 'id': doc.id}));
    } on FirebaseException catch (error) {
      return Result.failure('Could not load the earlier signed summary', error);
    } catch (_) {
      return const Result.failure('Could not read the earlier signed summary');
    }
  }

  @override
  Future<Result<BulkImportSummary>> bulkImportClassrooms(
      String schoolId, List<YearLevelImportData> yearLevels) async {
    try {
      int yearLevelsCreated = 0;
      int classroomsCreated = 0;
      int consumablesCreated = 0;
      int packsAllocated = 0;

      // PASS 1: Create all year levels first and build a lookup map
      // This ensures composite class breakdowns can reference year levels
      // that appear later in the import order
      final Map<String, String> yearLevelIdMap = {};

      for (final yearLevelData in yearLevels) {
        final yearLevelQuery = await _recordsFor(schoolId)
            .collection('yearLevels')
            .where('label', isEqualTo: yearLevelData.label)
            .limit(1)
            .get();

        if (yearLevelQuery.docs.isEmpty) {
          final yearLevel = YearLevel(
            id: '',
            label: yearLevelData.label,
            createdAt: DateTime.now(),
          );

          final json = yearLevel.toJson();
          json.remove('id');

          final docRef = await _recordsFor(schoolId)
              .collection('yearLevels')
              .add(json);

          yearLevelIdMap[yearLevelData.label] = docRef.id;
          yearLevelsCreated++;
        } else {
          yearLevelIdMap[yearLevelData.label] = yearLevelQuery.docs.first.id;
        }
      }

      // Collect all breakdown labels that might reference year levels not in import
      final allBreakdownLabels = <String>{};
      for (final yearLevelData in yearLevels) {
        for (final classroom in yearLevelData.classrooms) {
          for (final breakdown in classroom.studentBreakdowns) {
            allBreakdownLabels.add(breakdown.yearLevelLabel);
          }
        }
      }

      // Pre-fetch any year levels referenced in breakdowns but not in import
      for (final label in allBreakdownLabels) {
        if (!yearLevelIdMap.containsKey(label)) {
          final query = await _recordsFor(schoolId)
              .collection('yearLevels')
              .where('label', isEqualTo: label)
              .limit(1)
              .get();

          if (query.docs.isNotEmpty) {
            yearLevelIdMap[label] = query.docs.first.id;
          }
        }
      }

      // PASS 2: Create classrooms and their related data
      for (final yearLevelData in yearLevels) {
        final yearLevelId = yearLevelIdMap[yearLevelData.label]!;

        for (final classroomData in yearLevelData.classrooms) {
          // Check if classroom already exists
          final classroomQuery = await _recordsFor(schoolId)
              .collection('yearLevels')
              .doc(yearLevelId)
              .collection('classrooms')
              .where('name', isEqualTo: classroomData.name)
              .limit(1)
              .get();

          String classroomId;

          if (classroomQuery.docs.isEmpty) {
            final classroom = Classroom(
              id: '',
              name: classroomData.name,
              createdAt: DateTime.now(),
            );

            final json = classroom.toJson();
            json.remove('id');

            final docRef = await _recordsFor(schoolId)
                .collection('yearLevels')
                .doc(yearLevelId)
                .collection('classrooms')
                .add(json);

            classroomId = docRef.id;
            classroomsCreated++;
          } else {
            classroomId = classroomQuery.docs.first.id;
          }

          // Set pack total
          if (classroomData.packs > 0) {
            final packTotal = PackTotal(
              id: '',
              total: classroomData.packs,
              createdAt: DateTime.now(),
            );

            final json = packTotal.toJson();
            json.remove('id');

            await _recordsFor(schoolId)
                .collection('yearLevels')
                .doc(yearLevelId)
                .collection('classrooms')
                .doc(classroomId)
                .collection('packTotals')
                .add(json);

            packsAllocated += classroomData.packs;
          }

          // Create year level breakdowns for composite classes
          for (final studentBreakdown in classroomData.studentBreakdowns) {
            // Use the pre-built map to get yearLevelId
            final breakdownYearLevelId =
                yearLevelIdMap[studentBreakdown.yearLevelLabel] ?? '';

            final breakdown = YearLevelBreakdown(
              id: '',
              yearLevelId: breakdownYearLevelId,
              yearLevelLabel: studentBreakdown.yearLevelLabel,
              studentCount: studentBreakdown.studentCount,
              createdAt: DateTime.now(),
            );

            final json = breakdown.toJson();
            json.remove('id');

            await _recordsFor(schoolId)
                .collection('yearLevels')
                .doc(yearLevelId)
                .collection('classrooms')
                .doc(classroomId)
                .collection('yearLevelBreakdowns')
                .add(json);
          }

          // Create consumables for this classroom
          for (final consumableData in classroomData.consumables) {
            final consumableQuery = await _recordsFor(schoolId)
                .collection('yearLevels')
                .doc(yearLevelId)
                .collection('classrooms')
                .doc(classroomId)
                .collection('consumables')
                .where('itemName', isEqualTo: consumableData.itemName)
                .limit(1)
                .get();

            if (consumableQuery.docs.isEmpty) {
              final consumable = Consumable(
                id: '',
                itemName: consumableData.itemName,
                quantity: consumableData.quantity,
                unit: consumableData.unit,
                createdAt: DateTime.now(),
              );

              final json = consumable.toJson();
              json.remove('id');

              await _recordsFor(schoolId)
                  .collection('yearLevels')
                  .doc(yearLevelId)
                  .collection('classrooms')
                  .doc(classroomId)
                  .collection('consumables')
                  .add(json);

              consumablesCreated++;
            } else {
              final existingDoc = consumableQuery.docs.first;
              final existingData = existingDoc.data();
              final existingQuantity = existingData['quantity'] as int? ?? 0;

              await existingDoc.reference.update({
                'quantity': existingQuantity + consumableData.quantity,
              });
            }
          }
        }
      }


      return Result.success(BulkImportSummary(
        yearLevelsCreated: yearLevelsCreated,
        classroomsCreated: classroomsCreated,
        consumablesCreated: consumablesCreated,
        packsAllocated: packsAllocated,
      ));
    } catch (e) {
      return Result.failure('Failed to import classrooms: $e');
    }
  }

  // School Timers
  @override
  Stream<SchoolTimer?> watchActiveTimer(String schoolId) {
    return _recordsFor(schoolId)
        .collection('timers')
        .doc('active')
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }
      final data = snapshot.data()!;
      // Check if timer is actually active
      if (data['isActive'] != true) {
        return null;
      }
      return SchoolTimer.fromJson({
        ...data,
        'id': _timerSessionId(data),
      });
    });
  }

  @override
  Stream<List<SchoolTimer>> watchTimerHistory(String schoolId, {int limit = 20}) {
    return _recordsFor(schoolId)
        .collection('timers')
        .doc('active')
        .collection('history')
        .orderBy('stoppedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data.remove('id');
        return SchoolTimer.fromJson({
          'id': doc.id,
          ...data,
        });
      }).toList();
    });
  }

  String _timerSessionId(Map<String, dynamic> data) {
    final session = data['sessionId'];
    if (session is String && session.isNotEmpty) return session;
    final startedAt = data['startedAt'] as Timestamp;
    return 'legacy-${startedAt.seconds}-${startedAt.nanoseconds}';
  }

  @override
  Future<Result<SchoolTimer>> startTimer(
    String schoolId,
    SchoolTimer timer,
  ) async {
    final ref = _recordsFor(schoolId)
        .collection('timers').doc('active');
    try {
      return await _firestore.runTransaction((transaction) async {
        final data = (await transaction.get(ref)).data();
        if (data?['isActive'] == true) {
          if (_timerSessionId(data!) == timer.id) return Result.success(timer);
          return const Result.failure('A timer is already running for this school');
        }
        final history = await transaction.get(ref.collection('history').doc(timer.id));
        if (history.exists) {
          return const Result.failure('This timer has already finished');
        }
        transaction.set(ref, timer.toJson()
          ..remove('id')
          ..['sessionId'] = timer.id
          ..['startedAt'] = FieldValue.serverTimestamp()
          ..['createdAt'] = FieldValue.serverTimestamp());
        return Result.success(timer);
      });
    } catch (e) {
      return Result.failure('Failed to start timer: $e');
    }
  }

  @override
  Future<Result<void>> stopTimer(
    String schoolId,
    String timerId,
    String stoppedByUid,
    String stoppedByName,
  ) async {
    final ref = _recordsFor(schoolId)
        .collection('timers').doc('active');
    final history = ref.collection('history').doc(timerId);
    final stoppedAt = FieldValue.serverTimestamp();
    try {
      return await _firestore.runTransaction((transaction) async {
        final data = (await transaction.get(ref)).data();
        if (data == null || data['isActive'] != true || _timerSessionId(data) != timerId) {
          if ((await transaction.get(history)).exists) return const Result.success(null);
          return const Result.failure('That timer is no longer active');
        }

        final changes = {
          'sessionId': timerId,
          'isActive': false,
          'stoppedAt': stoppedAt,
          'stoppedByUid': stoppedByUid,
          'stoppedByName': stoppedByName,
        };
        transaction.set(history, {...data, ...changes});
        transaction.update(ref, changes);
        return const Result.success(null);
      });
    } catch (e) {
      return Result.failure('Failed to stop timer: $e');
    }
  }

  // Timer History CRUD (admin only)
  @override
  Future<Result<void>> createTimerHistoryEntry(String schoolId, SchoolTimer timer) async {
    try {
      final data = timer.toJson();
      data.remove('id');

      await _recordsFor(schoolId)
          .collection('timers')
          .doc('active')
          .collection('history')
          .doc(timer.id.isEmpty ? null : timer.id)
          .set(data);

      debugPrint('Timer history entry created for school $schoolId');
      return const Result.success(null);
    } catch (e) {
      debugPrint('Error creating timer history entry: $e');
      return Result.failure('Failed to create timer entry: $e');
    }
  }

  @override
  Future<Result<void>> updateTimerHistoryEntry(String schoolId, SchoolTimer timer) async {
    try {
      final data = timer.toJson();
      data.remove('id');

      await _recordsFor(schoolId)
          .collection('timers')
          .doc('active')
          .collection('history')
          .doc(timer.id)
          .update(data);

      debugPrint('Timer history entry updated for school $schoolId');
      return const Result.success(null);
    } catch (e) {
      debugPrint('Error updating timer history entry: $e');
      return Result.failure('Failed to update timer entry: $e');
    }
  }

  @override
  Future<Result<void>> deleteTimerHistoryEntry(String schoolId, String timerId) async {
    try {
      await _recordsFor(schoolId)
          .collection('timers')
          .doc('active')
          .collection('history')
          .doc(timerId)
          .delete();

      debugPrint('Timer history entry deleted for school $schoolId');
      return const Result.success(null);
    } catch (e) {
      debugPrint('Error deleting timer history entry: $e');
      return Result.failure('Failed to delete timer entry: $e');
    }
  }
}
