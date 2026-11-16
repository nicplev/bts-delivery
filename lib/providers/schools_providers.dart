import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/school.dart';
import '../models/delivery_visit.dart';
import '../repositories/schools_repository.dart';
import '../repositories/classroom_edit.dart';
import '../services/result.dart';
import 'repository_providers.dart';
import 'delivery_visit_provider.dart';
import 'auth_providers.dart';

final schoolsProvider = StreamProvider.autoDispose<List<School>>((ref) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  if (ref.watch(isAdminProvider)) return schoolsRepository.watchSchools();

  return ref.watch(currentStaffProvider).when(
        loading: () => const Stream.empty(),
        error: Stream.error,
        data: (staff) {
          if (staff == null) return Stream.value(const <School>[]);
          return schoolsRepository.watchSchools(
            schoolIds: staff.hasManagerAccess ? null : staff.assignedSchoolIds,
          );
        },
      );
}, dependencies: [schoolsRepositoryProvider]);

final schoolByIdProvider = StreamProvider.autoDispose.family<School?, String>(
  (ref, schoolId) {
    final repository = ref.watch(schoolsRepositoryProvider);
    Stream<School?> watchSchool() => repository.watchSchools(
        schoolIds: [schoolId]).map((schools) => schools.firstOrNull);

    if (ref.watch(isAdminProvider)) return watchSchool();

    return ref.watch(currentStaffProvider).when(
          loading: () => const Stream.empty(),
          error: Stream.error,
          data: (staff) {
            final canAccess = staff != null &&
                (staff.hasManagerAccess ||
                    staff.assignedSchoolIds.contains(schoolId));
            return canAccess ? watchSchool() : Stream.value(null);
          },
        );
  },
  dependencies: [schoolsRepositoryProvider],
);

final yearLevelsProvider =
    StreamProvider.autoDispose.family<List<YearLevel>, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchYearLevels(schoolId);
}, dependencies: [schoolsRepositoryProvider]);

final classroomsProvider = StreamProvider.autoDispose
    .family<List<Classroom>, ({String schoolId, String yearLevelId})>(
        (ref, params) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchClassrooms(params.schoolId, params.yearLevelId);
}, dependencies: [schoolsRepositoryProvider]);

final classroomPhotosProvider = StreamProvider.autoDispose.family<
    List<Photo>,
    ({
      String schoolId,
      String yearLevelId,
      String classroomId,
      String? deliveryId
    })>(
  (ref, params) {
    final schoolsRepository = ref.watch(baseSchoolsRepositoryProvider);
    return schoolsRepository.watchClassroomPhotos(
      params.schoolId,
      params.yearLevelId,
      params.classroomId,
      deliveryId: params.deliveryId,
    );
  },
  dependencies: [schoolsRepositoryProvider],
);

final packTotalProvider = StreamProvider.autoDispose.family<PackTotal?,
    ({String schoolId, String yearLevelId, String classroomId})>((ref, params) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchLatestPackTotal(
      params.schoolId, params.yearLevelId, params.classroomId);
}, dependencies: [schoolsRepositoryProvider]);

final consumablesProvider = StreamProvider.autoDispose
    .family<List<Consumable>, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchConsumables(schoolId);
}, dependencies: [schoolsRepositoryProvider]);

final classroomConsumablesProvider = StreamProvider.autoDispose.family<
    List<Consumable>,
    ({String schoolId, String yearLevelId, String classroomId})>((ref, params) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchClassroomConsumables(
    params.schoolId,
    params.yearLevelId,
    params.classroomId,
  );
}, dependencies: [schoolsRepositoryProvider]);

final signOffProvider =
    StreamProvider.autoDispose.family<SignOff?, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchSignOff(schoolId);
}, dependencies: [schoolsRepositoryProvider]);

final contactsProvider =
    StreamProvider.autoDispose.family<List<Contact>, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchContacts(schoolId);
}, dependencies: [schoolsRepositoryProvider]);

final mapAssetsProvider =
    StreamProvider.autoDispose.family<List<MapAsset>, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchMapAssets(schoolId);
}, dependencies: [schoolsRepositoryProvider]);

final notesProvider =
    StreamProvider.autoDispose.family<List<Note>, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchNotes(schoolId);
}, dependencies: [schoolsRepositoryProvider]);

final classroomNotesProvider = StreamProvider.autoDispose.family<List<Note>,
    ({String schoolId, String yearLevelId, String classroomId})>((ref, params) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchClassroomNotes(
    params.schoolId,
    params.yearLevelId,
    params.classroomId,
  );
}, dependencies: [schoolsRepositoryProvider]);

