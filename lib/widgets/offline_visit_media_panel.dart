import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delivery_visit.dart';
import '../models/offline/offline_media.dart';
import '../models/school.dart';
import '../providers/delivery_visit_provider.dart';
import '../providers/offline_media_providers.dart';
import '../services/delivery_visit_access.dart';
import '../services/media/offline_media_cache.dart';
import '../services/media/visit_media_inventory.dart';
import '../services/offline/connectivity_service.dart';
import 'offline_media_view.dart';
import 'design/design.dart';
import '../services/date_utils.dart';

/// Counts derived from the visit media state, split into the school map and
/// classroom photos. Purely presentational: it adds no state of its own.
class _MediaSummary {
  _MediaSummary(this.state, {required this.mapPhase, required this.mapChanged})
      : hasMap = state?.inventory != null &&
            _inventoryMap(state!.inventory!) != null;

  final OfflineMediaVisitState? state;
  final OfflineMediaPhase? mapPhase;
  final bool mapChanged;
  final bool hasMap;

  MediaInventory? get inventory => state?.inventory;
  int get total => state?.totalAvailable ?? 0;
  int get ready => state?.ready ?? 0;
  int get missing => (total - ready).clamp(0, total);
  bool get mapReady => hasMap && mapPhase == OfflineMediaPhase.ready;
  int get photosTotal => hasMap ? (total - 1).clamp(0, total) : total;
  int get photosReady =>
      (mapReady ? ready - 1 : ready).clamp(0, photosTotal).toInt();
  int get photosMissing => photosTotal - photosReady;
  bool get mapMissing => hasMap && !mapReady;

  /// "4 photos" / "the school map" / "5 files" still to download.
  String? get toDownload {
    if (missing == 0) return null;
    if (!mapMissing && photosMissing == missing) {
      return _count(photosMissing, 'photo');
    }
    if (mapMissing && photosMissing == 0) return 'school map';
    return _count(missing, 'file');
  }
}

String _count(int n, String noun) => n == 1 ? '1 $noun' : '$n ${noun}s';

