import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../delivery_visit.dart';

enum OfflineMediaKind { map, photo }

enum OfflineMediaPhase {
  available,
  queued,
  downloading,
  ready,
  stale,
  missing,
  failed,
  interrupted,
}

enum OfflineMediaIssue {
  tooLarge,
  cacheFull,
  changed,
  interrupted,
  unavailable,
  invalidFile,
  cancellationStalled,
}

class OfflineMediaAsset {
  const OfflineMediaAsset._(
    this.bucket,
    this.schoolId,
    this.visit,
    this.path,
    this.kind,
  );

  final String bucket;
  final String schoolId;
  final DeliveryVisit? visit;
  final String path;
  final OfflineMediaKind kind;

  String get extension => path.split('.').last.toLowerCase();
  bool get isPdf => extension == 'pdf';

  static OfflineMediaAsset? schoolMap({
    required String bucket,
    required String schoolId,
    required String? reference,
    DeliveryVisit? visit,
  }) {
    final path = _approvedPath(reference, bucket);
    if (path == null ||
        (visit != null && visit.schoolId != schoolId) ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(schoolId)) {
      return null;
    }
    final parts = path.split('/');
    if (parts.length != 4 ||
        parts[0] != 'schools' ||
        parts[1] != schoolId ||
        (parts[2] != 'maps' && parts[2] != 'map') ||
        !_mapExtensions.contains(_extension(parts.last))) {
      return null;
    }
    return OfflineMediaAsset._(
        bucket, schoolId, visit, path, OfflineMediaKind.map);
  }

  static OfflineMediaAsset? classroomPhoto({
    required String bucket,
    required String schoolId,
    required String yearLevelId,
    required String classroomId,
    required String photoId,
    required String reference,
    DeliveryVisit? visit,
  }) {
    final path = _approvedPath(reference, bucket);
    if (path == null || (visit != null && visit.schoolId != schoolId)) {
      return null;
    }
    final root = visit?.workspacePath ?? 'schools/$schoolId';
    final fileName = path.split('/').last;
    final normalPath =
        '$root/yearLevels/$yearLevelId/classrooms/$classroomId/photos/$fileName';
    final legacyPath = '$root/classrooms/$classroomId/$fileName';
    if (visit != null) {
      if (path != normalPath || fileName != '$photoId.jpg') return null;
    } else if ((path != normalPath && path != legacyPath) ||
        !_imageExtensions.contains(_extension(fileName))) {
      return null;
    }
    return OfflineMediaAsset._(
        bucket, schoolId, visit, path, OfflineMediaKind.photo);
  }

  static const _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif'
  };
  static const _mapExtensions = {..._imageExtensions, 'pdf'};

  static String _extension(String name) => name.split('.').last.toLowerCase();

  /// Convert a legacy Firebase reference to an object name. Authorization is
  /// applied by the configured Storage SDK, never by the old bearer URL.
  static String? _approvedPath(String? reference, String bucket) {
    if (reference == null || reference.isEmpty || bucket.isEmpty) return null;
    final uri = Uri.tryParse(reference);
    if (uri == null) return null;
    var path = reference;
    if (uri.hasScheme) {
      if (uri.userInfo.isNotEmpty || uri.hasFragment || uri.hasPort) {
        return null;
      }
      final parts = uri.pathSegments;
      if (uri.scheme == 'gs' && uri.host == bucket && !uri.hasQuery) {
        path = parts.join('/');
      } else if (uri.scheme == 'https' &&
          uri.host == 'firebasestorage.googleapis.com' &&
          parts.length == 5 &&
          parts[0] == 'v0' &&
          parts[1] == 'b' &&
          parts[2] == bucket &&
          parts[3] == 'o') {
        path = parts[4];
      } else {
        return null;
      }
    }
    final segment = RegExp(r'^[A-Za-z0-9_.() -]{1,180}$');
    return path.split('/').every(
              (part) => part != '.' && part != '..' && segment.hasMatch(part),
            )
        ? path
        : null;
  }

  String accountKey(String uid) => _accountKey(uid, visit, bucket, path);

  static String visitKey({
    required String uid,
    required DeliveryVisit visit,
    required String bucket,
  }) =>
      _accountKey(uid, visit, bucket, null);

  static String _accountKey(
    String uid,
    DeliveryVisit? visit,
    String bucket,
    String? assetPath,
  ) =>
      sha256
          .convert(utf8.encode(jsonEncode([
            uid,
            visit?.deliveryId,
            visit?.schoolId,
            bucket,
            assetPath,
          ])))
          .toString();

  Map<String, dynamic> toJson() => {
        'bucket': bucket,
        'schoolId': schoolId,
        'deliveryId': visit?.deliveryId,
        'path': path,
        'kind': kind.name,
      };

  factory OfflineMediaAsset.fromJson(Map<String, dynamic> data) {
    final bucket = data['bucket'] as String;
    final schoolId = data['schoolId'] as String;
    final deliveryId = data['deliveryId'] as String?;
    final visit = deliveryId == null
        ? null
        : DeliveryVisit(deliveryId: deliveryId, schoolId: schoolId);
    final path = data['path'] as String;
    if (OfflineMediaKind.values.byName(data['kind'] as String) ==
        OfflineMediaKind.map) {
      return schoolMap(
              bucket: bucket,
              schoolId: schoolId,
              reference: path,
              visit: visit) ??
          (throw const FormatException('Invalid stored map'));
    }
    final parts = path.split('/');
    final fileName = parts.last;
    final canonical = parts.length == (visit == null ? 8 : 10);
    return classroomPhoto(
          bucket: bucket,
          schoolId: schoolId,
          yearLevelId: canonical ? parts[parts.length - 5] : '',
          classroomId:
              canonical ? parts[parts.length - 3] : parts[parts.length - 2],
          photoId: fileName.endsWith('.jpg')
              ? fileName.substring(0, fileName.length - 4)
              : fileName,
          reference: path,
          visit: visit,
        ) ??
        (throw const FormatException('Invalid stored photo'));
  }

  @override
  bool operator ==(Object other) =>
      other is OfflineMediaAsset &&
      other.bucket == bucket &&
      other.schoolId == schoolId &&
      other.visit == visit &&
      other.path == path &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(bucket, schoolId, visit, path, kind);
}

class MediaInventory {
  const MediaInventory({
    required this.assets,
    required this.checkedAt,
    required this.unavailableCount,
  });

  final List<OfflineMediaAsset> assets;
  final DateTime checkedAt;
  final int unavailableCount;

  Map<String, dynamic> toJson() => {
        'assets': assets.map((asset) => asset.toJson()).toList(),
        'checkedAt': checkedAt.toUtc().toIso8601String(),
        'unavailableCount': unavailableCount,
      };

  factory MediaInventory.fromJson(Map<String, dynamic> data) => MediaInventory(
        assets: (data['assets'] as List)
            .cast<Map<String, dynamic>>()
            .map(OfflineMediaAsset.fromJson)
            .toList(growable: false),
        checkedAt: DateTime.parse(data['checkedAt'] as String),
        unavailableCount: data['unavailableCount'] as int,
      );
}

typedef OfflineMediaState = ({
  OfflineMediaPhase phase,
  OfflineMediaIssue? issue,
  String? localPath,
  DateTime? verifiedAt,
  double? progress,
});

typedef RemoteMediaVersion = ({String generation, int size, String? md5Base64});
