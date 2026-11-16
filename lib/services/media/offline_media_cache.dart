import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../models/delivery_visit.dart';
import '../../models/offline/offline_media.dart';

typedef MediaTransfer = ({
  Future<void> done,
  Future<bool> Function() cancel,
});

abstract interface class OfflineMediaOrigin {
  Future<RemoteMediaVersion> metadata(OfflineMediaAsset asset);

  MediaTransfer download(
    OfflineMediaAsset asset,
    File target,
    void Function(int bytesTransferred) onProgress,
  );
}

typedef SavedMediaMap = ({OfflineMediaAsset asset, DateTime checkedAt});

typedef OfflineMediaVisitState = ({
  MediaInventory? inventory,
  int totalAvailable,
  int ready,
  int waiting,
  int failed,
  bool canRemoveVisitCopies,
  SavedMediaMap? savedMap,
  bool localError,
  bool discovering,
  bool clearing,
  bool cancellationStalled,
  double? progress,
});

class OfflineMediaCache {
  OfflineMediaCache({
    required Directory directory,
    required Box<String> manifest,
    required String bucket,
    required String? Function() currentUid,
    required bool Function() networkAvailable,
    required OfflineMediaOrigin origin,
    int fileLimit = 25 * 1024 * 1024,
    int totalLimit = 200 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 45),
    Duration cancelTimeout = const Duration(seconds: 5),
  })  : _directory = directory,
        _manifest = manifest,
        _bucket = bucket,
        _currentUid = currentUid,
        _networkAvailable = networkAvailable,
        _origin = origin,
        _fileLimit = fileLimit,
        _totalLimit = totalLimit,
        _timeout = timeout,
        _cancelTimeout = cancelTimeout;

  final Directory _directory;
  final Box<String> _manifest;
  final String _bucket;
  final String? Function() _currentUid;
  final bool Function() _networkAvailable;
  final OfflineMediaOrigin _origin;
  final int _fileLimit;
  final int _totalLimit;
  final Duration _timeout;
  final Duration _cancelTimeout;
  final _changes = StreamController<void>.broadcast();
  final _entries = <String, _MediaEntry>{};
  final _checkedFiles = <String, DateTime>{};
  final _inventories = <String, MediaInventory>{};
  Future<void> _mutationTail = Future.value();

  _Download? _active;
  ({String uid, DeliveryVisit visit, Completer<void> cancelled})? _preparation;
  bool _cancellationStalled = false;
  bool _disposed = false;
  bool _draining = false;
  bool _localError = false;
  bool _clearing = false;
  Future<void>? _runningDrain;

  Future<void> initialize() async {
    await _directory.create(recursive: true);
    final keptFiles = <String>{};
    for (final key in _manifest.keys.whereType<String>()) {
      if (!key.startsWith('media:')) continue;
      var entry = _MediaEntry.fromJson(_decode(_manifest.get(key)!));
      _entries[entry.key] = entry;
      final blob = entry.blob;
      if (blob != null) {
        keptFiles.add(blob.name);
        final file = _file(blob.name);
        try {
          if (await file.length() == blob.size &&
              await _hash(file, sha256) == blob.sha256) {
            _checkedFiles[blob.name] = (await file.stat()).modified;
          }
        } on FileSystemException {
          // A missing cache file remains discoverable and can be downloaded again.
        }
      }
      if (entry.phase == OfflineMediaPhase.queued) {
        entry = entry.withPhase(OfflineMediaPhase.interrupted,
            issue: OfflineMediaIssue.interrupted);
        await _put(entry);
      }
    }

    // A terminated process may leave a partial download or a finished file
    // whose journal publication was interrupted. Only this cache is scanned.
    await for (final entity in _directory.list(followLinks: false)) {
      if (entity is File && !keptFiles.contains(_basename(entity))) {
        await entity.delete();
      }
    }
  }

  Stream<OfflineMediaState> watchAsset(OfflineMediaAsset asset) =>
      _watch(() => assetState(asset)).distinct();

  Stream<OfflineMediaVisitState> watchVisit(DeliveryVisit visit) =>
      _watch(() => visitState(visit)).distinct();

  Stream<T> _watch<T>(T Function() value) => Stream.multi((sink) {
        final subscription = _changes.stream.listen(
          (_) => sink.add(value()),
          onDone: sink.close,
        );
        sink.onCancel = subscription.cancel;
        sink.add(value());
      });

  OfflineMediaState assetState(OfflineMediaAsset asset) {
    final uid = _currentUid();
    final entry = uid == null || asset.bucket != _bucket
        ? null
        : _entries[asset.accountKey(uid)];
    return _stateFor(entry);
  }

  OfflineMediaVisitState visitState(DeliveryVisit visit) {
    final uid = _currentUid();
    final inventory = uid == null ? null : _inventory(uid, visit);
    final entries = uid == null ? <_MediaEntry>[] : _visitEntries(uid, visit);
    final known = inventory?.assets ?? entries.map((entry) => entry.asset);
    final states = known.map(assetState).toList(growable: false);
    SavedMediaMap? savedMap;
    for (final entry in entries) {
      final blob = entry.blob;
      if (entry.asset.kind == OfflineMediaKind.map &&
          blob != null &&
          _localPath(blob) != null &&
          (savedMap == null || blob.verifiedAt.isAfter(savedMap.checkedAt))) {
        savedMap = (asset: entry.asset, checkedAt: blob.verifiedAt);
      }
    }
    return (
      inventory: inventory,
      totalAvailable: states.length,
      ready: states
          .where((state) => state.phase == OfflineMediaPhase.ready)
          .length,
      waiting: entries
          .where((entry) => entry.phase == OfflineMediaPhase.queued)
          .length,
      failed: states
          .where((state) =>
              state.phase == OfflineMediaPhase.failed ||
              state.phase == OfflineMediaPhase.interrupted ||
              state.phase == OfflineMediaPhase.missing ||
              state.phase == OfflineMediaPhase.stale)
          .length,
      canRemoveVisitCopies: entries.isNotEmpty,
      savedMap: savedMap,
      localError: _localError,
      discovering: _preparation?.uid == uid && _preparation?.visit == visit,
      clearing: _clearing,
      cancellationStalled: _cancellationStalled,
      progress: _active?.entry.uid == uid && _active?.entry.asset.visit == visit
          ? (_active?.percent ?? 0) / 100
          : null,
    );
  }

  Future<void> saveInventory({
    required String uid,
    required DeliveryVisit visit,
    required MediaInventory inventory,
  }) =>
      _mutate(() async {
        _requireOwner(uid);
        if (_clearing ||
            inventory.assets.any(
              (asset) => asset.visit != visit || asset.bucket != _bucket,
            )) {
          throw StateError('Offline media inventory changed');
        }
        final key = _inventoryKey(uid, visit);
        await _manifest.put(key, jsonEncode(inventory.toJson()));
        _inventories[key] = inventory;
        _notify();
      });

  Future<void> prepareVisit(
    DeliveryVisit visit, {
    required String uid,
    required Future<MediaInventory> Function(void Function() requireOwner) read,
  }) async {
    _requireOwner(uid);
    if (_preparation != null || _clearing) {
      throw StateError('Offline media is busy');
    }
    final cancelled = Completer<void>();
    _preparation = (uid: uid, visit: visit, cancelled: cancelled);
    _notify();

    void requireOwner() {
      _requireOwner(uid);
      if (cancelled.isCompleted) {
        throw const _MediaFailure(OfflineMediaIssue.interrupted);
      }
    }

    try {
      final inventory = await read(requireOwner);
      requireOwner();
      await saveInventory(uid: uid, visit: visit, inventory: inventory);
      requireOwner();
      await _request(inventory.assets, uid: uid, requireAccess: requireOwner);
    } finally {
      _preparation = null;
      _notify();
    }
  }

  /// Queue only explicitly selected items. A failed refresh keeps the last
  /// verified file available, including a map that has since changed remotely.
  Future<void> requestDownload(
    OfflineMediaAsset asset, {
    required String uid,
  }) =>
      _request([asset], uid: uid);

  Future<void> downloadInventory(DeliveryVisit visit,
      {required String uid}) async {
    _requireOwner(uid);
    final inventory = _inventory(uid, visit);
    if (inventory == null) {
      throw StateError('Visit media inventory unavailable');
    }
    await _request(inventory.assets, uid: uid);
  }

  Future<void> _request(
    Iterable<OfflineMediaAsset> assets, {
    required String uid,
    void Function()? requireAccess,
  }) =>
      _mutate(() async {
        requireAccess?.call();
        _requireOwner(uid);
        if (_clearing) throw StateError('Offline media is being cleared');
        final changes = <String, _MediaEntry>{};
        for (final asset in assets) {
          if (asset.visit == null || asset.bucket != _bucket) {
            throw StateError('Download is outside this visit cache');
          }
          final key = asset.accountKey(uid);
          final previous = _entries[key];
          if (_active?.entry.key == key ||
              previous?.phase == OfflineMediaPhase.queued) {
            continue;
          }
          if (_localPath(previous?.blob) != null &&
              asset.kind == OfflineMediaKind.photo) {
            continue;
          }
          changes[key] = (previous ?? _MediaEntry(uid: uid, asset: asset))
              .withPhase(OfflineMediaPhase.queued);
        }
        await _putAll(changes);
        _localError = false;
        wake();
      });

  Future<void> cancelAsset(OfflineMediaAsset asset, {required String uid}) =>
      _mutate(() async {
        _requireOwner(uid);
        final entry = _entries[asset.accountKey(uid)];
        if (entry != null) await _cancelEntries([entry]);
      });

  Future<void> cancelVisit(DeliveryVisit visit, {required String uid}) =>
      _mutate(() async {
        _requireOwner(uid);
        final preparation = _preparation;
        if (preparation?.uid == uid &&
            preparation?.visit == visit &&
            !preparation!.cancelled.isCompleted) {
          preparation.cancelled.complete();
        }
        await _cancelEntries(_visitEntries(uid, visit));
      });

  Future<void> _cancelEntries(Iterable<_MediaEntry> entries) async {
    final changes = <String, _MediaEntry>{};
    for (final entry in entries) {
      if (entry.phase != OfflineMediaPhase.queued) continue;
      if (_active?.entry.key == entry.key) {
        _active!.abort(OfflineMediaIssue.interrupted);
      } else {
        changes[entry.key] = entry.withPhase(OfflineMediaPhase.interrupted,
            issue: OfflineMediaIssue.interrupted);
      }
    }
    await _putAll(changes);
    _notify();
  }

  Future<void> removeVisit(DeliveryVisit visit, {required String uid}) =>
      _mutate(() async {
        _requireOwner(uid);
        final entries = _visitEntries(uid, visit);
        if ((_preparation?.uid == uid && _preparation?.visit == visit) ||
            entries.any((entry) => entry.phase == OfflineMediaPhase.queued)) {
          throw StateError('Cancel pending downloads before removing files');
        }
        for (final entry in entries) {
          _requireOwner(uid);
          await _manifest.delete('media:${entry.key}');
          _entries.remove(entry.key);
          await _deleteBlob(entry.blob);
        }
        _notify();
      });

  Future<int> deviceBytes({required String uid}) async {
    _requireOwner(uid);
    return _storedBytes();
  }

  /// Clear only downloaded files and their inventory, with no active writer.
  Future<void> clearDeviceCache({required String uid}) async {
    _requireOwner(uid);
    if (_clearing) throw const MediaCacheBusy();
    _clearing = true;
    _notify();
    try {
      final preparation = _preparation;
      if (preparation != null && !preparation.cancelled.isCompleted) {
        preparation.cancelled.complete();
      }
      _active?.abort(OfflineMediaIssue.interrupted);
      await _mutate(() => _cancelEntries(_entries.values.toList()));
      await _runningDrain?.timeout(_cancelTimeout + const Duration(seconds: 2));
      if (_cancellationStalled) throw const MediaCacheBusy();
      await _mutate(() async {
        _requireOwner(uid);
        final keys = _manifest.keys
            .whereType<String>()
            .where((key) =>
                key.startsWith('media:') || key.startsWith('inventory:'))
            .toList();
        await _manifest.deleteAll(keys);
        _entries.clear();
        _checkedFiles.clear();
        _inventories.clear();
        await for (final entity in _directory.list(followLinks: false)) {
          if (entity is File) await entity.delete();
        }
        _localError = false;
      });
    } on TimeoutException {
      throw const MediaCacheBusy();
    } on FileSystemException {
      _localError = true;
      rethrow;
    } finally {
      _clearing = false;
      _notify();
    }
  }

  void accountChanged(String? uid) {
    final preparation = _preparation;
    if (preparation != null &&
        preparation.uid != uid &&
        !preparation.cancelled.isCompleted) {
      preparation.cancelled.complete();
    }
    final active = _active;
    if (active != null && active.entry.uid != uid) {
      active.abort(OfflineMediaIssue.interrupted);
    }
    wake();
  }

  void wake() {
    _notify();
    if (_disposed ||
        _clearing ||
        _draining ||
        _cancellationStalled ||
        !_networkAvailable()) {
      return;
    }
    _draining = true;
    _runningDrain = _drain();
  }

  Future<void> _drain() async {
    try {
      while (!_disposed &&
          !_clearing &&
          !_cancellationStalled &&
          _networkAvailable()) {
        final uid = _currentUid();
        final next = _entries.values
            .where((entry) =>
                entry.uid == uid &&
                entry.asset.bucket == _bucket &&
                entry.phase == OfflineMediaPhase.queued)
            .firstOrNull;
        if (next == null) return;
        final active = _Download(next);
        _active = active;
        _notify();
        await _download(active);
        _active = null;
        _notify();
      }
    } catch (_) {
      _localError = true;
    } finally {
      _draining = false;
      _active = null;
      _notify();
    }
  }

  Future<void> _download(_Download active) async {
    final entry = active.entry;
    final part = _file('${const Uuid().v4()}.part');
    File? unpublished;
    var quarantined = false;
    try {
      _requireActive(active);
      final version = await _origin.metadata(entry.asset).timeout(_timeout);
      _requireActive(active);

      if (version.size <= 0 || version.generation.isEmpty) {
        throw const _MediaFailure(OfflineMediaIssue.invalidFile);
      }
      if (_localPath(entry.blob) != null &&
          entry.blob!.generation == version.generation &&
          entry.blob!.size == version.size) {
        await _put(entry.publish(entry.blob!.verifiedNow()));
        return;
      }
      if (version.size > _fileLimit) {
        throw const _MediaFailure(OfflineMediaIssue.tooLarge);
      }
      final usedBytes = await _storedBytes();
      if (usedBytes + version.size > _totalLimit) {
        throw const _MediaFailure(OfflineMediaIssue.cacheFull);
      }
      _requireActive(active);
      final transfer = _origin.download(entry.asset, part, (bytes) {
        if (bytes > _fileLimit || bytes > version.size) {
          active.abort(bytes > _fileLimit
              ? OfflineMediaIssue.tooLarge
              : OfflineMediaIssue.changed);
        } else if (usedBytes + bytes > _totalLimit) {
          active.abort(OfflineMediaIssue.cacheFull);
        }
        final percent = bytes * 100 ~/ version.size;
        if (active.percent != percent) {
          active.percent = percent.clamp(0, 100);
          _notify();
        }
      });
      active.transfer = transfer;
      if (active.issue != null) active.cancelTransfer();

      try {
        await Future.any<void>([transfer.done, active.aborted.future])
            .timeout(_timeout);
      } on TimeoutException {
        active.abort(OfflineMediaIssue.interrupted);
      }
      if (active.issue != null) {
        try {
          await transfer.done.timeout(_cancelTimeout);
        } on TimeoutException {
          // Keep the path reserved and the writer unique. A late callback
          // can only remove its temporary file and cannot publish it.
          active.issue = OfflineMediaIssue.cancellationStalled;
          quarantined = true;
          _cancellationStalled = true;
          unawaited(_settleLateTransfer(transfer, part));
        } catch (_) {
          // The native task reports successful cancellation as an error.
        }
      }
      _requireActive(active);

      if (await part.length() != version.size) {
        throw const _MediaFailure(OfflineMediaIssue.invalidFile);
      }
      final checksum = version.md5Base64;
      if (checksum != null && checksum.isNotEmpty) {
        final digest = await md5.bind(part.openRead()).first;
        if (base64Encode(digest.bytes) != checksum) {
          throw const _MediaFailure(OfflineMediaIssue.invalidFile);
        }
      }
      final digest = await _hash(part, sha256);
      // Storage's native writer follows an object path. Check its version again
      // before publishing, since a school map can change during a transfer.
      final currentVersion =
          await _origin.metadata(entry.asset).timeout(_timeout);
      _requireActive(active);
      if (currentVersion != version) {
        throw const _MediaFailure(OfflineMediaIssue.changed);
      }
      if (await _storedBytes() > _totalLimit) {
        throw const _MediaFailure(OfflineMediaIssue.cacheFull);
      }
      _requireActive(active);

      final name = '${const Uuid().v4()}.${entry.asset.extension}';
      unpublished = await part.rename(_file(name).path);
      final modifiedAt = (await unpublished.stat()).modified;
      _requireActive(active);
      final blob = _MediaBlob(
        name: name,
        generation: version.generation,
        size: version.size,
        sha256: digest,
        verifiedAt: DateTime.now().toUtc(),
      );
      await _put(entry.publish(blob));
      _checkedFiles[name] = modifiedAt;
      unpublished = null;
      try {
        await _deleteBlob(entry.blob);
      } on FileSystemException {
        // An orphan is charged against the budget and cleaned on restart.
        _localError = true;
      }
    } catch (error) {
      final issue = active.issue ??
          (error is _MediaFailure
              ? error.issue
              : OfflineMediaIssue.unavailable);
      final phase = switch (issue) {
        OfflineMediaIssue.interrupted => OfflineMediaPhase.interrupted,
        OfflineMediaIssue.changed when entry.blob != null =>
          OfflineMediaPhase.stale,
        _ => OfflineMediaPhase.failed,
      };
      if (!_disposed) await _put(entry.withPhase(phase, issue: issue));
    } finally {
      if (!quarantined && await part.exists()) await part.delete();
      if (unpublished != null && await unpublished.exists()) {
        await unpublished.delete();
      }
    }
  }

  Future<void> _settleLateTransfer(MediaTransfer transfer, File part) async {
    try {
      await transfer.done;
    } catch (_) {
      // Cancellation completes with an error.
    }
    try {
      if (await part.exists()) await part.delete();
    } on FileSystemException {
      _localError = true;
    } finally {
      _cancellationStalled = false;
      wake();
    }
  }

  OfflineMediaState _stateFor(_MediaEntry? entry) {
    final local = _localPath(entry?.blob);
    var phase = entry?.phase ?? OfflineMediaPhase.available;
    final active = _active;
    final isActive = active != null && active.entry.key == entry?.key;
    if (isActive) {
      phase = active.issue == null
          ? OfflineMediaPhase.downloading
          : OfflineMediaPhase.interrupted;
    } else if (local == null &&
        (phase == OfflineMediaPhase.ready ||
            phase == OfflineMediaPhase.stale)) {
      phase = OfflineMediaPhase.missing;
    }
    return (
      phase: phase,
      issue: isActive ? active.issue : entry?.issue,
      localPath: local,
      verifiedAt: local == null ? null : entry?.blob?.verifiedAt,
      progress:
          isActive && active.percent != null ? active.percent! / 100 : null,
    );
  }

  String? _localPath(_MediaBlob? blob) {
    if (blob == null) return null;
    final expectedModified = _checkedFiles[blob.name];
    if (expectedModified == null) return null;
    final file = _file(blob.name);
    try {
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file ||
          stat.size != blob.size ||
          stat.modified != expectedModified) {
        return null;
      }
      return file.path;
    } on FileSystemException {
      return null;
    }
  }

  Future<int> _storedBytes() async {
    var used = 0;
    await for (final item in _directory.list(followLinks: false)) {
      if (item is File) {
        final stat = await item.stat();
        if (stat.type == FileSystemEntityType.file) used += stat.size;
      }
    }
    return used;
  }

  Future<void> _deleteBlob(_MediaBlob? blob) async {
    if (blob == null) return;
    _checkedFiles.remove(blob.name);
    final file = _file(blob.name);
    if (await file.exists()) await file.delete();
  }

  List<_MediaEntry> _visitEntries(String uid, DeliveryVisit visit) =>
      _entries.values
          .where((entry) =>
              entry.uid == uid &&
              entry.asset.visit == visit &&
              entry.asset.bucket == _bucket)
          .toList(growable: false);

  MediaInventory? _inventory(String uid, DeliveryVisit visit) {
    final key = _inventoryKey(uid, visit);
    final cached = _inventories[key];
    if (cached != null) return cached;
    final data = _manifest.get(key);
    return data == null
        ? null
        : _inventories[key] = MediaInventory.fromJson(_decode(data));
  }

  String _inventoryKey(String uid, DeliveryVisit visit) =>
      'inventory:${OfflineMediaAsset.visitKey(uid: uid, visit: visit, bucket: _bucket)}';

  Future<void> _put(_MediaEntry entry) =>
      _mutate(() => _putAll({entry.key: entry}));

  Future<T> _mutate<T>(Future<T> Function() write) {
    final result = _mutationTail.then((_) => write());
    _mutationTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _putAll(Map<String, _MediaEntry> entries) async {
    if (entries.isEmpty) return;
    await _manifest.putAll({
      for (final entry in entries.values)
        'media:${entry.key}': jsonEncode(entry.toJson()),
    });
    _entries.addAll(entries);
    _notify();
  }

  void _requireOwner(String uid) {
    if (_disposed || _currentUid() != uid) {
      throw const _MediaFailure(OfflineMediaIssue.interrupted);
    }
  }

  void _requireActive(_Download active) {
    final issue = active.issue;
    if (issue != null) throw _MediaFailure(issue);
    _requireOwner(active.entry.uid);
  }

  File _file(String name) => File('${_directory.path}/$name');

  static String _basename(File file) => file.uri.pathSegments.last;

  static Future<String> _hash(File file, Hash hash) async =>
      (await hash.bind(file.openRead()).first).toString();

  static Map<String, dynamic> _decode(String value) =>
      jsonDecode(value) as Map<String, dynamic>;

  void _notify() {
    if (!_disposed) _changes.add(null);
  }

  void dispose() {
    _disposed = true;
    _active?.abort(OfflineMediaIssue.interrupted);
    final preparation = _preparation;
    if (preparation != null && !preparation.cancelled.isCompleted) {
      preparation.cancelled.complete();
    }
    unawaited(_changes.close());
  }
}

