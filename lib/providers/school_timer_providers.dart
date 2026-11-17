import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/school_timer.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';

/// Watches the active timer for a school.
/// Uses autoDispose to stop listening when user leaves the page.
final activeSchoolTimerProvider =
    StreamProvider.autoDispose.family<SchoolTimer?, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchActiveTimer(schoolId);
}, dependencies: [schoolsRepositoryProvider]);

/// Watches timer history for a school.
/// Uses autoDispose to stop listening when user leaves the page.
final schoolTimerHistoryProvider = StreamProvider.autoDispose
    .family<List<SchoolTimer>, String>((ref, schoolId) {
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  return schoolsRepository.watchTimerHistory(schoolId);
}, dependencies: [schoolsRepositoryProvider]);

/// Provider for checking if user can control timers (managers/admins only)
final canControlTimerProvider = Provider<bool>((ref) {
  final isAdmin = ref.watch(isAdminProvider);
  final isManager = ref.watch(isManagerProvider);
  return isAdmin || isManager;
});

/// Notifier for timer actions (start/stop)
class SchoolTimerNotifier extends StateNotifier<AsyncValue<void>> {
  SchoolTimerNotifier(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;
  final _uuid = const Uuid();

  Future<bool> startTimer(String schoolId) async {
    final canControl = _ref.read(canControlTimerProvider);
    if (!canControl) {
      state = AsyncValue.error(
        'Only managers and admins can start timers',
        StackTrace.current,
      );
      return false;
    }

    final staffAsync = _ref.read(currentStaffProvider);
    final staff = staffAsync.valueOrNull;
    if (staff == null) {
      state = AsyncValue.error(
        'Could not identify current user',
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncValue.loading();

    final timer = SchoolTimer(
      id: _uuid.v4(),
      schoolId: schoolId,
      startedAt: DateTime.now(),
      startedByUid: staff.id,
      startedByName: staff.name,
      createdAt: DateTime.now(),
    );

    final repository = _ref.read(schoolsRepositoryProvider);
    final result = await repository.startTimer(schoolId, timer);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, _) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> stopTimer(String schoolId, String timerId) async {
    final canControl = _ref.read(canControlTimerProvider);
    if (!canControl) {
      state = AsyncValue.error(
        'Only managers and admins can stop timers',
        StackTrace.current,
      );
      return false;
    }

    final staffAsync = _ref.read(currentStaffProvider);
    final staff = staffAsync.valueOrNull;
    if (staff == null) {
      state = AsyncValue.error(
        'Could not identify current user',
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncValue.loading();

    final repository = _ref.read(schoolsRepositoryProvider);
    final result = await repository.stopTimer(
      schoolId,
      timerId,
      staff.id,
      staff.name,
    );

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, _) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  // Timer History CRUD (admin only)
  Future<bool> createTimerEntry(
    String schoolId,
    DateTime startedAt,
    DateTime stoppedAt,
  ) async {
    final isAdmin = _ref.read(isAdminProvider);
    if (!isAdmin) {
      state = AsyncValue.error(
        'Only admins can create timer entries',
        StackTrace.current,
      );
      return false;
    }

    final staffAsync = _ref.read(currentStaffProvider);
    final staff = staffAsync.valueOrNull;
    if (staff == null) {
      state = AsyncValue.error(
        'Could not identify current user',
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncValue.loading();

    final timer = SchoolTimer(
      id: _uuid.v4(),
      schoolId: schoolId,
      startedAt: startedAt,
      stoppedAt: stoppedAt,
      startedByUid: staff.id,
      startedByName: staff.name,
      stoppedByUid: staff.id,
      stoppedByName: staff.name,
      isActive: false,
      createdAt: DateTime.now(),
    );

    final repository = _ref.read(schoolsRepositoryProvider);
    final result = await repository.createTimerHistoryEntry(schoolId, timer);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, _) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> updateTimerEntry(
    String schoolId,
    SchoolTimer timer,
    DateTime newStartedAt,
    DateTime newStoppedAt,
  ) async {
    final isAdmin = _ref.read(isAdminProvider);
    if (!isAdmin) {
      state = AsyncValue.error(
        'Only admins can edit timer entries',
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncValue.loading();

    final updatedTimer = timer.copyWith(
      startedAt: newStartedAt,
      stoppedAt: newStoppedAt,
    );

    final repository = _ref.read(schoolsRepositoryProvider);
    final result =
        await repository.updateTimerHistoryEntry(schoolId, updatedTimer);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, _) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteTimerEntry(String schoolId, String timerId) async {
    final isAdmin = _ref.read(isAdminProvider);
    if (!isAdmin) {
      state = AsyncValue.error(
        'Only admins can delete timer entries',
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncValue.loading();

    final repository = _ref.read(schoolsRepositoryProvider);
    final result = await repository.deleteTimerHistoryEntry(schoolId, timerId);

    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, _) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }
}

final schoolTimerNotifierProvider =
    StateNotifierProvider<SchoolTimerNotifier, AsyncValue<void>>((ref) {
  return SchoolTimerNotifier(ref);
}, dependencies: [schoolsRepositoryProvider]);
