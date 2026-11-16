import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../providers/schools_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/auth_providers.dart';
import '../../models/school.dart';
import '../../models/offline/offline_models.dart';
import '../../services/offline/offline_storage_service.dart';
import '../../utils/notification_utils.dart';
import 'package:uuid/uuid.dart';

/// Represents a photo that is being uploaded
class _PendingPhoto {
  final String id;
  final File localFile;
  final bool hasError;
  final String? errorMessage;

  const _PendingPhoto({
    required this.id,
    required this.localFile,
    this.hasError = false,
    this.errorMessage,
  });

  _PendingPhoto copyWith({
    String? id,
    File? localFile,
    bool? hasError,
    String? errorMessage,
  }) {
    return _PendingPhoto(
      id: id ?? this.id,
      localFile: localFile ?? this.localFile,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ClassroomDetailScreen extends ConsumerWidget {
  const ClassroomDetailScreen({
    super.key,
    required this.schoolId,
    required this.yearLevelId,
    required this.classroomId,
  });

  final String schoolId;
  final String yearLevelId;
  final String classroomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classroomsAsync = ref.watch(classroomsProvider((
      schoolId: schoolId,
      yearLevelId: yearLevelId,
    )));
    final packTotalAsync = ref.watch(packTotalProvider((
      schoolId: schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroomId,
    )));
    final consumablesAsync = ref.watch(classroomConsumablesProvider((
      schoolId: schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroomId,
    )));
    final notesAsync = ref.watch(classroomNotesProvider((
      schoolId: schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroomId,
    )));
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: classroomsAsync.when(
          data: (classrooms) {
            final classroom = classrooms.firstWhere(
              (c) => c.id == classroomId,
              orElse: () => Classroom(
                id: '',
                name: 'Classroom',
                createdAt: DateTime.now(),
              ),
            );
            return Text(classroom.name);
          },
          loading: () => const Text('Classroom'),
          error: (_, __) => const Text('Classroom'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Completion Status Card
          classroomsAsync.when(
            data: (classrooms) {
              final classroom = classrooms.firstWhere(
                (c) => c.id == classroomId,
                orElse: () => Classroom(
                  id: '',
                  name: 'Classroom',
                  createdAt: DateTime.now(),
                ),
              );
              return _buildCompletionStatusCard(context, ref, classroom);
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),

          // Pack Total Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Pack Total',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isAdmin)
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showUpdatePackTotalDialog(
                            context,
                            ref,
                            packTotalAsync.value?.total,
                          ),
                          tooltip: 'Update Pack Total',
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  packTotalAsync.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (error, _) => const Text(
                      'Error loading pack total',
                      style: TextStyle(color: Colors.red),
                    ),
                    data: (packTotal) {
                      if (packTotal == null) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'No pack total set',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (isAdmin) ...[
                              const SizedBox(height: 12),
                              Center(
                                child: ElevatedButton.icon(
                                  onPressed: () => _showUpdatePackTotalDialog(
                                    context,
                                    ref,
                                    null,
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Set Pack Total'),
                                ),
                              ),
                            ],
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${packTotal.total} packs',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Last updated: ${_formatDate(packTotal.createdAt)}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Year Level Breakdown Section (for composite classes)
          ref.watch(yearLevelBreakdownsProvider((
            schoolId: schoolId,
            yearLevelId: yearLevelId,
            classroomId: classroomId,
          ))).when(
            data: (breakdowns) {
              if (breakdowns.isEmpty) {
                // Only show empty state with Add button for admins
                // Non-admins don't see this section when no breakdowns exist
                if (!isAdmin) {
                  return const SizedBox.shrink();
                }
                return Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.people_outline, size: 28),
                                SizedBox(width: 12),
                                Text(
                                  'Student Distribution',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No student distribution set. Add year level breakdowns for composite classes.',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: ElevatedButton.icon(
                                onPressed: () => _showAddYearLevelBreakdownDialog(
                                  context,
                                  ref,
                                ),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Year Level'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              } else if (breakdowns.isNotEmpty) {
                // Show year level breakdown table
                final totalStudents = breakdowns.fold<int>(
                  0,
                  (sum, b) => sum + b.studentCount,
                );
                return Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.people_outline, size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Student Distribution',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (breakdowns.length > 1)
                                        Text(
                                          'Composite Class',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                // Only admins can add new year level breakdowns
                                if (isAdmin)
                                  IconButton(
                                    icon: const Icon(Icons.add),
                                    onPressed: () => _showAddYearLevelBreakdownDialog(
                                      context,
                                      ref,
                                    ),
                                    tooltip: 'Add Year Level',
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Table(
                              border: TableBorder.all(
                                color: Colors.grey.shade300,
                                width: 1,
                              ),
                              columnWidths: {
                                0: const FlexColumnWidth(2),
                                1: const FlexColumnWidth(1),
                                // Only show action column for admins
                                if (isAdmin) 2: const FixedColumnWidth(48),
                              },
                              children: [
                                TableRow(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                  ),
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Text(
                                        'Year Level',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Text(
                                        'Students',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    // Only show action column header for admins
                                    if (isAdmin) const SizedBox.shrink(),
                                  ],
                                ),
                                ...breakdowns.map((breakdown) => TableRow(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(breakdown.yearLevelLabel),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        '${breakdown.studentCount}',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    // Only admins can edit/delete breakdowns
                                    if (isAdmin)
                                      PopupMenuButton(
                                        icon: const Icon(Icons.more_vert, size: 20),
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            child: const Row(
                                              children: [
                                                Icon(Icons.edit, size: 16),
                                                SizedBox(width: 8),
                                                Text('Edit'),
                                              ],
                                            ),
                                            onTap: () {
                                              Future.delayed(Duration.zero, () {
                                                _showEditYearLevelBreakdownDialog(
                                                  context,
                                                  ref,
                                                  breakdown,
                                                );
                                              });
                                            },
                                          ),
                                          PopupMenuItem(
                                            child: const Row(
                                              children: [
                                                Icon(Icons.delete, size: 16, color: Colors.red),
                                                SizedBox(width: 8),
                                                Text('Delete', style: TextStyle(color: Colors.red)),
                                              ],
                                            ),
                                            onTap: () {
                                              Future.delayed(Duration.zero, () {
                                                _deleteYearLevelBreakdown(context, ref, breakdown);
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                  ],
                                )),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total Students',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '$totalStudents',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('Loading student distribution...'),
                    ],
                  ),
                ),
              ),
            ),
            error: (error, stackTrace) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.error, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          'Error loading student distribution',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Error: $error',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Consumables Section Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const Icon(Icons.inventory_outlined, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Consumables',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showAddConsumableDialog(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Consumables List
          consumablesAsync.when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (error, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error loading consumables',
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ),
            data: (consumables) {
              if (consumables.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No consumables yet',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add items like tissues, paper, etc.',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: consumables.map((consumable) {
                  final hasActualQuantity = consumable.actualQuantityDelivered != null;
                  final isPartialDelivery = hasActualQuantity &&
                      consumable.actualQuantityDelivered != consumable.quantity;
                  final isFullyDelivered = hasActualQuantity &&
                      consumable.actualQuantityDelivered == consumable.quantity;

                  // Determine colors based on status
                  Color backgroundColor;
                  Color iconColor;
                  Color textColor;
                  IconData iconData;

                  if (isPartialDelivery) {
                    backgroundColor = Colors.orange.shade50;
                    iconColor = Colors.orange.shade700;
                    textColor = Colors.orange.shade900;
                    iconData = Icons.warning_amber_rounded;
                  } else if (isFullyDelivered) {
                    backgroundColor = Colors.green.shade50;
                    iconColor = Colors.green.shade700;
                    textColor = Colors.green.shade900;
                    iconData = Icons.check_circle_rounded;
                  } else {
                    backgroundColor = Colors.white;
                    iconColor = Colors.grey.shade600;
                    textColor = Colors.black87;
                    iconData = Icons.inventory_2_outlined;
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isPartialDelivery
                            ? Colors.orange.shade300
                            : isFullyDelivered
                                ? Colors.green.shade300
                                : Colors.grey.shade200,
                        width: 1.5,
                      ),
                    ),
                    color: backgroundColor,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header row with icon, name, and menu
                          Row(
                            children: [
                              // Icon
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: iconColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  iconData,
                                  size: 24,
                                  color: iconColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      consumable.itemName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    hasActualQuantity
                                        ? RichText(
                                            text: TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: '${consumable.actualQuantityDelivered}',
                                                  style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: textColor,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: ' / ${consumable.quantity}',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: ' ${consumable.unit}',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.normal,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : Text(
                                            '${consumable.quantity} ${consumable.unit}',
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: Colors.grey.shade600,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                  ],
                                ),
                              ),
                              // Menu button
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _showEditConsumableDialog(context, ref, consumable);
                                  } else if (value == 'delete') {
                                    _showDeleteConsumableConfirmation(
                                        context, ref, consumable);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 20),
                                        SizedBox(width: 12),
                                        Text('Edit'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, size: 20, color: Colors.red),
                                        SizedBox(width: 12),
                                        Text('Delete',
                                            style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Quick action buttons
                          Row(
                            children: [
                              // Mark as Complete button
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    // Store mounted state before async operation
                                    if (!context.mounted) return;

                                    final updatedConsumable = consumable.copyWith(
                                      actualQuantityDelivered: consumable.quantity,
                                    );

                                    final success = await ref
                                        .read(schoolsNotifierProvider.notifier)
                                        .updateClassroomConsumable(
                                      schoolId,
                                      yearLevelId,
                                      classroomId,
                                      updatedConsumable,
                                    );

                                    if (!context.mounted) return;

                                    if (success) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('${consumable.itemName} marked as complete'),
                                          backgroundColor: Colors.green,
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.check_circle_outline, size: 18),
                                  label: const Text('Complete'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.green,
                                    side: BorderSide(color: Colors.green.shade300),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Set Actual Quantity button
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    _showSetActualConsumableDialog(context, ref, consumable);
                                  },
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Set Qty'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.orange,
                                    side: BorderSide(color: Colors.orange.shade300),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 24),

          // Photos Section (with optimistic upload support)
          _PhotosSection(
            schoolId: schoolId,
            yearLevelId: yearLevelId,
            classroomId: classroomId,
          ),

          const SizedBox(height: 24),

          // Notes Section Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const Icon(Icons.note_outlined, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Notes',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showAddNoteDialog(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Notes List
          notesAsync.when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (error, stackTrace) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Error loading notes',
                      style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Error: $error',
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            data: (notes) {
              if (notes.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.note_alt_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No notes yet',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add notes about this classroom',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: notes.map((note) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  note.content,
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _showEditNoteDialog(context, ref, note);
                                  } else if (value == 'delete') {
                                    _showDeleteNoteConfirmation(context, ref, note);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 20),
                                        SizedBox(width: 12),
                                        Text('Edit'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, size: 20, color: Colors.red),
                                        SizedBox(width: 12),
                                        Text('Delete', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (note.author != null) ...[
                                Icon(Icons.person, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  note.author!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                _formatDate(note.createdAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionStatusCard(
      BuildContext context, WidgetRef ref, Classroom classroom) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 20),
                SizedBox(width: 8),
                Text(
                  'Pack Delivery Status',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Select the status for packs only (not consumables)',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 20),
            // Status options as clean buttons
            Row(
              children: [
                Expanded(
                  child: _buildStatusOption(
                    context,
                    ref,
                    classroom,
                    yearLevelId,
                    ClassroomCompletionStatus.notAttended,
                    'Not Attended',
                    Icons.cancel_rounded,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatusOption(
                    context,
                    ref,
                    classroom,
                    yearLevelId,
                    ClassroomCompletionStatus.incomplete,
                    'Incomplete',
                    Icons.warning_amber_rounded,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatusOption(
                    context,
                    ref,
                    classroom,
                    yearLevelId,
                    ClassroomCompletionStatus.complete,
                    'Complete',
                    Icons.check_circle_rounded,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Show actual vs expected if incomplete
            if (classroom.completionStatus == ClassroomCompletionStatus.incomplete &&
                classroom.actualPacksDelivered != null)
              Builder(
                builder: (context) {
                  final packTotalAsync = ref.watch(packTotalProvider((
                    schoolId: schoolId,
                    yearLevelId: yearLevelId,
                    classroomId: classroom.id,
                  )));

                  return packTotalAsync.when(
                    data: (packTotal) {
                      final expected = packTotal?.total ?? 0;
                      final actual = classroom.actualPacksDelivered ?? 0;

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Partial Delivery',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$actual of $expected packs delivered',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                _showActualQuantityDialog(context, ref, classroom, yearLevelId);
                              },
                              child: const Text('Edit'),
                            ),
                          ],
                        ),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            if (classroom.completionStatus == ClassroomCompletionStatus.incomplete &&
                classroom.actualPacksDelivered != null)
              const SizedBox(height: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusOption(
    BuildContext context,
    WidgetRef ref,
    Classroom classroom,
    String yearLevelId,
    ClassroomCompletionStatus status,
    String label,
    IconData icon,
    Color color,
  ) {
    final isSelected = classroom.completionStatus == status;

    return GestureDetector(
      onTap: () async {
        // Get current staff's name
        final currentStaff = ref.read(currentStaffProvider).value;
        final currentUser = ref.read(currentUserProvider).value;

        // Use staff name if available, otherwise use user email
        String staffName = 'Unknown';
        if (currentStaff?.name != null) {
          staffName = currentStaff!.name;
        } else if (currentUser?.email != null) {
          staffName = currentUser!.email.split('@').first;
        }

        // If status is incomplete, show dialog to enter actual quantity
        if (status == ClassroomCompletionStatus.incomplete) {
          _showActualQuantityDialog(context, ref, classroom, yearLevelId);
        } else {
          // For complete or not attended, clear actual quantity
          final updatedClassroom = classroom.copyWith(
            completionStatus: status,
            actualPacksDelivered: null,
            lastUpdatedBy: staffName,
            lastUpdatedAt: DateTime.now(),
          );

          final success = await ref
              .read(schoolsNotifierProvider.notifier)
              .updateClassroom(schoolId, yearLevelId, updatedClassroom);

          if (context.mounted && success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Status updated to $label'),
                backgroundColor: color,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      },
      child: AspectRatio(
        aspectRatio: 1.0, // Makes it square
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey.shade600,
                size: 32,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActualQuantityDialog(
    BuildContext context,
    WidgetRef ref,
    Classroom classroom,
    String yearLevelId,
  ) {
    // Get the current pack total for reference
    final packTotalAsync = ref.read(packTotalProvider((
      schoolId: schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroom.id,
    )));

    final expectedTotal = packTotalAsync.value?.total ?? 0;

    final controller = TextEditingController(
      text: classroom.actualPacksDelivered?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Actual Packs Delivered'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Expected: $expectedTotal packs',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Actual Packs Delivered',
                  hintText: 'e.g., 23',
                  suffixText: 'packs',
                  helperText: 'Enter the actual number of packs delivered',
                ),
                keyboardType: TextInputType.number,
                autofocus: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter the actual quantity';
                  }
                  final number = int.tryParse(value.trim());
                  if (number == null) {
                    return 'Please enter a valid number';
                  }
                  if (number < 0) {
                    return 'Quantity cannot be negative';
                  }
                  return null;
                },
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
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext);

                // Get current staff's name
                final currentStaff = ref.read(currentStaffProvider).value;
                final currentUser = ref.read(currentUserProvider).value;

                // Use staff name if available, otherwise use user email
                String staffName = 'Unknown';
                if (currentStaff?.name != null) {
                  staffName = currentStaff!.name;
                } else if (currentUser?.email != null) {
                  staffName = currentUser!.email.split('@').first;
                }

                final actualQuantity = int.parse(controller.text.trim());
                final updatedClassroom = classroom.copyWith(
                  completionStatus: ClassroomCompletionStatus.incomplete,
                  actualPacksDelivered: actualQuantity,
                  lastUpdatedBy: staffName,
                  lastUpdatedAt: DateTime.now(),
                );

                final success = await ref
                    .read(schoolsNotifierProvider.notifier)
                    .updateClassroom(schoolId, yearLevelId, updatedClassroom);

                if (context.mounted && success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Status updated: $actualQuantity/$expectedTotal packs delivered',
                      ),
                      backgroundColor: Colors.orange,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showUpdatePackTotalDialog(
    BuildContext context,
    WidgetRef ref,
    int? currentTotal,
  ) {
    final controller = TextEditingController(
      text: currentTotal?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text(currentTotal == null ? 'Set Pack Total' : 'Update Pack Total'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Number of Packs',
              hintText: 'e.g., 25',
              suffixText: 'packs',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
            validator: (value) {
              if (value?.trim().isEmpty ?? true) {
                return 'Please enter a number';
              }
              final number = int.tryParse(value!);
              if (number == null || number < 0) {
                return 'Please enter a valid number';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              Navigator.pop(dialogContext);

              final packTotal = PackTotal(
                id: '',
                total: int.parse(controller.text.trim()),
                createdAt: DateTime.now(),
              );

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .updatePackTotal(
                      schoolId, yearLevelId, classroomId, packTotal);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Pack total updated successfully'
                        : 'Failed to update pack total'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );

                // Show notification that sign-off was cleared
                if (success) {
                  NotificationUtils.showSignOffClearedNotification(context);
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _showSetActualConsumableDialog(
      BuildContext context, WidgetRef ref, Consumable consumable) {
    final controller = TextEditingController(
      text: consumable.actualQuantityDelivered?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set Actual Quantity Delivered'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                consumable.itemName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Expected: ${consumable.quantity} ${consumable.unit}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Actual Quantity Delivered',
                  hintText: 'e.g., ${consumable.quantity - 2}',
                  suffixText: consumable.unit,
                  helperText: 'Leave empty to clear partial delivery',
                ),
                keyboardType: TextInputType.number,
                autofocus: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return null; // Allow empty to clear
                  }
                  final number = int.tryParse(value.trim());
                  if (number == null) {
                    return 'Please enter a valid number';
                  }
                  if (number < 0) {
                    return 'Quantity cannot be negative';
                  }
                  return null;
                },
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
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext);

                final valueText = controller.text.trim();
                final actualQuantity = valueText.isEmpty
                    ? null
                    : int.parse(valueText);

                final updatedConsumable = consumable.copyWith(
                  actualQuantityDelivered: actualQuantity,
                );

                final success = await ref
                    .read(schoolsNotifierProvider.notifier)
                    .updateClassroomConsumable(
                  schoolId,
                  yearLevelId,
                  classroomId,
                  updatedConsumable,
                );

                if (context.mounted && success) {
                  final message = actualQuantity == null
                      ? 'Partial delivery cleared for ${consumable.itemName}'
                      : 'Actual quantity set: $actualQuantity/${consumable.quantity} ${consumable.unit}';

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(message),
                      backgroundColor:
                          actualQuantity == null ? Colors.blue : Colors.orange,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddConsumableDialog(BuildContext context, WidgetRef ref) {
    final itemNameController = TextEditingController();
    final quantityController = TextEditingController();
    final unitController = TextEditingController(text: 'boxes');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Consumable'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: itemNameController,
                decoration: const InputDecoration(
                  labelText: 'Item Name',
                  hintText: 'e.g., Tissues, Paper',
                ),
                autofocus: true,
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Please enter an item name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: quantityController,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  hintText: 'e.g., 12',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value?.trim().isEmpty ?? true) {
                    return 'Please enter a quantity';
                  }
                  final number = int.tryParse(value!);
                  if (number == null || number < 1) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: unitController,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  hintText: 'e.g., boxes, reams, packs',
                ),
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Please enter a unit'
                    : null,
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
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              Navigator.pop(dialogContext);

              final consumable = Consumable(
                id: '',
                itemName: itemNameController.text.trim(),
                quantity: int.parse(quantityController.text.trim()),
                unit: unitController.text.trim(),
                createdAt: DateTime.now(),
              );

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .createClassroomConsumable(
                      schoolId, yearLevelId, classroomId, consumable);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Consumable added successfully'
                        : 'Failed to add consumable'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditConsumableDialog(
      BuildContext context, WidgetRef ref, Consumable consumable) {
    final itemNameController = TextEditingController(text: consumable.itemName);
    final quantityController =
        TextEditingController(text: consumable.quantity.toString());
    final unitController = TextEditingController(text: consumable.unit);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Consumable'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: itemNameController,
                decoration: const InputDecoration(
                  labelText: 'Item Name',
                  hintText: 'e.g., Tissues, Paper',
                ),
                autofocus: true,
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Please enter an item name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: quantityController,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  hintText: 'e.g., 12',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value?.trim().isEmpty ?? true) {
                    return 'Please enter a quantity';
                  }
                  final number = int.tryParse(value!);
                  if (number == null || number < 1) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: unitController,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  hintText: 'e.g., boxes, reams, packs',
                ),
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Please enter a unit'
                    : null,
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
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              Navigator.pop(dialogContext);

              final updatedConsumable = Consumable(
                id: consumable.id,
                itemName: itemNameController.text.trim(),
                quantity: int.parse(quantityController.text.trim()),
                unit: unitController.text.trim(),
                createdAt: consumable.createdAt,
              );

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .updateClassroomConsumable(
                      schoolId, yearLevelId, classroomId, updatedConsumable);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Consumable updated successfully'
                        : 'Failed to update consumable'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Shows a confirmation dialog before deleting a consumable item from the classroom.
  void _showDeleteConsumableConfirmation(
      BuildContext context, WidgetRef ref, Consumable consumable) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Consumable'),
        content: Text(
          'Are you sure you want to delete "${consumable.itemName}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .deleteClassroomConsumable(
                      schoolId, yearLevelId, classroomId, consumable.id);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Consumable deleted successfully'
                        : 'Failed to delete consumable'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Note management methods
  void _showAddNoteDialog(BuildContext context, WidgetRef ref) {
    final contentController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    // Get current staff's name for auto-assignment
    final currentStaff = ref.read(currentStaffProvider).value;
    final currentUser = ref.read(currentUserProvider).value;

    // Use staff name if available, otherwise use user email (without domain for brevity)
    String staffName = 'Unknown';
    if (currentStaff?.name != null) {
      staffName = currentStaff!.name;
    } else if (currentUser?.email != null) {
      // Extract name part from email (everything before @)
      staffName = currentUser!.email.split('@').first;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Note'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Enter your note here...',
                ),
                maxLines: 3,
                autofocus: true,
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Please enter a note'
                    : null,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      'Author: $staffName',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
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
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              Navigator.pop(dialogContext);

              final note = Note(
                id: '',
                content: contentController.text.trim(),
                author: staffName,
                createdAt: DateTime.now(),
              );

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .createClassroomNote(schoolId, yearLevelId, classroomId, note);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Note added successfully'
                        : 'Failed to add note'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditNoteDialog(BuildContext context, WidgetRef ref, Note note) {
    final contentController = TextEditingController(text: note.content);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Note'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Enter your note here...',
                ),
                maxLines: 3,
                autofocus: true,
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Please enter a note'
                    : null,
              ),
              if (note.author != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'Original author: ${note.author}',
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              Navigator.pop(dialogContext);

              final updatedNote = Note(
                id: note.id,
                content: contentController.text.trim(),
                author: note.author,  // Keep the original author
                createdAt: note.createdAt,
              );

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .updateClassroomNote(
                      schoolId, yearLevelId, classroomId, updatedNote);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Note updated successfully'
                        : 'Failed to update note'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteNoteConfirmation(
      BuildContext context, WidgetRef ref, Note note) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text(
          'Are you sure you want to delete this note? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .deleteClassroomNote(
                      schoolId, yearLevelId, classroomId, note.id);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Note deleted successfully'
                        : 'Failed to delete note'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Year Level Breakdown Dialog Methods

  void _showAddYearLevelBreakdownDialog(BuildContext context, WidgetRef ref) {
    // Standard year levels for student distribution in composite classes
    const standardYearLevels = [
      'Prep',
      'Year 1',
      'Year 2',
      'Year 3',
      'Year 4',
      'Year 5',
      'Year 6',
    ];

    final studentCountController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? selectedYearLevel;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Year Level'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Year Level',
                  border: OutlineInputBorder(),
                ),
                items: standardYearLevels.map((label) {
                  return DropdownMenuItem(
                    value: label,
                    child: Text(label),
                  );
                }).toList(),
                onChanged: (value) {
                  selectedYearLevel = value;
                },
                validator: (value) =>
                    value == null ? 'Please select a year level' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: studentCountController,
                decoration: const InputDecoration(
                  labelText: 'Student Count',
                  hintText: 'Enter number of students',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
                validator: (value) {
                  if (value?.trim().isEmpty ?? true) {
                    return 'Please enter student count';
                  }
                  final count = int.tryParse(value!);
                  if (count == null || count <= 0) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
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
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              if (selectedYearLevel == null) {
                return;
              }

              Navigator.pop(dialogContext);

              final breakdown = YearLevelBreakdown(
                id: const Uuid().v4(),
                yearLevelId: selectedYearLevel!,
                yearLevelLabel: selectedYearLevel!,
                studentCount: int.parse(studentCountController.text),
                createdAt: DateTime.now(),
              );

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .createYearLevelBreakdown(
                      schoolId, yearLevelId, classroomId, breakdown);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Year level added successfully'
                        : 'Failed to add year level'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditYearLevelBreakdownDialog(
      BuildContext context, WidgetRef ref, YearLevelBreakdown breakdown) {
    final studentCountController = TextEditingController(
      text: breakdown.studentCount.toString(),
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Year Level'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.school, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      breakdown.yearLevelLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: studentCountController,
                decoration: const InputDecoration(
                  labelText: 'Student Count',
                  hintText: 'Enter number of students',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
                validator: (value) {
                  if (value?.trim().isEmpty ?? true) {
                    return 'Please enter student count';
                  }
                  final count = int.tryParse(value!);
                  if (count == null || count <= 0) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
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
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              Navigator.pop(dialogContext);

              final updated = breakdown.copyWith(
                studentCount: int.parse(studentCountController.text),
              );

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .updateYearLevelBreakdown(
                      schoolId, yearLevelId, classroomId, updated);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Year level updated successfully'
                        : 'Failed to update year level'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteYearLevelBreakdown(
      BuildContext context, WidgetRef ref, YearLevelBreakdown breakdown) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Year Level'),
        content: Text(
          'Are you sure you want to remove ${breakdown.yearLevelLabel} (${breakdown.studentCount} students) from this classroom?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .deleteYearLevelBreakdown(
                      schoolId, yearLevelId, classroomId, breakdown.id);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Year level removed successfully'
                        : 'Failed to remove year level'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Widget to display a photo card with delete option
class _PhotoCard extends ConsumerWidget {
  const _PhotoCard({
    required this.photo,
    required this.onDelete,
  });

  final Photo photo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storageRepository = ref.watch(storageRepositoryProvider);
    final currentUser = ref.watch(currentUserProvider).value;
    final isAdmin = ref.watch(isAdminProvider);
    final isManager = ref.watch(isManagerProvider);

    // Determine if user can delete this photo
    // Admins and managers can delete any photo
    // Regular staff can only delete photos they uploaded
    final canDelete = isAdmin ||
                      isManager ||
                      (photo.uploadedBy != null && photo.uploadedBy == currentUser?.uid);

    return FutureBuilder<String>(
      future: storageRepository.getDownloadUrl(photo.storagePath).then(
            (result) => result.dataOrNull ?? '',
          ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey.shade400,
              ),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Card(
            child: Center(
              child: Icon(Icons.broken_image, color: Colors.grey.shade400),
            ),
          );
        }

        return GestureDetector(
          onTap: () => _showFullScreenImage(context, snapshot.data!),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Icon(Icons.broken_image,
                          color: Colors.grey.shade400),
                    );
                  },
                ),
                if (canDelete)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        icon: const Icon(Icons.delete, size: 18),
                        color: Colors.white,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: onDelete,
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

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  color: Colors.white,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget to display a pending photo card with upload indicator
class _PendingPhotoCard extends StatelessWidget {
  const _PendingPhotoCard({
    required this.pendingPhoto,
    required this.onRetry,
    required this.onCancel,
  });

  final _PendingPhoto pendingPhoto;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Local file thumbnail
          Image.file(
            pendingPhoto.localFile,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Icon(Icons.broken_image, color: Colors.grey.shade400),
              );
            },
          ),
          // Uploading overlay
          if (!pendingPhoto.hasError)
            Container(
              color: Colors.black38,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
          // Error overlay with retry
          if (pendingPhoto.hasError)
            Container(
              color: Colors.red.withValues(alpha: 0.8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 28),
                  const SizedBox(height: 4),
                  const Text(
                    'Failed',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: onRetry,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Retry',
                            style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onCancel,
                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Stateful widget that manages the photos section with optimistic uploads
class _PhotosSection extends ConsumerStatefulWidget {
  const _PhotosSection({
    required this.schoolId,
    required this.yearLevelId,
    required this.classroomId,
  });

  final String schoolId;
  final String yearLevelId;
  final String classroomId;

  @override
  ConsumerState<_PhotosSection> createState() => _PhotosSectionState();
}

class _PhotosSectionState extends ConsumerState<_PhotosSection> {
  final List<_PendingPhoto> _pendingPhotos = [];

  @override
  void initState() {
    super.initState();
    _loadUnuploadedPhotos();
  }

  /// Load any photos that were saved locally but not yet uploaded
  Future<void> _loadUnuploadedPhotos() async {
    final offlineStorage = ref.read(offlineStorageServiceProvider);
    final localPhotos = await offlineStorage.getPhotosForClassroom(
      widget.schoolId,
      widget.yearLevelId,
      widget.classroomId,
    );

    final unuploaded = localPhotos.where((p) => !p.isUploaded).toList();
    if (unuploaded.isNotEmpty && mounted) {
      setState(() {
        for (final localPhoto in unuploaded) {
          final file = File(localPhoto.localPath);
          if (file.existsSync()) {
            _pendingPhotos.add(_PendingPhoto(
              id: localPhoto.id,
              localFile: file,
            ));
          }
        }
      });
      // Retry uploading these photos
      for (final localPhoto in unuploaded) {
        final file = File(localPhoto.localPath);
        if (file.existsSync()) {
          _uploadPhotoInBackground(localPhoto.id, file);
        }
      }
    }
  }

  /// Save photo to persistent local storage before upload
  Future<File> _savePhotoLocally(File sourceFile, String photoId) async {
    final directory = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${directory.path}/classroom_photos');
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    final localPath = '${photosDir.path}/$photoId.jpg';
    return await sourceFile.copy(localPath);
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(classroomPhotosProvider((
      schoolId: widget.schoolId,
      yearLevelId: widget.yearLevelId,
      classroomId: widget.classroomId,
    )));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Photos Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              const Icon(Icons.photo_library_outlined, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Photos',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _handleAddPhoto(),
                icon: const Icon(Icons.add_a_photo, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Photos Grid/List
        photosAsync.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error loading photos',
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          ),
          data: (photos) {
            // Filter out pending photos that have already been uploaded
            // This prevents brief duplicate when Firestore updates before setState
            final uploadedIds = photos.map((p) => p.id).toSet();
            final activePendingPhotos = _pendingPhotos
                .where((p) => !uploadedIds.contains(p.id))
                .toList();

            final totalCount = activePendingPhotos.length + photos.length;

            if (totalCount == 0) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.photo_camera_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No photos yet',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Add photos to document classroom setup',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: totalCount,
              itemBuilder: (context, index) {
                // Show pending photos first
                if (index < activePendingPhotos.length) {
                  final pendingPhoto = activePendingPhotos[index];
                  return _PendingPhotoCard(
                    pendingPhoto: pendingPhoto,
                    onRetry: () => _retryUpload(pendingPhoto),
                    onCancel: () => _cancelUpload(pendingPhoto),
                  );
                }
                // Then show uploaded photos
                final photo = photos[index - activePendingPhotos.length];
                return _PhotoCard(
                  photo: photo,
                  onDelete: () => _handleDeletePhoto(photo),
                );
              },
            );
          },
        ),
      ],
    );
  }

  /// Handle adding a new photo with optimistic UI
  Future<void> _handleAddPhoto() async {
    final photoService = ref.read(photoServiceProvider);
    final offlineStorage = ref.read(offlineStorageServiceProvider);

    // Pick image
    final imageFile = await photoService.pickImage(context);
    if (imageFile == null) return;

    // Generate photo ID
    final photoId = const Uuid().v4();

    // Save photo locally FIRST to ensure it's not lost on poor connection
    final localFile = await _savePhotoLocally(imageFile, photoId);

    // Create LocalPhoto record and save to Hive
    final localPhoto = LocalPhoto(
      id: photoId,
      localPath: localFile.path,
      schoolId: widget.schoolId,
      yearLevelId: widget.yearLevelId,
      classroomId: widget.classroomId,
      createdAt: DateTime.now(),
      isUploaded: false,
      fileSize: await localFile.length(),
    );
    await offlineStorage.addLocalPhoto(localPhoto);

    // Add to pending photos immediately (optimistic update)
    setState(() {
      _pendingPhotos.add(_PendingPhoto(
        id: photoId,
        localFile: localFile,
      ));
    });

    // Upload in background
    await _uploadPhotoInBackground(photoId, localFile);
  }

  /// Upload photo to Firebase in the background
  Future<void> _uploadPhotoInBackground(String photoId, File imageFile) async {
    final photoService = ref.read(photoServiceProvider);
    final schoolsNotifier = ref.read(schoolsNotifierProvider.notifier);
    final currentUser = ref.read(currentUserProvider).value;
    final offlineStorage = ref.read(offlineStorageServiceProvider);

    final storagePath =
        'schools/${widget.schoolId}/yearLevels/${widget.yearLevelId}/classrooms/${widget.classroomId}/photos/$photoId.jpg';

    // Upload to Firebase Storage
    final uploadResult = await photoService.uploadPhoto(storagePath, imageFile);

    if (!mounted) return;

    if (!uploadResult.isSuccess) {
      // Mark as error in pending list
      setState(() {
        final index = _pendingPhotos.indexWhere((p) => p.id == photoId);
        if (index != -1) {
          _pendingPhotos[index] = _pendingPhotos[index].copyWith(
            hasError: true,
            errorMessage: uploadResult.errorOrNull,
          );
        }
      });
      return;
    }

    // Create Photo object and save to Firestore
    final photo = Photo(
      id: photoId,
      storagePath: storagePath,
      uploadedBy: currentUser?.uid,
      uploadedAt: DateTime.now(),
    );

    final result = await schoolsNotifier.addClassroomPhoto(
      widget.schoolId,
      widget.yearLevelId,
      widget.classroomId,
      photo,
    );

    if (!mounted) return;

    // Remove from pending (Firestore stream will show the uploaded photo)
    setState(() {
      _pendingPhotos.removeWhere((p) => p.id == photoId);
    });

    if (result) {
      // Mark as uploaded in local storage and clean up local file
      await offlineStorage.markPhotoAsUploaded(photoId, storagePath);
      await offlineStorage.deleteLocalPhoto(photoId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save photo'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Retry a failed upload
  void _retryUpload(_PendingPhoto pendingPhoto) {
    // Reset error state
    setState(() {
      final index = _pendingPhotos.indexWhere((p) => p.id == pendingPhoto.id);
      if (index != -1) {
        _pendingPhotos[index] = pendingPhoto.copyWith(
          hasError: false,
          errorMessage: null,
        );
      }
    });

    // Try uploading again
    _uploadPhotoInBackground(pendingPhoto.id, pendingPhoto.localFile);
  }

  /// Cancel/remove a pending photo
  Future<void> _cancelUpload(_PendingPhoto pendingPhoto) async {
    final offlineStorage = ref.read(offlineStorageServiceProvider);

    setState(() {
      _pendingPhotos.removeWhere((p) => p.id == pendingPhoto.id);
    });

    // Clean up local storage
    await offlineStorage.deleteLocalPhoto(pendingPhoto.id);
  }

  /// Handle deleting a photo
  Future<void> _handleDeletePhoto(Photo photo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text(
          'Are you sure you want to delete this photo? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await ref
        .read(schoolsNotifierProvider.notifier)
        .deleteClassroomPhoto(widget.schoolId, widget.yearLevelId, widget.classroomId, photo.id);

    if (success) {
      // Invalidate the photos provider to refresh the UI
      ref.invalidate(classroomPhotosProvider((
        schoolId: widget.schoolId,
        yearLevelId: widget.yearLevelId,
        classroomId: widget.classroomId,
      )));
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Photo deleted successfully' : 'Failed to delete photo',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }
}
