part of '../classroom_detail_screen.dart';

/// Classroom photos are attached, when taken, to what they show: the packs
/// or one consumable. Each item shows its own photos in a horizontal strip
/// with its own camera control; everything else (general photos, photos from
/// before attachments existed, photos of a removed consumable) is under
/// "Other photos". The classroom's one photos stream plus this device's
/// upload queue feed every strip.

/// Thumbnail size in the strips.
const double _thumbSize = 88;

/// A photo in a strip: either waiting on this device or saved to the server.
class _PhotoEntry {
  const _PhotoEntry.pending(EvidenceUpload this.pending) : photo = null;
  const _PhotoEntry.saved(Photo this.photo) : pending = null;

  final EvidenceUpload? pending;
  final Photo? photo;

  String get id => pending?.id ?? photo!.id;
  PhotoSubject? get subject => pending?.subject ?? photo!.subject;
}

/// What the classroom's photo sources currently hold.
class _RoomPhotos {
  _RoomPhotos._({
    required this.photos,
    required this.status,
    required this.uploadsFailed,
    required this.worker,
    required this.pending,
    required this.saved,
    required this.bucket,
  });

  /// Watches the photos stream and the upload queue for [room].
  factory _RoomPhotos.watch(WidgetRef ref, _Room room) {
    final photos = ref.watch(classroomPhotosProvider(room.photosKey));
    final uploads = ref.watch(evidenceUploadsProvider);
    final status = uploads.valueOrNull;
    final pending = status?.items
            .where((item) =>
                item.kind == EvidenceKind.photo &&
                item.schoolId == room.schoolId &&
                item.yearLevelId == room.yearLevelId &&
                item.classroomId == room.classroomId &&
                item.deliveryId == room.deliveryId)
            .toList() ??
        const <EvidenceUpload>[];
    final pendingIds = pending.map((item) => item.id).toSet();
    final saved = photos.valueOrNull
            ?.where((item) => !pendingIds.contains(item.id))
            .toList() ??
        const <Photo>[];
    return _RoomPhotos._(
      photos: photos,
      status: status,
      uploadsFailed: uploads.hasError || status?.localError == true,
      worker: ref.watch(evidenceUploadWorkerProvider).valueOrNull,
      pending: pending,
      saved: saved,
      bucket: saved.isEmpty ? null : ref.watch(offlineMediaBucketProvider),
    );
  }

  final AsyncValue<List<Photo>> photos;
  final EvidenceUploadStatus? status;
  final bool uploadsFailed;
  final EvidenceUploadWorker? worker;
  final List<EvidenceUpload> pending;
  final List<Photo> saved;
  final String? bucket;

  /// Photos waiting on this device first, then saved photos (newest first).
  List<_PhotoEntry> where(bool Function(PhotoSubject? subject) test) => [
        if (worker != null)
          for (final item in pending)
            if (test(item.subject)) _PhotoEntry.pending(item),
        for (final photo in saved)
          if (test(photo.subject)) _PhotoEntry.saved(photo),
      ];
}

/// Whether [subject] is the item [target] (a consumable keeps its photos
/// when it is renamed).
bool _sameItem(PhotoSubject? subject, PhotoSubject target) =>
    subject != null && subject.type == target.type && subject.id == target.id;

/// The compact photos row of one item (packs or a consumable): the count and
/// upload state beside its camera control, and the item's thumbnails below
/// when it has any.
class _ItemPhotos extends ConsumerWidget {
  const _ItemPhotos({
    required this.room,
    required this.subject,
    required this.name,
    this.iconOnly = false,
  });

  final _Room room;
  final PhotoSubject subject;

  /// How the item is read out: "packs", "Tissues".
  final String name;

