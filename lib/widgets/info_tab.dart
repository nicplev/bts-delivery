import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../models/offline/offline_media.dart';
import '../models/school.dart';
import '../providers/schools_providers.dart';
import '../providers/delivery_visit_provider.dart';
import '../providers/auth_providers.dart';
import '../providers/repository_providers.dart';
import '../providers/offline_media_providers.dart';
import 'package:uuid/uuid.dart';
import 'offline_media_view.dart';
import 'school_logo.dart';
import 'school_timer_history.dart';
import 'design/design.dart';
import '../services/date_utils.dart';

/// Visit hub › Info: grouped cards for the school's details, map, contacts,
/// classroom import and timer history.
class InfoTab extends ConsumerStatefulWidget {
  const InfoTab({super.key, required this.schoolId});

  final String schoolId;

  @override
  ConsumerState<InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends ConsumerState<InfoTab> {
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _schoolNameController = TextEditingController();
  final _schoolAddressController = TextEditingController();

  /// The inline map shown at most of the screen height.
  bool _mapEnlarged = false;

  @override
  void dispose() {
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _schoolNameController.dispose();
    _schoolAddressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final schoolAsync = ref.watch(schoolByIdProvider(widget.schoolId));
    final contactsAsync = ref.watch(contactsProvider(widget.schoolId));

    return schoolAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const _InfoMessage(
          icon: AppIcons.error, text: 'Couldn’t load school information'),
      data: (school) {
        if (school == null) {
          return const _InfoMessage(
              icon: AppIcons.school, text: 'School not found');
        }

        final canEditSchoolData = ref.watch(canEditSchoolDataProvider);
        const gap = SizedBox(height: AppTokens.sectionGap);

        return ListView(
          key: const PageStorageKey('school-info'),
          primary: true,
          padding: EdgeInsets.fromLTRB(
            AppTokens.gutter,
            8,
            AppTokens.gutter,
            AppInsets.bottom(context),
          ),
          children: [
            ..._buildSchoolInfoSection(school),
            gap,
            ..._buildSchoolMapSection(school),
            gap,
            ..._buildContactsSection(contactsAsync, canEdit: canEditSchoolData),
            if (canEditSchoolData &&
                ref.watch(activeDeliveryVisitProvider) == null) ...[
              gap,
              ..._buildBulkImportSection(school),
            ],
            gap,
            ..._buildTimerHistorySection(),
          ],
        );
      },
    );
  }

