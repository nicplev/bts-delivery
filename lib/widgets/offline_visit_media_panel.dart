import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delivery_visit.dart';
import '../models/offline/offline_media.dart';
import '../models/school.dart';
import '../providers/offline_media_providers.dart';
import '../services/media/offline_media_cache.dart';
import '../services/media/visit_media_inventory.dart';
import '../services/offline/connectivity_service.dart';
import 'offline_media_view.dart';
import 'design/design.dart';

class OfflineVisitMediaPanel extends ConsumerWidget {
  const OfflineVisitMediaPanel({
    super.key,
    required this.visit,
    required this.school,
  });

  final DeliveryVisit visit;
  final School school;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(offlineMediaOwnerProvider(visit.schoolId));
    if (uid == null) return const SizedBox.shrink();
    final state = ref.watch(offlineMediaVisitStateProvider(visit)).valueOrNull;
    final inventory = state?.inventory;
    final known = inventory != null;
    final mapChanged = inventory != null &&
        _assetMap(school, visit, ref.watch(offlineMediaBucketProvider)) !=
            _inventoryMap(inventory);
    final label = mapChanged
        ? 'Offline media · map changed'
        : known
            ? 'Offline media · ${state!.ready}/${state.totalAvailable} saved'
            : 'Offline media';
    final tone = mapChanged ? AppTone.yellow : AppTone.blue;
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: tone.inkFor(context),
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      ),
      icon: const Icon(Icons.download_outlined, size: 18),
      label: Text(label),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (_) => _VisitMediaSheet(
          visit: visit,
          school: school,
          expectedUid: uid,
        ),
      ),
    );
  }
}

class _VisitMediaSheet extends ConsumerStatefulWidget {
  const _VisitMediaSheet({
    required this.visit,
    required this.school,
    required this.expectedUid,
  });

  final DeliveryVisit visit;
  final School school;
  final String expectedUid;

  @override
  ConsumerState<_VisitMediaSheet> createState() => _VisitMediaSheetState();
}

