import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:uuid/uuid.dart';

import '../../models/offline/evidence_upload.dart';
import '../../models/photo_subject.dart';
import 'offline_storage_service.dart';

typedef StartUpload = ({
  Future<void> completion,
  Future<void> Function() cancel,
})
    Function(EvidenceUpload item, File file);

typedef SaveEvidence = Future<void> Function(
  EvidenceUpload item,
  void Function() requireOwner,
);

class EvidenceUploadStatus {
  const EvidenceUploadStatus({
    required this.items,
    required this.activeId,
    required this.legacyReviewCount,
    required this.localError,
  });

  final List<EvidenceUpload> items;
  final String? activeId;
  final int legacyReviewCount;
  final bool localError;
}

class EvidenceUploadWorker {
  EvidenceUploadWorker({
    required OfflineStorageService store,
    required String? Function() currentUid,
    required bool Function() hasNetwork,
    required StartUpload startUpload,
    required SaveEvidence saveEvidence,
    Duration attemptTimeout = const Duration(seconds: 45),
    Duration firstRetryDelay = const Duration(seconds: 5),
    int maxAttempts = 6,
  })  : _store = store,
        _currentUid = currentUid,
        _hasNetwork = hasNetwork,
        _startUpload = startUpload,
        _saveEvidence = saveEvidence,
        _attemptTimeout = attemptTimeout,
        _firstRetryDelay = firstRetryDelay,
        _maxAttempts = maxAttempts;

  final OfflineStorageService _store;
  final String? Function() _currentUid;
  final bool Function() _hasNetwork;
  final StartUpload _startUpload;
  final SaveEvidence _saveEvidence;
  final Duration _attemptTimeout;
  final Duration _firstRetryDelay;
  final int _maxAttempts;
  final _changes = StreamController<EvidenceUploadStatus>.broadcast();
  final _editing = <String>{};
  EvidenceUpload? _active;
  Future<void> Function()? _cancelUpload;
  Timer? _timer;
  bool _disposed = false;
  bool _draining = false;
  bool _localError = false;