String _capitalise(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// Compact entry for the visit hub: one quiet line stating the offline media
/// situation, opening the "Offline files" sheet.
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
    final value = ref.watch(offlineMediaVisitStateProvider(visit));
    final state = value.valueOrNull;
    final inventory = state?.inventory;
    final inventoryMap = inventory == null ? null : _inventoryMap(inventory);
    final mapPhase = inventoryMap == null
        ? null
        : ref
            .watch(offlineMediaAssetStateProvider(inventoryMap))
            .valueOrNull
            ?.phase;
    final mapChanged = inventory != null &&
        _assetMap(school, visit, ref.watch(offlineMediaBucketProvider)) !=
            inventoryMap;
    final summary =
        _MediaSummary(state, mapPhase: mapPhase, mapChanged: mapChanged);
    final failed = state?.failed ?? 0;

    final (String label, IconData icon) = switch (state) {
      _ when value.hasError || state?.localError == true => (
          'Offline media unavailable',
          AppIcons.warningOutline
        ),
      null => ('Offline files', AppIcons.download),
      _ when state.clearing => ('Clearing downloaded files', AppIcons.delete),
      _ when state.discovering => (
          'Checking for offline files',
          AppIcons.download
        ),
      _ when state.waiting > 0 => (
          'Downloading ${state.ready} of ${state.totalAvailable}',
          AppIcons.download
        ),
      _ when inventory == null => (
          'Offline files not downloaded',
          AppIcons.download
        ),
      _ when mapChanged => ('School map changed', AppIcons.warningOutline),
      _ when failed > 0 => (
          failed == 1
              ? '1 file needs a new download'
              : '$failed files need a new download',
          AppIcons.warningOutline
        ),
      _ when summary.total == 0 => ('No offline files', AppIcons.download),
      _ when summary.toDownload != null => (
          '${_capitalise(summary.toDownload!)} to download',
          AppIcons.download
        ),
      _ => ('Offline ready', AppIcons.complete),
    };
    final colors = AppPalette.of(context);
    return AppPressable(
      semanticLabel: 'Offline files: $label',
      excludeChildSemantics: true,
      onTap: () => showAppGlassSheet<void>(
        context: context,
        title: 'Offline files',
        contentPadding: EdgeInsets.zero,
        builder: (_) => _VisitMediaSheet(
          visit: visit,
          school: school,
          expectedUid: uid,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTokens.minTouchTarget),
        // Full-width row: the chevron sits at the trailing edge.
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.ink),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: AppTypography.subheadline
                    .copyWith(fontWeight: FontWeight.w600, color: colors.ink),
              ),
            ),
            const SizedBox(width: 8),
            Icon(AppIcons.chevron, size: 16, color: colors.chevron),
          ],
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
    final colors = AppPalette.of(context);
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
    final checked = date == null ? null : DateTimeUtils.formatDate(date);
    final currentMap = allowed
        ? _assetMap(
            widget.school, widget.visit, ref.watch(offlineMediaBucketProvider))
        : null;
    final inventoryMap = inventory == null ? null : _inventoryMap(inventory);
    final mapChanged =
        allowed && inventory != null && currentMap != inventoryMap;
    final mapPhase = inventoryMap == null
        ? null
        : ref
            .watch(offlineMediaAssetStateProvider(inventoryMap))
            .valueOrNull
            ?.phase;
    final summary =
        _MediaSummary(state, mapPhase: mapPhase, mapChanged: mapChanged);
    final records = allowed
        ? ref.watch(deliveryVisitReadinessProvider(widget.visit))
        : null;

    final canDownload = cache != null &&
        !clearing &&
        online &&
        !_working &&
        !discovering &&
        waiting == 0;
    final toDownload = summary.toDownload;
    final primaryLabel = inventory == null
        ? 'Download for offline'
        : toDownload != null && !mapChanged
            ? 'Download $toDownload'
            : 'Check and download again';

    final muted = AppTypography.subheadline.copyWith(color: colors.muted);
    final footnote = AppTypography.footnote.copyWith(color: colors.muted);

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'Save the map and photos to this device before you lose reception.',
          style: muted,
        ),
      ),
      const SizedBox(height: 16),
    ];

    if (!allowed) {
      children.add(const AppNotice(
        message: 'Offline media is unavailable to this account',
        icon: AppIcons.lock,
      ));
    } else {
      children.addAll([
        AppGroupedList(
          separatorIndent: 57,
          children: [
            _mapRow(summary, inventory, currentMap, mapChanged),
            _photosRow(summary, inventory),
            _recordsRow(records),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            inventory == null
                ? 'Check this visit for classroom photos and the school map.'
                : '${state!.ready} of ${state.totalAvailable} files from the last check saved · $checked',
            style: footnote,
          ),
        ),
        OfflineEarlierMapButton(visit: widget.visit, currentMap: currentMap),
        ..._notices(state, value, mapChanged, waiting, discovering, clearing),
        const SizedBox(height: 16),
        AppPrimaryButton(
          label: primaryLabel,
          icon: AppIcons.download,
          onPressed: canDownload ? () => _refreshAndDownload(cache) : null,
        ),
        if (!online && waiting == 0) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Connect to check for new media',
                style: footnote, textAlign: TextAlign.center),
          ),
        ],
        ..._secondaryActions(
            cache, state, inventory, online, waiting, discovering, clearing),
      ]);
    }
    children.addAll([
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'Anything you record offline is kept on this device and uploads when you reconnect.',
          style: footnote,
        ),
      ),
    ]);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.gutter, 0, AppTokens.gutter, AppTokens.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  // Saved / available is a confirmation, not a finished task: ink, not the
  // green done mark.
  Widget _check(String label) => Semantics(
        label: label,
        excludeSemantics: true,
        child: Icon(AppIcons.complete,
            size: 22, color: AppPalette.of(context).ink),
      );

  Widget _mapRow(_MediaSummary summary, MediaInventory? inventory,
      OfflineMediaAsset? currentMap, bool mapChanged) {
    final subtitle = switch (summary.mapPhase) {
      _ when inventory == null =>
        currentMap == null ? 'No school map' : 'Not downloaded yet',
      _ when mapChanged => currentMap == null
          ? 'Removed since the last check'
          : 'Changed since the last check',
      _ when !summary.hasMap => 'No school map',
      OfflineMediaPhase.ready => 'Saved on this device',
      OfflineMediaPhase.queued => 'Waiting to download',
      OfflineMediaPhase.downloading => 'Downloading',
      OfflineMediaPhase.stale => 'Earlier copy saved · needs a new download',
      OfflineMediaPhase.failed ||
      OfflineMediaPhase.interrupted ||
      OfflineMediaPhase.missing =>
        'Needs a new download',
      _ => 'Not downloaded yet',
    };
    return AppListRow(
      icon: AppIcons.map,
      title: 'School map',
      subtitle: subtitle,
      trailing: summary.mapReady && !mapChanged ? _check('Saved') : null,
    );
  }

  Widget _photosRow(_MediaSummary summary, MediaInventory? inventory) {
    final colors = AppPalette.of(context);
    final total = summary.photosTotal;
    final done = summary.photosReady;
    final complete = inventory != null && total > 0 && done >= total;
    final subtitle = inventory == null
        ? 'Not downloaded yet'
        : total == 0
            ? 'No classroom photos found'
            : '$done of $total saved';
    final showBar = inventory != null && total > 0 && !complete;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: AppIconTile(icon: AppIcons.gallery, size: 29),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Classroom photos',
                    style: AppTypography.body.copyWith(color: colors.ink)),
                Text(subtitle,
                    style: AppTypography.subheadline
                        .copyWith(color: colors.muted)),
                if (showBar) ...[
                  const SizedBox(height: 10),
                  AppProgressBar(
                    value: done / total,
                    semanticLabel: 'Classroom photos saved',
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
          if (complete) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _check('Saved'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _recordsRow(AsyncValue<VisitReadiness>? records) {
    final status = records?.valueOrNull?.status;
    final subtitle = records == null || records.hasError
        ? 'Unavailable to this account'
        : switch (status) {
            DeliveryVisitReadiness.ready => 'Available offline',
            DeliveryVisitReadiness.onlineOnly => 'Available while connected',
            DeliveryVisitReadiness.unavailableOffline =>
              'Not saved on this device',
            null => 'Checking',
          };
    return AppListRow(
      icon: AppIcons.records,
      title: 'Delivery records',
      subtitle: subtitle,
      trailing:
          status == DeliveryVisitReadiness.ready ? _check('Available') : null,
    );
  }

  List<Widget> _notices(
    OfflineMediaVisitState? state,
    AsyncValue<OfflineMediaVisitState>? value,
    bool mapChanged,
    int waiting,
    bool discovering,
    bool clearing,
  ) {
    final failed = state?.failed ?? 0;
    final unavailable = state?.inventory?.unavailableCount ?? 0;
    final notices = <Widget>[
      if (mapChanged)
        const AppNotice.warning(
            message: 'The school map changed since the last media check.'),
      if (failed > 0)
        AppNotice.warning(
            message: '${state!.failed} files need a new download'),
      if (state?.cancellationStalled == true)
        const AppNotice.warning(
            message:
                'A download could not stop. Close and reopen the app if it does not finish.'),
      if (unavailable > 0)
        AppNotice(
          message: '$unavailable files could not be included',
          icon: AppIcons.infoOutline,
        ),
      if (discovering)
        const AppNotice(
          message: 'Checking the visit for media',
          icon: AppIcons.download,
        ),
      if (waiting > 0)
        AppNotice(
          message: '$waiting downloads queued or running',
          icon: AppIcons.download,
        ),
      if (state?.progress != null)
        AppProgressBar(
          value: state!.progress!,
          semanticLabel: 'Current download',
        ),
      if (state?.localError == true || value?.hasError == true)
        const AppNotice(
          message: 'Could not read the offline media cache',
          icon: AppIcons.error,
        ),
      if (_error != null) AppNotice(message: _error!, icon: AppIcons.error),
      if (_working || clearing) const LinearProgressIndicator(),
    ];
    return [
      for (final notice in notices) ...[const SizedBox(height: 12), notice],
    ];
  }

  List<Widget> _secondaryActions(
    OfflineMediaCache? cache,
    OfflineMediaVisitState? state,
    MediaInventory? inventory,
    bool online,
    int waiting,
    bool discovering,
    bool clearing,
  ) {
    final actions = <Widget>[
      if (inventory != null && !online && waiting == 0 && state!.failed > 0)
        AppSecondaryButton(
          label: 'Retry when connected',
          icon: AppIcons.retry,
          large: false,
          onPressed: cache == null || _working
              ? null
              : () => _run(() => cache.downloadInventory(
                    widget.visit,
                    uid: widget.expectedUid,
                  )),
        ),
      if (waiting > 0 || discovering)
        AppSecondaryButton(
          label: 'Cancel downloads',
          icon: AppIcons.close,
          large: false,
          onPressed: cache == null
              ? null
              : () => _run(() => cache.cancelVisit(
                    widget.visit,
                    uid: widget.expectedUid,
                  )),
        ),
      if (state?.canRemoveVisitCopies == true && waiting == 0 && !discovering)
        AppSecondaryButton(
          label: 'Remove downloads',
          icon: AppIcons.delete,
          large: false,
          onPressed: cache == null || _working || clearing
              ? null
              : () => _remove(cache),
        ),
      // The destructive one of the two: removes every visit's media.
      AppSecondaryButton(
        label: 'Clear all downloaded media',
        icon: AppIcons.delete,
        destructive: true,
        large: false,
        onPressed: cache == null || clearing
            ? null
            : () => _run(() => _clearDevice(cache)),
      ),
    ];
    return [
      for (final action in actions) ...[const SizedBox(height: 8), action],
    ];
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
