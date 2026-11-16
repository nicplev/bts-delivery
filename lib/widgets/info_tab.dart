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
import 'school_timer_history.dart';
import 'design/design.dart';

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
      error: (_, __) =>
          const Center(child: Text('Couldn’t load school information')),
      data: (school) {
        if (school == null) {
          return const Center(child: Text('School not found'));
        }

        final canEditSchoolData = ref.watch(canEditSchoolDataProvider);

        return ListView(
          key: const PageStorageKey('school-info'),
          primary: true,
          padding: EdgeInsets.fromLTRB(
            AppTokens.gutter,
            16,
            AppTokens.gutter,
            MediaQuery.paddingOf(context).bottom + 16,
          ),
          children: [
            _buildSchoolInfoCard(school),
            const SizedBox(height: 16),
            _buildLocationCard(school.address),
            const SizedBox(height: 16),
            _buildSchoolMapCard(school),
            const SizedBox(height: 16),
            if (canEditSchoolData &&
                ref.watch(activeDeliveryVisitProvider) == null) ...[
              _buildBulkImportCard(school),
              const SizedBox(height: 16),
            ],
            _buildContactsCard(contactsAsync, canEdit: canEditSchoolData),
            const SizedBox(height: 16),
            _buildTimerHistoryCard(),
          ],
        );
      },
    );
  }

  Widget _buildTimerHistoryCard() {
    final isVisit = ref.watch(activeDeliveryVisitProvider) != null;
    final isAdmin = isVisit && ref.watch(isAdminProvider);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconTile(icon: Icons.history, tone: AppTone.green),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isVisit ? 'Visit timer history' : 'Earlier timer history',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              if (isAdmin)
                IconButton(
                  onPressed: () => _showAddTimerDialog(),
                  icon: const Icon(Icons.add),
                  tooltip: 'Add Timer Entry',
                ),
            ],
          ),
          const SizedBox(height: 12),
          SchoolTimerHistory(schoolId: widget.schoolId, readOnly: !isVisit),
        ],
      ),
    );
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

  Widget _buildSchoolInfoCard(School school) {
    final isAdmin = ref.watch(isAdminProvider);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconTile(icon: Icons.school, tone: AppTone.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'School Information',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              if (isAdmin)
                IconButton(
                  onPressed: () => _showEditSchoolDialog(school),
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit School',
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            icon: Icons.label,
            label: 'School Name',
            value: school.name,
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            icon: Icons.calendar_today,
            label: 'Added',
            value: _formatDate(school.createdAt),
          ),
          if (school.isSignedOff && school.lastSignOffDate != null) ...[
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.check_circle,
              label: 'Earlier school sign-off',
              value: _formatDate(school.lastSignOffDate!),
              valueColor: AppTone.green.ink,
            ),
            if (school.signedBy?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              _buildInfoRow(
                icon: Icons.person,
                label: 'Signed by',
                value: school.signedBy!,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIconTile(icon: icon, tone: AppTone.neutral, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTokens.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSchoolMapCard(School school) {
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
    final owner = ref.watch(offlineMediaOwnerProvider(school.id));

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconTile(icon: Icons.map_outlined, tone: AppTone.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text('School map',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              if (canEdit && reference != null)
                IconButton(
                  onPressed: () => _showDeleteMapConfirmation(school),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete map',
                ),
              if (canEdit)
                IconButton(
                  onPressed: () => _handleUploadSchoolMap(school),
                  icon: Icon(reference == null ? Icons.add : Icons.edit),
                  tooltip: reference == null ? 'Upload map' : 'Replace map',
                ),
            ],
          ),
          if (reference == null)
            const Text('No school map uploaded')
          else if (asset == null)
            const Text(
                'This school map cannot be opened from its saved reference')
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.controlRadius),
              child: SizedBox(
                width: double.infinity,
                height: 250,
                child: OfflineMediaPreview(asset: asset),
              ),
            ),
            if (visit != null) OfflineMediaDownloadStatus(asset: asset),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: owner == null
                      ? null
                      : () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => OfflineMediaScreen(
                                asset: asset,
                                ownerUid: owner,
                                title: 'School map',
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.open_in_full_outlined),
                  label: const Text('Open map'),
                ),
                if (visit != null)
                  OfflineMediaDownloadButton(asset: asset, compact: false),
              ],
            ),
          ],
          if (visit != null)
            OfflineEarlierMapButton(visit: visit, currentMap: asset),
        ],
      ),
    );
  }

  Widget _buildBulkImportCard(School school) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconTile(icon: Icons.upload_file, tone: AppTone.green),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Bulk Import',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Import multiple classrooms, year levels, and consumables at once using a CSV file.',
            style: TextStyle(color: AppTokens.muted),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              context.push(
                '/schools/${school.id}/bulk-import?schoolName=${Uri.encodeComponent(school.name)}',
              );
            },
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Import Classrooms'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(String? savedAddress) {
    final address = savedAddress?.trim() ?? '';

    return AppPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppIconTile(icon: Icons.location_on_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  address.isEmpty ? 'No address saved' : address,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _openInMaps(address),
                    icon: const Icon(Icons.open_in_new_outlined),
                    label: const Text('Open in Maps'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsCard(
    AsyncValue<List<Contact>> contactsAsync, {
    required bool canEdit,
  }) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconTile(icon: Icons.contacts, tone: AppTone.pink),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Contacts',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              if (canEdit)
                IconButton(
                  onPressed: _showAddContactDialog,
                  icon: const Icon(Icons.add),
                  tooltip: 'Add Contact',
                ),
            ],
          ),
          const SizedBox(height: 16),
          contactsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, __) => const Text('Couldn’t load contacts'),
            data: (contacts) {
              if (contacts.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(Icons.person_off,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        const Text(
                          'No contacts added yet',
                          style: TextStyle(color: AppTokens.muted),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return AppGroupedList(
                children: contacts.map((contact) {
                  return _buildContactTile(contact, canEdit: canEdit);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContactTile(Contact contact, {required bool canEdit}) {
    final hasPhone = contact.phone?.isNotEmpty == true;
    final hasEmail = contact.email?.isNotEmpty == true;
    return ListTile(
      leading: const AppIconTile(
          icon: Icons.person_outline, tone: AppTone.pink, size: 32),
      title: Text(
        contact.name,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPhone)
            Row(
              children: [
                const Icon(Icons.phone, size: 14),
                const SizedBox(width: 4),
                Expanded(child: Text(contact.phone!)),
              ],
            ),
          if (hasEmail)
            Row(
              children: [
                const Icon(Icons.email, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(contact.email!),
                ),
              ],
            ),
        ],
      ),
      trailing: canEdit || hasPhone || hasEmail
          ? PopupMenuButton<String>(
              itemBuilder: (context) => [
                if (hasPhone)
                  const PopupMenuItem(
                    value: 'call',
                    child: Row(
                      children: [
                        Icon(Icons.phone),
                        SizedBox(width: 8),
                        Text('Call'),
                      ],
                    ),
                  ),
                if (hasEmail)
                  const PopupMenuItem(
                    value: 'email',
                    child: Row(
                      children: [
                        Icon(Icons.email),
                        SizedBox(width: 8),
                        Text('Email'),
                      ],
                    ),
                  ),
                if (canEdit)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                if (canEdit)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
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
        title: const Text('Add Contact'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _contactNameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  prefixIcon: Icon(Icons.person),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contactPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contactEmailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
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
        title: const Text('Edit Contact'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _contactNameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  prefixIcon: Icon(Icons.person),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contactPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contactEmailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
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
        title: const Text('Delete Contact'),
        content: Text('Are you sure you want to delete ${contact.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _deleteContact(contact.id),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
          backgroundColor: Colors.red,
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
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add contact'),
            backgroundColor: Colors.red,
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
          backgroundColor: Colors.red,
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
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update contact'),
            backgroundColor: Colors.red,
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
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete contact'),
            backgroundColor: Colors.red,
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
            backgroundColor: Colors.red,
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
            backgroundColor: Colors.red,
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
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showEditSchoolDialog(School school) {
    _schoolNameController.text = school.name;
    _schoolAddressController.text = school.address ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit School'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _schoolNameController,
                decoration: const InputDecoration(
                  labelText: 'School Name *',
                  prefixIcon: Icon(Icons.school),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _schoolAddressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  prefixIcon: Icon(Icons.location_on),
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
          backgroundColor: Colors.red,
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
          backgroundColor: Colors.green,
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to update school'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // School Map Methods
  Future<void> _handleUploadSchoolMap(School school) async {
    final photoService = ref.read(photoServiceProvider);
    final storageRepository = ref.read(storageRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    // Pick file (image or PDF)
    final file = await photoService.pickSchoolMapFile(context);
    if (file == null) return;

    // Show uploading indicator
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 16),
            Text('Uploading school map...'),
          ],
        ),
        duration: Duration(seconds: 30),
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
          backgroundColor: Colors.red,
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
          backgroundColor: Colors.red,
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
          backgroundColor: Colors.green,
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to save school map'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDeleteMapConfirmation(School school) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete School Map'),
        content: const Text(
            'Are you sure you want to delete the school map? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _deleteSchoolMap(dialogContext, school),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
            backgroundColor: Colors.red,
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
          backgroundColor: Colors.green,
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to delete school map'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