class _VisitMediaSheetState extends ConsumerState<_VisitMediaSheet> {
  bool _working = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final allowed =
        ref.watch(offlineMediaOwnerProvider(widget.visit.schoolId)) ==
            widget.expectedUid;
    final value = allowed
        ? ref.watch(offlineMediaVisitStateProvider(widget.visit))
        : null;
    final cache =
        allowed ? ref.watch(offlineMediaWorkerProvider).valueOrNull : null;
    final state = value?.valueOrNull;
    final inventory = state?.inventory;
    final online = ref.watch(isOnlineProvider);
    final waiting = state?.waiting ?? 0;
    final discovering = state?.discovering ?? false;
    final clearing = state?.clearing ?? false;
    final date = inventory?.checkedAt.toLocal();
    final checked = date == null
        ? null
        : MaterialLocalizations.of(context).formatShortDate(date);
    final currentMap = allowed
        ? _assetMap(
            widget.school, widget.visit, ref.watch(offlineMediaBucketProvider))
        : null;
    final mapChanged =
        allowed && inventory != null && currentMap != _inventoryMap(inventory);

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppTokens.gutter, 0, AppTokens.gutter, AppTokens.sectionGap),
          children: [
            const AppSectionHeading(title: 'Offline media'),
            const SizedBox(height: 8),
            if (!allowed)
              const Text('Offline media is unavailable to this account')
            else ...[
              if (inventory == null)
                const Text(
                    'Check this visit for classroom photos and the school map.')
              else
                Text(
                    '${state!.ready} of ${state.totalAvailable} files from the last check saved · $checked'),
              if (mapChanged) ...[
                const SizedBox(height: 8),
                const AppStatusPill(
                  label: 'The school map changed since the last media check.',
                  icon: Icons.info_outline,
                  tone: AppTone.yellow,
                ),
              ],
              OfflineEarlierMapButton(
                  visit: widget.visit, currentMap: currentMap),
              if ((inventory?.unavailableCount ?? 0) > 0)
                Text(
                    '${inventory!.unavailableCount} files could not be included'),
              if (discovering) const Text('Checking the visit for media'),
              if (waiting > 0) Text('$waiting downloads queued or running'),
              if (state?.cancellationStalled == true)
                const Text(
                    'A download could not stop. Close and reopen the app if it does not finish.'),
              if (state?.progress != null)
                LinearProgressIndicator(value: state!.progress),
              if ((state?.failed ?? 0) > 0) ...[
                const SizedBox(height: 8),
                AppStatusPill(
                  label: '${state!.failed} files need a new download',
                  icon: Icons.error_outline,
                  tone: AppTone.pink,
                ),
              ],
              if (state?.localError == true || value?.hasError == true)
                const Text('Could not read the offline media cache'),
              if (_error != null) Text(_error!),
              if (_working || clearing) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton.icon(
                    onPressed: cache == null ||
                            clearing ||
                            !online ||
                            _working ||
                            discovering ||
                            waiting > 0
                        ? null
                        : () => _refreshAndDownload(cache),
                    icon: const Icon(Icons.download_outlined),
                    label: Text(inventory == null
                        ? 'Download for offline'
                        : 'Check and download again'),
                  ),
                  if (inventory != null &&
                      !online &&
                      waiting == 0 &&
                      state!.failed > 0)
                    OutlinedButton(
                      onPressed: cache == null || _working
                          ? null
                          : () => _run(() => cache.downloadInventory(
                                widget.visit,
                                uid: widget.expectedUid,
                              )),
                      child: const Text('Retry when connected'),
                    ),
                  if (waiting > 0 || discovering)
                    OutlinedButton(
                      onPressed: cache == null
                          ? null
                          : () => _run(() => cache.cancelVisit(
                                widget.visit,
                                uid: widget.expectedUid,
                              )),
                      child: const Text('Cancel downloads'),
                    ),
                  if (state?.canRemoveVisitCopies == true &&
                      waiting == 0 &&
                      !discovering)
                    TextButton(
                      onPressed: cache == null || _working || clearing
                          ? null
                          : () => _remove(cache),
                      child: const Text('Remove downloads'),
                    ),
                ],
              ),
              TextButton(
                onPressed: cache == null || clearing
                    ? null
                    : () => _run(() => _clearDevice(cache)),
                child: const Text('Clear downloaded media on this device'),
              ),
              if (!online && waiting == 0)
                const Text('Connect to check for new media'),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _refreshAndDownload(OfflineMediaCache cache) => _run(() {
        final reader = ref.read(readVisitMediaProvider);
        final visit = widget.visit;
        return cache.prepareVisit(visit,
            uid: widget.expectedUid,
            read: (requireOwner) => reader(visit, requireOwner));
      });

  Future<void> _remove(OfflineMediaCache cache) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove downloaded copies?'),
        content:
            const Text('You can download these files again when connected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    await _run(() => cache.removeVisit(widget.visit, uid: widget.expectedUid));
  }

  Future<void> _clearDevice(OfflineMediaCache cache) async {
    final bytes = await cache.deviceBytes(uid: widget.expectedUid);
    if (!mounted) return;
    final formatted = (bytes / (1024 * 1024)).toStringAsFixed(1);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear downloaded media?'),
        content: Text(
          'This removes $formatted MB of downloaded copies for all accounts on this device. '
          'You can download them again when connected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear downloads'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await cache.clearDeviceCache(uid: widget.expectedUid);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } on MediaCacheBusy {
      if (mounted) {
        setState(() {
          _error =
              'A download could not stop. Close and reopen the app to clear the cache.';
        });
      }
    } on MediaInventoryTooLarge {
      if (mounted) {
        setState(() =>
            _error = 'This visit has too many files for a single download.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update offline media. Try again.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

OfflineMediaAsset? _assetMap(
        School school, DeliveryVisit visit, String bucket) =>
    OfflineMediaAsset.schoolMap(
      bucket: bucket,
      schoolId: visit.schoolId,
      reference: school.schoolMapStoragePath ?? school.schoolMapUrl,
      visit: visit,
    );

OfflineMediaAsset? _inventoryMap(MediaInventory inventory) => inventory.assets
    .where((asset) => asset.kind == OfflineMediaKind.map)
    .firstOrNull;
