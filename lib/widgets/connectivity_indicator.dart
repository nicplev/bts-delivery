import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/offline_delivery_providers.dart';
import '../services/offline/connectivity_service.dart';
import 'sync_status_detail_sheet.dart';
import 'design/design.dart';

/// Neutral glass status capsule for the nav area: "Offline", evidence waiting
/// on this device, uploads in progress or needing review. Tapping it opens the
/// evidence upload sheet. Hidden when there is nothing to report.
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

    final icon = hasError || needsReview + legacy > 0
        ? AppIcons.warningOutline
        : isOffline
            ? AppIcons.offline
            : active
                ? AppIcons.upload
                : AppIcons.savedOnDevice;
    final colors = AppPalette.of(context);
    return Center(
      child: Semantics(
        liveRegion: true,
        child: AppPressable(
          onTap: () => SyncStatusDetailSheet.show(context),
          semanticLabel: '$label. Show evidence uploads',
          excludeChildSemantics: true,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(minHeight: AppTokens.minTouchTarget),
            child: AppGlass(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: colors.ink),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppTypography.subheadline.copyWith(
                          fontWeight: FontWeight.w600, color: colors.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
