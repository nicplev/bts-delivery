import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/school.dart';
import '../models/signoff_snapshot.dart';

/// Read every input required by the summary. A failed query or malformed row
/// rejects the capture. Cache reads can be incomplete even when they succeed.
Future<SignOffSnapshot> readSignOffSnapshot(
  DocumentReference<Map<String, dynamic>> school,
  Source source, {
  DocumentReference<Map<String, dynamic>>? workspace,
}) async {
  final options = GetOptions(source: source);
  final schoolDoc = await school.get(options);
  final data = schoolDoc.data();
  if (data == null) throw StateError('School data is unavailable');
  var reviewed = source == Source.server &&
      !schoolDoc.metadata.hasPendingWrites &&
      !schoolDoc.metadata.isFromCache;
  if (workspace != null) {
    final manifest = await workspace.get(options);
    if (manifest.data()?['status'] != 'ready') {
      throw StateError('Delivery workspace is unavailable');
    }
    if (manifest.metadata.hasPendingWrites || manifest.metadata.isFromCache) {
      reviewed = false;
    }
  }
  final records = workspace ?? school;

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> read(
    Query<Map<String, dynamic>> query,
  ) async {
    final value = await query.get(options);
    if (value.metadata.hasPendingWrites || value.metadata.isFromCache) {
      reviewed = false;
    }
    return value.docs;
  }

  final levels = await read(records.collection('yearLevels'));
  final notes = await read(records.collection('notes'));
  final schoolTotals = <String, ConsumableSummary>{};
  final byLevel = <String, Map<String, dynamic>>{};
  final byClass = <String, Map<String, Map<String, dynamic>>>{};
  final packsByLevel = <String, int>{};
  final packsByClass = <String, Map<String, int>>{};
  final notesByClassroom = <String, Map<String, List<String>>>{};
  final rows = <Map<String, dynamic>>[];
  final photos = <String>[];
  var packTotal = 0;

  for (final level in levels) {
    final label = (level.data()['label'] ?? level.data()['name']) as String;
    final year =
        packsByLevel.containsKey(label) ? '$label (${level.id})' : label;
    final classrooms = await read(level.reference.collection('classrooms'));
    final yearTotals = <String, ConsumableSummary>{};
    final classPacks = <String, int>{};
    final classItems = <String, Map<String, dynamic>>{};
    final classNotes = <String, List<String>>{};

    for (final doc in classrooms) {
      final classroom = Classroom.fromJson({...doc.data(), 'id': doc.id});
      final name = classPacks.containsKey(classroom.name)
          ? '${classroom.name} (${doc.id})'
          : classroom.name;
      final ref = doc.reference;
      final results = await Future.wait([
        read(ref
            .collection('packTotals')
            .orderBy('createdAt', descending: true)
            .limit(1)),
        read(ref.collection('consumables')),
        read(ref.collection('notes')),
        read(ref.collection('photos')),
      ]);
      if (results[0].isEmpty) reviewed = false;
      final packs =
          results[0].isEmpty ? 0 : results[0].single.data()['total'] as int;
      final items = <String, ConsumableSummary>{};
      final details = <String, ConsumableDeliveryDetail>{};
      for (final item in results[1]) {
        final value = Consumable.fromJson({...item.data(), 'id': item.id});
        _addItem(items, value);
        _addItem(yearTotals, value);
        _addItem(schoolTotals, value);
        final name = details.containsKey(value.itemName)
            ? '${value.itemName} (${item.id})'
            : value.itemName;
        details[name] = ConsumableDeliveryDetail(
          itemName: value.itemName,
          expectedQuantity: value.quantity,
          actualQuantityDelivered: value.actualQuantityDelivered,
          unit: value.unit,
        );
      }

      final partial = (classroom.actualPacksDelivered != null &&
              classroom.actualPacksDelivered != packs) ||
          details.values.any(
            (item) => item.actualQuantityDelivered != item.expectedQuantity,
          );
      final status =
          classroom.completionStatus == ClassroomCompletionStatus.complete &&
                  partial
              ? ClassroomCompletionStatus.incomplete
              : classroom.completionStatus;
      rows.add({
        'yearLevel': year,
        'classroomName': name,
        'yearLevelId': level.id,
        'classroomId': doc.id,
        'status': status.name,
        'expectedPacks': packs,
        if (results[0].isEmpty) 'expectedPacksUnavailable': true,
        'actualPacksDelivered': classroom.actualPacksDelivered,
        'consumables': details.map((id, value) => MapEntry(id, value.toJson())),
      });
      packTotal += packs;
      classPacks[name] = packs;
      classItems[name] = _encodeItems(items);
      final noteTexts = [
        for (final note in results[2]) _noteText(note.data()),
      ];
      if (noteTexts.isNotEmpty) classNotes[name] = noteTexts;
      photos.addAll(
          results[3].map((photo) => photo.data()['storagePath'] as String));
    }

    packsByLevel[year] =
        classPacks.values.fold(0, (total, value) => total + value);
    packsByClass[year] = classPacks;
    byLevel[year] = _encodeItems(yearTotals);
    byClass[year] = classItems;
    if (classNotes.isNotEmpty) notesByClassroom[year] = classNotes;
  }

  final snapshot = SignOffSnapshot(
    sourceReadAt: DateTime.now().toUtc(),
    serverReviewed: reviewed && rows.isNotEmpty,
    summary: {
      'schoolName': data['name'] as String,
      'schoolAddress': data['address'] as String?,
      'totalPacks': packTotal,
      'packTotalsByYearLevel': packsByLevel,
      'packTotalsByClassroom': packsByClass,
      'consumablesTotals': _encodeItems(schoolTotals),
      'consumablesByYearLevel': byLevel,
      'consumablesByClassroom': byClass,
      'classroomDeliveryDetails': rows,
      'photoUrls': photos,
      'notes': notes.isEmpty
          ? null
          : notes.map((note) => _noteText(note.data())).join('\n\n'),
      'notesByClassroom': notesByClassroom,
    },
  );
  return snapshot;
}

String _noteText(Map<String, dynamic> note) {
  final content = note['content'] as String;
  final author = note['author'] as String?;
  return author == null ? content : '$content (by $author)';
}

void _addItem(Map<String, ConsumableSummary> target, Consumable item) {
  final old = target[item.itemName];
  if (old != null && old.unit != item.unit) {
    throw const FormatException('Consumable units need review');
  }
  target[item.itemName] = ConsumableSummary(
    itemName: item.itemName,
    quantity: (old?.quantity ?? 0) + item.quantity,
    unit: item.unit,
  );
}

Map<String, dynamic> _encodeItems(Map<String, ConsumableSummary> items) =>
    items.map((id, value) => MapEntry(id, value.toJson()));
