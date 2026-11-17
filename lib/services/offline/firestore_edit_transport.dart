import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/offline/saved_edit.dart';
import 'saved_edit_recovery.dart';

class FirestoreEditTransport implements EditTransport {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  Stream<bool> watchPending(EditIntent intent) =>
      _db.doc(intent.path).snapshots(includeMetadataChanges: true).map((doc) =>
          doc.metadata.hasPendingWrites &&
          (!intent.isClassroom || doc.data()?['lastEditId'] == intent.id) &&
          _values(intent, doc).matches(intent));

  @override
  Stream<ServerEditValues> watchSettled(EditIntent intent) => _db
      .doc(intent.path)
      .snapshots(includeMetadataChanges: true)
      .where(
          (doc) => !doc.metadata.isFromCache && !doc.metadata.hasPendingWrites)
      .map((doc) => _values(intent, doc));

  @override
  Future<ServerEditValues> readServer(EditIntent intent) async {
    final doc =
        await _db.doc(intent.path).get(const GetOptions(source: Source.server));
    if (doc.metadata.isFromCache) {
      throw StateError('Server values are unavailable.');
    }
    return _values(intent, doc);
  }

  @override
  Future<void> submit(EditIntent intent, void Function() requireOwner) {
    if (intent.deletesDocument) {
      throw StateError('Review the server note before deleting it.');
    }
    final batch = _db.batch();
    final target = _db.doc(intent.path);
    final data = _fields(intent);
    if (intent.createsDocument) {
      batch.set(target, data);
    } else if (intent.kind == SavedEditKind.checklist) {
      batch.set(target, data, SetOptions(merge: true));
    } else {
      batch.update(target, data);
    }
    if (!intent.isClassroom && intent.kind != SavedEditKind.checklist) {
      batch.update(_db.doc(intent.classroomPath), _audit(intent));
    }
    requireOwner();
    return batch.commit();
  }

  @override
  Future<void> retry(
    EditIntent intent,
    ServerEditValues reviewed,
    void Function() requireOwner,
  ) {
    final target = _db.doc(intent.path);
    return _db.runTransaction<void>((transaction) async {
      requireOwner();
      final doc = await transaction.get(target);
      final current = _values(intent, doc);
      requireOwner();
      if (current.hasPendingWrites || !current.sameValues(reviewed)) {
        throw StateError('Server values changed since review.');
      }
      if (current.matches(intent)) return;
      final data = _fields(intent);
      if (intent.deletesDocument) {
        transaction.delete(target);
      } else if (intent.createsDocument) {
        if (current.exists) {
          throw StateError('Different record uses this identifier.');
        }
        transaction.set(target, data);
      } else if (intent.kind == SavedEditKind.checklist) {
        transaction.set(target, data, SetOptions(merge: true));
      } else {
        if (!current.exists) throw StateError('This record was removed.');
        transaction.update(target, data);
      }
      if (!intent.isClassroom && intent.kind != SavedEditKind.checklist) {
        transaction.update(_db.doc(intent.classroomPath), _audit(intent));
      }
      requireOwner();
    }, timeout: const Duration(seconds: 10), maxAttempts: 3);
  }

  Map<String, Object?> _fields(EditIntent intent) => {
        for (final entry in intent.fields.entries)
          entry.key: _isTimestamp(entry.key) && entry.value is int
              ? Timestamp.fromMicrosecondsSinceEpoch(entry.value as int)
              : entry.value,
        if (intent.isClassroom) ..._audit(intent),
        if (intent.isClassroom) 'lastEditId': intent.id,
      };

  Map<String, Object?> _audit(EditIntent intent) => {
        'lastUpdatedBy': intent.updatedBy,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      };

  ServerEditValues _values(
    EditIntent intent,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return ServerEditValues(
      exists: doc.exists,
      hasPendingWrites: doc.metadata.hasPendingWrites,
      fields: {
        for (final key in intent.fields.keys)
          if ((data?.containsKey(key) ?? false) ||
              (doc.exists && intent.deletesDocument && key == 'author'))
            key: data![key] is Timestamp
                ? (data[key] as Timestamp).microsecondsSinceEpoch
                : data[key],
      },
    );
  }

  bool _isTimestamp(String key) => key == 'createdAt' || key == 'completedAt';
}
