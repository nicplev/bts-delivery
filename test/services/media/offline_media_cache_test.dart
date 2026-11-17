import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bts_delivery_app/models/delivery_visit.dart';
import 'package:bts_delivery_app/models/offline/offline_media.dart';
import 'package:bts_delivery_app/services/media/offline_media_cache.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _visit = DeliveryVisit(deliveryId: 'visit-a', schoolId: 'school-a');
const _otherVisit = DeliveryVisit(deliveryId: 'visit-b', schoolId: 'school-a');
const _bucket = 'approved.firebasestorage.app';

OfflineMediaAsset _map(
        {DeliveryVisit visit = _visit, String name = 'map.pdf'}) =>
    OfflineMediaAsset.schoolMap(
      bucket: _bucket,
      schoolId: 'school-a',
      reference: 'schools/school-a/map/$name',
      visit: visit,
    )!;

OfflineMediaAsset _photo(
        {DeliveryVisit visit = _visit, String id = 'photo-a'}) =>
    OfflineMediaAsset.classroomPhoto(
      bucket: _bucket,
      schoolId: visit.schoolId,
      yearLevelId: 'year-a',
      classroomId: 'room-a',
      photoId: id,
      reference:
          '${visit.workspacePath}/yearLevels/year-a/classrooms/room-a/photos/$id.jpg',
      visit: visit,
    )!;

