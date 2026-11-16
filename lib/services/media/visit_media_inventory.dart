import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/delivery_visit.dart';
import '../../models/offline/offline_media.dart';

Future<MediaInventory> readVisitMediaInventory({
  required FirebaseFirestore firestore,
  required DeliveryVisit visit,
  required String bucket,
  required void Function() requireOwner,
}) async {
  const server = GetOptions(source: Source.server);
  const maxRead = Duration(seconds: 12);
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  const fileLimit = 500;
  const roomLimit = 400;
  const parallelReads = 4;
  final assets = <OfflineMediaAsset>[];
  var unavailable = 0;

  Duration timeLeft() {
    requireOwner();
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Checking visit media timed out');
    }
    return remaining < maxRead ? remaining : maxRead;
  }

  void requireCurrent(SnapshotMetadata metadata) {
    timeLeft();
    if (metadata.hasPendingWrites || metadata.isFromCache) {
      throw StateError('The visit has work still waiting to sync');
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> read(
    CollectionReference<Map<String, dynamic>> collection,
    int remaining,
  ) async {
    final timeout = timeLeft();
    final result =
        await collection.limit(remaining + 1).get(server).timeout(timeout);
    requireCurrent(result.metadata);
    if (result.docs.length > remaining) throw const MediaInventoryTooLarge();
    return result.docs;
  }

  final workspace = firestore.doc(visit.workspacePath);
  final workspaceTimeout = timeLeft();
  final manifest = await workspace.get(server).timeout(workspaceTimeout);
  requireCurrent(manifest.metadata);
  final workspaceData = manifest.data();
  if (workspaceData?['status'] != 'ready' ||
      workspaceData?['schoolId'] != visit.schoolId ||
      workspaceData?['deliveryId'] != visit.deliveryId) {
    throw StateError('This visit is not ready');
  }
  final schoolTimeout = timeLeft();
  final school = await firestore
      .collection('schools')
      .doc(visit.schoolId)
      .get(server)
      .timeout(schoolTimeout);
  requireCurrent(school.metadata);
  final data = school.data();
  if (data == null) throw StateError('School unavailable');
  final mapPath = data['schoolMapStoragePath'] ?? data['schoolMapUrl'];
  if (mapPath != null) {
    final asset = OfflineMediaAsset.schoolMap(
      bucket: bucket,
      schoolId: visit.schoolId,
      visit: visit,
      reference: mapPath is String ? mapPath : null,
    );
    if (asset == null) {
      unavailable++;
    } else {
      assets.add(asset);
    }
  }

  final levels = await read(workspace.collection('yearLevels'), 100);
  final rooms =
      <({String yearLevelId, DocumentReference<Map<String, dynamic>> ref})>[];
  for (var offset = 0; offset < levels.length; offset += parallelReads) {
    final slice =
        levels.sublist(offset, min(offset + parallelReads, levels.length));
    final roomBatches = await Future.wait(
      slice.map((level) => read(
          level.reference.collection('classrooms'), roomLimit - rooms.length)),
      eagerError: true,
    );
    for (var index = 0; index < slice.length; index++) {
      rooms.addAll(
        roomBatches[index]
            .map((room) => (yearLevelId: slice[index].id, ref: room.reference)),
      );
      if (rooms.length > roomLimit) throw const MediaInventoryTooLarge();
    }
  }

  for (var offset = 0; offset < rooms.length; offset += parallelReads) {
    final slice =
        rooms.sublist(offset, min(offset + parallelReads, rooms.length));
    final batches = await Future.wait(
      slice.map((room) => read(room.ref.collection('photos'),
          fileLimit - assets.length - unavailable)),
      eagerError: true,
    );
    for (var index = 0; index < batches.length; index++) {
      final room = slice[index];
      for (final photo in batches[index]) {
        if (assets.length + unavailable >= fileLimit) {
          throw const MediaInventoryTooLarge();
        }
        final path = photo.data()['storagePath'];
        final asset = path is String
            ? OfflineMediaAsset.classroomPhoto(
                bucket: bucket,
                schoolId: visit.schoolId,
                visit: visit,
                yearLevelId: room.yearLevelId,
                classroomId: room.ref.id,
                photoId: photo.id,
                reference: path,
              )
            : null;
        if (asset == null) {
          unavailable++;
        } else {
          assets.add(asset);
        }
      }
    }
  }

  timeLeft();
  return MediaInventory(
    assets: List.unmodifiable(assets),
    checkedAt: DateTime.now().toUtc(),
    unavailableCount: unavailable,
  );
}

class MediaInventoryTooLarge implements Exception {
  const MediaInventoryTooLarge();
}
