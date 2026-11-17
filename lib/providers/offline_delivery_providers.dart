import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/offline/evidence_upload.dart';
import '../models/school.dart';
import '../services/offline/connectivity_service.dart';
import '../services/offline/evidence_upload_worker.dart';
import '../services/offline/offline_storage_service.dart';
import 'repository_providers.dart';

final evidenceUploadWorkerProvider = FutureProvider<EvidenceUploadWorker>((
  ref,
) async {
  final store = ref.watch(offlineStorageServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final auth = ref.watch(authRepositoryProvider);
  final schools = ref.watch(baseSchoolsRepositoryProvider);
  final firebaseStorage = FirebaseStorage.instance;
  var disposed = false;
  ref.onDispose(() => disposed = true);

  await ref.watch(offlineStorageInitProvider.future);
  await store.recoverLegacyPhotos();
  if (disposed) throw StateError('Upload worker closed');

  final worker = EvidenceUploadWorker(
    store: store,
    currentUid: () => auth.currentUser?.uid,
    hasNetwork: () => connectivity.isOnline,
    startUpload: (item, file) {
      final reference = firebaseStorage.ref(item.storagePath);
      UploadTask? task;
      var cancelled = false;
      void checkOwner() {
        if (cancelled || auth.currentUser?.uid != item.ownerUid) {
          throw StateError('The upload is no longer active');
        }
      }

      Future<void> upload() async {
        final isSignature = item.kind == EvidenceKind.signature;
        final digest = (await sha256.bind(file.openRead()).first).toString();
        checkOwner();
        try {
          task = reference.putFile(
            file,
            SettableMetadata(
              contentType: isSignature ? 'image/png' : 'image/jpeg',
              customMetadata: {
                'uploadedBy': item.ownerUid,
                'sha256': digest,
              },
            ),
          );
          await task!;
        } on FirebaseException catch (error) {
          if (error.code != 'unauthorized' &&
              error.code != 'permission-denied') {
            rethrow;
          }
          checkOwner();
          // Evidence files are create-only. Recover a success whose local receipt
          // was interrupted by verifying the existing object belongs to this job.
          final metadata = await reference.getMetadata();
          checkOwner();
          if (metadata.customMetadata?['uploadedBy'] != item.ownerUid ||
              metadata.customMetadata?['sha256'] != digest) {
            rethrow;
          }
        }
      }

      return (
        completion: upload(),
        cancel: () async {
          cancelled = true;
          await task?.cancel();
        },
      );
    },
    saveEvidence: (item, requireOwner) async {
      requireOwner();
      if (item.kind == EvidenceKind.signature) {
        await schools.persistQueuedSignOff(item, requireOwner: requireOwner);
        return;
      }
      final result = await schools.addClassroomPhoto(
        item.schoolId,
        item.yearLevelId!,
        item.classroomId!,
        Photo(
          id: item.id,
          storagePath: item.storagePath,
          uploadedBy: item.ownerUid,
          uploadedAt: item.createdAt,
        ),
        deliveryId: item.deliveryId,
      );
      result.when(
        success: (_) {},
        failure: (_, exception) =>
            throw exception ?? StateError('Could not save photo'),
      );
    },
  );

  final networkChanges = connectivity.statusStream.listen((_) => worker.wake());
  final authChanges = auth.authStateChanges.listen((_) {
    worker.authenticationChanged();
  });
  final lifecycle = AppLifecycleListener(onResume: () {
    unawaited(connectivity.checkConnectivity());
    worker.wake();
  });
  ref.onDispose(() {
    lifecycle.dispose();
    unawaited(networkChanges.cancel());
    unawaited(authChanges.cancel());
    worker.dispose();
  });
  worker.wake();
  return worker;
});

final evidenceUploadsProvider =
    StreamProvider<EvidenceUploadStatus>((ref) async* {
  final worker = await ref.watch(evidenceUploadWorkerProvider.future);
  yield* worker.watch();
});
