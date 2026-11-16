import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/offline_delivery_providers.dart';
import '../services/offline/connectivity_service.dart';
import 'sync_status_detail_sheet.dart';

class ConnectivityIndicator extends ConsumerWidget {
  const ConnectivityIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityStatusProvider).valueOrNull;
    final uploads = ref.watch(evidenceUploadsProvider);
    final status = uploads.valueOrNull;
    final pending = status?.items.length ?? 0;
    final needsReview =
        status?.items.where((item) => item.needsAttention).length ?? 0;
    final legacy = status?.legacyReviewCount ?? 0;
    final isOffline = connectivity == ConnectivityStatus.offline;
    final hasError = uploads.hasError || status?.localError == true;
    final active = status?.activeId != null;
    if (!isOffline && !hasError && pending == 0 && legacy == 0) {
      return const SizedBox.shrink();
    }

    final label = [
      if (isOffline) 'Offline',
      if (hasError) 'Upload queue needs attention',
      if (pending > 0)
        active
            ? 'Syncing evidence ($pending)'
            : '$pending saved on this device',
      if (needsReview + legacy > 0) '${needsReview + legacy} need review',
    ].join(' · ');

    return Center(
      child: TextButton.icon(
        onPressed: () => SyncStatusDetailSheet.show(context),
        icon: Icon(
          hasError || needsReview + legacy > 0
              ? Icons.warning_amber_rounded
              : isOffline
                  ? Icons.cloud_off
                  : Icons.cloud_upload_outlined,
          size: 18,
        ),
        label: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