void main() {
  test('only configured bucket and exact visit media paths are allowed', () {
    final map = _map();
    final escaped = Uri.encodeComponent(map.path);
    final legacy = OfflineMediaAsset.schoolMap(
      bucket: _bucket,
      schoolId: 'school-a',
      reference:
          'https://firebasestorage.googleapis.com/v0/b/$_bucket/o/$escaped?alt=media&token=discarded',
      visit: _visit,
    );
    expect(legacy, map);
    for (final reference in [
      'https://example.invalid/map.pdf',
      'https://firebasestorage.googleapis.com.evil.invalid/v0/b/$_bucket/o/$escaped',
      'http://firebasestorage.googleapis.com/v0/b/$_bucket/o/$escaped',
      'gs://another-bucket/${map.path}',
      'schools/school-a/map/../map.pdf',
      'schools/other-school/map/map.pdf',
      'schools/school-a/signoffs/map.pdf',
    ]) {
      expect(
          OfflineMediaAsset.schoolMap(
            bucket: _bucket,
            schoolId: _visit.schoolId,
            reference: reference,
            visit: _visit,
          ),
          isNull,
          reason: reference);
    }
    final photo = _photo();
    expect(OfflineMediaAsset.fromJson(photo.toJson()), photo);
    expect(
        OfflineMediaAsset.classroomPhoto(
          bucket: _bucket,
          schoolId: _visit.schoolId,
          yearLevelId: 'year-a',
          classroomId: 'room-a',
          photoId: 'photo-a',
          reference: photo.path,
          visit: _otherVisit,
        ),
        isNull);
    expect(map.accountKey('person-a'),
        isNot(_map(visit: _otherVisit).accountKey('person-a')));
    expect(map.accountKey('person-a'), isNot(map.accountKey('person-b')));
  });

  group('offline media journal', () {
    late Directory temp;
    late Directory files;
    late _Origin origin;
    late OfflineMediaCache cache;
    var connected = true;
    String? uid = 'person-a';

    Future<void> open({
      int fileLimit = 25,
      int totalLimit = 200,
      Duration timeout = const Duration(seconds: 2),
    }) async {
      final journal = await Hive.openBox<String>('test-media');
      cache = OfflineMediaCache(
        directory: files,
        manifest: journal,
        bucket: _bucket,
        currentUid: () => uid,
        networkAvailable: () => connected,
        origin: origin,
        fileLimit: fileLimit,
        totalLimit: totalLimit,
        timeout: timeout,
        cancelTimeout: const Duration(milliseconds: 25),
      );
      await cache.initialize();
    }

    Future<void> restart() async {
      cache.dispose();
      await Hive.close();
      await open();
    }

    Future<OfflineMediaState> phase(
      OfflineMediaAsset asset,
      OfflineMediaPhase expected,
    ) =>
        cache
            .watchAsset(asset)
            .firstWhere((state) => state.phase == expected)
            .timeout(const Duration(seconds: 3), onTimeout: () {
          fail('Expected $expected, got ${cache.assetState(asset)}. '
              'Network calls ${origin.metadataReads}/${origin.transfers}.');
        });

    setUp(() async {
      connected = true;
      uid = 'person-a';
      temp = await Directory.systemTemp.createTemp('bts-visit-media');
      files = Directory('${temp.path}/media');
      Hive.init(temp.path);
      origin = _Origin();
      await open();
    });

    tearDown(() async {
      cache.dispose();
      await Hive.close();
      await temp.delete(recursive: true);
    });

    test('verified file reopens offline without recontacting Storage',
        () async {
      final photo = _photo();
      origin.put(photo, '1', [1, 2, 3, 4]);
      await cache.requestDownload(photo, uid: uid!);
      final saved = await phase(photo, OfflineMediaPhase.ready);
      expect(await File(saved.localPath!).readAsBytes(), [1, 2, 3, 4]);
      final reads = origin.metadataReads;

      connected = false;
      await restart();
      final offline = await phase(photo, OfflineMediaPhase.ready);
      expect(offline.localPath, saved.localPath);
      expect(origin.metadataReads, reads);
      expect(cache.assetState(_photo(visit: _otherVisit)).localPath, isNull);

      await cache.removeVisit(_visit, uid: uid!);
      expect(cache.assetState(photo).localPath, isNull);
      expect(await File(saved.localPath!).exists(), isFalse);
      expect(origin.metadataReads, reads);
    });

    test(
        'refresh respects mutable generation and preserves prior copy on failure',
        () async {
      final map = _map();
      origin.put(map, '1', [1, 2, 3]);
      await cache.requestDownload(map, uid: uid!);
      final saved = await phase(map, OfflineMediaPhase.ready);
      await cache.requestDownload(map, uid: uid!);
      expect((await phase(map, OfflineMediaPhase.ready)).localPath,
          saved.localPath);
      expect(origin.transfers, 1);

      origin.put(map, '2', [4, 5, 6]);
      origin.afterWrite = () => origin.put(map, '3', [7, 8, 9]);
      await cache.requestDownload(map, uid: uid!);
      final stale = await phase(map, OfflineMediaPhase.stale);
      expect(stale.issue, OfflineMediaIssue.changed);
      expect(stale.localPath, saved.localPath);
      expect(await File(stale.localPath!).readAsBytes(), [1, 2, 3]);

      origin.afterWrite = null;
      await cache.requestDownload(map, uid: uid!);
      final newer = await phase(map, OfflineMediaPhase.ready);
      expect(newer.localPath, isNot(saved.localPath));
      expect(await File(newer.localPath!).readAsBytes(), [7, 8, 9]);
      expect(await File(saved.localPath!).exists(), isFalse);
    });

    test('earlier map remains available when the current map uses a new path',
        () async {
      final previous = _map(name: 'previous.pdf');
      final current = _map(name: 'current.pdf');
      origin.put(previous, '1', [1, 2, 3]);
      await cache.requestDownload(previous, uid: uid!);
      final saved = await phase(previous, OfflineMediaPhase.ready);
      await cache.saveInventory(
        uid: uid!,
        visit: _visit,
        inventory: MediaInventory(
          assets: [current],
          checkedAt: DateTime.now(),
          unavailableCount: 0,
        ),
      );
      connected = false;
      await restart();
      final state = cache.visitState(_visit);
      expect(state.savedMap?.asset, previous);
      expect(state.ready, 0);
      expect(cache.assetState(current).localPath, isNull);
      expect(await File(saved.localPath!).readAsBytes(), [1, 2, 3]);
      uid = 'person-b';
      cache.accountChanged(uid);
      expect(cache.visitState(_visit).savedMap, isNull);
    });

    test('recovery removes partials and detects same-size corruption',
        () async {
      final photo = _photo();
      final map = _map();
      origin.put(photo, '1', [1, 2, 3, 4]);
      await cache.requestDownload(photo, uid: uid!);
      final saved = await phase(photo, OfflineMediaPhase.ready);
      await File(saved.localPath!).writeAsBytes([9, 8, 7, 6]);

      connected = false;
      await cache.requestDownload(map, uid: uid!);
      final orphan =
          await File('${files.path}/interrupted.part').writeAsBytes([1]);
      await restart();
      expect(
          (await phase(map, OfflineMediaPhase.interrupted)).localPath, isNull);
      expect(await orphan.exists(), isFalse);
      expect((await phase(photo, OfflineMediaPhase.missing)).localPath, isNull);
    });

    test('does not publish wrong bytes or an evicted file', () async {
      final photo = _photo();
      origin.put(photo, '1', [1, 2, 3]);
      origin.wrongBytes = true;
      await cache.requestDownload(photo, uid: uid!);
      expect((await phase(photo, OfflineMediaPhase.failed)).issue,
          OfflineMediaIssue.invalidFile);
      expect(files.listSync(), isEmpty);
      origin.wrongBytes = false;
      await cache.requestDownload(photo, uid: uid!);
      final saved = await phase(photo, OfflineMediaPhase.ready);
      await File(saved.localPath!).delete();
      expect(cache.assetState(photo).phase, OfflineMediaPhase.missing);
      expect(cache.assetState(photo).localPath, isNull);
    });

    test('account change hides downloaded files and interrupts a writer',
        () async {
      final map = _map();
      final photo = _photo();
      origin.put(map, '1', [1, 2, 3]);
      origin.put(photo, '1', [4, 5, 6]);
      await cache.requestDownload(map, uid: uid!);
      final saved = await phase(map, OfflineMediaPhase.ready);

      final transfer = Completer<void>();
      origin.pause = transfer;
      await cache.requestDownload(photo, uid: uid!);
      await origin.waitForTransfers(2);
      uid = 'person-b';
      cache.accountChanged(uid);
      expect(origin.cancellations, 1);
      expect(cache.assetState(map).localPath, isNull);
      expect(cache.assetState(photo).localPath, isNull);
      transfer.complete();
      await expectLater(cache.requestDownload(photo, uid: 'person-a'),
          throwsA(isA<Exception>()));

      uid = 'person-a';
      cache.accountChanged(uid);
      expect((await phase(photo, OfflineMediaPhase.interrupted)).localPath,
          isNull);
      expect(cache.assetState(map).localPath, saved.localPath);
    });

    test('hung cancellation stays actionable and cannot publish late bytes',
        () async {
      cache.dispose();
      await open(timeout: const Duration(milliseconds: 40));
      final photo = _photo();
      final second = _photo(id: 'second');
      origin.put(photo, '1', [1, 2, 3]);
      origin.put(second, '1', [4, 5, 6]);
      final stalled = Completer<void>();
      origin.pause = stalled;
      origin.ignoreCancel = true;
      await cache.requestDownload(photo, uid: uid!);
      await origin.waitForTransfers(1);
      await cache.cancelAsset(photo, uid: uid!);
      final failure = await phase(photo, OfflineMediaPhase.failed);
      expect(failure.issue, OfflineMediaIssue.cancellationStalled);
      expect(cache.visitState(_visit).cancellationStalled, isTrue);
      await expectLater(
          cache.clearDeviceCache(uid: uid!), throwsA(isA<MediaCacheBusy>()));
      await cache.requestDownload(second, uid: uid!);
      expect(origin.transfers, 1);

      origin.pause = null;
      stalled.complete();
      await phase(second, OfflineMediaPhase.ready);
      expect(cache.assetState(photo).localPath, isNull);
      expect(cache.visitState(_visit).cancellationStalled, isFalse);
      expect(files.listSync().length, 1);
    });

    test(
        'quota includes other accounts and partial bytes, without cross-account display',
        () async {
      cache.dispose();
      await open(fileLimit: 10, totalLimit: 12);
      final first = _photo();
      final second = _photo(id: 'second');
      final tooLarge = _photo(id: 'large');
      origin.put(first, '1', List.filled(6, 1));
      origin.put(second, '1', List.filled(5, 2));
      origin.put(tooLarge, '1', List.filled(11, 3));
      await cache.requestDownload(first, uid: uid!);
      await phase(first, OfflineMediaPhase.ready);

      uid = 'person-b';
      cache.accountChanged(uid);
      expect(cache.assetState(first).localPath, isNull);
      await File('${files.path}/partial.part').writeAsBytes([1, 2]);
      await cache.requestDownload(second, uid: uid!);
      expect((await phase(second, OfflineMediaPhase.failed)).issue,
          OfflineMediaIssue.cacheFull);
      expect(origin.transfers, 1);
      await cache.requestDownload(tooLarge, uid: uid!);
      expect((await phase(tooLarge, OfflineMediaPhase.failed)).issue,
          OfflineMediaIssue.tooLarge);
      expect(origin.transfers, 1);
    });

    test('device clear frees corrupt copies and other accounts’ quota',
        () async {
      cache.dispose();
      await open(fileLimit: 10, totalLimit: 10);
      final first = _photo();
      final second = _photo(id: 'second');
      origin.put(first, '1', List.filled(7, 1));
      origin.put(second, '1', List.filled(5, 2));
      await cache.requestDownload(first, uid: uid!);
      final saved = await phase(first, OfflineMediaPhase.ready);
      await File(saved.localPath!).writeAsBytes(List.filled(8, 3));
      expect(cache.assetState(first).phase, OfflineMediaPhase.missing);
      expect(cache.visitState(_visit).canRemoveVisitCopies, isTrue);

      uid = 'person-b';
      cache.accountChanged(uid);
      await cache.requestDownload(second, uid: uid!);
      expect((await phase(second, OfflineMediaPhase.failed)).issue,
          OfflineMediaIssue.cacheFull);
      expect(await cache.deviceBytes(uid: uid!), 8);
      final pendingUpload =
          await File('${temp.path}/pending-evidence.png').writeAsBytes([7]);
      await cache.clearDeviceCache(uid: uid!);
      expect(await cache.deviceBytes(uid: uid!), 0);
      expect(await pendingUpload.readAsBytes(), [7]);

      await cache.requestDownload(second, uid: uid!);
      await phase(second, OfflineMediaPhase.ready);
      uid = 'person-a';
      cache.accountChanged(uid);
      expect(cache.assetState(first).localPath, isNull);
    });

    test('inventory cancellation preserves last confirmed list', () async {
      final previous = MediaInventory(
        assets: [_map()],
        checkedAt: DateTime.utc(2026),
        unavailableCount: 1,
      );
      await cache.saveInventory(uid: uid!, visit: _visit, inventory: previous);
      final wait = Completer<void>();
      final job = cache.prepareVisit(
        _visit,
        uid: uid!,
        read: (requireOwner) async {
          await wait.future;
          requireOwner();
          return MediaInventory(
              assets: [_photo()],
              checkedAt: DateTime.now(),
              unavailableCount: 0);
        },
      );
      final cancelled = expectLater(job, throwsA(isA<Exception>()));
      expect(cache.visitState(_visit).discovering, isTrue);
      await cache.cancelVisit(_visit, uid: uid!);
      wait.complete();
      await cancelled;
      expect(cache.visitState(_visit).inventory?.assets, previous.assets);
      expect(cache.visitState(_visit).discovering, isFalse);
      expect(origin.transfers, 0);
    });
  });
}

