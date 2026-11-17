import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/delivery_visit.dart';
import '../models/offline/offline_media.dart';
import '../services/media/firebase_media_origin.dart';
import '../services/media/offline_media_cache.dart';
import '../services/media/visit_media_inventory.dart';
import '../services/offline/connectivity_service.dart';
import '../services/offline/offline_storage_service.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';

final offlineMediaBucketProvider = Provider<String>(
  (ref) => FirebaseStorage.instance.bucket,
);

final _mediaOriginProvider = Provider<FirebaseMediaOrigin>(
  (ref) => FirebaseMediaOrigin(FirebaseStorage.instance),
);

final offlineMediaWorkerProvider =
    FutureProvider<OfflineMediaCache>((ref) async {
  final auth = ref.watch(authRepositoryProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final origin = ref.watch(_mediaOriginProvider);
  final bucket = ref.watch(offlineMediaBucketProvider);
  var disposed = false;
  ref.onDispose(() => disposed = true);

  await ref.watch(offlineStorageInitProvider.future);
  final support = await getApplicationSupportDirectory();
  final manifest = await Hive.openBox<String>('offline_media_v1');
  final cache = OfflineMediaCache(
    directory: Directory('${support.path}/offline_media_v1'),
    manifest: manifest,
    bucket: bucket,
    currentUid: () => auth.currentUser?.uid,
    networkAvailable: () => connectivity.isOnline,
    origin: origin,
  );
  await cache.initialize();
  if (disposed) {
    cache.dispose();
    throw StateError('Offline media closed');
  }

  final authChanges = auth.authStateChanges.listen(
    (user) => cache.accountChanged(user?.uid),
  );
  final connectionChanges =
      connectivity.statusStream.listen((_) => cache.wake());
  final lifecycle = AppLifecycleListener(onResume: () {
    unawaited(connectivity.checkConnectivity());
    cache.wake();
  });
  ref.onDispose(() {
    lifecycle.dispose();
    unawaited(authChanges.cancel());
    unawaited(connectionChanges.cancel());
    cache.dispose();
  });
  return cache;
});

/// A saved image stays hidden when this account has no matching staff access.
final offlineMediaOwnerProvider = Provider.autoDispose.family<String?, String>(
  (ref, schoolId) {
    final auth = ref.watch(authStateProvider).asData?.value;
    final staff = ref.watch(currentStaffProvider).asData?.value;
    final currentUid = ref.watch(authRepositoryProvider).currentUser?.uid;
    if (auth == null ||
        auth.uid != currentUid ||
        staff?.uid != currentUid ||
        staff == null ||
        (!staff.hasManagerAccess &&
            !staff.assignedSchoolIds.contains(schoolId))) {
      return null;
    }
    return auth.uid;
  },
);

final offlineMediaAssetStateProvider = StreamProvider.autoDispose
    .family<OfflineMediaState, OfflineMediaAsset>((ref, asset) async* {
  final uid = ref.watch(offlineMediaOwnerProvider(asset.schoolId));
  if (uid == null || asset.visit == null) return;
  final cache = await ref.watch(offlineMediaWorkerProvider.future);
  yield* cache.watchAsset(asset);
});

final offlineMediaVisitStateProvider = StreamProvider.autoDispose
    .family<OfflineMediaVisitState, DeliveryVisit>((ref, visit) async* {
  final uid = ref.watch(offlineMediaOwnerProvider(visit.schoolId));
  if (uid == null) return;
  final cache = await ref.watch(offlineMediaWorkerProvider.future);
  yield* cache.watchVisit(visit);
});

final onlineMediaUrlProvider = FutureProvider.autoDispose
    .family<String, ({OfflineMediaAsset asset, String uid})>(
        (ref, request) async {
  if (ref.watch(offlineMediaOwnerProvider(request.asset.schoolId)) !=
      request.uid) {
    throw StateError('Media access changed');
  }
  final auth = ref.watch(authRepositoryProvider);
  final origin = ref.watch(_mediaOriginProvider);
  final url = await origin.viewUrl(request.asset);
  if (auth.currentUser?.uid != request.uid) {
    throw StateError('Media access changed');
  }
  return url;
});

typedef ReadVisitMedia = Future<MediaInventory> Function(
  DeliveryVisit visit,
  void Function() requireOwner,
);

final readVisitMediaProvider = Provider<ReadVisitMedia>((ref) {
  final bucket = ref.watch(offlineMediaBucketProvider);
  return (visit, requireOwner) => readVisitMediaInventory(
        firestore: FirebaseFirestore.instance,
        visit: visit,
        bucket: bucket,
        requireOwner: requireOwner,
      );
});
