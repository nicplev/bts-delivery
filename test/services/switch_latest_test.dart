import 'dart:async';

import 'package:bts_delivery_app/services/switch_latest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account switch clears old data and ignores the previous stream',
      () async {
    final auth = StreamController<String>(sync: true);
    final first = StreamController<String?>(sync: true);
    final second = StreamController<String?>(sync: true);
    final seen = <String?>[];
    final subscription = switchLatest<String, String?>(
      auth.stream,
      (uid) => uid == 'first' ? first.stream : second.stream,
      reset: () => null,
    ).listen(seen.add);

    auth.add('first');
    first.add('first account data');
    auth.add('second');
    first.add('late first account data');
    second.add('second account data');
    await Future<void>.delayed(Duration.zero);

    expect(seen, ['first account data', null, 'second account data']);
    await subscription.cancel();
    await auth.close();
    await first.close();
    await second.close();
  });

  test('document failures reach the active subscriber', () async {
    final error = StateError('permission denied');
    final stream = switchLatest(
      Stream.value('account'),
      (_) => Stream<String>.error(error),
    );
    await expectLater(
        stream, emitsInOrder([emitsError(same(error)), emitsDone]));
  });
}
