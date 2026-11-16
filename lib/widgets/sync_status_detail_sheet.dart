import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/offline/evidence_upload.dart';
import '../providers/auth_providers.dart';
import '../providers/offline_delivery_providers.dart';
import '../services/offline/connectivity_service.dart';
import '../services/offline/offline_storage_service.dart';

class SyncStatusDetailSheet extends ConsumerWidget {
  const SyncStatusDetailSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const SyncStatusDetailSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploads = ref.watch(evidenceUploadsProvider);
    final connectivity = ref.watch(connectivityStatusProvider).valueOrNull;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('Evidence uploads',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(switch (connectivity) {
              ConnectivityStatus.online => 'Network connection detected',
              ConnectivityStatus.offline => 'Waiting for a network connection',
              _ => 'Checking network connection',
            }),
            const SizedBox(height: 12),
            ...uploads.when(
              loading: () => [
                const Center(child: CircularProgressIndicator()),
              ],
              error: (_, __) => [
                const Text('Could not open saved evidence.'),
                TextButton(
                  onPressed: () => ref.invalidate(evidenceUploadWorkerProvider),
                  child: const Text('Retry'),
                ),
              ],
              data: (status) => [
                if (status.items.isEmpty && !status.localError)
                  const Text('No photos or signatures waiting to upload.'),
                if (status.localError)
                  const Text(
                      'Could not update the upload queue on this device.'),
                if (status.legacyReviewCount > 0)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: Text(
                        '${status.legacyReviewCount} items from an earlier app version'),
                    subtitle: const Text(
                      'Kept on this device for review. Contact your administrator for recovery.',
                    ),
                  ),
                if (status.legacyReviewCount > 0 && ref.watch(isAdminProvider))
                  const _LegacyPhotoRecovery(),
                for (final item in status.items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(item.kind == EvidenceKind.photo
                        ? Icons.photo_outlined
                        : Icons.draw_outlined),
                    title: Text(item.kind == EvidenceKind.photo
                        ? 'Classroom photo'
                        : 'Delivery signature'),
                    subtitle: Text(item.id == status.activeId
                        ? 'Syncing'
                        : item.statusText),
                    trailing: item.id == status.activeId
                        ? null
                        : EvidenceUploadActions(item: item),
                  ),
                if (status.localError ||
                    status.items
                        .any((item) => !item.paused && item.error != null))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _update(context, () async {
                        final worker =
                            await ref.read(evidenceUploadWorkerProvider.future);
                        await worker.retryAll();
                      }),
                      icon: const Icon(Icons.sync),
                      label: const Text('Retry uploads'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EvidenceUploadActions extends ConsumerWidget {
  const EvidenceUploadActions({super.key, required this.item});

  final EvidenceUpload item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<bool>(
      tooltip: 'Upload actions',
      onSelected: (retry) => _update(context, () async {
        final worker = await ref.read(evidenceUploadWorkerProvider.future);
        if (retry) {
          await worker.retry(item.id);
        } else {
          await worker.pause(item.id);
        }
      }),
      itemBuilder: (_) => [
        if (item.paused || item.error != null)
          PopupMenuItem(
              value: true, child: Text(item.paused ? 'Resume' : 'Retry')),
        if (!item.paused)
          const PopupMenuItem(value: false, child: Text('Pause')),
      ],
    );
  }
}

Future<void> _update(
    BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not update the upload. Try again.')),
    );
  }
}

class _LegacyPhotoRecovery extends ConsumerWidget {
  const _LegacyPhotoRecovery();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(offlineStorageServiceProvider);
    final photos = store.legacyPhotosForRecovery;
    if (photos.isEmpty) return const SizedBox.shrink();

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Recover older classroom photos'),
      subtitle: const Text('Export a local copy for review.'),
      children: [
        for (final photo in photos)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.photo_outlined),
            title: Text(MaterialLocalizations.of(context)
                .formatCompactDate(photo.createdAt.toLocal())),
            trailing: TextButton(
              onPressed: () async {
                final box = context.findRenderObject() as RenderBox?;
                final origin = box == null
                    ? null
                    : box.localToGlobal(Offset.zero) & box.size;
                final file = await store.legacyPhotoFile(photo);
                if (!context.mounted || !ref.read(isAdminProvider)) return;
                if (file == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('The original photo file is missing.')),
                  );
                  return;
                }
                try {
                  await Share.shareXFiles(
                    [XFile(file.path, mimeType: 'image/jpeg')],
                    sharePositionOrigin: origin,
                  );
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Could not export this photo.')),
                    );
                  }
                }
              },
              child: const Text('Export'),
            ),
          ),
      ],
    );
  }
}
