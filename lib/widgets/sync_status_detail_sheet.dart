import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/offline/evidence_upload.dart';
import '../models/offline/offline_models.dart';
import '../providers/auth_providers.dart';
import '../providers/offline_delivery_providers.dart';
import '../services/offline/connectivity_service.dart';
import '../services/offline/offline_storage_service.dart';
import 'design/design.dart';

/// "Evidence uploads": photos and signatures saved on this device and their
/// upload state, with retry / pause / resume and legacy photo recovery.
class SyncStatusDetailSheet extends ConsumerWidget {
  const SyncStatusDetailSheet({super.key});

  static void show(BuildContext context) {
    showAppGlassSheet<void>(
      context: context,
      title: 'Evidence uploads',
      contentPadding: EdgeInsets.zero,
      builder: (_) => const SyncStatusDetailSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploads = ref.watch(evidenceUploadsProvider);
    final connectivity = ref.watch(connectivityStatusProvider).valueOrNull;
    final colors = AppPalette.of(context);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
          AppTokens.gutter, 0, AppTokens.gutter, AppTokens.sectionGap),
      children: [
        AppStatusLine(
          text: switch (connectivity) {
            ConnectivityStatus.online => 'Network connection detected',
            ConnectivityStatus.offline => 'Waiting for a network connection',
            _ => 'Checking network connection',
          },
          icon: connectivity == ConnectivityStatus.offline
              ? AppIcons.offline
              : AppIcons.online,
        ),
        const SizedBox(height: 12),
        ...uploads.when(
          loading: () => [
            const Padding(
              padding: EdgeInsets.all(AppTokens.gutter),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (_, __) => [
            const AppNotice(
              message: 'Could not open saved evidence.',
              icon: AppIcons.error,
            ),
            const SizedBox(height: 8),
            AppSecondaryButton(
              label: 'Retry',
              icon: AppIcons.retry,
              onPressed: () => ref.invalidate(evidenceUploadWorkerProvider),
            ),
          ],
          data: (status) {
            final attention = [
              for (final item in status.items)
                if (item.needsAttention && item.id != status.activeId) item,
            ];
            final routine = [
              for (final item in status.items)
                if (!attention.contains(item)) item,
            ];
            final canRetryAll = status.localError ||
                status.items.any((item) => !item.paused && item.error != null);
            return [
              if (status.items.isEmpty && !status.localError)
                const AppNotice(
                  message: 'No photos or signatures waiting to upload.',
                  icon: AppIcons.completeOutline,
                ),
              if (status.localError) ...[
                const AppNotice(
                  message: 'Could not update the upload queue on this device.',
                  icon: AppIcons.error,
                ),
                const SizedBox(height: 12),
              ],
              for (final item in attention) ...[
                _AttentionCard(item: item),
                const SizedBox(height: 12),
              ],
              if (routine.isNotEmpty) ...[
                AppGroupedList(
                  separatorIndent: 68,
                  children: [
                    for (final item in routine)
                      _UploadRow(
                        key: ValueKey(item.id),
                        item: item,
                        active: item.id == status.activeId,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (canRetryAll) ...[
                AppSecondaryButton(
                  label: 'Retry uploads',
                  icon: AppIcons.retry,
                  onPressed: () => _update(context, () async {
                    final worker =
                        await ref.read(evidenceUploadWorkerProvider.future);
                    await worker.retryAll();
                  }),
                ),
                const SizedBox(height: 12),
              ],
              if (status.legacyReviewCount > 0) ...[
                const SizedBox(height: 8),
                const AppSectionLabel('From an earlier app version'),
                const SizedBox(height: 8),
                AppPanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppListRow(
                        icon: AppIcons.savedOnDevice,
                        title:
                            '${status.legacyReviewCount} items from an earlier app version',
                        subtitle:
                            'Kept on this device for review. Contact your administrator for recovery.',
                      ),
                      if (ref.watch(isAdminProvider))
                        const _LegacyPhotoRecovery(),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (status.items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Saved work stays on this device until the server confirms it.',
                    style: AppTypography.footnote.copyWith(color: colors.muted),
                  ),
                ),
            ];
          },
        ),
      ],
    );
  }
}

String _kindLabel(EvidenceUpload item) =>
    item.kind == EvidenceKind.photo ? 'Classroom photo' : 'Delivery signature';

IconData _kindIcon(EvidenceUpload item) =>
    item.kind == EvidenceKind.photo ? AppIcons.photos : AppIcons.signature;

/// A routine upload (saved on this device, waiting to retry, syncing).
class _UploadRow extends StatelessWidget {
  const _UploadRow({super.key, required this.item, required this.active});

  final EvidenceUpload item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 68),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            AppIconTile(icon: _kindIcon(item)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_kindLabel(item),
                      style: AppTypography.body.copyWith(color: colors.ink)),
                  Text(active ? 'Syncing' : item.statusText,
                      style: AppTypography.subheadline
                          .copyWith(color: colors.muted)),
                ],
              ),
            ),
            if (active)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              )
            else
              EvidenceUploadActions(item: item),
          ],
        ),
      ),
    );
  }
}

