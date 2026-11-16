import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/offline/evidence_upload.dart';
import '../../models/offline/offline_models.dart';

class OfflineStorageService {
  OfflineStorageService({Future<Directory> Function()? documentsDirectory})
      : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  static const evidenceBoxName = 'evidence_uploads';
  static const _signatureReceiptName = 'acknowledged_signature_ids';
  static const _legacyQueueName = 'sync_queue';
  static const _legacyPhotoName = 'local_photos';
  static const _legacyCompletionName = 'pending_delivery_completions';

  final Future<Directory> Function() _documentsDirectory;
  late final Directory _documents;
  late final Box<Map> _evidence;
  late final Box<bool> _signatureReceipts;
  late final Box<SyncQueueItem> _legacyQueue;
  late final Box<LocalPhoto> _legacyPhotos;
  late final Box<PendingDeliveryCompletion> _legacyCompletions;
  Future<void>? _initializing;

  Future<void> initialize() =>
      _initializing ??= _initialize().onError((error, stack) {
        _initializing = null;
        Error.throwWithStackTrace(
            error ?? StateError('Local storage failed'), stack);
      });

  Future<void> _initialize() async {
    final queueAdapter = SyncQueueItemAdapter();
    final photoAdapter = LocalPhotoAdapter();
    final completionAdapter = PendingDeliveryCompletionAdapter();
    if (!Hive.isAdapterRegistered(queueAdapter.typeId)) {
      Hive.registerAdapter(queueAdapter);
    }
    if (!Hive.isAdapterRegistered(photoAdapter.typeId)) {
      Hive.registerAdapter(photoAdapter);
    }
    if (!Hive.isAdapterRegistered(completionAdapter.typeId)) {
      Hive.registerAdapter(completionAdapter);
    }

    final documents = await _documentsDirectory();
    final evidence = await Hive.openBox<Map>(evidenceBoxName);
    final receipts = await Hive.openBox<bool>(_signatureReceiptName);
    final queue = await Hive.openBox<SyncQueueItem>(_legacyQueueName);
    final photos = await Hive.openBox<LocalPhoto>(_legacyPhotoName);
    final completions =
        await Hive.openBox<PendingDeliveryCompletion>(_legacyCompletionName);
    _documents = documents;
    _evidence = evidence;
    _signatureReceipts = receipts;
    _legacyQueue = queue;
    _legacyPhotos = photos;
    _legacyCompletions = completions;
  }

  Iterable<EvidenceUpload> get evidence =>
      _evidence.values.map(EvidenceUpload.fromRecord);

  EvidenceUpload? get(String id) {
    final row = _evidence.get(id);
    return row == null ? null : EvidenceUpload.fromRecord(row);
  }

  Future<void> put(EvidenceUpload item) =>
      _evidence.put(item.id, item.toRecord());

  bool signatureWasAcknowledged(String id) =>
      _signatureReceipts.containsKey(id);

  Future<void> rememberSignature(String id) => _signatureReceipts.put(id, true);

  Future<void> remove(String id) => _evidence.delete(id);

  File fileFor(EvidenceUpload item) => File(
        '${_documents.path}${Platform.pathSeparator}${item.localFileName}',
      );

  /// Write a journal entry before removing either legacy record. A matching
  /// queue entry is the only legacy source that can prove photo ownership.
  Future<void> recoverLegacyPhotos() async {
    for (final photo in _legacyPhotos.values.toList()) {
      if (photo.isUploaded) continue;
      final queued = _legacyQueue.get(photo.id);
      final owner = queued?.userId;
      if (queued == null ||
          owner == null ||
          owner.isEmpty ||
          queued.entityType != 'photo' ||
          queued.operationType != 'upload' ||
          queued.data['photoId'] != photo.id ||
          queued.data['schoolId'] != photo.schoolId ||
          queued.data['yearLevelId'] != photo.yearLevelId ||
          queued.data['classroomId'] != photo.classroomId ||
          queued.data['localPath'] != photo.localPath) {
        continue;
      }
      final item = EvidenceUpload(
        id: photo.id,
        kind: EvidenceKind.photo,
        ownerUid: owner,
        schoolId: photo.schoolId,
        yearLevelId: photo.yearLevelId,
        classroomId: photo.classroomId,
        createdAt: photo.createdAt,
        localFileName:
            'classroom_photos/${File(photo.localPath).uri.pathSegments.last}',
        storagePath: photoStoragePath(
          photo.schoolId,
          photo.yearLevelId,
          photo.classroomId,
          photo.id,
        ),
      );
      final existing = get(photo.id);
      if (existing != null &&
          (existing.ownerUid != owner ||
              existing.storagePath != item.storagePath)) {
        continue;
      }
      final currentFile = fileFor(item);
      final previousFile = File(photo.localPath);
      if (!await currentFile.exists() && await previousFile.exists()) {
        await currentFile.parent.create(recursive: true);
        await previousFile.copy(currentFile.path);
      }
      if (existing == null) await put(item);
      // Delete the queue entry last so an interruption can at worst leave an
      // extra legacy record in need of review. The uploaded file stays local.
      await _legacyPhotos.delete(photo.id);
      await _legacyQueue.delete(queued.id);
    }
  }

  List<LocalPhoto> get legacyPhotosForRecovery => _legacyPhotos.values
      .where((photo) => !photo.isUploaded || _legacyQueue.containsKey(photo.id))
      .toList(growable: false);

  Future<File?> legacyPhotoFile(LocalPhoto photo) async {
    final previous = File(photo.localPath);
    final file = File(
      '${_documents.path}/classroom_photos/${previous.uri.pathSegments.last}',
    );
    if (await file.exists()) return file;
    if (await previous.exists()) return previous;
    return null;
  }

  int legacyReviewCount(String? ownerUid) {
    if (ownerUid == null) return 0;
    final photos = legacyPhotosForRecovery.map((photo) => photo.id).toSet();
    final operations = _legacyQueue.values.where(
      (item) => item.userId == null || item.userId == ownerUid,
    );
    final completions = _legacyCompletions.values.where((item) =>
        !item.isUploaded &&
        (item.completedBy == null || item.completedBy == ownerUid));
    return photos.length +
        operations.where((item) => !photos.contains(item.id)).length +
        completions.length;
  }
}

final offlineStorageServiceProvider = Provider<OfflineStorageService>(
  (ref) => OfflineStorageService(),
);

final offlineStorageInitProvider = FutureProvider<void>((ref) {
  return ref.watch(offlineStorageServiceProvider).initialize();
});
