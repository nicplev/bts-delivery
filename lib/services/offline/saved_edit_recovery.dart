import 'dart:async';

import '../../models/offline/saved_edit.dart';
import '../../repositories/classroom_edit.dart';
import '../result.dart';
import 'saved_edit_store.dart';

abstract interface class EditTransport {
  Stream<bool> watchPending(EditIntent intent);
  Stream<ServerEditValues> watchSettled(EditIntent intent);
  Future<ServerEditValues> readServer(EditIntent intent);
  Future<void> submit(EditIntent intent, void Function() requireOwner);
  Future<void> retry(
    EditIntent intent,
    ServerEditValues reviewed,
    void Function() requireOwner,
  );
}

class SavedEditComparison {
  const SavedEditComparison({
    required this.current,
    required this.message,
    required this.canResolve,
    required this.canRetry,
    this.session,
  });

  final ServerEditValues? current;
  final String message;
  final bool canResolve;
  final bool canRetry;
  final int? session;
}

class SavedEditRecovery {
  SavedEditRecovery({
    required this.store,
    required this.transport,
    required this.currentUid,
    this.localWait = const Duration(milliseconds: 900),
    this.serverWait = const Duration(seconds: 5),
  });

  final SavedEditStore store;
  final EditTransport transport;
  final String? Function() currentUid;
  final Duration localWait;
  final Duration serverWait;

  final _admitting = <String, _Admission>{};
  final _native = <String, EditIntent>{};
  final _diskAdmissions = <String, _DiskAdmission>{};
  final _retrying = <String>{};
  final _storeWrites = <String, Future<void>>{};
  final _recovering = <String, StreamSubscription<ServerEditValues>>{};
  bool _disposed = false;
  int _generation = 0;
  String? _observedUid;

  int get _session {
    authenticationChanged();
    return _generation;
  }

  void authenticationChanged() {
    final uid = currentUid();
    if (_observedUid != uid) {
      _observedUid = uid;
      _generation++;
      _stopWatchingRecovered();
    }
  }

  bool _isOwner(EditIntent intent, [int? session]) {
    final currentSession = _session;
    return !_disposed &&
        _observedUid == intent.ownerUid &&
        (session == null || currentSession == session);
  }

  void _requireOwner(EditIntent intent, int session) {
    if (!_isOwner(intent, session)) {
      throw StateError('The signed-in account changed.');
    }
  }

  bool _activeAtPath(EditIntent intent) =>
      _native.values.any((current) => _pathKey(current) == _pathKey(intent)) ||
      _admitting.values
          .any((current) => _pathKey(current.intent) == _pathKey(intent)) ||
      _diskAdmissions.values
          .any((current) => _pathKey(current.intent) == _pathKey(intent));
  String _pathKey(EditIntent intent) => '${intent.ownerUid}:${intent.path}';

  Future<Result<ClassroomEditReceipt>> save(EditIntent intent) async {
    if (!_isOwner(intent)) {
      return const Result.failure('Sign in to save this edit.');
    }
    final admitting = _admitting[intent.key];
    if (admitting != null) {
      if (intent.fingerprint != admitting.intent.fingerprint) {
        return const Result.failure(
            'This saved edit already has different values.');
      }
      return admitting.result;
    }
    if (_retrying.contains(_pathKey(intent))) {
      return const Result.failure('Finish reviewing the previous edit first.');
    }

    final result = _save(intent, _session);
    _admitting[intent.key] = (intent: intent, result: result);
    try {
      return await result;
    } finally {
      _admitting.remove(intent.key);
    }
  }

