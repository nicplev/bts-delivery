import 'dart:async';

/// Listens to the latest selected stream until the source selects another.
Stream<T> switchLatest<S, T>(
  Stream<S> source,
  Stream<T> Function(S) select, {
  T Function()? reset,
}) {
  return Stream.multi((sink) {
    StreamSubscription<T>? current;
    var generation = 0;
    var sourceDone = false;
    var currentDone = true;

    void finishIfDone() {
      if (sourceDone && currentDone) sink.close();
    }

    final outer = source.listen(
        (value) {
          if (generation > 0 && reset != null) sink.add(reset());
          final selectedGeneration = ++generation;
          unawaited(current?.cancel());
          currentDone = false;
          try {
            current = select(value).listen(
              (value) {
                if (selectedGeneration == generation) sink.add(value);
              },
              onError: (Object error, StackTrace stack) {
                if (selectedGeneration == generation) {
                  sink.addError(error, stack);
                }
              },
              onDone: () {
                if (selectedGeneration != generation) return;
                currentDone = true;
                finishIfDone();
              },
            );
          } catch (error, stack) {
            currentDone = true;
            sink.addError(error, stack);
          }
        },
        onError: sink.addError,
        onDone: () {
          sourceDone = true;
          finishIfDone();
        });
    sink.onCancel = () async {
      generation++;
      await outer.cancel();
      await current?.cancel();
    };
  });
}
