import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bts_delivery_app/models/offline/evidence_upload.dart';
import 'package:bts_delivery_app/models/offline/offline_models.dart';
import 'package:bts_delivery_app/models/photo_subject.dart';
import 'package:bts_delivery_app/services/offline/evidence_upload_worker.dart';
import 'package:bts_delivery_app/services/offline/offline_storage_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory documents;
  late OfflineStorageService store;
  EvidenceUploadWorker? worker;
  String? uid = 'uid-a';
  var online = false;

  Future<void> openStore() async {
    Hive.init(documents.path);
    store = OfflineStorageService(documentsDirectory: () async => documents);
    await store.initialize();
  }

  EvidenceUploadWorker start({
    required StartUpload upload,
    required SaveEvidence save,
    int maxAttempts = 2,
  }) {
    final result = EvidenceUploadWorker(
      store: store,
      currentUid: () => uid,
      hasNetwork: () => online,
      startUpload: upload,
      saveEvidence: save,
      firstRetryDelay: const Duration(milliseconds: 10),
      maxAttempts: maxAttempts,
    );
    worker = result;
    result.wake();
    return result;
  }

  Future<void> enqueue(EvidenceUploadWorker worker, {int byte = 42}) =>
      worker.enqueueSignature(
        id: 'signature-1',
        ownerUid: 'uid-a',
        schoolId: 'school-a',
        deliveryId: 'visit-a',
        bytes: Uint8List.fromList([byte]),
        payload: {
          'classrooms': [
            {'id': 'class-1', 'count': 3},
          ],
        },
      );

  Future<void> restart() async {
    worker?.dispose();
    worker = null;
    await Hive.close();
    await openStore();
  }

  Future<void> idle(EvidenceUploadWorker worker) => worker
      .watch()
      .firstWhere((state) => state.items.isEmpty && state.activeId == null)
      .timeout(const Duration(seconds: 3));

  setUp(() async {
    uid = 'uid-a';
    online = false;
    documents = await Directory.systemTemp.createTemp('bts-evidence-test');
    await openStore();
  });

  tearDown(() async {
    worker?.dispose();
    worker = null;
    await Hive.close();
    await documents.delete(recursive: true);
  });

  test('offline signature survives restart, reconnects, and cannot be replaced',
      () async {
    final offline = start(
      upload: (_, __) => throw StateError('network should remain idle'),
      save: (_, __) async => throw StateError('network should remain idle'),
    );
    await enqueue(offline);
    final pending = offline.status.items.single;
    expect(await offline.localFile(pending).readAsBytes(), [42]);
    expect(pending.ownerUid, 'uid-a');
    expect(pending.deliveryId, 'visit-a');
    await expectLater(enqueue(offline, byte: 43), throwsStateError);

    await restart();
    var uploads = 0;
    final onlineWorker = start(
      upload: (item, file) {
        uploads++;
        expect(item.storagePath, 'schools/school-a/signoffs/signature-1.png');
        expect(file.readAsBytesSync(), [42]);
        return (completion: Future.value(), cancel: () async {});
      },
      save: (item, requireOwner) async {
        requireOwner();
        expect(item.payload, {
          'classrooms': [
            {'id': 'class-1', 'count': 3},
          ],
        });
      },
    );
    expect(onlineWorker.status.items.single.id, 'signature-1');

    online = true;
    onlineWorker.wake();
    await idle(onlineWorker);
    expect(uploads, 1);
    expect(await offline.localFile(pending).exists(), isFalse);
    await restart();
    final afterAcknowledgement = start(
      upload: (_, __) => throw StateError('already acknowledged'),
      save: (_, __) async => throw StateError('already acknowledged'),
    );
    await expectLater(
        enqueue(afterAcknowledgement, byte: 44), throwsStateError);
  });

  test('failed metadata write keeps the file and does not repeat upload',
      () async {
    var uploads = 0;
    var saves = 0;
    ({Future<void> completion, Future<void> Function() cancel}) upload(
      EvidenceUpload item,
      File file,
    ) {
      uploads++;
      return (completion: Future.value(), cancel: () async {});
    }

    final fails = start(
      upload: upload,
      save: (_, __) async {
        saves++;
        throw const FileSystemException('metadata unavailable');
      },
    );
    online = true;
    await enqueue(fails);
    final failed = await fails
        .watch()
        .firstWhere((state) => state.items.any((item) => item.needsAttention))
        .timeout(const Duration(seconds: 3));
    final local = fails.localFile(failed.items.single);
    expect(saves, 2);
    expect(uploads, 1);
    expect(failed.items.single.error, EvidenceUploadError.saveFailed);
    expect(await local.exists(), isTrue);

    await restart();
    final recovers = start(
      upload: upload,
      save: (item, requireOwner) async {
        requireOwner();
        expect(item.id, 'signature-1');
        expect(item.uploaded, isTrue);
        expect(await local.exists(), isTrue);
        saves++;
      },
    );
    await recovers.retry('signature-1');
    await idle(recovers);
    expect(saves, 3);
    expect(uploads, 1);
    expect(await local.exists(), isFalse);
  });

  test('account switch cancels active upload and keeps it for original user',
      () async {
    final firstUpload = Completer<void>();
    final started = Completer<void>();
    final canceled = Completer<void>();
    final owners = <String>[];
    var attempts = 0;
    final current = start(
      upload: (item, _) {
        expect(item.ownerUid, uid);
        if (++attempts == 1) {
          started.complete();
          return (
            completion: firstUpload.future,
            cancel: () async {
              firstUpload.completeError(StateError('cancelled'));
              canceled.complete();
            },
          );
        }
        return (completion: Future.value(), cancel: () async {});
      },
      save: (item, requireOwner) async {
        requireOwner();
        owners.add(item.ownerUid);
      },
    );
    online = true;
    await enqueue(current);
    await started.future.timeout(const Duration(seconds: 3));
    uid = 'uid-b';
    current.authenticationChanged();
    await canceled.future.timeout(const Duration(seconds: 3));
    expect(current.status.items, isEmpty);
    expect(await store.fileFor(store.get('signature-1')!).exists(), isTrue);
    await expectLater(current.retry('signature-1'), throwsA(isA<Exception>()));
    expect(owners, isEmpty);

    uid = 'uid-a';
    current.authenticationChanged();
    await idle(current);
    expect(owners, ['uid-a']);
    expect(attempts, 2);
  });

  test('pausing a waiting entry keeps it through restart until resumed',
      () async {
    final waiting = start(
      upload: (_, __) => throw StateError('still offline'),
      save: (_, __) async => throw StateError('still offline'),
    );
    await enqueue(waiting);
    await waiting.pause('signature-1');
    expect(waiting.status.items.single.paused, isTrue);

    await restart();
    online = true;
    var uploads = 0;
    final resumed = start(
      upload: (_, __) {
        uploads++;
        return (completion: Future.value(), cancel: () async {});
      },
      save: (_, requireOwner) async => requireOwner(),
    );
    expect(resumed.status.items.single.paused, isTrue);
    expect(uploads, 0);
    await resumed.retry('signature-1');
    await idle(resumed);
    expect(uploads, 1);
  });

  test('visit photo stays in its visit after the capture file is gone',
      () async {
    final source =
        await File('${documents.path}/camera.jpg').writeAsBytes([4, 2]);
    final offline = start(
      upload: (_, __) => throw StateError('still offline'),
      save: (_, __) async => throw StateError('still offline'),
    );
    await offline.enqueuePhoto(
      ownerUid: 'uid-a',
      schoolId: 'school-a',
      yearLevelId: 'year-a',
      classroomId: 'class-a',
      deliveryId: 'visit-2',
      source: source,
    );
    await source.delete();
    final photo = offline.status.items.single;
    expect(photo.deliveryId, 'visit-2');
    expect(photo.storagePath,
        'deliveries/visit-2/workspace/school-a/yearLevels/year-a/classrooms/class-a/photos/${photo.id}.jpg');
    await restart();
    final onlineWorker = start(
      upload: (item, file) {
        expect(item.storagePath, photo.storagePath);
        expect(file.readAsBytesSync(), [4, 2]);
        return (completion: Future.value(), cancel: () async {});
      },
      save: (item, requireOwner) async {
        requireOwner();
        expect(item.id, photo.id);
        expect(item.deliveryId, 'visit-2');
      },
    );
    online = true;
    onlineWorker.wake();
    await idle(onlineWorker);
  });

  test('migrates provably owned processing photos and retains unknown photos',
      () async {
    final known = await File('${documents.path}/classroom_photos/known.jpg')
        .create(recursive: true);
    final unknown = await File('${documents.path}/classroom_photos/unknown.jpg')
        .create(recursive: true);
    await known.writeAsBytes([1]);
    await unknown.writeAsBytes([2]);
    final photos = Hive.box<LocalPhoto>('local_photos');
    for (final (id, file) in [('known', known), ('unknown', unknown)]) {
      await photos.put(
          id,
          LocalPhoto(
            id: id,
            localPath: file.path,
            schoolId: 'school-a',
            yearLevelId: 'year-a',
            classroomId: 'class-a',
            createdAt: DateTime.now(),
          ));
    }
    await Hive.box<SyncQueueItem>('sync_queue').put(
      'known',
      SyncQueueItem(
        id: 'known',
        operationType: 'upload',
        entityType: 'photo',
        data: {
          'photoId': 'known',
          'localPath': known.path,
          'schoolId': 'school-a',
          'yearLevelId': 'year-a',
          'classroomId': 'class-a',
        },
        createdAt: DateTime.now(),
        isProcessing: true,
        userId: 'uid-a',
      ),
    );

    await store.recoverLegacyPhotos();
    await store.recoverLegacyPhotos();
    expect(store.evidence.single.ownerUid, 'uid-a');
    expect(store.evidence.single.storagePath,
        'schools/school-a/yearLevels/year-a/classrooms/class-a/photos/known.jpg');
    expect(await store.fileFor(store.evidence.single).readAsBytes(), [1]);
    expect(store.legacyReviewCount('uid-a'), 1);
    final legacy = store.legacyPhotosForRecovery.single;
    expect(legacy.id, 'unknown');
    expect(await (await store.legacyPhotoFile(legacy))!.readAsBytes(), [2]);
    expect(await unknown.exists(), isTrue);
  });

  group('photo attachment', () {
    final tissues = PhotoSubject.consumable(id: 'tissues-1', label: 'Tissues');
    FirebaseException denied() =>
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

    Future<EvidenceUpload> enqueuePhoto(
      EvidenceUploadWorker worker, {
      PhotoSubject? subject,
      String name = 'camera',
    }) async {
      final source =
          await File('${documents.path}/$name.jpg').writeAsBytes([7, 7]);
      await worker.enqueuePhoto(
        ownerUid: 'uid-a',
        schoolId: 'school-a',
        yearLevelId: 'year-a',
        classroomId: 'class-a',
        deliveryId: 'visit-a',
        source: source,
        subject: subject,
      );
      return worker.status.items.last;
    }

    StartUpload countingUpload(List<String> uploads) => (item, file) {
          uploads.add(item.id);
          return (completion: Future.value(), cancel: () async {});
        };

    Future<EvidenceUploadStatus> attention(EvidenceUploadWorker worker) =>
        worker
            .watch()
            .firstWhere(
                (state) => state.items.any((item) => item.needsAttention))
            .timeout(const Duration(seconds: 3));

    test('the attachment is kept on the device through a restart', () async {
      final offline = start(
        upload: (_, __) => throw StateError('offline'),
        save: (_, __) async => throw StateError('offline'),
      );
      final queued = await enqueuePhoto(offline, subject: tissues);
      expect(queued.subject, tissues);
      expect(queued.subjectType, 'consumable');
      expect(queued.subjectId, 'tissues-1');
      expect(queued.subjectLabel, 'Tissues');
      final packs =
          await enqueuePhoto(offline, subject: PhotoSubject.packs, name: 'p');

      await restart();
      final reopened = start(
        upload: (_, __) => throw StateError('offline'),
        save: (_, __) async => throw StateError('offline'),
      );
      final items = {
        for (final item in reopened.status.items) item.id: item,
      };
      expect(items[queued.id]!.subject, tissues);
      expect(items[packs.id]!.subject, PhotoSubject.packs);
      expect(items[packs.id]!.toRecord().containsKey('subjectId'), isFalse);
      expect(items[packs.id]!.toRecord().containsKey('subjectLabel'), isFalse);
    });

    test('a general photo entry has no attachment keys', () async {
      final offline = start(
        upload: (_, __) => throw StateError('offline'),
        save: (_, __) async => throw StateError('offline'),
      );
      final queued = await enqueuePhoto(offline);
      expect(queued.hasSubject, isFalse);
      final keys = store.get(queued.id)!.toRecord().keys;
      expect(keys, isNot(contains('subjectType')));
      expect(keys, isNot(contains('subjectId')));
      expect(keys, isNot(contains('subjectLabel')));
    });

    test('an entry saved by the previous app version loads and uploads',
        () async {
      final file = await File('${documents.path}/pending_evidence/old.jpg')
          .create(recursive: true);
      await file.writeAsBytes([3]);
      // The exact record shape written before photo attachments existed.
      await Hive.box<Map>(OfflineStorageService.evidenceBoxName).put('old', {
        'id': 'old',
        'kind': 'photo',
        'ownerUid': 'uid-a',
        'schoolId': 'school-a',
        'localFileName': 'pending_evidence/old.jpg',
        'storagePath':
            'schools/school-a/yearLevels/year-a/classrooms/class-a/photos/old.jpg',
        'createdAt': DateTime.utc(2026, 11, 1),
        'deliveryId': null,
        'yearLevelId': 'year-a',
        'classroomId': 'class-a',
        'payload': '{}',
        'attempts': 0,
        'retryAt': null,
        'error': null,
        'paused': false,
        'uploaded': false,
        'acknowledged': false,
      });
      await restart();
      final old = store.get('old')!;
      expect(old.hasSubject, isFalse);
      expect(old.subject, isNull);
      expect(old.yearLevelId, 'year-a');

      final uploads = <String>[];
      final saved = <EvidenceUpload>[];
      online = true;
      final worker = start(
        upload: countingUpload(uploads),
        save: (item, requireOwner) async {
          requireOwner();
          saved.add(item);
        },
      );
      await idle(worker);
      expect(uploads, ['old']);
      expect(saved.single.id, 'old');
      expect(saved.single.hasSubject, isFalse);
      expect(await file.exists(), isFalse);
    });

    test('rules that accept attachments store the photo tagged, once',
        () async {
      final uploads = <String>[];
      final saved = <EvidenceUpload>[];
      final worker = start(
        upload: countingUpload(uploads),
        save: (item, requireOwner) async {
          requireOwner();
          saved.add(item);
        },
      );
      final queued = await enqueuePhoto(worker, subject: tissues);
      online = true;
      worker.wake();
      await idle(worker);
      expect(uploads, [queued.id]);
      expect(saved, hasLength(1));
      expect(saved.single.subject, tissues);
      expect(store.get(queued.id), isNull);
    });

    test(
        'rules that predate attachments store the photo untagged exactly '
        'once', () async {
      final uploads = <String>[];
      final attempts = <EvidenceUpload>[];
      final stored = <String, EvidenceUpload>{};
      final worker = start(
        upload: countingUpload(uploads),
        save: (item, requireOwner) async {
          requireOwner();
          attempts.add(item);
          // The deployed rules refuse any key they do not know.
          if (item.hasSubject) throw denied();
          stored.putIfAbsent(item.id, () => item);
        },
      );
      final queued = await enqueuePhoto(worker, subject: PhotoSubject.packs);
      online = true;
      worker.wake();
      await idle(worker);
      expect(uploads, [queued.id]);
      expect(
          attempts.map((item) => item.subject), [PhotoSubject.packs, null]);
      expect(attempts.last.id, queued.id);
      expect(attempts.last.storagePath, queued.storagePath);
      expect(stored.keys, [queued.id]);
      expect(stored[queued.id]!.hasSubject, isFalse);
      expect(store.get(queued.id), isNull);
      expect(await store.fileFor(queued).exists(), isFalse);
    });

    test('a general photo is saved as before: one write, no retry on denial',
        () async {
      final uploads = <String>[];
      final attempts = <EvidenceUpload>[];
      final worker = start(
        upload: countingUpload(uploads),
        save: (item, requireOwner) async {
          requireOwner();
          attempts.add(item);
          throw denied();
        },
      );
      final queued = await enqueuePhoto(worker);
      online = true;
      worker.wake();
      final failed = (await attention(worker)).items.single;
      expect(attempts, hasLength(1));
      expect(attempts.single.toRecord(),
          {...queued.toRecord(), 'uploaded': true});
      expect(uploads, [queued.id]);
      expect(failed.error, EvidenceUploadError.accessDenied);
      expect(failed.retryAt, isNull);
      expect(failed.attempts, 1);
      expect(await store.fileFor(queued).exists(), isTrue);
    });

    test('a tagged photo refused for another reason keeps the existing failure',
        () async {
      final uploads = <String>[];
      final attempts = <EvidenceUpload>[];
      final worker = start(
        upload: countingUpload(uploads),
        save: (item, requireOwner) async {
          requireOwner();
          attempts.add(item);
          throw denied(); // e.g. no longer assigned to the school
        },
      );
      final queued = await enqueuePhoto(worker, subject: tissues);
      online = true;
      worker.wake();
      final failed = (await attention(worker)).items.single;
      expect(attempts.map((item) => item.subject), [tissues, null]);
      expect(uploads, [queued.id]);
      expect(failed.error, EvidenceUploadError.accessDenied);
      expect(failed.retryAt, isNull);
      expect(failed.attempts, 1);
      // The queue entry keeps its attachment and its file.
      expect(failed.subject, tissues);
      expect(await store.fileFor(queued).exists(), isTrue);
    });

    test('other record errors on a tagged photo are retried tagged', () async {
      final uploads = <String>[];
      final attempts = <EvidenceUpload>[];
      final worker = start(
        upload: countingUpload(uploads),
        save: (item, requireOwner) async {
          requireOwner();
          attempts.add(item);
          throw FirebaseException(
              plugin: 'cloud_firestore', code: 'unavailable');
        },
      );
      final queued = await enqueuePhoto(worker, subject: tissues);
      online = true;
      worker.wake();
      final failed = (await attention(worker)).items.single;
      // maxAttempts is 2: two ordinary attempts with backoff, never untagged.
      expect(attempts.map((item) => item.subject), [tissues, tissues]);
      expect(uploads, [queued.id]);
      expect(failed.error, EvidenceUploadError.saveFailed);
      expect(failed.retryAt, isNull);
    });
  });
}
