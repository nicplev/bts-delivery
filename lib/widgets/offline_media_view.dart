import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/offline/offline_media.dart';
import '../models/delivery_visit.dart';
import '../providers/offline_media_providers.dart';
import '../services/offline/connectivity_service.dart';

class OfflineMediaPreview extends ConsumerWidget {
  const OfflineMediaPreview({
    super.key,
    required this.asset,
    this.fit = BoxFit.contain,
    this.zoom = false,
    this.expectedUid,
    this.localOnly = false,
  });

  final OfflineMediaAsset asset;
  final BoxFit fit;
  final bool zoom;
  final String? expectedUid;
  final bool localOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(offlineMediaOwnerProvider(asset.schoolId));
    if (uid == null || (expectedUid != null && uid != expectedUid)) {
      return const _MediaMessage('Media unavailable to this account');
    }

    final saved = asset.visit == null
        ? null
        : ref.watch(offlineMediaAssetStateProvider(asset));
    if (saved?.isLoading == true && saved?.hasValue == false) {
      return const Center(child: CircularProgressIndicator());
    }
    final path = saved?.valueOrNull?.localPath;
    if (path != null && File(path).existsSync()) {
      final file = File(path);
      return asset.isPdf
          ? SfPdfViewer.file(file, key: ValueKey((uid, path)))
          : _image(Image.file(
              file,
              key: ValueKey((uid, path)),
              fit: fit,
              errorBuilder: (_, __, ___) => const _MediaMessage(
                'Saved file unavailable. Download it again.',
              ),
            ));
    }

    if (localOnly) {
      return const _MediaMessage('Previously saved file is unavailable');
    }
    if (!ref.watch(isOnlineProvider)) {
      return const _MediaMessage('Download this file before going offline');
    }
    final remote = ref.watch(onlineMediaUrlProvider((asset: asset, uid: uid)));
    return remote.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const _MediaMessage('Could not open this file'),
      data: (url) => asset.isPdf
          ? SfPdfViewer.network(url, key: ValueKey((uid, url)))
          : _image(Image.network(
              url,
              key: ValueKey((uid, url)),
              fit: fit,
              errorBuilder: (_, __, ___) =>
                  const _MediaMessage('Could not open this image'),
            )),
    );
  }

  Widget _image(Widget image) => zoom
      ? InteractiveViewer(maxScale: 4, child: Center(child: image))
      : image;
}

class OfflineMediaScreen extends ConsumerWidget {
  const OfflineMediaScreen({
    super.key,
    required this.asset,
    required this.ownerUid,
    required this.title,
    this.localOnly = false,
  });

  final OfflineMediaAsset asset;
  final String ownerUid;
  final String title;
  final bool localOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView =
        ref.watch(offlineMediaOwnerProvider(asset.schoolId)) == ownerUid;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (canView && asset.visit != null && !localOnly)
            OfflineMediaDownloadButton(asset: asset),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canView && asset.visit != null)
              OfflineMediaDownloadStatus(asset: asset),
            Expanded(
              child: OfflineMediaPreview(
                asset: asset,
                expectedUid: ownerUid,
                zoom: true,
                localOnly: localOnly,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OfflineEarlierMapButton extends ConsumerWidget {
  const OfflineEarlierMapButton({
    super.key,
    required this.visit,
    required this.currentMap,
  });

  final DeliveryVisit visit;
  final OfflineMediaAsset? currentMap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(offlineMediaOwnerProvider(visit.schoolId));
    if (uid == null) return const SizedBox.shrink();
    final earlier =
        ref.watch(offlineMediaVisitStateProvider(visit)).valueOrNull?.savedMap;
    if (earlier == null || earlier.asset == currentMap) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => OfflineMediaScreen(
              asset: earlier.asset,
              ownerUid: uid,
              title: 'Previously saved map',
              localOnly: true,
            ),
          ),
        ),
        icon: const Icon(Icons.history),
        label: Text(
          'Open previously saved map\nChecked ${_checkedAt(context, earlier.checkedAt)}',
        ),
      ),
    );
  }
}

class OfflineMediaDownloadButton extends ConsumerWidget {
  const OfflineMediaDownloadButton({
    super.key,
    required this.asset,
    this.compact = true,
  });

