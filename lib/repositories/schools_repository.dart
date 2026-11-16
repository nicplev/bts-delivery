import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/result.dart';
import '../models/school.dart';
import '../models/school_timer.dart';
import 'storage_repository.dart';

abstract class SchoolsRepository {
  Stream<List<School>> watchSchools();
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
  Future<Result<Classroom>> updateClassroom(
      String schoolId, String yearLevelId, Classroom classroom);
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
      String schoolId, String yearLevelId, String classroomId);
  Future<Result<Photo>> addClassroomPhoto(
      String schoolId, String yearLevelId, String classroomId, Photo photo);
  Future<Result<void>> deleteClassroomPhoto(
      String schoolId, String yearLevelId, String classroomId, String photoId);

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
  Stream<SignOff?> watchSignOff(String schoolId);
  Future<Result<SignOff>> createOrUpdateSignOff(
      String schoolId, SignOff signOff);
  Future<Result<void>> clearSignOff(String schoolId);

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
  Future<Result<SignedSchoolSummary>> createSignedSchoolSummary(
      String schoolId, String signedBy, String? signatureUrl);
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
  final StorageRepository _storageRepository;

  FirebaseSchoolsRepository(this._storageRepository);

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

      await _firestore
          .collection('schools')
          .doc(schoolId)
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
  Stream<List<School>> watchSchools() {
    return _firestore
        .collection('schools')
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        // Remove any id field from data to prevent overwriting
        data.remove('id');

        return School.fromJson({
          'id': doc.id,
          ...data,
        });
      }).toList();
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
    return _firestore
        .collection('schools')
        .doc(schoolId)
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

      final docRef = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .add(data);
      final created = yearLevel.copyWith(id: docRef.id);

      // Clear sign-off since structure changed
      await _clearSignOffOnDataChange(schoolId);

      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create year level: $e');
    }
  }

  @override
  Future<Result<YearLevel>> updateYearLevel(
      String schoolId, YearLevel yearLevel) async {
    try {
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevel.id)
          .update(yearLevel.toJson());

      // Clear sign-off since structure changed
      await _clearSignOffOnDataChange(schoolId);

      return Result.success(yearLevel);
    } catch (e) {
      return Result.failure('Failed to update year level: $e');
    }
  }

  @override
  Future<Result<void>> deleteYearLevel(
      String schoolId, String yearLevelId) async {
    try {
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .delete();

      // Clear sign-off since structure changed
      await _clearSignOffOnDataChange(schoolId);

      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete year level: $e');
    }
  }

  // Classrooms
  @override
  Stream<List<Classroom>> watchClassrooms(String schoolId, String yearLevelId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
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

      final docRef = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .add(data);
      final created = classroom.copyWith(id: docRef.id);

      // Clear sign-off since classroom structure changed
      await _clearSignOffOnDataChange(schoolId);

      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create classroom: $e');
    }
  }

  @override
  Future<Result<Classroom>> updateClassroom(
      String schoolId, String yearLevelId, Classroom classroom) async {
    try {
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroom.id)
          .update(classroom.toJson());

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroom.id);

      // Clear sign-off since classroom data changed
      await _clearSignOffOnDataChange(schoolId);

      return Result.success(classroom);
    } catch (e) {
      return Result.failure('Failed to update classroom: $e');
    }
  }

  @override
  Future<Result<void>> deleteClassroom(
      String schoolId, String yearLevelId, String classroomId) async {
    try {
      debugPrint(
          'Deleting classroom: schoolId=$schoolId, yearLevelId=$yearLevelId, classroomId=$classroomId');
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .delete();
      debugPrint('Classroom deleted successfully');

      // Clear sign-off since classroom structure changed
      await _clearSignOffOnDataChange(schoolId);

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
    return _firestore
        .collection('schools')
        .doc(schoolId)
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

      final docRef = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('yearLevelBreakdowns')
          .add(data);
      final created = breakdown.copyWith(id: docRef.id);

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);

      // Clear sign-off since classroom data changed
      await _clearSignOffOnDataChange(schoolId);

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
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('yearLevelBreakdowns')
          .doc(breakdown.id)
          .update(breakdown.toJson());

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);

      // Clear sign-off since classroom data changed
      await _clearSignOffOnDataChange(schoolId);

      return Result.success(breakdown);
    } catch (e) {
      return Result.failure('Failed to update year level breakdown: $e');
    }
  }

  @override
  Future<Result<void>> deleteYearLevelBreakdown(String schoolId,
      String yearLevelId, String classroomId, String breakdownId) async {
    try {
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('yearLevelBreakdowns')
          .doc(breakdownId)
          .delete();

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);

      // Clear sign-off since classroom data changed
      await _clearSignOffOnDataChange(schoolId);

      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete year level breakdown: $e');
    }
  }

  // Photos
  @override
  Stream<List<Photo>> watchClassroomPhotos(
      String schoolId, String yearLevelId, String classroomId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('yearLevels')
        .doc(yearLevelId)
        .collection('classrooms')
        .doc(classroomId)
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
  Future<Result<Photo>> addClassroomPhoto(String schoolId, String yearLevelId,
      String classroomId, Photo photo) async {
    try {
      final docRef = _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('photos')
          .doc(photo.id);

      await docRef.set(photo.copyWith(id: docRef.id).toJson());
      final created = photo.copyWith(id: docRef.id);

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);

      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to add photo: $e');
    }
  }

  @override
  Future<Result<void>> deleteClassroomPhoto(String schoolId, String yearLevelId,
      String classroomId, String photoId) async {
    try {
      // First, get the photo document to retrieve the storage path
      final photoDoc = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('photos')
          .doc(photoId)
          .get();

      if (!photoDoc.exists) {
        return const Result.failure('Photo not found');
      }

      final photoData = photoDoc.data();
      if (photoData == null) {
        return const Result.failure('Photo data is null');
      }

      // Get the storage path from the photo document
      final storagePath = photoData['storagePath'] as String?;

      // Delete the file from Firebase Storage if storagePath exists
      if (storagePath != null && storagePath.isNotEmpty) {
        final storageResult = await _storageRepository.deleteFile(storagePath);
        if (!storageResult.isSuccess) {
          debugPrint('Warning: Failed to delete file from storage: ${storageResult.errorOrNull}');
          // Continue to delete Firestore document even if storage deletion fails
        }
      }

      // Delete the Firestore document
      await photoDoc.reference.delete();

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);

      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete photo: $e');
    }
  }

  // Pack Totals
  @override
  Stream<PackTotal?> watchLatestPackTotal(
      String schoolId, String yearLevelId, String classroomId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
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
      final docRef = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('packTotals')
          .add(packTotal.toJson());
      final created = packTotal.copyWith(id: docRef.id);

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);

      // Clear sign-off since pack totals changed
      await _clearSignOffOnDataChange(schoolId);

      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to update pack total: $e');
    }
  }

  // Consumables
  @override
  Stream<List<Consumable>> watchConsumables(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
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

      final docRef = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('consumables')
          .add(json);
      final created = consumable.copyWith(id: docRef.id);

      // Clear sign-off since consumables changed
      await _clearSignOffOnDataChange(schoolId);

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

      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('consumables')
          .doc(consumable.id)
          .update(json);

      // Clear sign-off since consumables changed
      await _clearSignOffOnDataChange(schoolId);

      return Result.success(consumable);
    } catch (e) {
      return Result.failure('Failed to update consumable: $e');
    }
  }

  @override
  Future<Result<void>> deleteConsumable(
      String schoolId, String consumableId) async {
    try {
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('consumables')
          .doc(consumableId)
          .delete();

      // Clear sign-off since consumables changed
      await _clearSignOffOnDataChange(schoolId);

      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete consumable: $e');
    }
  }

  // Classroom Consumables
  @override
  Stream<List<Consumable>> watchClassroomConsumables(
      String schoolId, String yearLevelId, String classroomId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
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

      final docRef = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('consumables')
          .add(data);
      final created = consumable.copyWith(id: docRef.id);

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);

      // Clear sign-off since classroom consumables changed
      await _clearSignOffOnDataChange(schoolId);

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

      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('consumables')
          .doc(consumable.id)
          .update(json);

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);

      // Clear sign-off since classroom consumables changed
      await _clearSignOffOnDataChange(schoolId);

      return Result.success(consumable);
    } catch (e) {
      return Result.failure('Failed to update classroom consumable: $e');
    }
  }

  @override
  Future<Result<void>> deleteClassroomConsumable(String schoolId,
      String yearLevelId, String classroomId, String consumableId) async {
    try {
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('consumables')
          .doc(consumableId)
          .delete();

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);

      // Clear sign-off since classroom consumables changed
      await _clearSignOffOnDataChange(schoolId);

      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete classroom consumable: $e');
    }
  }

  // Sign-off
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

  @override
  Future<Result<SignOff>> createOrUpdateSignOff(
      String schoolId, SignOff signOff) async {
    try {
      debugPrint('Saving sign-off for school: $schoolId');
      debugPrint('Sign-off data: ${signOff.toJson()}');

      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('meta')
          .doc('signoff')
          .set(signOff.toJson());

      debugPrint('Sign-off saved successfully');
      return Result.success(signOff);
    } catch (e) {
      debugPrint('Error saving sign-off: $e');
      return Result.failure('Failed to save sign-off: $e');
    }
  }

  @override
  Future<Result<void>> clearSignOff(String schoolId) async {
    try {
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('meta')
          .doc('signoff')
          .delete();
      return const Result.success(null);
    } catch (e) {
      // If document doesn't exist, that's fine
      return const Result.success(null);
    }
  }

  /// Helper method to clear sign-off when data changes
  /// This should be called whenever pack totals, consumables, or structure changes
  /// Returns true if a sign-off was cleared, false if there was no sign-off to clear
  Future<bool> _clearSignOffOnDataChange(String schoolId) async {
    try {
      // Check if sign-off exists before trying to delete
      final signOffDoc = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('meta')
          .doc('signoff')
          .get();

      if (!signOffDoc.exists) {
        // No sign-off to clear
        return false;
      }

      // Delete the sign-off document
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('meta')
          .doc('signoff')
          .delete();

      // Update school document to mark as not signed off
      await _firestore.collection('schools').doc(schoolId).update({
        'isSignedOff': false,
        'lastSignOffDate': null,
        'signedBy': null,
      });

      debugPrint('Sign-off cleared for school $schoolId due to data changes');
      return true;
    } catch (e) {
      // If sign-off doesn't exist, that's fine - no need to clear it
      debugPrint('Note: Could not clear sign-off (may not exist): $e');
      return false;
    }
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
    return _firestore
        .collection('schools')
        .doc(schoolId)
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
      final docRef = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('notes')
          .add(note.toJson());
      final created = note.copyWith(id: docRef.id);

      // Clear sign-off since notes changed
      await _clearSignOffOnDataChange(schoolId);

      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create note: $e');
    }
  }

  @override
  Future<Result<void>> deleteNote(String schoolId, String noteId) async {
    try {
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('notes')
          .doc(noteId)
          .delete();

      // Clear sign-off since notes changed
      await _clearSignOffOnDataChange(schoolId);

      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete note: $e');
    }
  }

  // Classroom Notes
  @override
  Stream<List<Note>> watchClassroomNotes(
      String schoolId, String yearLevelId, String classroomId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
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

      final docRef = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('notes')
          .add(json);
      final created = note.copyWith(id: docRef.id);

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);

      // Clear sign-off since classroom notes changed
      await _clearSignOffOnDataChange(schoolId);

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

      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('notes')
          .doc(note.id)
          .update(json);

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);

      // Clear sign-off since classroom notes changed
      await _clearSignOffOnDataChange(schoolId);

      return Result.success(note);
    } catch (e) {
      return Result.failure('Failed to update classroom note: $e');
    }
  }

  @override
  Future<Result<void>> deleteClassroomNote(
      String schoolId, String yearLevelId, String classroomId, String noteId) async {
    try {
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .doc(yearLevelId)
          .collection('classrooms')
          .doc(classroomId)
          .collection('notes')
          .doc(noteId)
          .delete();

      // Update classroom's last modified metadata
      await _updateClassroomLastModified(schoolId, yearLevelId, classroomId);

      // Clear sign-off since classroom notes changed
      await _clearSignOffOnDataChange(schoolId);

      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete classroom note: $e');
    }
  }

  // Signed School Summaries
  @override
  Future<Result<SignedSchoolSummary>> createSignedSchoolSummary(
      String schoolId, String signedBy, String? signatureUrl) async {
    try {
      debugPrint('=== Starting createSignedSchoolSummary ===');
      debugPrint('School ID: $schoolId');
      debugPrint('Signed By: $signedBy');
      debugPrint('Signature URL: $signatureUrl');

      // Get school data
      debugPrint('Step 1: Fetching school document...');
      final schoolDoc =
          await _firestore.collection('schools').doc(schoolId).get();
      if (!schoolDoc.exists) {
        final error = 'School not found: $schoolId';
        debugPrint('ERROR: $error');
        return Result.failure(error);
      }

      final schoolData = schoolDoc.data()!;
      schoolData.remove('id');
      final school = School.fromJson({'id': schoolDoc.id, ...schoolData});
      debugPrint('School loaded: ${school.name}');

      // Get all year levels
      debugPrint('Step 2: Fetching year levels...');
      final yearLevelsSnapshot = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('yearLevels')
          .orderBy('createdAt')
          .get();
      debugPrint('Found ${yearLevelsSnapshot.docs.length} year levels');

      int totalPacks = 0;
      Map<String, int> packTotalsByYearLevel = {};
      Map<String, Map<String, int>> packTotalsByClassroom = {};
      Map<String, ConsumableSummary> consumablesTotals = {};
      Map<String, Map<String, ConsumableSummary>> consumablesByYearLevel = {};
      Map<String, Map<String, Map<String, ConsumableSummary>>>
          consumablesByClassroom = {};
      Map<String, Map<String, List<String>>> notesByClassroom = {};
      List<String> photoUrls = [];
      List<String> criticalErrors = [];
      List<ClassroomDeliveryDetail> classroomDeliveryDetails = [];

      // Process each year level
      debugPrint('Step 3: Processing year levels and classrooms...');
      for (final yearLevelDoc in yearLevelsSnapshot.docs) {
        try {
          final yearLevelId = yearLevelDoc.id;
          final yearLevelData = yearLevelDoc.data();
          final yearLevelLabel =
              yearLevelData['label'] ?? yearLevelData['name'] ?? 'Unknown';
          debugPrint('  Processing year level: $yearLevelLabel (ID: $yearLevelId)');

          int yearLevelPackTotal = 0;
          Map<String, ConsumableSummary> yearLevelConsumables = {};
          Map<String, int> yearLevelClassrooms = {};
          Map<String, Map<String, ConsumableSummary>>
              yearLevelClassroomConsumables = {};

          // Get all classrooms for this year level
          final classroomsSnapshot = await _firestore
              .collection('schools')
              .doc(schoolId)
              .collection('yearLevels')
              .doc(yearLevelId)
              .collection('classrooms')
              .orderBy('createdAt')
              .get();
          debugPrint('    Found ${classroomsSnapshot.docs.length} classrooms');

          // Process each classroom
          for (final classroomDoc in classroomsSnapshot.docs) {
            try {
              final classroomId = classroomDoc.id;
              final classroomName = classroomDoc.data()['name'] ?? 'Unknown';
              debugPrint('      Processing classroom: $classroomName');

              // Get year level breakdowns for composite class support
              final breakdownsSnapshot = await _firestore
                  .collection('schools')
                  .doc(schoolId)
                  .collection('yearLevels')
                  .doc(yearLevelId)
                  .collection('classrooms')
                  .doc(classroomId)
                  .collection('yearLevelBreakdowns')
                  .get();

              // Get pack total for this classroom
              final packTotalsSnapshot = await _firestore
                  .collection('schools')
                  .doc(schoolId)
                  .collection('yearLevels')
                  .doc(yearLevelId)
                  .collection('classrooms')
                  .doc(classroomId)
                  .collection('packTotals')
                  .orderBy('createdAt', descending: true)
                  .limit(1)
                  .get();

              if (packTotalsSnapshot.docs.isNotEmpty) {
                final packTotalData = packTotalsSnapshot.docs.first.data();
                final packTotal = (packTotalData['total'] ?? 0) as int;

                // For composite classes, distribute packs proportionally across year levels
                // For now, we add the full pack total to the current year level
                // TODO: Future enhancement - proportionally distribute based on student counts
                totalPacks += packTotal;
                yearLevelPackTotal += packTotal;
                yearLevelClassrooms[classroomName] = packTotal;

                // Log if this is a composite class
                if (breakdownsSnapshot.docs.isNotEmpty) {
                  final breakdownCount = breakdownsSnapshot.docs.length;
                  debugPrint('        Pack total: $packTotal (Composite class with $breakdownCount year levels)');

                  // Log the breakdown details
                  for (final breakdownDoc in breakdownsSnapshot.docs) {
                    final breakdownData = breakdownDoc.data();
                    final breakdownLabel = breakdownData['yearLevelLabel'] ?? 'Unknown';
                    final studentCount = breakdownData['studentCount'] ?? 0;
                    debugPrint('          - $breakdownLabel: $studentCount students');
                  }
                } else {
                  debugPrint('        Pack total: $packTotal');
                }
              }

              // Get consumables for this classroom
              final consumablesSnapshot = await _firestore
                  .collection('schools')
                  .doc(schoolId)
                  .collection('yearLevels')
                  .doc(yearLevelId)
                  .collection('classrooms')
                  .doc(classroomId)
                  .collection('consumables')
                  .get();

              Map<String, ConsumableSummary> classroomConsumables = {};

              for (final consumableDoc in consumablesSnapshot.docs) {
                try {
                  final data = consumableDoc.data();
                  final itemName = (data['itemName'] ?? 'Unknown') as String;
                  final quantity = (data['quantity'] ?? 0) as int;
                  final unit = (data['unit'] ?? 'pcs') as String;

                  final summary = ConsumableSummary(
                    itemName: itemName,
                    quantity: quantity,
                    unit: unit,
                  );

                  // Add to classroom consumables
                  classroomConsumables[itemName] = summary;

                  // Add to year level totals
                  if (yearLevelConsumables.containsKey(itemName)) {
                    final existing = yearLevelConsumables[itemName]!;
                    yearLevelConsumables[itemName] = ConsumableSummary(
                      itemName: itemName,
                      quantity: existing.quantity + quantity,
                      unit: unit,
                    );
                  } else {
                    yearLevelConsumables[itemName] = summary;
                  }

                  // Add to school totals
                  if (consumablesTotals.containsKey(itemName)) {
                    final existing = consumablesTotals[itemName]!;
                    consumablesTotals[itemName] = ConsumableSummary(
                      itemName: itemName,
                      quantity: existing.quantity + quantity,
                      unit: unit,
                    );
                  } else {
                    consumablesTotals[itemName] = summary;
                  }
                } catch (e) {
                  debugPrint('        WARNING: Failed to process consumable ${consumableDoc.id}: $e');
                  // Continue with other consumables
                }
              }
              debugPrint('        Consumables: ${classroomConsumables.length} types');

              yearLevelClassroomConsumables[classroomName] = classroomConsumables;

              // Get photos for this classroom
              final photosSnapshot = await _firestore
                  .collection('schools')
                  .doc(schoolId)
                  .collection('yearLevels')
                  .doc(yearLevelId)
                  .collection('classrooms')
                  .doc(classroomId)
                  .collection('photos')
                  .get();

              for (final photoDoc in photosSnapshot.docs) {
                try {
                  final photoData = photoDoc.data();
                  final storagePath = photoData['storagePath'];
                  if (storagePath != null && storagePath is String) {
                    photoUrls.add(storagePath);
                  }
                } catch (e) {
                  debugPrint('        WARNING: Failed to process photo ${photoDoc.id}: $e');
                }
              }
              debugPrint('        Photos: ${photosSnapshot.docs.length}');

              // Get notes for this classroom
              final classroomNotesSnapshot = await _firestore
                  .collection('schools')
                  .doc(schoolId)
                  .collection('yearLevels')
                  .doc(yearLevelId)
                  .collection('classrooms')
                  .doc(classroomId)
                  .collection('notes')
                  .get();

              List<String> classroomNotesList = [];
              for (final noteDoc in classroomNotesSnapshot.docs) {
                try {
                  final noteData = noteDoc.data();
                  final content = noteData['content'];
                  final author = noteData['author'];
                  if (content != null && content is String) {
                    final noteText = author != null && author is String
                        ? '$content (by $author)'
                        : content;
                    classroomNotesList.add(noteText);
                  }
                } catch (e) {
                  debugPrint('        WARNING: Failed to process note ${noteDoc.id}: $e');
                }
              }

              if (classroomNotesList.isNotEmpty) {
                if (!notesByClassroom.containsKey(yearLevelLabel)) {
                  notesByClassroom[yearLevelLabel] = {};
                }
                notesByClassroom[yearLevelLabel]![classroomName] = classroomNotesList;
              }
              debugPrint('        Notes: ${classroomNotesList.length}');

              // Capture classroom delivery details for Excel export
              final classroomData = classroomDoc.data();
              final completionStatusString = classroomData['completionStatus'] as String?;
              final completionStatus = completionStatusString != null
                  ? ClassroomCompletionStatus.values.firstWhere(
                      (e) => e.toString() == 'ClassroomCompletionStatus.$completionStatusString',
                      orElse: () => ClassroomCompletionStatus.notAttended,
                    )
                  : ClassroomCompletionStatus.notAttended;

              final actualPacksDelivered = classroomData['actualPacksDelivered'] as int?;
              final expectedPacks = packTotalsSnapshot.docs.isNotEmpty
                  ? (packTotalsSnapshot.docs.first.data()['total'] ?? 0) as int
                  : 0;

              // Build consumable delivery details
              Map<String, ConsumableDeliveryDetail> consumableDetails = {};
              for (final consumableDoc in consumablesSnapshot.docs) {
                try {
                  final data = consumableDoc.data();
                  final itemName = (data['itemName'] ?? 'Unknown') as String;
                  final expectedQuantity = (data['quantity'] ?? 0) as int;
                  final actualQuantityDelivered = data['actualQuantityDelivered'] as int?;
                  final unit = (data['unit'] ?? 'pcs') as String;

                  consumableDetails[itemName] = ConsumableDeliveryDetail(
                    itemName: itemName,
                    expectedQuantity: expectedQuantity,
                    actualQuantityDelivered: actualQuantityDelivered,
                    unit: unit,
                  );
                } catch (e) {
                  debugPrint('        WARNING: Failed to build consumable detail: $e');
                }
              }

              // Calculate actual delivery status using same logic as sign-off tab
              ClassroomCompletionStatus actualStatus = completionStatus;

              if (completionStatus == ClassroomCompletionStatus.notAttended) {
                actualStatus = ClassroomCompletionStatus.notAttended;
              } else if (completionStatus == ClassroomCompletionStatus.complete) {
                // Check for partial pack deliveries
                final hasPartialPacks = actualPacksDelivered != null &&
                    actualPacksDelivered != expectedPacks;

                // Check for partial consumable deliveries
                final hasPartialConsumables = consumableDetails.values.any((consumable) {
                  return consumable.actualQuantityDelivered != null &&
                      consumable.actualQuantityDelivered != consumable.expectedQuantity;
                });

                // Check for unattended consumables (no actual quantity set)
                final hasUnattendedConsumables = consumableDetails.values.any((consumable) {
                  return consumable.actualQuantityDelivered == null;
                });

                // If ANY packs or consumables are incomplete or not attended, show as incomplete
                if (hasPartialPacks || hasPartialConsumables || hasUnattendedConsumables) {
                  actualStatus = ClassroomCompletionStatus.incomplete;
                } else {
                  actualStatus = ClassroomCompletionStatus.complete;
                }
              }

              // Add classroom delivery detail with calculated status
              classroomDeliveryDetails.add(ClassroomDeliveryDetail(
                yearLevel: yearLevelLabel,
                classroomName: classroomName,
                status: actualStatus,
                expectedPacks: expectedPacks,
                actualPacksDelivered: actualPacksDelivered,
                consumables: consumableDetails,
              ));
            } catch (e) {
              debugPrint('      ERROR processing classroom: $e');
              criticalErrors.add('Classroom error: $e');
              // Continue with other classrooms
            }
          }

          packTotalsByYearLevel[yearLevelLabel] = yearLevelPackTotal;
          packTotalsByClassroom[yearLevelLabel] = yearLevelClassrooms;
          consumablesByYearLevel[yearLevelLabel] = yearLevelConsumables;
          consumablesByClassroom[yearLevelLabel] = yearLevelClassroomConsumables;
          debugPrint('    Year level totals - Packs: $yearLevelPackTotal, Consumables: ${yearLevelConsumables.length} types');
        } catch (e) {
          debugPrint('  ERROR processing year level: $e');
          criticalErrors.add('Year level error: $e');
          // Continue with other year levels
        }
      }

      // Check if we had too many critical errors
      if (criticalErrors.length > 10) {
        final errorMsg = 'Too many errors during data collection (${criticalErrors.length} errors)';
        debugPrint('FATAL: $errorMsg');
        debugPrint('First 5 errors: ${criticalErrors.take(5).join(', ')}');
        return Result.failure(errorMsg);
      }

      // Get notes
      final notesSnapshot = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('notes')
          .orderBy('createdAt', descending: true)
          .get();

      String? notes;
      if (notesSnapshot.docs.isNotEmpty) {
        notes = notesSnapshot.docs
            .map((doc) => doc.data()['content'] as String)
            .join('\n\n');
      }

      // Create the summary document
      final summary = SignedSchoolSummary(
        id: '',
        schoolId: schoolId,
        schoolName: school.name,
        schoolAddress: school.address,
        signedBy: signedBy,
        signatureUrl: signatureUrl,
        signedDate: DateTime.now(),
        totalPacks: totalPacks,
        packTotalsByYearLevel: packTotalsByYearLevel,
        packTotalsByClassroom: packTotalsByClassroom,
        consumablesTotals: consumablesTotals,
        consumablesByYearLevel: consumablesByYearLevel,
        consumablesByClassroom: consumablesByClassroom,
        classroomDeliveryDetails: classroomDeliveryDetails,
        photoUrls: photoUrls,
        notes: notes,
        notesByClassroom: notesByClassroom,
        createdAt: DateTime.now(),
      );

      // Save to Firestore
      debugPrint(
          'Saving summary with $totalPacks total packs and ${consumablesTotals.length} consumable types');

      // Manually serialize nested consumables to ensure proper JSON conversion
      final Map<String, dynamic> consumablesTotalsJson = {};
      for (final entry in consumablesTotals.entries) {
        consumablesTotalsJson[entry.key] = entry.value.toJson();
      }

      final Map<String, dynamic> consumablesByYearLevelJson = {};
      for (final yearEntry in consumablesByYearLevel.entries) {
        final yearMap = <String, dynamic>{};
        for (final itemEntry in yearEntry.value.entries) {
          yearMap[itemEntry.key] = itemEntry.value.toJson();
        }
        consumablesByYearLevelJson[yearEntry.key] = yearMap;
      }

      final Map<String, dynamic> consumablesByClassroomJson = {};
      for (final yearEntry in consumablesByClassroom.entries) {
        final yearMap = <String, dynamic>{};
        for (final classEntry in yearEntry.value.entries) {
          final classMap = <String, dynamic>{};
          for (final itemEntry in classEntry.value.entries) {
            classMap[itemEntry.key] = itemEntry.value.toJson();
          }
          yearMap[classEntry.key] = classMap;
        }
        consumablesByClassroomJson[yearEntry.key] = yearMap;
      }

      // Serialize classroom delivery details with manual consumables conversion
      final List<Map<String, dynamic>> classroomDeliveryDetailsJson = [];
      for (final detail in classroomDeliveryDetails) {
        // Manually convert consumables map
        final Map<String, dynamic> consumablesJson = {};
        for (final entry in detail.consumables.entries) {
          consumablesJson[entry.key] = entry.value.toJson();
        }

        classroomDeliveryDetailsJson.add({
          'yearLevel': detail.yearLevel,
          'classroomName': detail.classroomName,
          'status': detail.status.toString().split('.').last, // Enum to string
          'expectedPacks': detail.expectedPacks,
          'actualPacksDelivered': detail.actualPacksDelivered,
          'consumables': consumablesJson,
        });
      }

      final data = {
        'schoolId': schoolId,
        'schoolName': school.name,
        'schoolAddress': school.address,
        'signedBy': signedBy,
        'signatureUrl': signatureUrl,
        'signedDate': Timestamp.fromDate(DateTime.now()),
        'totalPacks': totalPacks,
        'packTotalsByYearLevel': packTotalsByYearLevel,
        'packTotalsByClassroom': packTotalsByClassroom,
        'consumablesTotals': consumablesTotalsJson,
        'consumablesByYearLevel': consumablesByYearLevelJson,
        'consumablesByClassroom': consumablesByClassroomJson,
        'classroomDeliveryDetails': classroomDeliveryDetailsJson,
        'photoUrls': photoUrls,
        'notes': notes,
        'notesByClassroom': notesByClassroom,
        'createdAt': Timestamp.fromDate(DateTime.now()),
      };

      debugPrint('Summary data prepared, saving to Firestore...');
      debugPrint('Total packs: $totalPacks, Consumable types: ${consumablesTotals.length}, Photos: ${photoUrls.length}');
      if (criticalErrors.isNotEmpty) {
        debugPrint('WARNING: ${criticalErrors.length} non-fatal errors occurred during data collection');
      }

      // Use schoolId as the document ID so each school only has one summary
      // This prevents creating multiple similar documents
      try {
        await _firestore
            .collection('signed_school_summaries')
            .doc(schoolId)
            .set(data);
        debugPrint('✓ Summary saved successfully to Firestore with ID: $schoolId');
      } catch (e) {
        final errorMsg = 'Failed to write to Firestore: $e';
        debugPrint('✗ FIRESTORE ERROR: $errorMsg');
        return Result.failure(errorMsg);
      }
      final created = summary.copyWith(id: schoolId);
      return Result.success(created);
    } catch (e) {
      debugPrint('Error creating signed school summary: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      return Result.failure('Failed to create signed school summary: $e');
    }
  }

  @override
  Future<Result<SignedSchoolSummary?>> getSignedSchoolSummary(String schoolId) async {
    try {
      debugPrint('Fetching signed school summary for: $schoolId');
      final doc = await _firestore
          .collection('signed_school_summaries')
          .doc(schoolId)
          .get();

      if (!doc.exists) {
        debugPrint('No signed summary found for school: $schoolId');
        return const Result.success(null);
      }

      final data = doc.data();
      if (data == null) {
        debugPrint('Document exists but has no data for school: $schoolId');
        return const Result.success(null);
      }

      final summary = SignedSchoolSummary.fromJson({'id': doc.id, ...data});
      debugPrint('Successfully fetched signed summary');
      return Result.success(summary);
    } catch (e) {
      debugPrint('Error fetching signed school summary: $e');
      return Result.failure('Failed to fetch signed school summary: $e');
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
        final yearLevelQuery = await _firestore
            .collection('schools')
            .doc(schoolId)
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

          final docRef = await _firestore
              .collection('schools')
              .doc(schoolId)
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
          final query = await _firestore
              .collection('schools')
              .doc(schoolId)
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
          final classroomQuery = await _firestore
              .collection('schools')
              .doc(schoolId)
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

            final docRef = await _firestore
                .collection('schools')
                .doc(schoolId)
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

            await _firestore
                .collection('schools')
                .doc(schoolId)
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

            await _firestore
                .collection('schools')
                .doc(schoolId)
                .collection('yearLevels')
                .doc(yearLevelId)
                .collection('classrooms')
                .doc(classroomId)
                .collection('yearLevelBreakdowns')
                .add(json);
          }

          // Create consumables for this classroom
          for (final consumableData in classroomData.consumables) {
            final consumableQuery = await _firestore
                .collection('schools')
                .doc(schoolId)
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

              await _firestore
                  .collection('schools')
                  .doc(schoolId)
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

      // Clear sign-off since bulk data was imported
      await _clearSignOffOnDataChange(schoolId);

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
    return _firestore
        .collection('schools')
        .doc(schoolId)
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
        'id': snapshot.id,
        ...data,
      });
    });
  }

  @override
  Stream<List<SchoolTimer>> watchTimerHistory(String schoolId, {int limit = 20}) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
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

  @override
  Future<Result<SchoolTimer>> startTimer(String schoolId, SchoolTimer timer) async {
    try {
      // Check if there's already an active timer
      final activeDoc = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('timers')
          .doc('active')
          .get();

      if (activeDoc.exists && activeDoc.data()?['isActive'] == true) {
        return const Result.failure('A timer is already running for this school');
      }

      // Create the timer document
      final data = timer.toJson();
      data.remove('id');

      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('timers')
          .doc('active')
          .set(data);

      final created = timer.copyWith(id: 'active');
      debugPrint('Timer started for school $schoolId by ${timer.startedByName}');
      return Result.success(created);
    } catch (e) {
      debugPrint('Error starting timer: $e');
      return Result.failure('Failed to start timer: $e');
    }
  }

  @override
  Future<Result<void>> stopTimer(
      String schoolId, String timerId, String stoppedByUid, String stoppedByName) async {
    try {
      final activeDoc = await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('timers')
          .doc('active')
          .get();

      if (!activeDoc.exists || activeDoc.data()?['isActive'] != true) {
        return const Result.failure('No active timer found');
      }

      final activeData = activeDoc.data()!;
      final stoppedAt = DateTime.now();

      // Move to history with stopped info
      final historyData = {
        ...activeData,
        'isActive': false,
        'stoppedAt': Timestamp.fromDate(stoppedAt),
        'stoppedByUid': stoppedByUid,
        'stoppedByName': stoppedByName,
      };

      // Use a batch to ensure atomicity
      final batch = _firestore.batch();

      // Add to history subcollection
      final historyRef = _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('timers')
          .doc('active')
          .collection('history')
          .doc();
      batch.set(historyRef, historyData);

      // Clear the active timer (set isActive to false)
      batch.update(activeDoc.reference, {
        'isActive': false,
        'stoppedAt': Timestamp.fromDate(stoppedAt),
        'stoppedByUid': stoppedByUid,
        'stoppedByName': stoppedByName,
      });

      await batch.commit();

      debugPrint('Timer stopped for school $schoolId by $stoppedByName');
      return const Result.success(null);
    } catch (e) {
      debugPrint('Error stopping timer: $e');
      return Result.failure('Failed to stop timer: $e');
    }
  }

  // Timer History CRUD (admin only)
  @override
  Future<Result<void>> createTimerHistoryEntry(String schoolId, SchoolTimer timer) async {
    try {
      final data = timer.toJson();
      data.remove('id');

      await _firestore
          .collection('schools')
          .doc(schoolId)
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

      await _firestore
          .collection('schools')
          .doc(schoolId)
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
      await _firestore
          .collection('schools')
          .doc(schoolId)
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
