import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/offline_delivery_providers.dart';
import '../services/offline/connectivity_service.dart';
import 'sync_status_detail_sheet.dart';
import 'design/design.dart';

/// Neutral glass status capsule shown under a screen's title: "Offline", evidence waiting
/// on this device, uploads in progress or needing review. Tapping it opens the
/// evidence upload sheet. Hidden when there is nothing to report.
///
/// Placement: directly under the screen's large title, aligned with it at the
/// leading edge (when it wraps, the text stays left-aligned with the icon on
/// the first line). [padding] is applied only while the capsule is shown.
class ConnectivityIndicator extends ConsumerWidget {
  const ConnectivityIndicator({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

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
      if (needsReview + legacy > 0)
        needsReview + legacy == 1
            ? '1 needs review'
            : '${needsReview + legacy} need review',
    ].join(' · ');

    final icon = hasError || needsReview + legacy > 0
        ? AppIcons.warningOutline
        : isOffline
            ? AppIcons.offline
            : active
                ? AppIcons.upload
                : AppIcons.savedOnDevice;
    return Padding(
      padding: padding,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppGlassStatus(
          label: label,
          icon: icon,
          leadingAligned: true,
          onTap: () => SyncStatusDetailSheet.show(context),
          semanticLabel: '$label. Show evidence uploads',
        ),
      ),
    );
  }
}
