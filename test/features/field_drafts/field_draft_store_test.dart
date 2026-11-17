import 'dart:io';

import 'package:bts_delivery_app/services/offline/field_draft_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('reopens a draft only for the matching account, visit, form and entity',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('field-drafts-test-');
    Hive.init(directory.path);
    addTearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    const note = FieldDraftTarget(
      schoolId: 'school',
      deliveryId: 'monday',
      yearLevelId: 'year',
      classroomId: 'room',
      form: 'note',
      entityId: 'note-1',
    );
    final key = note.keyFor('owner');
    final store = await HiveFieldDraftStore.open();
    await store.write(
        key, FieldDraft(revision: 'r1', values: {'content': 'north door'}));
    await Hive.close();

    final restored = await HiveFieldDraftStore.open();
    expect((await restored.read(key))?.revision, 'r1');
    expect((await restored.read(key))?.values, {'content': 'north door'});
    expect(await restored.read(note.keyFor('another-account')), isNull);
    for (final different in [
      const FieldDraftTarget(
          schoolId: 'school',
          deliveryId: 'tuesday',
          yearLevelId: 'year',
          classroomId: 'room',
          form: 'note',
          entityId: 'note-1'),
      const FieldDraftTarget(
          schoolId: 'school',
          yearLevelId: 'year',
          classroomId: 'room',
          form: 'note',
          entityId: 'note-1'),
      const FieldDraftTarget(
          schoolId: 'school',
          deliveryId: 'monday',
          yearLevelId: 'year',
          classroomId: 'other-room',
          form: 'note',
          entityId: 'note-1'),
      const FieldDraftTarget(
          schoolId: 'school',
          deliveryId: 'monday',
          yearLevelId: 'year',
          classroomId: 'room',
          form: 'note',
          entityId: 'note-2'),
      const FieldDraftTarget(
          schoolId: 'school',
          deliveryId: 'monday',
          yearLevelId: 'year',
          classroomId: 'room',
          form: 'rename',
          entityId: 'note-1'),
    ]) {
      expect(await restored.read(different.keyFor('owner')), isNull);
    }
  });

  test('finishing an older revision cannot clear a newer draft', () async {
    final directory =
        await Directory.systemTemp.createTemp('field-drafts-test-');
    Hive.init(directory.path);
    addTearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    final store = await HiveFieldDraftStore.open();
    await store.write(
        'note', FieldDraft(revision: 'old', values: {'content': 'a'}));
    await store.write(
        'note', FieldDraft(revision: 'new', values: {'content': 'b'}));
    await store.remove('note', revision: 'old');
    expect((await store.read('note'))?.values, {'content': 'b'});
    await store.remove('note', revision: 'new');
    expect(await store.read('note'), isNull);
  });
}
