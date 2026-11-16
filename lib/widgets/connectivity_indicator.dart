import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/offline/connectivity_service.dart';
import '../services/offline/sync_queue_manager.dart';
import '../providers/offline_delivery_providers.dart';
import '../app/theme/brand_colors.dart';
import 'sync_status_detail_sheet.dart';

class ConnectivityIndicator extends ConsumerWidget {
  const ConnectivityIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivityAsync = ref.watch(connectivityStatusProvider);
    final syncStatusAsync = ref.watch(syncStatusProvider);
    final pendingCountAsync = ref.watch(pendingDeliveryCountProvider);

    return connectivityAsync.when(
      data: (connectivity) {
        if (connectivity == ConnectivityStatus.online) {
          // Show sync status when online
          return syncStatusAsync.when(
            data: (syncStatus) => _buildSyncIndicator(context, ref, syncStatus),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          );
        } else {
          // Show offline indicator with pending count
          return pendingCountAsync.when(
            data: (count) => _buildOfflineIndicator(context, count),
            loading: () => _buildOfflineIndicator(context, 0),
            error: (_, __) => _buildOfflineIndicator(context, 0),
          );
        }
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildOfflineIndicator(BuildContext context, int pendingCount) {
    return GestureDetector(
      onTap: () {
        // Show sync status detail sheet when tapped
        SyncStatusDetailSheet.show(context);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        color: BrandColors.kakaBlue,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 16,
              color: BrandColors.gray1,
            ),
            const SizedBox(width: 8),
            Text(
              pendingCount > 0
                  ? 'Offline Mode • $pendingCount pending'
                  : 'Offline Mode',
              style: const TextStyle(
                color: BrandColors.gray1,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.info_outline,
              size: 14,
              color: BrandColors.gray1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncIndicator(BuildContext context, WidgetRef ref, SyncStatus status) {
    final syncStatsAsync = ref.watch(syncStatsProvider);
    final connectivityAsync = ref.watch(connectivityStatusProvider);

    switch (status) {
      case SyncStatus.syncing:
        return syncStatsAsync.when(
          data: (stats) {
            final pendingCount = stats['pendingItems'] as int? ?? 0;
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              color: Colors.blue.shade700,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    pendingCount > 0
                        ? 'Syncing $pendingCount items...'
                        : 'Syncing...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            color: Colors.blue.shade700,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Syncing...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        );
      case SyncStatus.completed:
        // Hide when sync is complete - no need to show banner
        return const SizedBox.shrink();
      case SyncStatus.partial:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          color: BrandColors.kakaBlue,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.warning,
                size: 16,
                color: BrandColors.gray1,
              ),
              SizedBox(width: 8),
              Text(
                'Some items failed to sync',
                style: TextStyle(
                  color: BrandColors.gray1,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      case SyncStatus.error:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          color: Colors.red.shade700,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: Colors.white,
              ),
              SizedBox(width: 8),
              Text(
                'Sync error',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      case SyncStatus.waitingForWifi:
        // Check current connectivity - hide banner if online now
        return connectivityAsync.when(
          data: (connectivity) {
            if (connectivity == ConnectivityStatus.online) {
              // Connected now, don't show waiting banner
              return const SizedBox.shrink();
            }
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              color: Colors.blue.shade700,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.wifi_off,
                    size: 16,
                    color: Colors.white,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Waiting for Wi-Fi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// Floating sync button for manual sync
class FloatingSyncButton extends ConsumerWidget {
  const FloatingSyncButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatsAsync = ref.watch(syncStatsProvider);

    return syncStatsAsync.when(
      data: (stats) {
        final pendingCount = stats['pendingItems'] as int? ?? 0;
        final isSyncing = stats['isSyncing'] as bool? ?? false;

        if (pendingCount == 0 && !isSyncing) {
          return const SizedBox.shrink();
        }

        return FloatingActionButton.extended(
          onPressed: isSyncing
              ? null
              : () async {
                  final manager =
                      await ref.read(syncQueueManagerProvider.future);
                  await manager.triggerManualSync();
                },
          icon: isSyncing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.sync),
          label: Text(
            isSyncing ? 'Syncing...' : 'Sync ($pendingCount)',
          ),
          backgroundColor:
              isSyncing ? Colors.grey : Theme.of(context).primaryColor,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
