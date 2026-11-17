import 'dart:async';
import 'dart:math';

/// Runs Firestore "in" queries within the per-query disjunction limit and
/// combines their latest snapshots. No partial result is emitted while a
/// query is still loading or has failed.
Stream<List<T>> watchInChunks<T>(
  Iterable<String> ids,
  Stream<List<T>> Function(List<String>) watch,
) {
  final distinctIds = ids.toSet().toList();
  if (distinctIds.isEmpty) return Stream.value(<T>[]);

  const queryLimit = 30;
  final chunks = [
    for (var start = 0; start < distinctIds.length; start += queryLimit)
      distinctIds.sublist(start, min(start + queryLimit, distinctIds.length)),
  ];
  if (chunks.length == 1) return watch(chunks.single);

  return Stream.multi((controller) {
    final snapshots = List<List<T>?>.filled(chunks.length, null);
    final subscriptions = <StreamSubscription<List<T>>>[];
    var remaining = chunks.length;
    for (var index = 0; index < chunks.length; index++) {
      subscriptions.add(
        watch(chunks[index]).listen(
          (records) {
            snapshots[index] = records;
            if (snapshots.every((snapshot) => snapshot != null)) {
              controller.addSync([
                for (final snapshot in snapshots) ...snapshot!,
              ]);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            snapshots[index] = null;
            controller.addErrorSync(error, stackTrace);
          },
          onDone: () {
            if (--remaining == 0) controller.closeSync();
          },
        ),
      );
    }
    controller.onCancel = () async {
      await Future.wait(subscriptions.map((subscription) {
        return subscription.cancel();
      }));
    };
  });
}
