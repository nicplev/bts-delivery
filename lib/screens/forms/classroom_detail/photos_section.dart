part of '../classroom_detail_screen.dart';

/// Classroom photos: photos waiting to upload (with their upload state and
/// actions) and synced thumbnails that open the viewer.
class _PhotosSection extends ConsumerStatefulWidget {
  const _PhotosSection({required this.room});

  final _Room room;

  @override
  ConsumerState<_PhotosSection> createState() => _PhotosSectionState();
}

class _PhotosSectionState extends ConsumerState<_PhotosSection> {
  bool _saving = false;

  _Room get _room => widget.room;

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final colors = AppPalette.of(context);
    final photos = ref.watch(classroomPhotosProvider(room.photosKey));
    final mediaBucket = photos.valueOrNull?.isNotEmpty == true
        ? ref.watch(offlineMediaBucketProvider)
        : null;
    final uploads = ref.watch(evidenceUploadsProvider);
    final status = uploads.valueOrNull;
    final worker = ref.watch(evidenceUploadWorkerProvider).valueOrNull;
    final pending = status?.items
            .where((item) =>
                item.kind == EvidenceKind.photo &&
                item.schoolId == room.schoolId &&
                item.yearLevelId == room.yearLevelId &&
                item.classroomId == room.classroomId &&
                item.deliveryId == room.deliveryId)
            .toList() ??
        [];
    final pendingIds = pending.map((item) => item.id).toSet();
    final remote = photos.valueOrNull
            ?.where((item) => !pendingIds.contains(item.id))
            .toList() ??
        [];
    final canAdd = !_saving && worker != null;

