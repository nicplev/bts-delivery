import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/school.dart';
import '../../repositories/schools_repository.dart';
import 'repository_providers.dart';
import 'auth_providers.dart';

final schoolsProvider = StreamProvider<List<School>>((ref) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  final currentStaffAsync = ref.watch(currentStaffProvider);
  final isAdmin = ref.watch(isAdminProvider);

  return currentStaffAsync.when(
    loading: () => const Stream.empty(),
    error: (error, _) => Stream.error(error),
    data: (currentStaff) {
      // Admins and Managers can see all schools
      if (isAdmin || (currentStaff?.hasManagerAccess ?? false)) {
        return schoolsRepository.watchSchools();
      }

      // If user is not linked to staff, return empty
      if (currentStaff == null) {
        return Stream.value(<School>[]);
      }

      // Regular staff only see their assigned schools
      if (currentStaff.assignedSchoolIds.isEmpty) {
        return Stream.value(<School>[]);
      }

      // Filter schools by assigned IDs
      return schoolsRepository.watchSchools().map((schools) {
        return schools.where((school) =>
          currentStaff.assignedSchoolIds.contains(school.id)
        ).toList();
      });
    },
  );
});

final yearLevelsProvider =
    StreamProvider.family<List<YearLevel>, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchYearLevels(schoolId);
});

final classroomsProvider = StreamProvider.family<List<Classroom>,
    ({String schoolId, String yearLevelId})>((ref, params) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchClassrooms(params.schoolId, params.yearLevelId);
});

final classroomPhotosProvider = StreamProvider.family<List<Photo>,
    ({String schoolId, String yearLevelId, String classroomId})>((ref, params) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchClassroomPhotos(
      params.schoolId, params.yearLevelId, params.classroomId);
});

final packTotalProvider = StreamProvider.family<PackTotal?,
    ({String schoolId, String yearLevelId, String classroomId})>((ref, params) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchLatestPackTotal(
      params.schoolId, params.yearLevelId, params.classroomId);
});

final consumablesProvider =
    StreamProvider.family<List<Consumable>, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchConsumables(schoolId);
});

final classroomConsumablesProvider = StreamProvider.family<List<Consumable>,
    ({String schoolId, String yearLevelId, String classroomId})>((ref, params) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchClassroomConsumables(
    params.schoolId,
    params.yearLevelId,
    params.classroomId,
  );
});

final signOffProvider =
    StreamProvider.family<SignOff?, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchSignOff(schoolId);
});

final contactsProvider =
    StreamProvider.family<List<Contact>, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchContacts(schoolId);
});

final mapAssetsProvider =
    StreamProvider.family<List<MapAsset>, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchMapAssets(schoolId);
});

final notesProvider =
    StreamProvider.family<List<Note>, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchNotes(schoolId);
});

final classroomNotesProvider = StreamProvider.family<List<Note>,
    ({String schoolId, String yearLevelId, String classroomId})>((ref, params) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchClassroomNotes(
    params.schoolId,
    params.yearLevelId,
    params.classroomId,
  );
});

final yearLevelBreakdownsProvider = StreamProvider.family<List<YearLevelBreakdown>,
    ({String schoolId, String yearLevelId, String classroomId})>((ref, params) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchYearLevelBreakdowns(
    params.schoolId,
    params.yearLevelId,
    params.classroomId,
  );
});

// Provider for aggregated classroom totals
final classroomTotalsProvider =
    FutureProvider.family<Map<String, int>, String>((ref, schoolId) async {
  // Get all year levels for this school
  final yearLevelsAsync = await ref.watch(yearLevelsProvider(schoolId).future);

  Map<String, int> totals = {};

  // For each year level, get classrooms and their pack totals
  for (final yearLevel in yearLevelsAsync) {
    final classroomsAsync = await ref.watch(
        classroomsProvider((schoolId: schoolId, yearLevelId: yearLevel.id))
            .future);

    int yearLevelTotal = 0;
    for (final classroom in classroomsAsync) {
      try {
        final packTotal = await ref.watch(packTotalProvider((
          schoolId: schoolId,
          yearLevelId: yearLevel.id,
          classroomId: classroom.id
        )).future);
        yearLevelTotal += packTotal?.total ?? 0;
      } catch (e) {
        // If pack total fails, just continue
        continue;
      }
    }

    totals[yearLevel.id] = yearLevelTotal;
  }

  return totals;
});

// Provider for school-wide total
final schoolTotalProvider =
    FutureProvider.family<int, String>((ref, schoolId) async {
  final totals = await ref.watch(classroomTotalsProvider(schoolId).future);
  return totals.values.fold<int>(0, (sum, value) => sum + value);
});