  final OfflineMediaAsset asset;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(offlineMediaOwnerProvider(asset.schoolId));
    if (asset.visit == null || uid == null) return const SizedBox.shrink();
    final cache = ref.watch(offlineMediaWorkerProvider).valueOrNull;
    final state = ref.watch(offlineMediaAssetStateProvider(asset)).valueOrNull;
    final phase = state?.phase;
    final pending = phase == OfflineMediaPhase.queued ||
        phase == OfflineMediaPhase.downloading;
    final ready = phase == OfflineMediaPhase.ready;
    if (ready && asset.kind == OfflineMediaKind.photo) {
      return const Tooltip(
        message: 'Saved for offline',
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.offline_pin_outlined),
        ),
      );
    }

    final action = pending
        ? 'Cancel download'
        : ready
            ? 'Refresh saved map'
            : phase == OfflineMediaPhase.interrupted ||
                    phase == OfflineMediaPhase.failed ||
                    phase == OfflineMediaPhase.missing ||
                    phase == OfflineMediaPhase.stale
                ? 'Retry download'
                : 'Download for offline';
    final icon = pending ? Icons.close : Icons.download_outlined;
    Future<void> perform() async {
      try {
        if (pending) {
          await cache!.cancelAsset(asset, uid: uid);
        } else {
          await cache!.requestDownload(asset, uid: uid);
        }
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update the download')),
        );
      }
    }

    return compact
        ? IconButton(
            tooltip: action,
            onPressed: cache == null ? null : perform,
            icon: Icon(icon),
          )
        : OutlinedButton.icon(
            onPressed: cache == null ? null : perform,
            icon: Icon(icon),
            label: Text(action),
          );
  }
}

class OfflineMediaDownloadStatus extends ConsumerWidget {
  const OfflineMediaDownloadStatus({super.key, required this.asset});

  final OfflineMediaAsset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(offlineMediaOwnerProvider(asset.schoolId)) == null) {
      return const SizedBox.shrink();
    }
    final value = ref.watch(offlineMediaAssetStateProvider(asset));
    final state = value.valueOrNull;
    if (state == null) {
      return value.hasError
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Offline downloads unavailable'),
            )
          : const SizedBox.shrink();
    }

    final verification = state.verifiedAt;
    final savedMap = asset.kind == OfflineMediaKind.map && verification != null
        ? 'Saved map copy · checked ${_checkedAt(context, verification)}'
        : null;
    final label = switch (state.phase) {
      OfflineMediaPhase.available => null,
      OfflineMediaPhase.ready when asset.kind == OfflineMediaKind.map => null,
      OfflineMediaPhase.ready => 'Saved for offline',
      OfflineMediaPhase.queued => 'Waiting to download',
      OfflineMediaPhase.downloading => 'Downloading',
      OfflineMediaPhase.missing => 'Saved file unavailable. Download it again.',
      OfflineMediaPhase.stale => 'Showing the earlier saved map copy',
      OfflineMediaPhase.interrupted =>
        'Download interrupted. Retry when ready.',
      OfflineMediaPhase.failed => switch (state.issue) {
          OfflineMediaIssue.tooLarge => 'File exceeds the 25 MB download limit',
          OfflineMediaIssue.cacheFull => 'Offline storage is full',
          OfflineMediaIssue.changed =>
            'File changed during the download. Retry.',
          OfflineMediaIssue.invalidFile =>
            'Could not verify the downloaded file',
          OfflineMediaIssue.cancellationStalled =>
            'The transfer could not stop. Close and reopen the app if it does not finish.',
          _ => 'Could not download the file',
        },
    };
    if (label == null && savedMap == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (savedMap != null) Text(savedMap),
          if (label != null) Text(label),
          if (state.phase == OfflineMediaPhase.downloading)
            LinearProgressIndicator(value: state.progress),
        ],
      ),
    );
  }
}

class _MediaMessage extends StatelessWidget {
  const _MediaMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}

String _checkedAt(BuildContext context, DateTime date) {
  final local = date.toLocal();
  final strings = MaterialLocalizations.of(context);
  return '${strings.formatShortDate(local)}, ${strings.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}
