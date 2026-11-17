import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/offline/field_draft_store.dart';

final fieldDraftStoreProvider = FutureProvider<FieldDraftStore>(
  (_) => HiveFieldDraftStore.open(),
);
