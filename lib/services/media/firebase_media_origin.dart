import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import '../../models/offline/offline_media.dart';
import 'offline_media_cache.dart';

class FirebaseMediaOrigin implements OfflineMediaOrigin {
  FirebaseMediaOrigin(this._storage);

  final FirebaseStorage _storage;

  Reference _reference(OfflineMediaAsset asset) {
    if (asset.bucket != _storage.bucket) {
      throw StateError('Media is outside the configured bucket');
    }
    return _storage.ref(asset.path);
  }

  Future<String> viewUrl(OfflineMediaAsset asset) =>
      _reference(asset).getDownloadURL().timeout(const Duration(seconds: 15));

  @override
  Future<RemoteMediaVersion> metadata(OfflineMediaAsset asset) async {
    final metadata = await _reference(asset).getMetadata();
    return (
      generation: metadata.generation ?? '',
      size: metadata.size ?? 0,
      md5Base64: metadata.md5Hash,
    );
  }

  @override
  MediaTransfer download(
    OfflineMediaAsset asset,
    File target,
    void Function(int bytesTransferred) onProgress,
  ) {
    final task = _reference(asset).writeToFile(target);
    final progress = task.snapshotEvents.listen(
      (snapshot) => onProgress(snapshot.bytesTransferred),
      // Completion owns failure handling and partial-file cleanup.
      onError: (Object _) {},
    );
    return (
      done: task.then<void>((_) {}).whenComplete(progress.cancel),
      cancel: task.cancel,
    );
  }
}