  /// A 44 pt camera button instead of the labelled capsule.
  final bool iconOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = _RoomPhotos.watch(ref, room);
    final entries = photos.where((s) => _sameItem(s, subject));
    final colors = AppPalette.of(context);
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          entries.isEmpty ? 'No photos' : _plural(entries.length, 'photo'),
          style: AppTypography.subheadline.copyWith(
            color: entries.isEmpty ? colors.muted : colors.ink,
            fontWeight: entries.isEmpty ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
        ..._uploadStateLines(context, entries, topGap: 2),
      ],
    );
    final button = _AddPhotoButton(
      room: room,
      subject: subject,
      name: name,
      style: iconOnly ? _AddPhotoStyle.icon : _AddPhotoStyle.capsule,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          if (appStackTrailing(context, constraints)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [summary, const SizedBox(height: 8), button],
            );
          }
          return Row(
            children: [
              Expanded(child: summary),
              const SizedBox(width: 12),
              button,
            ],
          );
        }),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 10),
          _PhotoStrip(
            key: ValueKey(subject.isPacks
                ? 'photo-strip-packs'
                : 'photo-strip-${subject.id}'),
            room: room,
            photos: photos,
            entries: entries,
            subjectName: name,
          ),
        ],
      ],
    );
  }
}

/// "1 waiting to upload" and, in the warning colour, "1 photo needs
/// attention" for the photos in [entries] still on this device.
List<Widget> _uploadStateLines(
  BuildContext context,
  List<_PhotoEntry> entries, {
  double topGap = 4,
}) {
  final pending = [
    for (final entry in entries)
      if (entry.pending != null) entry.pending!,
  ];
  final attention = pending.where((item) => item.needsAttention).toList();
  final waiting = pending.length - attention.length;
  return [
    if (waiting > 0) ...[
      SizedBox(height: topGap),
      _StateLine(
        icon: AppIcons.waitingToUpload,
        text: '$waiting waiting to upload',
      ),
    ],
    if (attention.isNotEmpty) ...[
      SizedBox(height: topGap),
      _StateLine(
        icon: AppIcons.warning,
        iconColor: AppPalette.of(context).warningInk,
        text: attention.length == 1
            ? '1 photo needs attention · ${attention.single.statusText}'
            : '${attention.length} photos need attention',
      ),
    ],
  ];
}

/// A small icon and footnote line (no side padding, unlike [AppStatusLine]).
class _StateLine extends StatelessWidget {
  const _StateLine({required this.icon, required this.text, this.iconColor});

  final IconData icon;
  final String text;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: iconColor ?? colors.ink),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              style: AppTypography.footnote.copyWith(color: colors.muted)),
        ),
      ],
    );
  }
}

/// A horizontally scrolling row of square thumbnails. Vertical drags that
/// start on it still scroll the page.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    super.key,
    required this.room,
    required this.photos,
    required this.entries,
    required this.subjectName,
  });

  final _Room room;
  final _RoomPhotos photos;
  final List<_PhotoEntry> entries;

  /// "packs", "Tissues", "Tissues (removed item)"; null for general photos.
  final String? subjectName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _thumbSize,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final what = subjectName == null
              ? 'Classroom photo'
              : 'Photo of $subjectName';
          final pending = entry.pending;
          final Widget tile;
          if (pending != null) {
            tile = _PendingPhotoTile(
              key: ValueKey('pending-${pending.id}'),
              item: pending,
              file: photos.worker!.localFile(pending),
              active: pending.id == photos.status?.activeId,
              description: what,
            );
          } else {
            final photo = entry.photo!;
            final deliveryId = room.deliveryId;
            final visit = deliveryId == null
                ? null
                : DeliveryVisit(deliveryId: deliveryId, schoolId: room.schoolId);
            tile = _PhotoCard(
              key: ValueKey(photo.id),
              photo: photo,
              asset: OfflineMediaAsset.classroomPhoto(
                bucket: photos.bucket!,
                schoolId: room.schoolId,
                yearLevelId: room.yearLevelId,
                classroomId: room.classroomId,
                photoId: photo.id,
                reference: photo.storagePath,
                visit: visit,
              ),
              schoolId: room.schoolId,
              semanticLabel: '$what, ${index + 1} of ${entries.length}',
              viewerTitle: subjectName == null
                  ? 'Classroom photo'
                  : 'Photo of $subjectName',
              onRemove: () => _removePhoto(context, room, photo),
            );
          }
          return SizedBox.square(dimension: _thumbSize, child: tile);
        },
      ),
    );
  }
}

/// Opaque thumbnail frame: radius 12 with a hairline outline.
class _ThumbFrame extends StatelessWidget {
  const _ThumbFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final radius = BorderRadius.circular(AppTokens.controlRadius);
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: colors.highContrast
            ? Border.all(color: colors.outline)
            : Border.all(color: colors.separator, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(color: colors.surfaceQuiet, child: child),
      ),
    );
  }
}