class MediaCacheBusy implements Exception {
  const MediaCacheBusy();
}

class _Download {
  _Download(this.entry);

  final _MediaEntry entry;
  final aborted = Completer<void>();
  MediaTransfer? transfer;
  int? percent;
  OfflineMediaIssue? issue;
  bool _cancelling = false;

  void abort(OfflineMediaIssue reason) {
    issue ??= reason;
    if (!aborted.isCompleted) aborted.complete();
    cancelTransfer();
  }

  void cancelTransfer() {
    final current = transfer;
    if (current == null || _cancelling) return;
    _cancelling = true;
    unawaited(_cancel(current));
  }

  Future<void> _cancel(MediaTransfer current) async {
    try {
      await current.cancel();
    } catch (_) {
      // If the task cannot cancel, its completion still cannot be published.
    }
  }
}

class _MediaFailure implements Exception {
  const _MediaFailure(this.issue);

  final OfflineMediaIssue issue;
}

class _MediaEntry {
  _MediaEntry({
    required this.uid,
    required this.asset,
    this.phase = OfflineMediaPhase.available,
    this.issue,
    this.blob,
  }) : key = asset.accountKey(uid);

  final String uid;
  final OfflineMediaAsset asset;
  final String key;
  final OfflineMediaPhase phase;
  final OfflineMediaIssue? issue;
  final _MediaBlob? blob;

