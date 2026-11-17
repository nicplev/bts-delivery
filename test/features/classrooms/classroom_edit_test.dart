import 'dart:async';

import 'package:bts_delivery_app/models/school.dart';
import 'package:bts_delivery_app/repositories/classroom_edit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renaming preserves delivery progress and unknown document fields', () {
    final existing = {
      'name': 'Room A',
      'completionStatus': 'incomplete',
      'actualPacksDelivered': 11,
      'yearLevelBreakdowns': [
        {'id': 'breakdown'},
      ],
      'legacyField': 'preserve',
    };

    final rename = ClassroomEdit.rename(' Room A1 ');
    expect(rename.fields, {'name': 'Room A1'});
    expect({...existing, ...rename.fields}, {...existing, 'name': 'Room A1'});
  });

  test('status edits only update status and actual quantity', () {
    expect(
      ClassroomEdit.status(ClassroomCompletionStatus.incomplete, 11).fields,
      {'completionStatus': 'incomplete', 'actualPacksDelivered': 11},
    );
    expect(
      ClassroomEdit.status(ClassroomCompletionStatus.complete, null).fields,
      {'completionStatus': 'complete', 'actualPacksDelivered': null},
    );
    expect(
      () => ClassroomEdit.status(ClassroomCompletionStatus.incomplete, -1),
      throwsArgumentError,
    );
    expect(
      () => ClassroomEdit.status(ClassroomCompletionStatus.complete, 11),
      throwsArgumentError,
    );
  });

  test('another pending edit cannot confirm this edit', () async {
    final edits = StreamController<String?>();
    final commit = Completer<void>();
    final result = observeClassroomEdit(
      editId: 'target',
      pendingEditIds: edits.stream,
      write: () => commit.future,
      confirmationTimeout: const Duration(milliseconds: 15),
    );
    edits.add('different');
    final receipt = (await result).dataOrNull!;
    expect(receipt.status, ClassroomEditStatus.unconfirmed);
    expect(edits.hasListener, isFalse);
    commit.complete();
    expect((await receipt.acknowledgment).isSuccess, isTrue);
    await edits.close();
  });

  test('offline pending confirmation can later receive a server rejection',
      () async {
    final edits = StreamController<String?>();
    final commit = Completer<void>();
    final result = observeClassroomEdit(
      editId: 'target',
      pendingEditIds: edits.stream,
      write: () => commit.future,
    );
    edits.add(null);
    edits.add('target');
    final receipt = (await result).dataOrNull!;
    expect(receipt.status, ClassroomEditStatus.pending);
    expect(edits.hasListener, isFalse);

    commit.completeError(StateError('permission-denied'));
    expect((await receipt.acknowledgment).isFailure, isTrue);
    await edits.close();
  });

  test('a server result wins if no local pending snapshot is observed',
      () async {
    final edits = StreamController<String?>();
    final result = await observeClassroomEdit(
      editId: 'target',
      pendingEditIds: edits.stream,
      write: () async {},
    );
    expect(result.dataOrNull?.status, ClassroomEditStatus.saved);
    expect(edits.hasListener, isFalse);
    await edits.close();
  });
}