/// A photo still on this device: its local file, its upload state as a small
/// badge and the existing upload actions (pause, retry, resume).
class _PendingPhotoTile extends StatelessWidget {
  const _PendingPhotoTile({
    super.key,
    required this.item,
    required this.file,
    required this.active,
    required this.description,
  });

  final EvidenceUpload item;
  final File file;
  final bool active;

  /// "Photo of packs", "Classroom photo".
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final attention = item.needsAttention;
    final state = active
        ? 'syncing'
        : attention || item.error != null
            ? item.statusText.toLowerCase()
            : 'waiting to upload';
    final Widget badge;
    if (attention) {
      badge = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: colors.warningTint,
          shape: BoxShape.circle,
          border: Border.all(
              color: colors.highContrast ? colors.warningInk : colors.glassEdge,
              width: colors.highContrast ? 1.5 : 0.5),
        ),
        child: Icon(item.paused ? AppIcons.paused : AppIcons.warning,
            size: 16, color: colors.warningInk),
      );
    } else {
      badge = AppGlassCircle(
        icon: AppIcons.waitingToUpload,
        size: 28,
        iconSize: 16,
        loading: active,
      );
    }
    return _ThumbFrame(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            container: true,
            image: true,
            label: '$description, $state',
            child: Image.file(
              file,
              cacheWidth: 264,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(AppIcons.gallery, color: colors.muted, size: 28),
              ),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: ExcludeSemantics(child: badge),
          ),
          if (!active)
            Positioned(
              top: 0,
              right: 0,
              child: EvidenceUploadActions(item: item, overMedia: true),
            ),
        ],
      ),
    );
  }
}

/// A saved photo: tap to open the full viewer; the offline download control
/// (in a visit) and remove (when allowed) sit over it as small glass buttons.
class _PhotoCard extends ConsumerWidget {
  const _PhotoCard({
    super.key,
    required this.photo,
    required this.asset,
    required this.schoolId,
    required this.semanticLabel,
    required this.viewerTitle,
    required this.onRemove,
  });

  final Photo photo;
  final OfflineMediaAsset? asset;
  final String schoolId;

  /// "Photo of Tissues, 1 of 2".
  final String semanticLabel;
  final String viewerTitle;
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

    return _ThumbFrame(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (owner != null && source != null)
            AppPressable(
              semanticLabel: semanticLabel,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => OfflineMediaScreen(
                    asset: source,
                    ownerUid: owner,
                    title: viewerTitle,
                  ),
                ),
              ),
              child: OfflineMediaPreview(asset: source, fit: BoxFit.cover),
            )
          else
            Semantics(
              label: '$semanticLabel, unavailable',
              image: true,
              child: Center(
                child: Icon(AppIcons.gallery, color: colors.muted, size: 28),
              ),
            ),
          // Diagonal corners keep most of a small photo visible.
          if (source?.visit != null)
            Positioned(
              left: 0,
              bottom: 0,
              child: OfflineMediaDownloadButton(asset: source!, glassSize: 28),
            ),
          if (canRemove)
            Positioned(
              top: 0,
              right: 0,
              child: AppGlassIconButton(
                icon: AppIcons.removeCircle,
                semanticLabel: 'Remove from classroom',
                tooltip: 'Remove from classroom',
                size: 28,
                iconSize: 16,
                hitSize: AppTokens.minTouchTarget,
                onPressed: onRemove,
              ),
            ),
        ],
      ),
    );
  }
}

enum _AddPhotoStyle {
  /// "Add photo" grey capsule with a camera icon.
  capsule,

  /// A 44 pt grey circle with a camera icon.
  icon,

  /// The section header's "Add" capsule.
  section,
}

/// Takes or chooses a photo (the existing picker sheet, permissions and
/// compression) and saves it on this device in the durable upload queue,
/// attached to [subject] (a general photo when null).
class _AddPhotoButton extends ConsumerStatefulWidget {
  const _AddPhotoButton({
    required this.room,
    required this.subject,
    required this.name,
    required this.style,
  });