final yearLevelBreakdownsProvider = StreamProvider.autoDispose.family<
    List<YearLevelBreakdown>,
    ({String schoolId, String yearLevelId, String classroomId})>((ref, params) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchYearLevelBreakdowns(
    params.schoolId,
    params.yearLevelId,
    params.classroomId,
  );
}, dependencies: [schoolsRepositoryProvider]);

final classroomTotalsProvider =
    FutureProvider.autoDispose.family<Map<String, int>, String>(
  (ref, schoolId) async {
    final yearLevels = await ref.watch(yearLevelsProvider(schoolId).future);
    final totals = await Future.wait([
      for (final level in yearLevels)
        ref.watch(_yearLevelPackTotalProvider(
            (schoolId: schoolId, yearLevelId: level.id)).future),
    ], eagerError: true);
    return {
      for (var index = 0; index < yearLevels.length; index++)
        yearLevels[index].id: totals[index],
    };
  },
  dependencies: [yearLevelsProvider, _yearLevelPackTotalProvider],
);

final _yearLevelPackTotalProvider = FutureProvider.autoDispose
    .family<int, ({String schoolId, String yearLevelId})>((ref, params) async {
  final classrooms = await ref.watch(classroomsProvider(params).future);
  final packTotals = await Future.wait([
    for (final classroom in classrooms)
      ref.watch(packTotalProvider((
        schoolId: params.schoolId,
        yearLevelId: params.yearLevelId,
        classroomId: classroom.id,
      )).future),
  ], eagerError: true);
  return packTotals.fold<int>(
      0, (sum, packTotal) => sum + (packTotal?.total ?? 0));
}, dependencies: [classroomsProvider, packTotalProvider]);

final schoolTotalProvider =
    FutureProvider.autoDispose.family<int, String>((ref, schoolId) async {
  final totals = await ref.watch(classroomTotalsProvider(schoolId).future);
  return totals.values.fold<int>(0, (sum, value) => sum + value);
}, dependencies: [classroomTotalsProvider]);

final yearLevelConsumablesTotalsProvider = FutureProvider.autoDispose.family<
    Map<String, ({int quantity, String unit})>,
    ({String schoolId, String yearLevelId})>((ref, params) async {
  final classrooms = await ref.watch(classroomsProvider(params).future);
  final classroomConsumables = await Future.wait([
    for (final classroom in classrooms)
      ref.watch(classroomConsumablesProvider((
        schoolId: params.schoolId,
        yearLevelId: params.yearLevelId,
        classroomId: classroom.id,
      )).future),
  ], eagerError: true);
  return _sumConsumables([
    for (final items in classroomConsumables)
      for (final item in items)
        (name: item.itemName, quantity: item.quantity, unit: item.unit),
  ]);
}, dependencies: [classroomsProvider, classroomConsumablesProvider]);

final schoolConsumablesTotalsProvider = FutureProvider.autoDispose
    .family<Map<String, ({int quantity, String unit})>, String>(
        (ref, schoolId) async {
  final yearLevels = await ref.watch(yearLevelsProvider(schoolId).future);
  final levelTotals = await Future.wait([
    for (final level in yearLevels)
      ref.watch(
        yearLevelConsumablesTotalsProvider((
          schoolId: schoolId,
          yearLevelId: level.id,
        )).future,
      ),
  ], eagerError: true);
  return _sumConsumables([
    for (final totals in levelTotals)
      for (final entry in totals.entries)
        (
          name: entry.key,
          quantity: entry.value.quantity,
          unit: entry.value.unit
        ),
  ]);
}, dependencies: [yearLevelsProvider, yearLevelConsumablesTotalsProvider]);

Map<String, ({int quantity, String unit})> _sumConsumables(
  Iterable<({String name, int quantity, String unit})> items,
) {
  final totals = <String, ({int quantity, String unit})>{};
  for (final item in items) {
    final existing = totals[item.name];
    if (existing != null &&
        existing.unit.trim().toLowerCase() != item.unit.trim().toLowerCase()) {
      throw StateError('Consumable "${item.name}" uses incompatible units');
    }
    totals[item.name] = (
      quantity: (existing?.quantity ?? 0) + item.quantity,
      unit: item.unit,
    );
  }
  return totals;
}

typedef ClassroomLocation = ({
  String schoolId,
  String yearLevelId,
  String classroomId,
  DeliveryVisit? visit,
});

final classroomEditFailuresProvider =
    StateNotifierProvider<ClassroomEditFailures, List<ClassroomLocation>>(
        (ref) {
  // A previous account's pending writes must never surface in a new session.
  ref.watch(authStateProvider.select((auth) => auth.valueOrNull?.uid));
  return ClassroomEditFailures();
});