    final rows = <Widget>[
      if (uploads.hasError || status?.localError == true)
        Padding(
          padding: const EdgeInsets.all(12),
          child: _AttentionNotice(
            onReview: () => SyncStatusDetailSheet.show(context),
          ),
        ),
      if (worker != null)
        for (final item in pending)
          AppListRow(
            key: ValueKey('pending-${item.id}'),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                worker.localFile(item),
                cacheWidth: 144,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const AppIconTile(icon: AppIcons.gallery, size: 44),
              ),
            ),
            title: 'Classroom photo',
            subtitle: item.id == status?.activeId ? 'Syncing' : item.statusText,
            trailing: item.id == status?.activeId
                ? null
                : EvidenceUploadActions(item: item),
          ),
      if (photos.isLoading && remote.isEmpty && pending.isEmpty)
        const _MessageRow(title: 'Loading photos…', loading: true),
      if (photos.hasError)
        _MessageRow(
          title: 'Could not load synced photos',
          isError: true,
          trailing: AppSecondaryButton(
            label: 'Retry',
            expand: false,
            large: false,
            onPressed: () =>
                ref.invalidate(classroomPhotosProvider(room.photosKey)),
          ),
        ),
      if (photos.hasValue && remote.isEmpty && pending.isEmpty)
        AppListRow(
          icon: AppIcons.photos,
          title: 'No photos yet',
          showChevron: false,
          trailing:
              canAdd ? Icon(AppIcons.add, size: 20, color: colors.ink) : null,
          onTap: canAdd ? _handleAddPhoto : null,
          semanticLabel: 'No photos yet. Add photo',
        ),
      if (remote.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pending.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('Synced photos',
                      style: AppTypography.footnote.copyWith(
                          fontWeight: FontWeight.w600, color: colors.muted)),
                ),
              GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: remote.length,
                itemBuilder: (context, index) {
                  final photo = remote[index];
                  final deliveryId = room.deliveryId;
                  final visit = deliveryId == null
                      ? null
                      : DeliveryVisit(
                          deliveryId: deliveryId, schoolId: room.schoolId);
                  final asset = OfflineMediaAsset.classroomPhoto(
                    bucket: mediaBucket!,
                    schoolId: room.schoolId,
                    yearLevelId: room.yearLevelId,
                    classroomId: room.classroomId,
                    photoId: photo.id,
                    reference: photo.storagePath,
                    visit: visit,
                  );
                  return _PhotoCard(
                    key: ValueKey(photo.id),
                    photo: photo,
                    asset: asset,
                    schoolId: room.schoolId,
                    onRemove: () => _handleRemovePhoto(photo),
                  );
                },
              ),
            ],
          ),
        ),
    ];

    return _Section(
      label: 'Photos',
      action: _AddButton(
        label: _saving ? 'Saving…' : 'Add',
        semanticLabel: _saving ? 'Saving photo' : 'Add photo',
        icon: AppIcons.photos,
        onPressed: canAdd ? _handleAddPhoto : null,
      ),
      caption: pending.isEmpty
          ? null
          : AppStatusLine(
              icon: AppIcons.waitingToUpload,
              text: '${pending.length} waiting to upload',
            ),
      child: rows.isEmpty
          ? const SizedBox.shrink()
          : AppGroupedList(separatorIndent: 72, children: rows),
    );
  }

  Future<void> _handleAddPhoto() async {
    final worker = ref.read(evidenceUploadWorkerProvider).valueOrNull;
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (worker == null || uid == null) return;

    final photoService = ref.read(photoServiceProvider);
    final classroom = _room;
    setState(() => _saving = true);
    try {
      final file = await photoService.pickImage(context);
      if (file == null) return;
      await worker.enqueuePhoto(
        ownerUid: uid,
        schoolId: classroom.schoolId,
        yearLevelId: classroom.yearLevelId,
        classroomId: classroom.classroomId,
        source: file,
        deliveryId: classroom.deliveryId,
      );
      if (mounted) _showMessage(context, 'Photo saved on this device');
    } catch (_) {
      if (mounted) {
        _showMessage(context, 'Could not save the photo. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleRemovePhoto(Photo photo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove photo from classroom?'),
        content: const Text(
          'The saved photo stays available to signed records that include it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          _destructiveButton(
            dialogContext,
            label: 'Remove',
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final room = _room;
    final success = await ref
        .read(schoolsNotifierProvider.notifier)
        .deleteClassroomPhoto(
            room.schoolId, room.yearLevelId, room.classroomId, photo.id,
            deliveryId: room.deliveryId);

    if (success && mounted) {
      ref.invalidate(classroomPhotosProvider(room.photosKey));
    }

    if (mounted) {
      _showMessage(
        context,
        success
            ? 'Photo removed from classroom'
            : 'Could not remove the photo from the classroom',
      );
    }
  }
}

class _PhotoCard extends ConsumerWidget {
  const _PhotoCard({
    super.key,
    required this.photo,
    required this.asset,
    required this.schoolId,
    required this.onRemove,
  });

  final Photo photo;
  final OfflineMediaAsset? asset;
  final String schoolId;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppPalette.of(context);
    final owner = ref.watch(offlineMediaOwnerProvider(schoolId));
    final canRemove = owner != null &&
        (ref.watch(isAdminProvider) ||
            ref.watch(isManagerProvider) ||
            photo.uploadedBy == owner);
    final source = asset;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.controlRadius),
      child: ColoredBox(
        color: colors.surfaceQuiet,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (owner != null && source != null)
              AppPressable(
                semanticLabel: 'Open classroom photo',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => OfflineMediaScreen(
                      asset: source,
                      ownerUid: owner,
                      title: 'Classroom photo',
                    ),
                  ),
                ),
                child: OfflineMediaPreview(asset: source, fit: BoxFit.cover),
              )
            else
              Center(
                child: Icon(AppIcons.gallery,
                    color: colors.muted,
                    size: 28,
                    semanticLabel: 'Photo unavailable'),
              ),
            if (source?.visit != null)
              Positioned(
                top: 4,
                left: 4,
                child: OfflineMediaDownloadButton(asset: source!),
              ),
            if (canRemove)
              Positioned(
                top: 4,
                right: 4,
                child: AppGlassIconButton(
                  icon: AppIcons.removeCircle,
                  semanticLabel: 'Remove from classroom',
                  tooltip: 'Remove from classroom',
                  onPressed: onRemove,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Amber notice for saved photos that need a decision (paused, failed or a
/// local storage problem).
class _AttentionNotice extends StatelessWidget {
  const _AttentionNotice({required this.onReview});

  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return AppNotice.warning(
      message: 'Saved photos need attention',
      trailing: AppSecondaryButton(
        label: 'Review',
        expand: false,
        large: false,
        onPressed: onReview,
      ),
    );
  }
}