  Future<Result<ClassroomEditReceipt>> _save(
      EditIntent intent, int session) async {
    EditReceiptRecord? previous;
    try {
      // A timed-out disk write can still finish. Never reuse its optimistic or
      // unknown record to clear a draft until persistence is settled.
      await _diskAdmissions[intent.key]?.write.timeout(serverWait);
      previous =
          await store.read(intent.ownerUid, intent.id).timeout(serverWait);
      _requireOwner(intent, session);
      if (previous != null) {
        if (previous.fingerprint != intent.fingerprint) {
          return const Result.failure(
              'This saved edit already has different values.');
        }
        return _previousReceipt(previous.state,
            nativePending: _native.containsKey(intent.key));
      }
      final write = store.put(SavedEdit(intent, SavedEditState.waiting));
      _diskAdmissions[intent.key] = (intent: intent, write: write);
      unawaited(write.then<void>(
        (_) => _diskAdmissions.remove(intent.key),
        onError: (Object _) => _diskAdmissions.remove(intent.key),
      ));
      await write.timeout(serverWait);
    } catch (_) {
      return const Result.failure(
        'Could not save this edit on the device. Your input is still in the form.',
      );
    }

    if (!_isOwner(intent, session)) {
      return _previousReceipt(SavedEditState.waiting);
    }
    final local = Completer<void>();
    StreamSubscription<bool>? listener;
    try {
      if (!intent.deletesDocument) {
        listener = transport.watchPending(intent).listen((pending) {
          if (pending && !local.isCompleted) local.complete();
        }, onError: (Object _) {});
      }
    } catch (_) {
      // The original write can still acknowledge without a local listener.
    }

    _native[intent.key] = intent;
    final acknowledgment = _submit(intent, session);
    try {
      final status = await Future.any([
        local.future.then((_) => ClassroomEditStatus.pending),
        acknowledgment.then((result) => result.isSuccess
            ? ClassroomEditStatus.saved
            : ClassroomEditStatus.unconfirmed),
      ]).timeout(localWait, onTimeout: () => ClassroomEditStatus.unconfirmed);
      if (status == ClassroomEditStatus.pending) {
        unawaited(_mutate(intent, () async {
          if (_native.containsKey(intent.key)) {
            await store.put(SavedEdit(intent, SavedEditState.queued));
          }
        }).catchError((Object _) {}));
      }
      return Result.success((status: status, acknowledgment: acknowledgment));
    } finally {
      await listener?.cancel();
    }
  }

  Future<Result<void>> _submit(EditIntent intent, int session) async {
    if (intent.deletesDocument) return _submitDeletion(intent, session);
    try {
      await transport.submit(intent, () => _requireOwner(intent, session));
    } catch (_) {
      await _settleNative(intent, serverAccepted: false);
      return const Result.failure(
          'Firestore could not accept the edit. It is saved for review.');
    }
    await _settleNative(intent, serverAccepted: true);
    return const Result.success(null);
  }

  Future<Result<void>> _submitDeletion(EditIntent intent, int session) async {
    SavedEditState state = SavedEditState.waiting;
    try {
      final current = await transport.readServer(intent).timeout(serverWait);
      _requireOwner(intent, session);
      if (!current.hasPendingWrites) {
        if (current.matches(intent)) {
          state = SavedEditState.matched;
        } else if (current.sameValues(ServerEditValues(
          exists: true,
          hasPendingWrites: false,
          fields: intent.fields,
        ))) {
          await transport.retry(
              intent, current, () => _requireOwner(intent, session));
          await _settleNative(intent, serverAccepted: true);
          return const Result.success(null);
        } else {
          state = SavedEditState.review;
        }
      }
    } catch (_) {
      // A disconnected or changed record remains saved for explicit review.
    }
    await _settleNative(intent, serverAccepted: false, state: state);
    return const Result.failure('The deletion is saved for review.');
  }

  Future<void> _settleNative(
    EditIntent intent, {
    required bool serverAccepted,
    SavedEditState state = SavedEditState.rejected,
  }) async {
    try {
      await _mutate(intent, () async {
        _native.remove(intent.key);
        if (serverAccepted) {
          await store.finish(intent);
        } else {
          await store.put(SavedEdit(intent, state));
        }
      });
    } catch (_) {
      // The durable copy remains available for server comparison.
    }
  }