// Provider for year level consumables totals
// Returns a map of item names to their total quantities
final yearLevelConsumablesTotalsProvider = FutureProvider.family<
    Map<String, ({int quantity, String unit})>,
    ({String schoolId, String yearLevelId})>((ref, params) async {

  // Get all classrooms for this year level
  final classrooms = await ref.watch(
    classroomsProvider((
      schoolId: params.schoolId,
      yearLevelId: params.yearLevelId,
    )).future,
  );

  Map<String, ({int quantity, String unit})> totals = {};

  // For each classroom, get its consumables and aggregate
  for (final classroom in classrooms) {
    try {
      final consumables = await ref.watch(
        classroomConsumablesProvider((
          schoolId: params.schoolId,
          yearLevelId: params.yearLevelId,
          classroomId: classroom.id,
        )).future,
      );

      for (final consumable in consumables) {
        final existing = totals[consumable.itemName];
        if (existing != null) {
          // If item already exists, add to quantity (assuming same unit)
          totals[consumable.itemName] = (
            quantity: existing.quantity + consumable.quantity,
            unit: consumable.unit,
          );
        } else {
          totals[consumable.itemName] = (
            quantity: consumable.quantity,
            unit: consumable.unit,
          );
        }
      }
    } catch (e) {
      // If loading consumables fails, just continue
      continue;
    }
  }

  return totals;
});

// Provider for school-wide consumables totals
// Returns a map of item names to their total quantities
final schoolConsumablesTotalsProvider = FutureProvider.family<
    Map<String, ({int quantity, String unit})>,
    String>((ref, schoolId) async {

  // Get all year levels for this school
  final yearLevels = await ref.watch(yearLevelsProvider(schoolId).future);

  Map<String, ({int quantity, String unit})> totals = {};

  // For each year level, get its consumables totals and aggregate
  for (final yearLevel in yearLevels) {
    try {
      final yearLevelTotals = await ref.watch(
        yearLevelConsumablesTotalsProvider((
          schoolId: schoolId,
          yearLevelId: yearLevel.id,
        )).future,
      );

      for (final entry in yearLevelTotals.entries) {
        final itemName = entry.key;
        final itemData = entry.value;

        final existing = totals[itemName];
        if (existing != null) {
          totals[itemName] = (
            quantity: existing.quantity + itemData.quantity,
            unit: itemData.unit,
          );
        } else {
          totals[itemName] = itemData;
        }
      }
    } catch (e) {
      // If loading year level totals fails, just continue
      continue;
    }
  }

  return totals;
});

class SchoolsNotifier extends StateNotifier<AsyncValue<void>> {
  SchoolsNotifier(this._schoolsRepository) : super(const AsyncValue.data(null));

  final SchoolsRepository _schoolsRepository;