  /// Section label with an optional small grey capsule action on the right.
  /// The action wraps below the label when large text leaves no room.
  Widget _label(String text, {Widget? action}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: action == null
            ? AppSectionLabel(text)
            : Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [AppSectionLabel(text), action],
              ),
      );

  Widget _smallAction(
    String label,
    IconData icon,
    VoidCallback onPressed, {
    Key? key,
  }) =>
      AppSecondaryButton(
        key: key,
        label: label,
        icon: icon,
        expand: false,
        large: false,
        onPressed: onPressed,
      );

  List<Widget> _buildTimerHistorySection() {
    final isVisit = ref.watch(activeDeliveryVisitProvider) != null;
    final isAdmin = isVisit && ref.watch(isAdminProvider);

    return [
      _label(
        isVisit ? 'Visit timer history' : 'Earlier timer history',
        action: isAdmin
            ? _smallAction('Add entry', AppIcons.add, _showAddTimerDialog,
                key: const ValueKey('add-timer-entry'))
            : null,
      ),
      AppPanel(
        padding: EdgeInsets.zero,
        child:
            SchoolTimerHistory(schoolId: widget.schoolId, readOnly: !isVisit),
      ),
    ];
  }

  void _showAddTimerDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => TimerEntryDialog(
        schoolId: widget.schoolId,
        timer: null,
        ref: ref,
      ),
    );
  }

  List<Widget> _buildSchoolInfoSection(School school) {
    final isAdmin = ref.watch(isAdminProvider);
    final canEditLogo = ref.watch(canEditSchoolDataProvider);
    final address = school.address?.trim() ?? '';

    return [
      _label(
        'School information',
        action: isAdmin
            ? _smallAction(
                'Edit', AppIcons.edit, () => _showEditSchoolDialog(school),
                key: const ValueKey('edit-school'))
            : null,
      ),
      AppGroupedList(
        separatorIndent: 57,
        children: [
          _InfoRow(
            icon: AppIcons.school,
            leading: SchoolLogo(school: school, size: 29),
            label: 'School name',
            value: school.name,
          ),
          if (canEditLogo) SchoolLogoEditor(school: school),
          _InfoRow(
            icon: AppIcons.location,
            label: 'Address',
            value: address.isEmpty ? 'No address saved' : address,
          ),
          if (address.isNotEmpty)
            AppListRow(
              key: const ValueKey('open-in-maps'),
              icon: AppIcons.map,
              title: 'Open in Maps',
              trailing: Icon(AppIcons.external,
                  size: 18, color: AppPalette.of(context).chevron),
              showChevron: false,
              onTap: () => _openInMaps(address),
            ),
          _InfoRow(
            icon: AppIcons.calendar,
            label: 'Added',
            value: _formatDate(school.createdAt),
          ),
          if (school.isSignedOff && school.lastSignOffDate != null) ...[
            _InfoRow(
              icon: AppIcons.completeOutline,
              label: 'Earlier school sign-off',
              value: _formatDate(school.lastSignOffDate!),
            ),
            if (school.signedBy?.isNotEmpty == true)
              _InfoRow(
                icon: AppIcons.person,
                label: 'Signed by',
                value: school.signedBy!,
              ),
          ],
        ],
      ),
    ];
  }

  List<Widget> _buildSchoolMapSection(School school) {
    final canEdit = ref.watch(canEditSchoolDataProvider);
    final visit = ref.watch(activeDeliveryVisitProvider);
    final reference = school.schoolMapStoragePath ?? school.schoolMapUrl;
    final asset = reference == null
        ? null
        : OfflineMediaAsset.schoolMap(
            bucket: ref.watch(offlineMediaBucketProvider),
            schoolId: school.id,
            reference: reference,
            visit: visit,
          );
    final colors = AppPalette.of(context);

    // The map itself is viewed (and zoomed / enlarged) in place, so there is
    // no separate "Open map" screen any more.
    final actions = <Widget>[
      if (asset != null && visit != null)
        OfflineMediaDownloadButton(asset: asset, compact: false),
      if (canEdit)
        AppSecondaryButton(
          key: const ValueKey('upload-school-map'),
          label: reference == null ? 'Upload map' : 'Replace map',
          icon: AppIcons.upload,
          large: false,
          onPressed: () => _handleUploadSchoolMap(school),
        ),
      if (canEdit && reference != null)
        AppSecondaryButton(
          key: const ValueKey('delete-school-map'),
          label: 'Delete map',
          icon: AppIcons.delete,
          large: false,
          onPressed: () => _showDeleteMapConfirmation(school),
        ),
    ];

    final details = <Widget>[
      if (reference == null || asset == null)
        Row(
          children: [
            const AppIconTile(icon: AppIcons.map, size: 29),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                reference == null
                    ? 'No school map uploaded'
                    : 'This school map cannot be opened from its saved reference',
                style: AppTypography.body.copyWith(color: colors.muted),
              ),
            ),
          ],
        )
      else if (visit != null)
        OfflineMediaDownloadStatus(asset: asset),
      if (actions.isNotEmpty) ...[
        const SizedBox(height: 12),
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          actions[i],
        ],
      ],
      if (visit != null)
        OfflineEarlierMapButton(visit: visit, currentMap: asset),
    ];

    return [
      _label('School map'),
      AppPanel(
        key: const ValueKey('info-school-map'),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (asset != null)
              OfflineMapViewer(
                key: const ValueKey('info-map-viewer'),
                asset: asset,
                height: 320,
                enlarged: _mapEnlarged,
                onEnlargedChanged: (value) =>
                    setState(() => _mapEnlarged = value),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16, asset == null ? 16 : 6, 16, actions.isEmpty ? 10 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: details,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildBulkImportSection(School school) {
    return [
      _label('Import'),
      AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppIconTile(icon: AppIcons.importFile, size: 29),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Import multiple classrooms, year levels, and consumables at once using a CSV file.',
                    style: AppTypography.subheadline
                        .copyWith(color: AppPalette.of(context).muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppSecondaryButton(
              key: const ValueKey('import-classrooms'),
              label: 'Import classrooms',
              icon: AppIcons.importFile,
              onPressed: () {
                context.push(
                  '/schools/${school.id}/bulk-import?schoolName=${Uri.encodeComponent(school.name)}',
                );
              },
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildContactsSection(
    AsyncValue<List<Contact>> contactsAsync, {
    required bool canEdit,
  }) {
    final colors = AppPalette.of(context);
    return [
      _label(
        'Contacts',
        action: canEdit
            ? _smallAction('Add', AppIcons.add, _showAddContactDialog,
                key: const ValueKey('add-contact'))
            : null,
      ),
      contactsAsync.when(
        loading: () => const AppPanel(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => AppPanel(
          child: Text('Couldn’t load contacts',
              style: AppTypography.body.copyWith(color: colors.muted)),
        ),
        data: (contacts) {
          if (contacts.isEmpty) {
            return AppPanel(
              child: Row(
                children: [
                  const AppIconTile(icon: AppIcons.people, size: 29),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No contacts added yet',
                      style: AppTypography.body.copyWith(color: colors.muted),
                    ),
                  ),
                ],
              ),
            );
          }

          return AppGroupedList(
            separatorIndent: 57,
            children: [
              for (final contact in contacts)
                _buildContactTile(contact, canEdit: canEdit),
            ],
          );
        },
      ),
    ];
  }

  Widget _buildContactTile(Contact contact, {required bool canEdit}) {
    final hasPhone = contact.phone?.isNotEmpty == true;
    final hasEmail = contact.email?.isNotEmpty == true;
    final details = [
      if (hasPhone) contact.phone!,
      if (hasEmail) contact.email!,
    ];
    return AppListRow(
      icon: AppIcons.person,
      title: contact.name,
      subtitle: details.isEmpty ? null : details.join('\n'),
      trailing: canEdit || hasPhone || hasEmail
          ? AppMenuButton<String>(
              tooltip: 'Contact options',
              itemBuilder: (context) => [
                if (hasPhone)
                  appMenuItem(context, 'call', 'Call', icon: AppIcons.phone),
                if (hasEmail)
                  appMenuItem(context, 'email', 'Email', icon: AppIcons.email),
                if (canEdit)
                  appMenuItem(context, 'edit', 'Edit', icon: AppIcons.edit),
                if (canEdit)
                  appMenuItem(context, 'delete', 'Delete',
                      icon: AppIcons.delete, destructive: true),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'call':
                    _callContact(contact.phone!);
                    break;
                  case 'email':
                    _emailContact(contact.email!);
                    break;
                  case 'edit':
                    if (ref.read(canEditSchoolDataProvider)) {
                      _showEditContactDialog(contact);
                    }
                    break;
                  case 'delete':
                    if (ref.read(canEditSchoolDataProvider)) {
                      _showDeleteContactConfirmation(contact);
                    }
                    break;
                }
              },
            )
          : null,
    );
  }

  void _showAddContactDialog() {
    _contactNameController.clear();
    _contactPhoneController.clear();
    _contactEmailController.clear();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add contact'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _contactNameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  prefixIcon: Icon(AppIcons.person),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contactPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(AppIcons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contactEmailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(AppIcons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _addContact(dialogContext),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditContactDialog(Contact contact) {
    _contactNameController.text = contact.name;
    _contactPhoneController.text = contact.phone ?? '';
    _contactEmailController.text = contact.email ?? '';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit contact'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _contactNameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  prefixIcon: Icon(AppIcons.person),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contactPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(AppIcons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contactEmailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(AppIcons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _updateContact(contact, dialogContext),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteContactConfirmation(Contact contact) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete contact'),
        content: Text('Are you sure you want to delete ${contact.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _deleteContact(contact.id),
            style: appDestructiveButtonStyle(context),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _addContact(BuildContext dialogContext) async {
    if (_contactNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a contact name'),
        ),
      );
      return;
    }

    final contact = Contact(
      id: '',
      name: _contactNameController.text.trim(),
      phone: _contactPhoneController.text.trim().isEmpty
          ? null
          : _contactPhoneController.text.trim(),
      email: _contactEmailController.text.trim().isEmpty
          ? null
          : _contactEmailController.text.trim(),
      createdAt: DateTime.now(),
    );

    // Close dialog first
    Navigator.pop(dialogContext);

    // Wait a bit for dialog to close
    await Future.delayed(const Duration(milliseconds: 100));

    final success = await ref
        .read(schoolsNotifierProvider.notifier)
        .createContact(widget.schoolId, contact);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact added successfully'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add contact'),
          ),
        );
      }
    }
  }

  Future<void> _updateContact(
      Contact contact, BuildContext dialogContext) async {
    if (_contactNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a contact name'),
        ),
      );
      return;
    }

    final updatedContact = contact.copyWith(
      name: _contactNameController.text.trim(),
      phone: _contactPhoneController.text.trim().isEmpty
          ? null
          : _contactPhoneController.text.trim(),
      email: _contactEmailController.text.trim().isEmpty
          ? null
          : _contactEmailController.text.trim(),
    );

    // Close dialog first
    Navigator.pop(dialogContext);

    // Wait a bit for dialog to close
    await Future.delayed(const Duration(milliseconds: 100));

    final success = await ref
        .read(schoolsNotifierProvider.notifier)
        .updateContact(widget.schoolId, updatedContact);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact updated successfully'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update contact'),
          ),
        );
      }
    }
  }

  Future<void> _deleteContact(String contactId) async {
    final success = await ref
        .read(schoolsNotifierProvider.notifier)
        .deleteContact(widget.schoolId, contactId);

    if (mounted) {
      Navigator.pop(context);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact deleted successfully'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete contact'),
          ),
        );
      }
    }
  }

  Future<void> _openInMaps(String address) async {
    try {
      final encodedAddress = Uri.encodeComponent(address);
      final url = Uri.parse('https://maps.google.com/?q=$encodedAddress');

      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open maps: $e'),
          ),
        );
      }
    }
  }

  Future<void> _callContact(String phone) async {
    try {
      final url = Uri.parse('tel:$phone');
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not make call: $e'),
          ),
        );
      }
    }
  }

  Future<void> _emailContact(String email) async {
    try {
      final url = Uri.parse('mailto:$email');
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open email: $e'),
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) => DateTimeUtils.formatDate(date);

  void _showEditSchoolDialog(School school) {
    _schoolNameController.text = school.name;
    _schoolAddressController.text = school.address ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit school'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _schoolNameController,
                decoration: const InputDecoration(
                  labelText: 'School Name *',
                  prefixIcon: Icon(AppIcons.school),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _schoolAddressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  prefixIcon: Icon(AppIcons.location),
                ),
                textCapitalization: TextCapitalization.words,
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _updateSchool(school, dialogContext),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateSchool(School school, BuildContext dialogContext) async {
    if (_schoolNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a school name'),
        ),
      );
      return;
    }

    // Store the notifier and messenger BEFORE any async operations
    final notifier = ref.read(schoolsNotifierProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    final updatedSchool = school.copyWith(
      name: _schoolNameController.text.trim(),
      address: _schoolAddressController.text.trim().isEmpty
          ? null
          : _schoolAddressController.text.trim(),
    );

    // Close dialog using the dialog context before async operation
    if (dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }

    final success = await notifier.updateSchool(updatedSchool);

    if (success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('School updated successfully'),
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to update school'),
        ),
      );
    }
  }

  // School Map Methods
  Future<void> _handleUploadSchoolMap(School school) async {
    final photoService = ref.read(photoServiceProvider);
    final storageRepository = ref.read(storageRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    final indicatorColor = AppPalette.of(context).canvas;

    // Pick file (image or PDF)
    final file = await photoService.pickSchoolMapFile(context);
    if (file == null) return;

    // Show uploading indicator
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
            const Expanded(child: Text('Uploading school map...')),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
    );

    // Delete old file if exists
    if (school.schoolMapStoragePath != null) {
      await storageRepository.deleteFile(school.schoolMapStoragePath!);
    }

    // Upload to Firebase Storage
    final mapId = const Uuid().v4();
    final extension = file.path.split('.').last.toLowerCase();
    final storagePath = 'schools/${school.id}/map/$mapId.$extension';

    final uploadResult = await photoService.uploadSchoolMap(storagePath, file);

    messenger.clearSnackBars();

    if (!uploadResult.isSuccess) {
      messenger.showSnackBar(
        SnackBar(
          content:
              Text(uploadResult.errorOrNull ?? 'Failed to upload school map'),
        ),
      );
      return;
    }

    // Get download URL
    final urlResult = await storageRepository.getDownloadUrl(storagePath);
    if (!urlResult.isSuccess) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to get download URL'),
        ),
      );
      return;
    }

    // Update school with map URL
    final updatedSchool = school.copyWith(
      schoolMapUrl: urlResult.dataOrNull,
      schoolMapStoragePath: storagePath,
    );

    final success = await ref
        .read(schoolsNotifierProvider.notifier)
        .updateSchool(updatedSchool);

    if (success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('School map uploaded successfully'),
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to save school map'),
        ),
      );
    }
  }

  void _showDeleteMapConfirmation(School school) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete school map'),
        content: const Text(
            'Are you sure you want to delete the school map? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _deleteSchoolMap(dialogContext, school),
            style: appDestructiveButtonStyle(context),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSchoolMap(
      BuildContext dialogContext, School school) async {
    Navigator.of(dialogContext).pop(); // Close dialog

    final storageRepository = ref.read(storageRepositoryProvider);
    final schoolsNotifier = ref.read(schoolsNotifierProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    // Delete file from storage
    if (school.schoolMapStoragePath != null) {
      final deleteResult =
          await storageRepository.deleteFile(school.schoolMapStoragePath!);

      if (deleteResult.isFailure) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              deleteResult.errorOrNull ??
                  'Failed to delete school map from storage',
            ),
          ),
        );
        return;
      }
    }

    // Update school to remove map URL
    final updatedSchool = school.copyWith(
      schoolMapUrl: null,
      schoolMapStoragePath: null,
    );

    final success = await schoolsNotifier.updateSchool(updatedSchool);

    if (!mounted) return;

    if (success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('School map deleted successfully'),
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to delete school map'),
        ),
      );
    }
  }
}

/// A read-only fact: grey icon tile, muted label, value below (wraps freely).
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.leading,
  });

  final IconData icon;

  /// Replaces the icon tile (e.g. the school's logo).
  final Widget? leading;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              leading ?? AppIconTile(icon: icon, size: 29),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTypography.footnote.copyWith(
                          color: colors.muted, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: AppTypography.body.copyWith(color: colors.ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoMessage extends StatelessWidget {
  const _InfoMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconTile(icon: icon, size: 48),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTypography.body
                  .copyWith(color: AppPalette.of(context).muted),
            ),
          ],
        ),
      ),
    );
  }
}
