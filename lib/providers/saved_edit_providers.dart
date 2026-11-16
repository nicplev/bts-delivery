import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/offline/saved_edit.dart';
import '../services/offline/connectivity_service.dart';
import '../services/offline/firestore_edit_transport.dart';
import '../services/offline/saved_edit_recovery.dart';
import '../services/offline/saved_edit_store.dart';
import 'auth_providers.dart';
import 'repository_providers.dart';

final savedEditRecoveryProvider = Provider<SavedEditRecovery>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final recovery = SavedEditRecovery(
    store: HiveSavedEditStore(),
    transport: FirestoreEditTransport(),
    currentUid: () => auth.currentUser?.uid,
  );
  ref.onDispose(recovery.dispose);
  return recovery;
});

final savedEditsProvider = StreamProvider.autoDispose<List<SavedEdit>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(savedEditRecoveryProvider).store.watch(uid).map(
        (edits) => ref.read(authStateProvider).valueOrNull?.uid == uid
            ? edits
            : const [],
      );
});

/// Observes lifecycle changes for server comparison only.
final savedEditLifecycleProvider = Provider<void>((ref) {
  final recovery = ref.watch(savedEditRecoveryProvider);
  final auth = ref.watch(authRepositoryProvider);
  final network = ref.watch(connectivityServiceProvider);
  var running = false;
  var requested = false;
  var disposed = false;

  Future<void> check() async {
    requested = true;
    if (running) return;
    running = true;
    try {
      while (requested && !disposed) {
        requested = false;
        final uid = auth.currentUser?.uid;
        if (uid == null || !network.isOnline) continue;
        try {
          await recovery.reconcile(uid);
        } catch (_) {
          // The saved-edits view reports local storage errors independently.
        }
      }
    } finally {
      running = false;
    }
  }

  final onAuth = auth.authStateChanges.listen((_) {
    recovery.authenticationChanged();
    unawaited(check());
  });
  final onNetwork = network.statusStream.listen((_) => unawaited(check()));
  final lifecycle = AppLifecycleListener(onResume: () => unawaited(check()));
  ref.onDispose(() {
    disposed = true;
    lifecycle.dispose();
    unawaited(onAuth.cancel());
    unawaited(onNetwork.cancel());
  });
  unawaited(check());
});
