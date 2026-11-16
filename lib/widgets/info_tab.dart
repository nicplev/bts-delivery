import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'dart:async';
import '../models/school.dart';
import '../providers/schools_providers.dart';
import '../providers/auth_providers.dart';
import '../providers/repository_providers.dart';
import 'package:uuid/uuid.dart';
import 'school_timer_history.dart';

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

  GoogleMapController? _mapController;

  @override
  void dispose() {
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _schoolNameController.dispose();
    _schoolAddressController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final schoolsAsync = ref.watch(schoolsProvider);
    final contactsAsync = ref.watch(contactsProvider(widget.schoolId));

    return schoolsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
      data: (schools) {
        final school =
            schools.where((s) => s.id == widget.schoolId).firstOrNull;

        if (school == null) {
          return const Center(child: Text('School not found'));
        }

        final canEditSchoolData = ref.watch(canEditSchoolDataProvider);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSchoolInfoCard(school),
            const SizedBox(height: 16),
            _buildSchoolMapCard(school),
            const SizedBox(height: 16),
            if (canEditSchoolData) ...[
              _buildBulkImportCard(school),
              const SizedBox(height: 16),
            ],
            if (school.address?.isNotEmpty == true) ...[
              _buildMapCard(school),
              const SizedBox(height: 16),
            ],
            _buildContactsCard(contactsAsync),
            const SizedBox(height: 16),
            _buildTimerHistoryCard(),
          ],
        );
      },
    );
  }

  Widget _buildTimerHistoryCard() {
    final isAdmin = ref.watch(isAdminProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Timer History',
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
            SchoolTimerHistory(schoolId: widget.schoolId),
          ],
        ),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.school, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
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
            if (school.address?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              _buildInfoRow(
                icon: Icons.location_on,
                label: 'Address',
                value: school.address!,
              ),
            ],
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
                label: 'Last Sign-off',
                value: _formatDate(school.lastSignOffDate!),
                valueColor: Colors.green,
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
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
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
    final isAdmin = ref.watch(isAdminProvider);
    final isManager = ref.watch(isManagerProvider);
    final canEdit = isAdmin || isManager;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.map_outlined, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'School Map',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (canEdit && school.schoolMapUrl != null)
                  IconButton(
                    onPressed: () => _showDeleteMapConfirmation(school),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete Map',
                    color: Colors.red,
                  ),
                if (canEdit)
                  IconButton(
                    onPressed: () => _handleUploadSchoolMap(school),
                    icon: Icon(school.schoolMapUrl == null ? Icons.add : Icons.edit),
                    tooltip: school.schoolMapUrl == null ? 'Upload Map' : 'Replace Map',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (school.schoolMapUrl == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.map_outlined, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        'No school map uploaded',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      if (canEdit) ...[
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _handleUploadSchoolMap(school),
                          icon: const Icon(Icons.cloud_upload),
                          label: const Text('Upload Map'),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else ...[
              // Check if it's a PDF by looking at the storage path (more reliable than URL)
              Builder(
                builder: (context) {
                  final isPdf = school.schoolMapStoragePath?.toLowerCase().endsWith('.pdf') ??
                                school.schoolMapUrl!.toLowerCase().contains('.pdf');

                  if (isPdf) {
                    // For PDFs, get fresh URL and show preview using SfPdfViewer with zoom controls
                    if (school.schoolMapStoragePath != null) {
                      final storageRepository = ref.read(storageRepositoryProvider);
                      return FutureBuilder<String>(
                        future: storageRepository.getDownloadUrl(school.schoolMapStoragePath!).then(
                          (result) => result.dataOrNull ?? school.schoolMapUrl!,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Container(
                              height: 200,
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          final pdfUrl = snapshot.data ?? school.schoolMapUrl!;
                          return _buildPdfViewer(pdfUrl);
                        },
                      );
                    }

                    // Fallback for PDF without storage path
                    return _buildPdfViewer(school.schoolMapUrl!);
                  }

                  // For images, use FutureBuilder to get fresh URL from storage path
                  if (school.schoolMapStoragePath != null) {
                    final storageRepository = ref.read(storageRepositoryProvider);
                    return FutureBuilder<String>(
                      future: storageRepository.getDownloadUrl(school.schoolMapStoragePath!).then(
                        (result) => result.dataOrNull ?? school.schoolMapUrl!,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            height: 300,
                            color: Colors.grey[200],
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        final imageUrl = snapshot.data ?? school.schoolMapUrl!;
                        return _buildImageViewer(imageUrl);
                      },
                    );
                  }

                  // Fallback: use stored URL directly
                  return _buildImageViewer(school.schoolMapUrl!);
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _viewSchoolMap(school.schoolMapUrl!),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open in Browser'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds PDF viewer with zoom controls
  Widget _buildPdfViewer(String pdfUrl) {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        final pdfController = PdfViewerController();

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                SfPdfViewer.network(
                  pdfUrl,
                  controller: pdfController,
                  canShowScrollHead: true,
                  canShowScrollStatus: true,
                  enableDoubleTapZooming: true,
                  enableTextSelection: false,
                  canShowPaginationDialog: true,
                  pageLayoutMode: PdfPageLayoutMode.continuous,
                  scrollDirection: PdfScrollDirection.vertical,
                  interactionMode: PdfInteractionMode.pan,
                ),
                // PDF badge
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.picture_as_pdf, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'PDF',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                // Zoom controls
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.zoom_out, color: Colors.white, size: 20),
                          onPressed: () {
                            final newZoom = (pdfController.zoomLevel - 0.5).clamp(1.0, 4.0);
                            pdfController.zoomLevel = newZoom;
                          },
                          tooltip: 'Zoom out',
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                        ),
                        IconButton(
                          icon: const Icon(Icons.fit_screen, color: Colors.white, size: 20),
                          onPressed: () {
                            pdfController.zoomLevel = 1.0;
                          },
                          tooltip: 'Reset zoom',
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                        ),
                        IconButton(
                          icon: const Icon(Icons.zoom_in, color: Colors.white, size: 20),
                          onPressed: () {
                            final newZoom = (pdfController.zoomLevel + 0.5).clamp(1.0, 4.0);
                            pdfController.zoomLevel = newZoom;
                          },
                          tooltip: 'Zoom in',
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
                // Hint text
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Double-tap to zoom',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Builds image viewer with zoom controls and double-tap to reset
  Widget _buildImageViewer(String imageUrl) {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        final transformController = TransformationController();
        var isZoomed = false;

        void resetZoom() {
          transformController.value = Matrix4.identity();
          setLocalState(() {
            isZoomed = false;
          });
        }

        void zoomIn() {
          final currentScale = transformController.value.getMaxScaleOnAxis();
          final newScale = (currentScale * 1.5).clamp(1.0, 4.0);
          transformController.value = Matrix4.diagonal3Values(newScale, newScale, 1);
          setLocalState(() {
            isZoomed = newScale > 1.0;
          });
        }

        void zoomOut() {
          final currentScale = transformController.value.getMaxScaleOnAxis();
          final newScale = (currentScale / 1.5).clamp(1.0, 4.0);
          if (newScale <= 1.0) {
            resetZoom();
          } else {
            transformController.value = Matrix4.diagonal3Values(newScale, newScale, 1);
            setLocalState(() {
              isZoomed = true;
            });
          }
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                GestureDetector(
                  onDoubleTap: () {
                    if (isZoomed) {
                      resetZoom();
                    } else {
                      // Zoom to 2x on double-tap
                      transformController.value = Matrix4.diagonal3Values(2.0, 2.0, 1);
                      setLocalState(() {
                        isZoomed = true;
                      });
                    }
                  },
                  child: InteractiveViewer(
                    transformationController: transformController,
                    minScale: 1.0,
                    maxScale: 4.0,
                    panEnabled: true,
                    scaleEnabled: true,
                    onInteractionEnd: (_) {
                      setLocalState(() {
                        isZoomed = transformController.value.getMaxScaleOnAxis() > 1.0;
                      });
                    },
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      height: 300,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => Container(
                        height: 300,
                        color: Colors.grey[200],
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        height: 300,
                        color: Colors.grey[200],
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text(
                              'Failed to load map',
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Zoom controls
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.zoom_out, color: Colors.white, size: 20),
                          onPressed: zoomOut,
                          tooltip: 'Zoom out',
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                        ),
                        IconButton(
                          icon: const Icon(Icons.fit_screen, color: Colors.white, size: 20),
                          onPressed: resetZoom,
                          tooltip: 'Reset zoom',
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                        ),
                        IconButton(
                          icon: const Icon(Icons.zoom_in, color: Colors.white, size: 20),
                          onPressed: zoomIn,
                          tooltip: 'Zoom in',
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
                // Hint text
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Double-tap to zoom',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBulkImportCard(School school) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.upload_file, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
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
              style: TextStyle(color: Colors.grey),
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
      ),
    );
  }

  Widget _buildMapCard(School school) {
    // Using a hardcoded location for Beaumaris (you can add geocoding later)
    // This is approximately where Beaumaris, VIC 3193 is located
    const LatLng beaumaris = LatLng(-37.9833, 145.0333);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.map, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Location',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 200,
                child: GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: beaumaris,
                    zoom: 15,
                  ),
                  markers: {
                    Marker(
                      markerId: const MarkerId('school_location'),
                      position: beaumaris,
                      infoWindow: InfoWindow(
                        title: school.name,
                        snippet: school.address,
                      ),
                    ),
                  },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openInMaps(school.address ?? ''),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in Maps'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsCard(AsyncValue<List<Contact>> contactsAsync) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.contacts, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Contacts',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
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
              error: (error, _) => Center(
                child: Text('Error loading contacts: $error'),
              ),
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
                          Text(
                            'No contacts added yet',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: contacts.map((contact) {
                    return _buildContactTile(contact);
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactTile(Contact contact) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(contact.name[0].toUpperCase()),
        ),
        title: Text(
          contact.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (contact.phone?.isNotEmpty == true)
              Row(
                children: [
                  const Icon(Icons.phone, size: 14),
                  const SizedBox(width: 4),
                  Text(contact.phone!),
                ],
              ),
            if (contact.email?.isNotEmpty == true)
              Row(
                children: [
                  const Icon(Icons.email, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      contact.email!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            if (contact.phone?.isNotEmpty == true)
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
            if (contact.email?.isNotEmpty == true)
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
                _showEditContactDialog(contact);
                break;
              case 'delete':
                _showDeleteContactConfirmation(contact);
                break;
            }
          },
        ),
      ),
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
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
          content: Text(uploadResult.errorOrNull ?? 'Failed to upload school map'),
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

  void _viewSchoolMap(String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open map: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDeleteMapConfirmation(School school) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete School Map'),
        content: const Text('Are you sure you want to delete the school map? This action cannot be undone.'),
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

  Future<void> _deleteSchoolMap(BuildContext dialogContext, School school) async {
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
