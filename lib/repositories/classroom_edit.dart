import 'dart:async';

import '../models/school.dart';
import '../services/result.dart';

class ClassroomEdit {
  ClassroomEdit.rename(String name) : fields = {'name': name.trim()} {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'A classroom name is required');
    }
  }

  ClassroomEdit.status(ClassroomCompletionStatus status, int? actualPacks)
      : fields = {
          'completionStatus': status.name,
          'actualPacksDelivered': actualPacks,
        } {
    final incomplete = status == ClassroomCompletionStatus.incomplete;
    if (incomplete
        ? actualPacks == null || actualPacks < 0
        : actualPacks != null) {
      throw ArgumentError.value(
          actualPacks, 'actualPacks', 'Invalid pack count for status');
    }
  }

  final Map<String, Object?> fields;
}

enum ClassroomEditStatus { saved, pending, unconfirmed }

typedef ClassroomEditReceipt = ({
  ClassroomEditStatus status,
  Future<Result<void>> acknowledgment,
});

/// A matching local mutation confirms that this edit reached the Firestore
/// write queue. The write future separately reports server acknowledgment.
Future<Result<ClassroomEditReceipt>> observeClassroomEdit({
  required String editId,
  required Stream<String?> pendingEditIds,
  required Future<void> Function() write,
  Duration confirmationTimeout = const Duration(seconds: 5),
}) async {
  final locallySaved = Completer<void>();
  final subscription = pendingEditIds.listen(
    (pendingId) {
      if (pendingId == editId && !locallySaved.isCompleted) {
        locallySaved.complete();
      }
    },
    onError: (Object _) {
      // The write future can still report a server result when a read fails.
    },
  );
  final acknowledgment = Future.sync(write).then<Result<void>>(
    (_) => const Result.success(null),
    onError: (Object error, StackTrace _) => Result.failure(
      'The classroom edit was rejected.',
      error is Exception ? error : null,
    ),
  );

  Result<ClassroomEditReceipt> receipt(ClassroomEditStatus status) =>
      Result.success((status: status, acknowledgment: acknowledgment));

  try {
    return await Future.any([
      locallySaved.future.then((_) => receipt(ClassroomEditStatus.pending)),
      acknowledgment.then((result) {
        return result.when(
          success: (_) => receipt(ClassroomEditStatus.saved),
          failure: Result<ClassroomEditReceipt>.failure,
        );
      }),
    ]).timeout(
      confirmationTimeout,
      onTimeout: () => receipt(ClassroomEditStatus.unconfirmed),
    );
  } finally {
    await subscription.cancel();
  }
}
