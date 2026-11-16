import 'dart:async';

import 'package:bts_delivery_app/repositories/scoped_query_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an empty assignment list performs no database query', () async {
    final results = watchInChunks<String>([], (_) => fail('unexpected query'));
    expect(await results.first, isEmpty);
  });

  test('waits for all query chunks, propagates errors, and cancels all watches',
      () async {
    final requested = <List<String>>[];
    final streams = <StreamController<List<String>>>[];
    final results = <List<String>>[];
    final errors = <Object>[];
    final ids = ['0', ...List.generate(32, (index) => '$index')];

    final subscription = watchInChunks(ids, (chunk) {
      requested.add(chunk);
      final stream = StreamController<List<String>>();
      streams.add(stream);
      return stream.stream;
    }).listen(results.add, onError: errors.add);
    addTearDown(subscription.cancel);

    expect(requested.map((chunk) => chunk.length), [30, 2]);
    streams.first.add(['first']);
    await Future<void>.delayed(Duration.zero);
    expect(results, isEmpty);

    streams.last.add(['second']);
    await Future<void>.delayed(Duration.zero);
    expect(results, [
      ['first', 'second']
    ]);

    final error = StateError('chunk failed');
    streams.last.addError(error);
    streams.first.add(['first updated']);
    await Future<void>.delayed(Duration.zero);
    expect(errors, [error]);
    expect(results, hasLength(1));

    streams.last.add(['second recovered']);
    await Future<void>.delayed(Duration.zero);
    expect(results.last, ['first updated', 'second recovered']);

    await subscription.cancel();
    expect(streams.every((stream) => !stream.hasListener), isTrue);
    for (final stream in streams) {
      await stream.close();
    }
  });
}