class _Origin implements OfflineMediaOrigin {
  final files = <String, ({String generation, List<int> bytes})>{};
  int transfers = 0;
  int metadataReads = 0;
  int cancellations = 0;
  bool ignoreCancel = false;
  bool wrongBytes = false;
  Completer<void>? pause;
  void Function()? afterWrite;

  void put(OfflineMediaAsset asset, String generation, List<int> bytes) {
    files[asset.path] = (generation: generation, bytes: bytes);
  }

  @override
  Future<RemoteMediaVersion> metadata(OfflineMediaAsset asset) async {
    metadataReads++;
    final file = files[asset.path]!;
    return (
      generation: file.generation,
      size: file.bytes.length,
      md5Base64: base64Encode(md5.convert(file.bytes).bytes),
    );
  }

  @override
  MediaTransfer download(
    OfflineMediaAsset asset,
    File target,
    void Function(int) onProgress,
  ) {
    transfers++;
    final bytes = files[asset.path]!.bytes;
    final waiting = pause;
    var cancelled = false;
    return (
      done: () async {
        await waiting?.future;
        if (cancelled) throw const FileSystemException('canceled');
        await target
            .writeAsBytes(wrongBytes ? List.filled(bytes.length, 0) : bytes);
        onProgress(bytes.length);
        afterWrite?.call();
      }(),
      cancel: () async {
        cancellations++;
        if (!ignoreCancel) cancelled = true;
        return !ignoreCancel;
      },
    );
  }

  Future<void> waitForTransfers(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (transfers < count) {
      if (DateTime.now().isAfter(deadline)) fail('Download did not start');
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }
}