  Result<ClassroomEditReceipt> _previousReceipt(
    SavedEditState state, {
    bool nativePending = false,
  }) {
    if (state == SavedEditState.dismissed) {
      return const Result.failure(
          'This saved copy was cleared. Change the form before saving again.');
    }
    final status = switch (state) {
      SavedEditState.acknowledged => ClassroomEditStatus.saved,
      SavedEditState.queued when nativePending => ClassroomEditStatus.pending,
      _ => ClassroomEditStatus.unconfirmed,
    };
    return Result.success((
      status: status,
      acknowledgment: Future.value(status == ClassroomEditStatus.saved
          ? const Result.success(null)
          : const Result.failure(
              'This saved copy still needs a server check.')),
    ));
  }

  /// A reboot or reconnect only compares server state. It never replays a write.
  Future<void> reconcile(String ownerUid) async {
    final session = _session;
    if (_disposed || _observedUid != ownerUid) return;
    final edits = await store.pending(ownerUid);
    for (var start = 0; start < edits.length; start += 4) {
      if (_disposed || _session != session) return;
      await Future.wait(edits
          .skip(start)
          .take(4)
          .map((edit) => _reconcileOne(edit, session)));
    }
  }

  Future<void> _reconcileOne(SavedEdit edit, int session) async {
    final intent = edit.intent;
    if (!_eligibleForComparison(intent, session)) return;
    try {
      final current = await transport.readServer(intent).timeout(serverWait);
      if (!_eligibleForComparison(intent, session)) return;
      if (current.hasPendingWrites) {
        _watchRecovered(intent, session);
      } else {
        _stopWatchingEdit(intent.key);
        await _recordComparison(intent, current, session);
      }
    } catch (_) {
      // Keep the existing state on network, local storage, or permission errors.
    }
  }

  bool _eligibleForComparison(EditIntent intent, int session) =>
      _isOwner(intent, session) &&
      !_activeAtPath(intent) &&
      !_retrying.contains(_pathKey(intent));

  void _watchRecovered(EditIntent intent, int session) {
    // Bound the listeners used for native writes that survived a restart.
    if (_recovering.length >= 4 || _recovering.containsKey(intent.key)) return;
    final subscription = transport.watchSettled(intent).listen(
      (current) {
        if (!_isOwner(intent, session) ||
            current.hasPendingWrites ||
            !_recovering.containsKey(intent.key)) {
          return;
        }
        _stopWatchingEdit(intent.key);
        unawaited(_observeRecoveredResult(intent, current, session));
      },
      onError: (Object _) {
        if (_isOwner(intent, session)) _stopWatchingEdit(intent.key);
      },
      onDone: () {
        if (_isOwner(intent, session)) _stopWatchingEdit(intent.key);
      },
    );
    _recovering[intent.key] = subscription;
  }

  Future<void> _observeRecoveredResult(
    EditIntent intent,
    ServerEditValues current,
    int session,
  ) async {
    try {
      await _recordComparison(intent, current, session);
      if (_isOwner(intent, session)) await reconcile(intent.ownerUid);
    } catch (_) {
      // Retain the durable record if the local comparison cannot be recorded.
    }
  }

  void _stopWatchingEdit(String key) {
    unawaited(_recovering.remove(key)?.cancel().catchError((Object _) {}));
  }

  void _stopWatchingRecovered() {
    for (final key in _recovering.keys.toList()) {
      _stopWatchingEdit(key);
    }
  }

  Future<void> _recordComparison(
    EditIntent intent,
    ServerEditValues current,
    int session,
  ) =>
      _mutate(intent, () async {
        if (!_eligibleForComparison(intent, session)) return;
        final existing = (await store.read(intent.ownerUid, intent.id))?.edit;
        if (existing == null || !_eligibleForComparison(intent, session)) {
          return;
        }
        final next = current.matches(intent)
            ? SavedEditState.matched
            : existing.state == SavedEditState.rejected
                ? SavedEditState.rejected
                : SavedEditState.review;
        if (existing.state != next) await store.put(SavedEdit(intent, next));
      });