  EvidenceUploadStatus get status {
    final uid = _currentUid();
    return EvidenceUploadStatus(
      items: List.unmodifiable(_store.evidence
          .where((item) => !item.acknowledged && item.ownerUid == uid)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt))),
      activeId: _active?.ownerUid == uid ? _active?.id : null,
      legacyReviewCount: _store.legacyReviewCount(uid),
      localError: _localError,
    );
  }

  Stream<EvidenceUploadStatus> watch() => Stream.multi((sink) {
        final subscription =
            _changes.stream.listen(sink.add, onDone: sink.close);
        sink.onCancel = subscription.cancel;
        sink.add(status);
      });

  File localFile(EvidenceUpload item) => _store.fileFor(item);

  Future<void> enqueuePhoto({
    required String ownerUid,
    required String schoolId,
    required String yearLevelId,
    required String classroomId,
    required File source,
    String? deliveryId,
    PhotoSubject? subject,
  }) {
    final id = const Uuid().v4();
    return _enqueue(
      EvidenceUpload(
        id: id,
        kind: EvidenceKind.photo,
        deliveryId: deliveryId,
        ownerUid: ownerUid,
        schoolId: schoolId,
        yearLevelId: yearLevelId,
        classroomId: classroomId,
        localFileName: 'pending_evidence/$id.jpg',
        storagePath: photoStoragePath(
          schoolId,
          yearLevelId,
          classroomId,
          id,
          deliveryId: deliveryId,
        ),
        createdAt: DateTime.now().toUtc(),
        subjectType: subject?.type,
        subjectId: subject?.id,
        subjectLabel: subject?.label,
      ),
      (temp) => source.copy(temp.path),
    );
  }

  /// Returns after the signature and its metadata are persisted on this device.
  /// The payload must contain JSON values.
  Future<void> enqueueSignature({
    required String id,
    required String ownerUid,
    required String schoolId,
    String? deliveryId,
    required Uint8List bytes,
    required Map<String, dynamic> payload,
  }) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) || bytes.isEmpty) {
      throw ArgumentError('Invalid signature evidence');
    }
    final item = EvidenceUpload(
      id: id,
      kind: EvidenceKind.signature,
      ownerUid: ownerUid,
      schoolId: schoolId,
      deliveryId: deliveryId,
      localFileName: 'pending_evidence/$id.png',
      storagePath: 'schools/$schoolId/signoffs/$id.png',
      createdAt: DateTime.now().toUtc(),
      payload: payload,
    );
    // Validate and detach the draft from mutable form state before saving.
    return _enqueue(
      EvidenceUpload.fromRecord(item.toRecord()),
      (temp) => temp.writeAsBytes(bytes, flush: true),
    );
  }

  Future<void> _enqueue(
    EvidenceUpload item,
    Future<File> Function(File) write,
  ) async {
    _requireOwner(item.ownerUid);
    if (!_editing.add(item.id)) {
      throw StateError('Evidence is already being saved');
    }
    try {
      if (_store.get(item.id) != null ||
          _store.signatureWasAcknowledged(item.id)) {
        throw StateError('The evidence ID is already in use');
      }
      final file = localFile(item);
      await file.parent.create(recursive: true);
      final temp = await write(File('${file.path}.tmp'));
      await temp.rename(file.path);
      await _store.put(item);
    } finally {
      _editing.remove(item.id);
      wake();
    }
  }

  /// Keep the file and the queue entry so a user can resume it later.
  Future<void> pause(String id) =>
      _edit(id, (item) => item.updateProgress(paused: true));

  Future<void> retry(String id) =>
      _edit(id, (item) => item.updateProgress(attempts: 0, paused: false));

  Future<void> retryAll() async {
    for (final item in status.items) {
      if (item.id != _active?.id && !item.paused && item.error != null) {
        await retry(item.id);
      }
    }
    _localError = false;
    wake();
  }

  Future<void> _edit(
    String id,
    EvidenceUpload Function(EvidenceUpload) update,
  ) async {
    final item = _store.get(id);
    if (item == null || item.acknowledged) return;
    _requireOwner(item.ownerUid);
    if (_active?.id == id || !_editing.add(id)) {
      throw StateError('Evidence is currently syncing');
    }
    try {
      await _store.put(update(item));
    } finally {
      _editing.remove(id);
      wake();
    }
  }

  void authenticationChanged() {
    if (_active?.ownerUid != _currentUid()) {
      unawaited(_cancelActiveUpload());
    }
    wake();
  }

  void wake() {
    if (_disposed) return;
    _publish();
    if (_draining) return;
    _timer?.cancel();
    _timer = Timer(Duration.zero, _drain);
  }

  Future<void> _drain() async {
    if (_disposed || _draining) return;
    _draining = true;
    try {
      for (final item
          in _store.evidence.where((item) => item.acknowledged).toList()) {
        await _cleanUp(item);
      }
      while (!_disposed && _hasNetwork()) {
        final owner = _currentUid();
        final now = DateTime.now();
        EvidenceUpload? next;
        DateTime? nextRetry;
        for (final item in status.items) {
          if (item.ownerUid != owner ||
              item.paused ||
              item.needsAttention ||
              _editing.contains(item.id)) {
            continue;
          }
          final retryAt = item.retryAt;
          if (retryAt == null || !retryAt.isAfter(now)) {
            next = item;
            break;
          }
          if (nextRetry == null || retryAt.isBefore(nextRetry)) {
            nextRetry = retryAt;
          }
        }
        if (next == null) {
          if (nextRetry != null) {
            _timer = Timer(nextRetry.difference(now), _drain);
          }
          break;
        }
        _active = next;
        _publish();
        await _process(next);
        _active = null;
        _publish();
      }
    } catch (_) {
      // Leave the journal intact when writing to the device fails.
      _localError = true;
      if (!_disposed) _timer = Timer(_firstRetryDelay, _drain);
    } finally {
      _active = null;
      _draining = false;
      _publish();
    }
  }

  Future<void> _process(EvidenceUpload item) async {
    var progress = item;
    void requireOwner() => _requireOwner(progress.ownerUid);
    try {
      if (!progress.uploaded) {
        final file = localFile(progress);
        if (!await file.exists()) {
          await _store.put(progress.updateProgress(
            error: EvidenceUploadError.missingFile,
          ));
          return;
        }
        requireOwner();
        final upload = _startUpload(progress, file);
        _cancelUpload = upload.cancel;
        try {
          await upload.completion.timeout(_attemptTimeout);
        } on TimeoutException {
          await _cancelActiveUpload();
          rethrow;
        } finally {
          _cancelUpload = null;
        }
        progress = progress.updateProgress(uploaded: true);
        await _store.put(progress);
      }
      requireOwner();
      await _saveRecord(progress, requireOwner);
    } on _OwnerChanged {
      return;
    } catch (error) {
      if (_disposed || _currentUid() != progress.ownerUid) return;
      final denied = error is FirebaseException &&
          (error.code == 'permission-denied' || error.code == 'unauthorized');
      final attempts = progress.attempts + 1;
      final retryAt = denied || attempts >= _maxAttempts
          ? null
          : DateTime.now().add(_firstRetryDelay * (1 << (attempts - 1)));
      await _store.put(progress.updateProgress(
        attempts: attempts,
        retryAt: retryAt,
        error: denied
            ? EvidenceUploadError.accessDenied
            : progress.uploaded
                ? EvidenceUploadError.saveFailed
                : EvidenceUploadError.uploadFailed,
      ));
      return;
    }

    // Keep the success marker until cleanup is finished. A crash during
    // cleanup will resume cleanup without uploading a second time.
    final acknowledged = progress.updateProgress(acknowledged: true);
    await _store.put(acknowledged);
    await _cleanUp(acknowledged);
  }

  /// Writes the evidence record. A photo attached to an item is retried once
  /// as a general photo when the server refuses the record: the rules on the
  /// server may predate photo attachments, and a photo must never be stuck
  /// because of that. Any other error, or a second refusal, is handled by the
  /// caller exactly as before. The queue entry keeps its attachment.
  Future<void> _saveRecord(
    EvidenceUpload item,
    void Function() requireOwner,
  ) async {
    try {
      await _saveEvidence(item, requireOwner).timeout(_attemptTimeout);
    } on FirebaseException catch (error) {
      if (item.kind != EvidenceKind.photo ||
          !item.hasSubject ||
          error.code != 'permission-denied') {
        rethrow;
      }
      requireOwner();
      await _saveEvidence(item.withoutSubject(), requireOwner)
          .timeout(_attemptTimeout);
    }
  }

  Future<void> _cleanUp(EvidenceUpload item) async {
    if (_editing.contains(item.id)) return;
    if (item.kind == EvidenceKind.signature) {
      await _store.rememberSignature(item.id);
    }
    final file = localFile(item);
    if (await file.exists()) await file.delete();
    await _store.remove(item.id);
    _localError = false;
  }

  void _requireOwner(String uid) {
    if (_disposed || _currentUid() != uid) throw const _OwnerChanged();
  }

  Future<void> _cancelActiveUpload() async {
    final cancel = _cancelUpload;
    _cancelUpload = null;
    if (cancel == null) return;
    try {
      await cancel();
    } catch (_) {
      // A task can finish while cancellation is being requested.
    }
  }

  void _publish() {
    if (!_disposed) _changes.add(status);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_cancelActiveUpload());
    unawaited(_changes.close());
  }
}

class _OwnerChanged implements Exception {
  const _OwnerChanged();
}