  Future<bool> updateSchool(School school) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.updateSchool(school);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> createYearLevel(String schoolId, YearLevel yearLevel) async {
    state = const AsyncValue.loading();
    final result =
        await _schoolsRepository.createYearLevel(schoolId, yearLevel);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> updateYearLevel(String schoolId, YearLevel yearLevel) async {
    state = const AsyncValue.loading();
    final result =
        await _schoolsRepository.updateYearLevel(schoolId, yearLevel);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteYearLevel(String schoolId, String yearLevelId) async {
    state = const AsyncValue.loading();
    final result =
        await _schoolsRepository.deleteYearLevel(schoolId, yearLevelId);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> createClassroom(
      String schoolId, String yearLevelId, Classroom classroom) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.createClassroom(
        schoolId, yearLevelId, classroom);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> updateClassroom(
      String schoolId, String yearLevelId, Classroom classroom) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.updateClassroom(
        schoolId, yearLevelId, classroom);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteClassroom(
      String schoolId, String yearLevelId, String classroomId) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.deleteClassroom(
        schoolId, yearLevelId, classroomId);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> addClassroomPhoto(String schoolId, String yearLevelId,
      String classroomId, Photo photo) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.addClassroomPhoto(
        schoolId, yearLevelId, classroomId, photo);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteClassroomPhoto(String schoolId, String yearLevelId,
      String classroomId, String photoId) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.deleteClassroomPhoto(
        schoolId, yearLevelId, classroomId, photoId);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> updatePackTotal(String schoolId, String yearLevelId,
      String classroomId, PackTotal packTotal) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.updatePackTotal(
        schoolId, yearLevelId, classroomId, packTotal);

    return result.when(
      success: (_) async {
        // Clear sign-off when pack totals change
        await _schoolsRepository.clearSignOff(schoolId);
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> createConsumable(String schoolId, Consumable consumable) async {
    state = const AsyncValue.loading();
    final result =
        await _schoolsRepository.createConsumable(schoolId, consumable);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> updateConsumable(String schoolId, Consumable consumable) async {
    state = const AsyncValue.loading();
    final result =
        await _schoolsRepository.updateConsumable(schoolId, consumable);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteConsumable(String schoolId, String consumableId) async {
    state = const AsyncValue.loading();
    final result =
        await _schoolsRepository.deleteConsumable(schoolId, consumableId);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> createClassroomConsumable(String schoolId, String yearLevelId, String classroomId, Consumable consumable) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.createClassroomConsumable(
        schoolId, yearLevelId, classroomId, consumable);

    return result.when(
      success: (_) async {
        // Clear sign-off when consumables change
        await _schoolsRepository.clearSignOff(schoolId);
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> updateClassroomConsumable(String schoolId, String yearLevelId, String classroomId, Consumable consumable) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.updateClassroomConsumable(
        schoolId, yearLevelId, classroomId, consumable);

    return result.when(
      success: (_) async {
        // Clear sign-off when consumables change
        await _schoolsRepository.clearSignOff(schoolId);
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteClassroomConsumable(String schoolId, String yearLevelId, String classroomId, String consumableId) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.deleteClassroomConsumable(
        schoolId, yearLevelId, classroomId, consumableId);

    return result.when(
      success: (_) async {
        // Clear sign-off when consumables change
        await _schoolsRepository.clearSignOff(schoolId);
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> createOrUpdateSignOff(String schoolId, SignOff signOff) async {
    state = const AsyncValue.loading();
    final result =
        await _schoolsRepository.createOrUpdateSignOff(schoolId, signOff);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> createContact(String schoolId, Contact contact) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.createContact(schoolId, contact);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> updateContact(String schoolId, Contact contact) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.updateContact(schoolId, contact);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteContact(String schoolId, String contactId) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.deleteContact(schoolId, contactId);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> createMapAsset(String schoolId, MapAsset mapAsset) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.createMapAsset(schoolId, mapAsset);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteMapAsset(String schoolId, String mapAssetId) async {
    state = const AsyncValue.loading();
    final result =
        await _schoolsRepository.deleteMapAsset(schoolId, mapAssetId);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> createNote(String schoolId, Note note) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.createNote(schoolId, note);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteNote(String schoolId, String noteId) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.deleteNote(schoolId, noteId);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  // Classroom Notes Methods
  Future<bool> createClassroomNote(
      String schoolId, String yearLevelId, String classroomId, Note note) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.createClassroomNote(
        schoolId, yearLevelId, classroomId, note);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> updateClassroomNote(
      String schoolId, String yearLevelId, String classroomId, Note note) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.updateClassroomNote(
        schoolId, yearLevelId, classroomId, note);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteClassroomNote(
      String schoolId, String yearLevelId, String classroomId, String noteId) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.deleteClassroomNote(
        schoolId, yearLevelId, classroomId, noteId);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> createSignedSchoolSummary(String schoolId, String signedBy, String? signatureUrl) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.createSignedSchoolSummary(
      schoolId,
      signedBy,
      signatureUrl,
    );

    return result.when(
      success: (_) {
        debugPrint('✓ Sign-off summary created successfully');
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        debugPrint('✗ ERROR in createSignedSchoolSummary provider: $message');
        debugPrint('Exception: $exception');
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  // Year Level Breakdown Methods
  Future<bool> createYearLevelBreakdown(
      String schoolId,
      String yearLevelId,
      String classroomId,
      YearLevelBreakdown breakdown) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.createYearLevelBreakdown(
        schoolId, yearLevelId, classroomId, breakdown);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> updateYearLevelBreakdown(
      String schoolId,
      String yearLevelId,
      String classroomId,
      YearLevelBreakdown breakdown) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.updateYearLevelBreakdown(
        schoolId, yearLevelId, classroomId, breakdown);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteYearLevelBreakdown(String schoolId, String yearLevelId,
      String classroomId, String breakdownId) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.deleteYearLevelBreakdown(
        schoolId, yearLevelId, classroomId, breakdownId);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }
}

final schoolsNotifierProvider =
    StateNotifierProvider<SchoolsNotifier, AsyncValue<void>>((ref) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return SchoolsNotifier(schoolsRepository);
});