/// A paused or failed upload: amber card with its one card-level action.
class _AttentionCard extends ConsumerWidget {
  const _AttentionCard({required this.item});

  final EvidenceUpload item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppPalette.of(context);
    final missing = item.error == EvidenceUploadError.missingFile;
    final heading = item.paused ? 'Upload paused' : 'Upload needs attention';
    final detail = [
      item.statusText,
      if (!missing) 'The original is still on this device.',
    ].join('. ');
    return AppPanel(
      key: ValueKey(item.id),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIconTile.warning(icon: _kindIcon(item)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        heading,
                        style: AppTypography.footnote.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.warningInk),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _kindLabel(item),
                      style: AppTypography.headline.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: AppTypography.subheadline
                          .copyWith(color: colors.muted),
                    ),
                  ],
                ),
              ),
              EvidenceUploadActions(item: item),
            ],
          ),
          const SizedBox(height: 16),
          AppPrimaryButton(
            label: item.paused ? 'Resume upload' : 'Retry upload',
            icon: AppIcons.retry,
            onPressed: () => _update(context, () async {
              final worker =
                  await ref.read(evidenceUploadWorkerProvider.future);
              await worker.retry(item.id);
            }),
          ),
        ],
      ),
    );
  }
}

/// Per-upload menu: Retry / Resume and Pause.
class EvidenceUploadActions extends ConsumerWidget {
  const EvidenceUploadActions({super.key, required this.item});

  final EvidenceUpload item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppPalette.of(context);
    return PopupMenuButton<bool>(
      tooltip: 'Upload actions',
      icon: Icon(AppIcons.more, color: colors.ink, size: 22),
      constraints: const BoxConstraints(minWidth: 160),
      style: IconButton.styleFrom(
        minimumSize:
            const Size(AppTokens.minTouchTarget, AppTokens.minTouchTarget),
      ),
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

/// Administrator-only export of older classroom photos (collapsed by default).
class _LegacyPhotoRecovery extends ConsumerStatefulWidget {
  const _LegacyPhotoRecovery();

  @override
  ConsumerState<_LegacyPhotoRecovery> createState() =>
      _LegacyPhotoRecoveryState();
}

class _LegacyPhotoRecoveryState extends ConsumerState<_LegacyPhotoRecovery> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(offlineStorageServiceProvider);
    final photos = store.legacyPhotosForRecovery;
    if (photos.isEmpty) return const SizedBox.shrink();
    final colors = AppPalette.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, thickness: 1, indent: 57, color: colors.separator),
        Semantics(
          expanded: _expanded,
          child: AppListRow(
            icon: AppIcons.exportFile,
            title: 'Recover older classroom photos',
            subtitle: 'Export a local copy for review.',
            showChevron: false,
            trailing: AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              child:
                  Icon(AppIcons.chevronDown, size: 18, color: colors.chevron),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
        ),
        if (_expanded)
          for (final photo in photos) ...[
            Divider(
                height: 1, thickness: 1, indent: 57, color: colors.separator),
            AppListRow(
              icon: AppIcons.gallery,
              title: MaterialLocalizations.of(context)
                  .formatCompactDate(photo.createdAt.toLocal()),
              trailing: Builder(
                builder: (buttonContext) => AppSecondaryButton(
                  label: 'Export',
                  expand: false,
                  large: false,
                  onPressed: () => _export(buttonContext, store, photo),
                ),
              ),
            ),
          ],
      ],
    );
  }

  Future<void> _export(
    BuildContext context,
    OfflineStorageService store,
    LocalPhoto photo,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final file = await store.legacyPhotoFile(photo);
    if (!context.mounted || !ref.read(isAdminProvider)) return;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The original photo file is missing.')),
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
          const SnackBar(content: Text('Could not export this photo.')),
        );
      }
    }
  }
}