  final _Room room;
  final PhotoSubject? subject;

  /// "packs" or the item name; null for a general photo.
  final String? name;
  final _AddPhotoStyle style;

  @override
  ConsumerState<_AddPhotoButton> createState() => _AddPhotoButtonState();
}

class _AddPhotoButtonState extends ConsumerState<_AddPhotoButton> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final worker = ref.watch(evidenceUploadWorkerProvider).valueOrNull;
    final onPressed = !_saving && worker != null ? _add : null;
    final name = widget.name;
    final semanticLabel = _saving
        ? 'Saving photo'
        : name == null
            ? 'Add photo'
            : 'Add photo of $name';
    switch (widget.style) {
      case _AddPhotoStyle.section:
        return _AddButton(
          label: _saving ? 'Saving…' : 'Add',
          semanticLabel: semanticLabel,
          icon: AppIcons.photos,
          onPressed: onPressed,
        );
      case _AddPhotoStyle.capsule:
        return _AddButton(
          label: _saving ? 'Saving…' : 'Add photo',
          semanticLabel: semanticLabel,
          icon: AppIcons.photos,
          onPressed: onPressed,
        );
      case _AddPhotoStyle.icon:
        final colors = AppPalette.of(context);
        final ink = onPressed == null
            ? colors.ink.withValues(alpha: 0.35)
            : colors.ink;
        return Tooltip(
          message: 'Add photo',
          excludeFromSemantics: true,
          child: AppPressable(
            onTap: onPressed,
            semanticLabel: semanticLabel,
            excludeChildSemantics: true,
            child: Container(
              width: AppTokens.minTouchTarget,
              height: AppTokens.minTouchTarget,
              decoration: BoxDecoration(
                color: colors.fill,
                shape: BoxShape.circle,
                border: colors.highContrast
                    ? Border.all(color: colors.outline)
                    : null,
              ),
              child: _saving
                  ? Padding(
                      padding: const EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: colors.ink),
                    )
                  : Icon(AppIcons.photos, size: 20, color: ink),
            ),
          ),
        );
    }
  }

  Future<void> _add() async {
    setState(() => _saving = true);
    try {
      await _pickAndSavePhoto(context, ref, widget.room, widget.subject);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Takes or chooses a photo with the existing picker and saves it on this
/// device in the durable upload queue, attached to [subject].
Future<void> _pickAndSavePhoto(
  BuildContext context,
  WidgetRef ref,
  _Room room,
  PhotoSubject? subject,
) async {
  final worker = ref.read(evidenceUploadWorkerProvider).valueOrNull;
  final uid = ref.read(authRepositoryProvider).currentUser?.uid;
  if (worker == null || uid == null) return;
  try {
    final file = await ref.read(photoServiceProvider).pickImage(context);
    if (file == null) return;
    await worker.enqueuePhoto(
      ownerUid: uid,
      schoolId: room.schoolId,
      yearLevelId: room.yearLevelId,
      classroomId: room.classroomId,
      source: file,
      deliveryId: room.deliveryId,
      subject: subject,
    );
    if (context.mounted) _showMessage(context, 'Photo saved on this device');
  } catch (_) {
    if (context.mounted) {
      _showMessage(context, 'Could not save the photo. Try again.');
    }
  }
}

/// Removes a saved photo from the classroom after confirmation (the stored
/// image stays for signed records that include it).
Future<void> _removePhoto(BuildContext context, _Room room, Photo photo) async {
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

  if (confirm != true || !context.mounted) return;

  final container = ProviderScope.containerOf(context, listen: false);
  final success = await container
      .read(schoolsNotifierProvider.notifier)
      .deleteClassroomPhoto(
          room.schoolId, room.yearLevelId, room.classroomId, photo.id,
          deliveryId: room.deliveryId);

  if (success) container.invalidate(classroomPhotosProvider(room.photosKey));

  if (context.mounted) {
    _showMessage(
      context,
      success
          ? 'Photo removed from classroom'
          : 'Could not remove the photo from the classroom',
    );
  }
}

/// General classroom photos, every photo taken before photos were attached
/// to items, and photos of consumables that have since been deleted (under
/// the item's saved name).
class _OtherPhotosSection extends ConsumerWidget {
  const _OtherPhotosSection({required this.room});

  final _Room room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppPalette.of(context);
    final photos = _RoomPhotos.watch(ref, room);
    final consumables = ref.watch(classroomConsumablesProvider(room.packKey));
    final currentIds = consumables.valueOrNull?.map((item) => item.id).toSet();
    final general = photos.where((subject) => subject == null);
    // Photos of a consumable that is not on the list (once the list is
    // known), grouped by item and labelled with the name saved with them.
    final removed = <String, List<_PhotoEntry>>{};
    if (currentIds != null || consumables.hasError) {
      for (final entry in photos.where((subject) =>
          subject != null &&
          !subject.isPacks &&
          !(currentIds?.contains(subject.id) ?? false))) {
        removed.putIfAbsent(entry.subject!.id!, () => []).add(entry);
      }
    }
    final all = [...general, for (final group in removed.values) ...group];
    final canAdd = photos.worker != null;

    String removedName(List<_PhotoEntry> group) {
      final label = group
          .map((entry) => entry.subject?.label ?? '')
          .firstWhere((label) => label.isNotEmpty, orElse: () => '');
      if (consumables.hasError) return label.isEmpty ? 'Item' : label;
      return label.isEmpty ? 'Removed item' : '$label (removed item)';
    }

    Widget groupLabel(String text) => Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            text,
            style: AppTypography.footnote
                .copyWith(fontWeight: FontWeight.w600, color: colors.muted),
          ),
        );

    final content = <Widget>[
      if (general.isNotEmpty && removed.isNotEmpty) groupLabel('General'),
      if (general.isNotEmpty)
        _PhotoStrip(
          key: const ValueKey('photo-strip-other'),
          room: room,
          photos: photos,
          entries: general,
          subjectName: null,
        ),
      for (final group in removed.entries) ...[
        if (general.isNotEmpty || group.key != removed.keys.first)
          const SizedBox(height: 14),
        groupLabel(removedName(group.value)),
        _PhotoStrip(
          key: ValueKey('photo-strip-removed-${group.key}'),
          room: room,
          photos: photos,
          entries: group.value,
          subjectName: removedName(group.value),
        ),
      ],
    ];

    final rows = <Widget>[
      if (photos.uploadsFailed)
        Padding(
          padding: const EdgeInsets.all(12),
          child: _AttentionNotice(
            onReview: () => SyncStatusDetailSheet.show(context),
          ),
        ),
      if (photos.photos.isLoading && all.isEmpty)
        const _MessageRow(title: 'Loading photos…', loading: true),
      if (photos.photos.hasError)
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
      if (photos.photos.hasValue && all.isEmpty)
        _EmptyOtherPhotosRow(room: room, enabled: canAdd),
      if (content.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: content,
          ),
        ),
    ];

    final stateLines = _uploadStateLines(context, all);
    return _Section(
      label: 'Other photos',
      action: _AddPhotoButton(
        room: room,
        subject: null,
        name: null,
        style: _AddPhotoStyle.section,
      ),
      caption: stateLines.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: stateLines,
              ),
            ),
      child: rows.isEmpty
          ? const SizedBox.shrink()
          : AppGroupedList(separatorIndent: 16, children: rows),
    );
  }
}

/// "No other photos" with the add control, as one compact row.
class _EmptyOtherPhotosRow extends ConsumerStatefulWidget {
  const _EmptyOtherPhotosRow({required this.room, required this.enabled});

  final _Room room;
  final bool enabled;

  @override
  ConsumerState<_EmptyOtherPhotosRow> createState() =>
      _EmptyOtherPhotosRowState();
}

class _EmptyOtherPhotosRowState extends ConsumerState<_EmptyOtherPhotosRow> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final canAdd = widget.enabled && !_saving;
    return AppListRow(
      icon: AppIcons.photos,
      title: 'No other photos',
      showChevron: false,
      trailing: canAdd ? Icon(AppIcons.add, size: 20, color: colors.ink) : null,
      onTap: canAdd ? _add : null,
      semanticLabel: 'No other photos. Add photo',
    );
  }

  Future<void> _add() async {
    setState(() => _saving = true);
    try {
      await _pickAndSavePhoto(context, ref, widget.room, null);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
