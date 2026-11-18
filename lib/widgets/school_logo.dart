import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/school.dart';
import '../providers/auth_providers.dart';
import '../providers/repository_providers.dart';
import '../providers/schools_providers.dart';
import 'design/design.dart';

/// Builds the image for a logo download URL. [cacheKey] is scoped to the
/// signed-in account (see [schoolLogoImage]).
typedef SchoolLogoImageResolver = ImageProvider Function(
    String url, String cacheKey);

/// Logos load through `cached_network_image` so one that has been seen once
/// still shows offline. Tests and screenshots replace this.
final schoolLogoImageResolverProvider = Provider<SchoolLogoImageResolver>(
  (ref) => (url, cacheKey) => CachedNetworkImageProvider(url, cacheKey: cacheKey),
);

/// The logo image of [school], or null when it has none (or nobody is signed
/// in). The cache key includes the account, so a copy saved while one person
/// was signed in is never shown to another account on the same device: like
/// downloaded visit media, each cached logo belongs to the account that
/// loaded it.
ImageProvider? schoolLogoImage(WidgetRef ref, School? school) {
  final url = school?.logoUrl?.trim();
  if (url == null || url.isEmpty) return null;
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return null;
  final cacheKey = 'school-logo/$uid/${school!.logoStoragePath ?? url}';
  return ref.watch(schoolLogoImageResolverProvider)(url, cacheKey);
}

/// [AppSchoolAvatar] for a school the screen already has.
class SchoolLogo extends ConsumerWidget {
  const SchoolLogo({
    super.key,
    required this.school,
    this.size = 40,
    this.semanticLabel,
  });

  final School? school;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppSchoolAvatar(
        logo: schoolLogoImage(ref, school),
        size: size,
        semanticLabel: semanticLabel,
      );
}

/// [AppSchoolAvatar] for a school known only by id (a delivery row). Uses the
/// shared [schoolByIdProvider] listener (one school document), so it shows the
/// default icon until the school has loaded and whenever it can't be read.
class SchoolLogoForId extends ConsumerWidget {
  const SchoolLogoForId({super.key, required this.schoolId, this.size = 40});

  final String schoolId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final school = ref.watch(schoolByIdProvider(schoolId)).valueOrNull;
    return AppSchoolAvatar(logo: schoolLogoImage(ref, school), size: size);
  }
}

/// "School logo" row for people who can edit school data: the current logo
/// (or the default icon) and Add / Replace / Remove. Changes save straight
/// away, like the school map.
class SchoolLogoEditor extends ConsumerStatefulWidget {
  const SchoolLogoEditor({
    super.key,
    required this.school,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final School school;
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<SchoolLogoEditor> createState() => _SchoolLogoEditorState();
}

class _SchoolLogoEditorState extends ConsumerState<SchoolLogoEditor> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final school = widget.school;
    final hasLogo = school.logoUrl?.trim().isNotEmpty == true;
    final description = _busy
        ? 'Saving…'
        : hasLogo
            ? 'Shown in place of the school icon'
            : 'No logo. The school icon shows instead.';

    return Padding(
      key: const ValueKey('school-logo-editor'),
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                SchoolLogo(
                  school: school,
                  size: 48,
                  semanticLabel: hasLogo ? 'Logo of ${school.name}' : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'School logo',
                        style: AppTypography.footnote.copyWith(
                            color: colors.muted, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: AppTypography.subheadline
                            .copyWith(color: colors.ink),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Full-width capsules, like the school map's actions.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSecondaryButton(
                key: ValueKey(
                    hasLogo ? 'school-logo-replace' : 'school-logo-add'),
                label: hasLogo ? 'Replace logo' : 'Add logo',
                icon: AppIcons.upload,
                large: false,
                onPressed: _busy
                    ? null
                    : () => _run(() => uploadSchoolLogo(context, ref, school)),
              ),
              if (hasLogo) ...[
                const SizedBox(height: 8),
                AppSecondaryButton(
                  key: const ValueKey('school-logo-remove'),
                  label: 'Remove logo',
                  icon: AppIcons.delete,
                  large: false,
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => confirmRemoveSchoolLogo(context, ref, school)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Picks a logo (camera or library), uploads it as
/// `schools/{schoolId}/logo/{uuid}.jpg`, saves its URL and path on the school
/// and then deletes the logo it replaces.
Future<void> uploadSchoolLogo(
    BuildContext context, WidgetRef ref, School school) async {
  if (!ref.read(canEditSchoolDataProvider)) return;
  final photoService = ref.read(photoServiceProvider);
  final storage = ref.read(storageRepositoryProvider);
  final notifier = ref.read(schoolsNotifierProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  final indicatorColor = AppPalette.of(context).canvas;

  final bytes = await photoService.pickSchoolLogo(context);
  if (bytes == null) return;

  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: indicatorColor),
          ),
          const SizedBox(width: 16),
          const Expanded(child: Text('Uploading school logo…')),
        ],
      ),
      duration: const Duration(seconds: 30),
    ),
  );

  final storagePath = 'schools/${school.id}/logo/${const Uuid().v4()}.jpg';
  final upload = await storage.uploadJpegBytes(storagePath, bytes);
  messenger.clearSnackBars();
  final url = upload.dataOrNull;
  if (!upload.isSuccess || url == null) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Couldn’t upload the school logo. Try again.')));
    return;
  }

  final saved = await notifier.updateSchoolLogo(
    school.id,
    logoUrl: url,
    logoStoragePath: storagePath,
  );
  if (!saved) {
    // The school still points to its previous logo; drop the unused upload.
    await storage.deleteFile(storagePath);
    messenger.showSnackBar(const SnackBar(
        content: Text('Couldn’t save the school logo. Try again.')));
    return;
  }

  final previous = school.logoStoragePath;
  if (previous != null && previous != storagePath) {
    // Best effort: the school already shows the new logo.
    await storage.deleteFile(previous);
  }
  messenger.showSnackBar(const SnackBar(content: Text('School logo updated')));
}

/// Asks before removing the logo (error-coloured action), then deletes the
/// file and clears the logo on the school, like deleting the school map.
Future<void> confirmRemoveSchoolLogo(
    BuildContext context, WidgetRef ref, School school) async {
  if (!ref.read(canEditSchoolDataProvider)) return;
  final storage = ref.read(storageRepositoryProvider);
  final notifier = ref.read(schoolsNotifierProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remove school logo?'),
      content: const Text(
          'The default school icon will show instead. You can add a logo again at any time.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirm-remove-school-logo'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: appDestructiveButtonStyle(dialogContext),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final path = school.logoStoragePath;
  if (path != null) {
    final deleted = await storage.deleteFile(path);
    // A file that is already gone doesn't stop the logo being cleared.
    if (deleted.isFailure &&
        !(deleted.errorOrNull?.contains('object-not-found') ?? false)) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Couldn’t remove the school logo. Try again.')));
      return;
    }
  }

  final cleared = await notifier.updateSchoolLogo(
    school.id,
    logoUrl: null,
    logoStoragePath: null,
  );
  messenger.showSnackBar(SnackBar(
    content: Text(cleared
        ? 'School logo removed'
        : 'Couldn’t remove the school logo. Try again.'),
  ));
}
