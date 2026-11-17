import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import '../models/delivery_visit.dart';
import 'staff_access_api.dart';

enum DeliveryVisitReadiness {
  ready,
  onlineOnly,
  unavailableOffline;

  bool canOpen({required bool online}) =>
      this == ready || (this == onlineOnly && online);
}

/// Confirms that an independent workspace exists and its preparation reads
/// are available on this device before entering a visit without a connection.
class DeliveryVisitAccess {
  DeliveryVisitAccess(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const _readinessBox = 'ready_delivery_visits';
  static const _serverOptions = GetOptions(source: Source.server);
  static const _cacheOptions = GetOptions(source: Source.cache);
  static const _readTimeout = Duration(seconds: 15);

  Future<DeliveryVisitReadiness> open(
    DeliveryVisit visit, {
    required String uid,
    required bool online,
  }) async {
    _ensureOwner(uid);
    final receipts = await Hive.openBox<Map>(_readinessBox);
    _ensureOwner(uid);

    final key = '$uid/${visit.workspacePath}';
    final root = _firestore.doc(visit.workspacePath);
    if (online) {
      try {
        var manifest = await root.get(_serverOptions).timeout(_readTimeout);
        _ensureOwner(uid);
        if (!_isReady(manifest.data(), visit)) {
          await callStaffAccess('prepareVisit', {
            'schoolId': visit.schoolId,
            'deliveryId': visit.deliveryId,
          });
          manifest = await root.get(_serverOptions).timeout(_readTimeout);
          if (!_isReady(manifest.data(), visit)) {
            throw StateError('The visit workspace is incomplete.');
          }
        }
        _ensureOwner(uid);
        final inventory = await _hydrate(visit, root, uid);
        _ensureOwner(uid);
        final receipt = {
          'preparedAt': (manifest.data()!['preparedAt'] as Timestamp)
              .millisecondsSinceEpoch,
          'collections': inventory,
        };
        if (!await _verifyCache(receipt, root, visit, uid)) {
          _ensureOwner(uid);
          return DeliveryVisitReadiness.onlineOnly;
        }
        await receipts.put(key, receipt);
        _ensureOwner(uid);
        return DeliveryVisitReadiness.ready;
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' ||
            error.code == 'unauthenticated') {
          // A current authorization failure takes precedence over an old receipt.
          await receipts.delete(key);
          rethrow;
        }
        if (await _verifyCache(receipts.get(key), root, visit, uid)) {
          return DeliveryVisitReadiness.ready;
        }
        rethrow;
      } catch (_) {
        if (await _verifyCache(receipts.get(key), root, visit, uid)) {
          return DeliveryVisitReadiness.ready;
        }
        rethrow;
      }
    }
    return await _verifyCache(receipts.get(key), root, visit, uid)
        ? DeliveryVisitReadiness.ready
        : DeliveryVisitReadiness.unavailableOffline;
  }

  Future<Map<String, List<String>>> _hydrate(
    DeliveryVisit visit,
    DocumentReference<Map<String, dynamic>> root,
    String uid,
  ) async {
    final school = await _firestore
        .collection('schools')
        .doc(visit.schoolId)
        .get(_serverOptions)
        .timeout(_readTimeout);
    if (!school.exists) throw StateError('The school cannot be found.');

    final inventory = <String, List<String>>{};
    Future<List<String>> load(String path) async {
      _ensureOwner(uid);
      final snapshot = await _firestore
          .collection(path)
          .get(_serverOptions)
          .timeout(_readTimeout);
      final ids = snapshot.docs.map((doc) => doc.id).toList();
      inventory[path] = ids;
      return ids;
    }

    final visitPath = root.path;
    final permanent = 'schools/${visit.schoolId}';
    final levels = await load('$visitPath/yearLevels');
    final rooms = <String>[];
    final classroomCollections = [
      for (final level in levels) '$visitPath/yearLevels/$level/classrooms',
    ];
    await _forEachBatched([
      '$permanent/contacts',
      '$permanent/maps',
      '$visitPath/consumables',
      '$visitPath/notes',
      ...classroomCollections,
    ], (path) async {
      final ids = await load(path);
      if (path.endsWith('/classrooms')) {
        rooms.addAll(ids.map((id) => '$path/$id'));
      }
    });
    await _forEachBatched([
      for (final room in rooms) ...[
        '$room/packTotals',
        '$room/consumables',
        '$room/yearLevelBreakdowns',
        '$room/notes',
        '$room/photos',
      ],
    ], load);
    return inventory;
  }

  Future<bool> _verifyCache(
    Map<dynamic, dynamic>? receipt,
    DocumentReference<Map<String, dynamic>> root,
    DeliveryVisit visit,
    String uid,
  ) async {
    if (receipt == null) return false;
    try {
      _ensureOwner(uid);
      final manifest = await root.get(_cacheOptions);
      final school = await _firestore
          .collection('schools')
          .doc(visit.schoolId)
          .get(_cacheOptions);
      if (!_isReady(manifest.data(), visit) || !school.exists) return false;
      final preparedAt = manifest.data()!['preparedAt'] as Timestamp;
      if (receipt['preparedAt'] != preparedAt.millisecondsSinceEpoch) {
        return false;
      }
      final collections = receipt['collections'] as Map;
      await _forEachBatched(collections.keys.cast<String>().toList(),
          (path) async {
        _ensureOwner(uid);
        final ids = (collections[path] as List).cast<String>();
        final snapshot = await _firestore.collection(path).get(_cacheOptions);
        final cached = snapshot.docs.map((doc) => doc.id).toSet();
        if (!cached.containsAll(ids)) {
          throw StateError('Saved classroom data is incomplete.');
        }
      });
      _ensureOwner(uid);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isReady(Map<String, dynamic>? data, DeliveryVisit visit) =>
      data?['status'] == 'ready' &&
      data?['preparedAt'] is Timestamp &&
      data?['schoolId'] == visit.schoolId &&
      data?['deliveryId'] == visit.deliveryId;

  void _ensureOwner(String uid) {
    if (_auth.currentUser?.uid != uid) {
      throw StateError('The signed-in account changed.');
    }
  }

  Future<void> _forEachBatched<T>(
    List<String> paths,
    Future<T> Function(String) read,
  ) async {
    const batchSize = 8;
    for (var offset = 0; offset < paths.length; offset += batchSize) {
      await Future.wait(
        paths.sublist(offset, min(offset + batchSize, paths.length)).map(read),
      );
    }
  }
}
