import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/offline/offline_media.dart';
import '../models/delivery_visit.dart';
import '../providers/offline_media_providers.dart';
import '../services/offline/connectivity_service.dart';
import 'design/design.dart';

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
      return const _MediaMessage('Media unavailable to this account',
          icon: AppIcons.lock);
    }

    final saved = asset.visit == null
        ? null
        : ref.watch(offlineMediaAssetStateProvider(asset));
    if (saved?.isLoading == true && saved?.hasValue == false) {
      return const _MediaLoading();
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
                icon: AppIcons.error,
              ),
            ));
    }

    if (localOnly) {
      return const _MediaMessage('Previously saved file is unavailable',
          icon: AppIcons.error);
    }
    if (!ref.watch(isOnlineProvider)) {
      return const _MediaMessage('Download this file before going offline',
          icon: AppIcons.offline);
    }
    final remote = ref.watch(onlineMediaUrlProvider((asset: asset, uid: uid)));
    return remote.when(
      loading: () => const _MediaLoading(),
      error: (_, __) =>
          const _MediaMessage('Could not open this file', icon: AppIcons.error),
      data: (url) => asset.isPdf
          ? SfPdfViewer.network(url, key: ValueKey((uid, url)))
          : _image(Image.network(
              url,
              key: ValueKey((uid, url)),
              fit: fit,
              errorBuilder: (_, __, ___) => const _MediaMessage(
                  'Could not open this image',
                  icon: AppIcons.error),
            )),
    );
  }

  Widget _image(Widget image) => zoom
      ? InteractiveViewer(maxScale: 4, child: Center(child: image))
      : image;
}

/// Full-screen viewer: media fills the screen beneath a glass back button and
/// (for visit media) a glass download action; the title and download state
/// sit in a glass caption at the bottom.
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
    final colors = AppPalette.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: colors.canvas,
      appBar: AppNavBar(
        actions: [
          if (canView && asset.visit != null && !localOnly)
            OfflineMediaDownloadButton(asset: asset),
        ],
      ),
      body: Semantics(
        label: title,
        explicitChildNodes: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding:
                    EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
                child: OfflineMediaPreview(
                  asset: asset,
                  expectedUid: ownerUid,
                  zoom: true,
                  localOnly: localOnly,
                ),
              ),
            ),
            Positioned(
              left: AppTokens.gutter,
              right: AppTokens.gutter,
              bottom: AppInsets.bottom(context, extra: 12),
              child: AppGlass(
                borderRadius: BorderRadius.circular(AppTokens.cardRadius),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title,
                          style: AppTypography.headline
                              .copyWith(color: colors.ink)),
                    ),
                    if (canView && asset.visit != null)
                      OfflineMediaDownloadStatus(asset: asset),
                  ],
                ),
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
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppSecondaryButton(
        large: false,
        icon: AppIcons.history,
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
        label:
            'Open previously saved map\nChecked ${_checkedAt(context, earlier.checkedAt)}',
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

  /// A 44 pt round glass icon button (over media / in the nav area); `false`
  /// gives a labelled grey capsule.
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
      final colors = AppPalette.of(context);
      return Tooltip(
        message: 'Saved for offline',
        child: Semantics(
          label: 'Saved for offline',
          image: true,
          child: SizedBox.square(
            dimension: AppTokens.minTouchTarget,
            child: AppGlass(
              child: Center(
                child: Icon(AppIcons.complete, size: 20, color: colors.ink),
              ),
            ),
          ),
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
    final icon = pending
        ? AppIcons.close
        : ready
            ? AppIcons.retry
            : AppIcons.download;
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
        ? AppGlassIconButton(
            icon: icon,
            semanticLabel: action,
            tooltip: action,
            onPressed: cache == null ? null : perform,
          )
        : AppSecondaryButton(
            onPressed: cache == null ? null : perform,
            icon: icon,
            label: action,
            large: false,
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
              padding: EdgeInsets.symmetric(vertical: 6),
              child: AppStatusLine(
                text: 'Offline downloads unavailable',
                icon: AppIcons.error,
              ),
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
    final needsDownload = switch (state.phase) {
      OfflineMediaPhase.missing ||
      OfflineMediaPhase.stale ||
      OfflineMediaPhase.interrupted ||
      OfflineMediaPhase.failed =>
        true,
      _ => false,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (savedMap != null)
            AppStatusLine(text: savedMap, icon: AppIcons.savedOnDevice),
          if (label != null) ...[
            if (savedMap != null) const SizedBox(height: 4),
            if (needsDownload)
              AppNotice.warning(message: label)
            else
              AppStatusLine(
                text: label,
                icon: state.phase == OfflineMediaPhase.ready
                    ? AppIcons.complete
                    : AppIcons.download,
              ),
          ],
          if (state.phase == OfflineMediaPhase.downloading) ...[
            const SizedBox(height: 8),
            AppProgressBar(
              value: state.progress ?? 0,
              semanticLabel: 'Download progress',
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaLoading extends StatelessWidget {
  const _MediaLoading();

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          label: 'Loading media',
          child: const CircularProgressIndicator(),
        ),
      );
}

/// Neutral placeholder for media that cannot be shown: grey tile, ink glyph,
/// muted message.
class _MediaMessage extends StatelessWidget {
  const _MediaMessage(this.text, {this.icon = AppIcons.gallery});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final roomy = constraints.maxHeight >= 120 && constraints.maxWidth >= 140;
      return ColoredBox(
        color: colors.surfaceQuiet,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (roomy) ...[
                  ExcludeSemantics(child: AppIconTile(icon: icon, size: 48)),
                  const SizedBox(height: 8),
                ],
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: AppTypography.footnote.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

String _checkedAt(BuildContext context, DateTime date) {
  final local = date.toLocal();
  final strings = MaterialLocalizations.of(context);
  return '${strings.formatShortDate(local)}, ${strings.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}
