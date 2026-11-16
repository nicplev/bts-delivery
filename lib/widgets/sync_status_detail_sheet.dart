import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/offline_delivery_providers.dart';
import '../services/offline/sync_queue_manager.dart';
import '../app/theme/brand_colors.dart';

/// Bottom sheet showing detailed sync status
class SyncStatusDetailSheet extends ConsumerWidget {
  const SyncStatusDetailSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const SyncStatusDetailSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatsAsync = ref.watch(syncStatsProvider);
    final pendingCompletionsAsync = ref.watch(pendingDeliveryCompletionsProvider);
    final storageSizeAsync = ref.watch(pendingStorageSizeProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.sync, size: 24, color: BrandColors.kakaBlue),
                  const SizedBox(width: 12),
                  const Text(
                    'Sync Status',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Sync Stats
              syncStatsAsync.when(
                data: (stats) {
                  final pendingItems = stats['pendingItems'] as int? ?? 0;
                  final isSyncing = stats['isSyncing'] as bool? ?? false;
                  final lastSyncTime = stats['lastSyncTime'] as DateTime?;

                  return Column(
                    children: [
                      _buildStatCard(
                        icon: Icons.pending_actions,
                        title: 'Pending Items',
                        value: '$pendingItems',
                        color: pendingItems > 0 ? BrandColors.kakaBlue : Colors.green,
                      ),
                      const SizedBox(height: 12),
                      if (lastSyncTime != null)
                        _buildInfoRow(
                          icon: Icons.update,
                          label: 'Last Sync',
                          value: _formatDateTime(lastSyncTime),
                        ),
                      if (isSyncing)
                        _buildInfoRow(
                          icon: Icons.sync,
                          label: 'Status',
                          value: 'Syncing...',
                        ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Text('Error loading sync stats'),
              ),

              const SizedBox(height: 20),

              // Pending Deliveries
              pendingCompletionsAsync.when(
                data: (completions) {
                  if (completions.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pending Delivery Completions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...completions.take(5).map((completion) {
                        return _buildPendingCompletionCard(completion);
                      }),
                      if (completions.length > 5)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'And ${completions.length - 5} more...',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              const SizedBox(height: 20),

              // Storage Size
              storageSizeAsync.when(
                data: (size) => _buildInfoRow(
                  icon: Icons.storage,
                  label: 'Pending Storage',
                  value: size,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              const SizedBox(height: 20),

              // Sync Button
              syncStatsAsync.when(
                data: (stats) {
                  final pendingItems = stats['pendingItems'] as int? ?? 0;
                  final isSyncing = stats['isSyncing'] as bool? ?? false;

                  if (pendingItems == 0) {
                    return const SizedBox.shrink();
                  }

                  return SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isSyncing
                          ? null
                          : () async {
                              final manager = await ref.read(syncQueueManagerProvider.future);
                              await manager.triggerManualSync();
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
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
                      label: Text(isSyncing ? 'Syncing...' : 'Sync Now'),
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCompletionCard(completion) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.local_shipping,
            size: 20,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delivery ${completion.deliveryId.substring(0, 8)}...',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (completion.signatureLocalPath != null)
                      const Icon(Icons.edit, size: 14),
                    if (completion.signatureLocalPath != null)
                      const SizedBox(width: 4),
                    if (completion.photoLocalPaths.isNotEmpty) ...[
                      const Icon(Icons.photo_camera, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${completion.photoLocalPaths.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Icon(
            Icons.cloud_upload,
            size: 20,
            color: BrandColors.kakaBlue,
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