  _MediaEntry withPhase(OfflineMediaPhase value, {OfflineMediaIssue? issue}) =>
      _MediaEntry(
          uid: uid, asset: asset, phase: value, issue: issue, blob: blob);

  _MediaEntry publish(_MediaBlob value) => _MediaEntry(
        uid: uid,
        asset: asset,
        phase: OfflineMediaPhase.ready,
        blob: value,
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'asset': asset.toJson(),
        'phase': phase.name,
        'issue': issue?.name,
        'blob': blob?.toJson(),
      };

  factory _MediaEntry.fromJson(Map<String, dynamic> data) {
    final issue = data['issue'] as String?;
    final blob = data['blob'] as Map<String, dynamic>?;
    return _MediaEntry(
      uid: data['uid'] as String,
      asset: OfflineMediaAsset.fromJson(data['asset'] as Map<String, dynamic>),
      phase: OfflineMediaPhase.values.byName(data['phase'] as String),
      issue: issue == null ? null : OfflineMediaIssue.values.byName(issue),
      blob: blob == null ? null : _MediaBlob.fromJson(blob),
    );
  }
}

class _MediaBlob {
  const _MediaBlob({
    required this.name,
    required this.generation,
    required this.size,
    required this.sha256,
    required this.verifiedAt,
  });

  final String name;
  final String generation;
  final int size;
  final String sha256;
  final DateTime verifiedAt;

  _MediaBlob verifiedNow() => _MediaBlob(
        name: name,
        generation: generation,
        size: size,
        sha256: sha256,
        verifiedAt: DateTime.now().toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'generation': generation,
        'size': size,
        'sha256': sha256,
        'verifiedAt': verifiedAt.toIso8601String(),
      };

  factory _MediaBlob.fromJson(Map<String, dynamic> data) {
    final name = data['name'] as String;
    if (!RegExp(r'^[a-f0-9-]+\.[a-z0-9]+$').hasMatch(name)) {
      throw const FormatException('Invalid cache filename');
    }
    return _MediaBlob(
      name: name,
      generation: data['generation'] as String,
      size: data['size'] as int,
      sha256: data['sha256'] as String,
      verifiedAt: DateTime.parse(data['verifiedAt'] as String),
    );
  }
}