  Future<SavedEditComparison> compare(EditIntent intent) async {
    final session = _session;
    if (!_isOwner(intent, session)) {
      return _unavailable('The signed-in account changed.');
    }
    if (_activeAtPath(intent)) {
      return _unavailable('The original save is still waiting for Firestore.');
    }
    try {
      final current = await transport.readServer(intent).timeout(serverWait);
      if (!_isOwner(intent, session)) {
        return _unavailable('The signed-in account changed.');
      }
      if (current.hasPendingWrites || _activeAtPath(intent)) {
        return _unavailable('This record still has changes waiting to sync.');
      }
      if (current.matches(intent)) {
        return SavedEditComparison(
          current: current,
          message: 'The current server values match your saved edit.',
          canResolve: true,
          canRetry: false,
          session: session,
        );
      }
      final creationConflict = intent.createsDocument && current.exists;
      final missingUpdate = !intent.createsDocument &&
          intent.kind != SavedEditKind.checklist &&
          !current.exists;
      return SavedEditComparison(
        current: current,
        message: creationConflict
            ? 'A different record already uses this saved entry’s identifier.'
            : missingUpdate
                ? 'This record was removed from the server.'
                : intent.deletesDocument
                    ? 'Review the current note before deleting it.'
                    : 'The current server values differ from the saved edit.',
        canResolve: true,
        canRetry: !creationConflict && !missingUpdate,
        session: session,
      );
    } catch (_) {
      return _unavailable(
          'Could not check the current server values. Try again when connected.');
    }
  }

  SavedEditComparison _unavailable(String message) => SavedEditComparison(
        current: null,
        message: message,
        canResolve: false,
        canRetry: false,
      );

  Future<Result<void>> retry(EditIntent intent, SavedEditComparison reviewed) =>
      _resolve(intent, reviewed, retry: true);

  Future<Result<void>> clear(EditIntent intent, SavedEditComparison reviewed) =>
      _resolve(intent, reviewed, retry: false);

  Future<Result<void>> _resolve(
    EditIntent intent,
    SavedEditComparison reviewed, {
    required bool retry,
  }) async {
    final reviewedValues = reviewed.current;
    final session = _session;
    if (!_isOwner(intent, session) ||
        reviewed.session != session ||
        reviewedValues == null ||
        !reviewed.canResolve ||
        (retry && !reviewed.canRetry)) {
      return const Result.failure(
          'Check the current server values before continuing.');
    }
    final path = _pathKey(intent);
    if (_activeAtPath(intent) || !_retrying.add(path)) {
      return const Result.failure(
          'A save for this record is still in progress.');
    }
    try {
      return await _mutate(intent, () async {
        _requireOwner(intent, session);
        final saved = (await store.read(intent.ownerUid, intent.id))?.edit;
        if (saved == null) return const Result.success(null);
        if (saved.intent.fingerprint != intent.fingerprint ||
            saved.intent.capturedAt != intent.capturedAt) {
          return const Result.failure('The saved edit changed. Open it again.');
        }
        final current = await transport.readServer(intent).timeout(serverWait);
        _requireOwner(intent, session);
        if (current.hasPendingWrites || !current.sameValues(reviewedValues)) {
          return const Result.failure(
              'Server values changed. Review them again.');
        }
        if (retry) {
          await transport.retry(
              intent, current, () => _requireOwner(intent, session));
        }
        _requireOwner(intent, session);
        await store.finish(intent,
            dismissed: !retry && !current.matches(intent));
        return const Result.success(null);
      });
    } catch (_) {
      return const Result.failure(
          'Could not finish this review. The saved edit is still on this device.');
    } finally {
      _retrying.remove(path);
    }
  }

  Future<T> _mutate<T>(EditIntent intent, Future<T> Function() change) async {
    final key = intent.key;
    final previous = _storeWrites[key];
    final run = Future<T>(() async {
      await previous;
      return change();
    });
    final barrier = run.then<void>((_) {}, onError: (Object _) {});
    _storeWrites[key] = barrier;
    try {
      return await run;
    } finally {
      if (identical(_storeWrites[key], barrier)) _storeWrites.remove(key);
    }
  }

  void dispose() {
    _disposed = true;
    _stopWatchingRecovered();
  }
}

typedef _Admission = ({
  EditIntent intent,
  Future<Result<ClassroomEditReceipt>> result
});

typedef _DiskAdmission = ({EditIntent intent, Future<void> write});