class ClassroomEditFailures extends StateNotifier<List<ClassroomLocation>> {
  ClassroomEditFailures() : super(const []);

  void record(ClassroomLocation location) {
    if (mounted && !state.contains(location)) state = [...state, location];
  }

  void dismiss(ClassroomLocation location) {
    state = state.where((entry) => entry != location).toList();
  }
}

class SchoolsNotifier extends StateNotifier<AsyncValue<void>> {
  SchoolsNotifier(this._schoolsRepository, this._ref)
      : super(const AsyncValue.data(null));

  final SchoolsRepository _schoolsRepository;
  final Ref _ref;

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

  Future<Result<ClassroomEditStatus>> updateClassroomName(
    String schoolId,
    String yearLevelId,
    String classroomId, {
    required String name,
  }) {
    return _trackClassroomEdit(
      (
        schoolId: schoolId,
        yearLevelId: yearLevelId,
        classroomId: classroomId,
        visit: _ref.read(activeDeliveryVisitProvider),
      ),
      (updatedBy) => _schoolsRepository.updateClassroomName(
        schoolId,
        yearLevelId,
        classroomId,
        name: name,
        updatedBy: updatedBy,
      ),
    );
  }

  Future<Result<ClassroomEditStatus>> updateClassroomStatus(
    String schoolId,
    String yearLevelId,
    String classroomId, {
    required ClassroomCompletionStatus status,
    required int? actualPacksDelivered,
  }) {
    return _trackClassroomEdit(
      (
        schoolId: schoolId,
        yearLevelId: yearLevelId,
        classroomId: classroomId,
        visit: _ref.read(activeDeliveryVisitProvider),
      ),
      (updatedBy) => _schoolsRepository.updateClassroomStatus(
        schoolId,
        yearLevelId,
        classroomId,
        status: status,
        actualPacksDelivered: actualPacksDelivered,
        updatedBy: updatedBy,
      ),
    );
  }

  Future<Result<ClassroomEditStatus>> _trackClassroomEdit(
    ClassroomLocation location,
    Future<Result<ClassroomEditReceipt>> Function(String updatedBy) submit,
  ) async {
    final staff = _ref.read(currentStaffProvider).valueOrNull;
    if (staff == null) {
      return const Result.failure('Link your staff account before editing.');
    }
    final failures = _ref.read(classroomEditFailuresProvider.notifier);
    final result = await submit(staff.name);
    return result.when(
      success: (receipt) {
        unawaited(receipt.acknowledgment.then((acknowledgment) {
          if (acknowledgment.isFailure) failures.record(location);
        }));
        return Result.success(receipt.status);
      },
      failure: (message, exception) {
        failures.record(location);
        return Result.failure(message, exception);
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

  Future<bool> deleteClassroomPhoto(
      String schoolId, String yearLevelId, String classroomId, String photoId,
      {String? deliveryId}) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.deleteClassroomPhoto(
        schoolId, yearLevelId, classroomId, photoId,
        deliveryId: deliveryId);

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

  Future<bool> createClassroomConsumable(String schoolId, String yearLevelId,
      String classroomId, Consumable consumable) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.createClassroomConsumable(
        schoolId, yearLevelId, classroomId, consumable);

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

  Future<bool> updateClassroomConsumable(String schoolId, String yearLevelId,
      String classroomId, Consumable consumable) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.updateClassroomConsumable(
        schoolId, yearLevelId, classroomId, consumable);

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

  Future<bool> deleteClassroomConsumable(String schoolId, String yearLevelId,
      String classroomId, String consumableId) async {
    state = const AsyncValue.loading();
    final result = await _schoolsRepository.deleteClassroomConsumable(
        schoolId, yearLevelId, classroomId, consumableId);

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
  Future<bool> createClassroomNote(String schoolId, String yearLevelId,
      String classroomId, Note note) async {
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

  Future<bool> updateClassroomNote(String schoolId, String yearLevelId,
      String classroomId, Note note) async {
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

  Future<bool> deleteClassroomNote(String schoolId, String yearLevelId,
      String classroomId, String noteId) async {
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

  // Year Level Breakdown Methods
  Future<bool> createYearLevelBreakdown(String schoolId, String yearLevelId,
      String classroomId, YearLevelBreakdown breakdown) async {
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

  Future<bool> updateYearLevelBreakdown(String schoolId, String yearLevelId,
      String classroomId, YearLevelBreakdown breakdown) async {
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
  return SchoolsNotifier(schoolsRepository, ref);
}, dependencies: [schoolsRepositoryProvider, activeDeliveryVisitProvider]);
