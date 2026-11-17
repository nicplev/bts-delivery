import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/schools_providers.dart';
import '../../providers/delivery_visit_provider.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/classroom_edit.dart';
import '../../services/offline/field_draft_store.dart';
import '../../widgets/field_draft_dialog.dart';
import '../../providers/auth_providers.dart';
import '../../models/school.dart';
import '../../models/offline/evidence_upload.dart';
import '../../models/offline/offline_media.dart';
import '../../models/delivery_visit.dart';
import '../../providers/offline_delivery_providers.dart';
import '../../providers/offline_media_providers.dart';
import '../../widgets/sync_status_detail_sheet.dart';
import '../../widgets/offline_media_view.dart';
import 'package:uuid/uuid.dart';
import '../../widgets/design/design.dart';

class ClassroomDetailScreen extends ConsumerWidget {
  const ClassroomDetailScreen({
    super.key,
    required this.schoolId,
    required this.yearLevelId,
    required this.classroomId,
    this.deliveryId,
  });

  final String schoolId;
  final String yearLevelId;
  final String classroomId;
  final String? deliveryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = ref.watch(activeDeliveryVisitProvider);
    if (deliveryId != null &&
        (visit?.deliveryId != deliveryId || visit?.schoolId != schoolId)) {
      return const Scaffold(
        body: Center(child: Text('Couldn’t open the records for this visit.')),
      );
    }
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
        toolbarHeight: MediaQuery.textScalerOf(context).scale(24) * 2 + 12,
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
            return Text(classroom.name,
                maxLines: 2, overflow: TextOverflow.ellipsis);
          },
          loading: () => const Text('Classroom'),
          error: (_, __) => const Text('Classroom'),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppTokens.gutter,
          12,
          AppTokens.gutter,
          MediaQuery.paddingOf(context).bottom + 16,
        ),
        children: [
          _buildPacksPanel(
            context,
            ref,
            classroomsAsync: classroomsAsync,
            packTotalAsync: packTotalAsync,
            canEditExpected: isAdmin,
          ),
          const SizedBox(height: AppTokens.sectionGap),

          // Year Level Breakdown Section (for composite classes)
          ref
              .watch(yearLevelBreakdownsProvider((
                schoolId: schoolId,
                yearLevelId: yearLevelId,
                classroomId: classroomId,
              )))
              .when(
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
                                Text(
                                  'No student distribution set. Add year level breakdowns for composite classes.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 12),
                                Center(
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _showAddYearLevelBreakdownDialog(
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                                color: AppTone.yellow
                                                    .inkFor(context),
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
                                        onPressed: () =>
                                            _showAddYearLevelBreakdownDialog(
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
                                    color: AppPalette.of(context).outline,
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
                                        color:
                                            AppPalette.of(context).surfaceQuiet,
                                      ),
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.all(8),
                                          child: Text(
                                            'Year Level',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.all(8),
                                          child: Text(
                                            'Students',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold),
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
                                              child: Text(
                                                  breakdown.yearLevelLabel),
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
                                              PopupMenuButton<bool>(
                                                icon: const Icon(
                                                    Icons.more_vert,
                                                    size: 20),
                                                onSelected: (edit) {
                                                  if (!context.mounted) return;
                                                  if (edit) {
                                                    _showEditYearLevelBreakdownDialog(
                                                      context,
                                                      ref,
                                                      breakdown,
                                                    );
                                                  } else {
                                                    _deleteYearLevelBreakdown(
                                                      context,
                                                      ref,
                                                      breakdown,
                                                    );
                                                  }
                                                },
                                                itemBuilder: (_) => [
                                                  const PopupMenuItem(
                                                    value: true,
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.edit,
                                                            size: 16),
                                                        SizedBox(width: 8),
                                                        Text('Edit'),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: false,
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.delete,
                                                            size: 16,
                                                            color:
                                                                AppPalette.of(
                                                                        context)
                                                                    .error),
                                                        const SizedBox(width: 8),
                                                        Text('Delete',
                                                            style: TextStyle(
                                                                color: AppPalette.of(context).error)),
                                                      ],
                                                    ),
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
                                    color: AppTone.blue.tintFor(context),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
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
                                          color: AppTone.blue.inkFor(context),
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
                        Row(
                          children: [
                            Icon(Icons.error,
                                color: AppPalette.of(context).error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Error loading student distribution',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppPalette.of(context).error,
                                ),
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

          AppSectionHeading(
            title: 'Consumables',
            trailing: TextButton.icon(
              onPressed: () => _showAddConsumableDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
          const SizedBox(height: 8),

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
                  style: TextStyle(color: AppPalette.of(context).error),
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
                            color: AppPalette.of(context).muted,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No consumables yet',
                            style: TextStyle(
                              color: AppPalette.of(context).muted,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add items like tissues, paper, etc.',
                            style: TextStyle(
                              color: AppPalette.of(context).muted,
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
                  final hasActualQuantity =
                      consumable.actualQuantityDelivered != null;
                  final isPartialDelivery = hasActualQuantity &&
                      consumable.actualQuantityDelivered != consumable.quantity;
                  final isFullyDelivered = hasActualQuantity &&
                      consumable.actualQuantityDelivered == consumable.quantity;

                  final (tone, icon, status) = isPartialDelivery
                      ? (
                          AppTone.yellow,
                          Icons.warning_amber_rounded,
                          'Quantity differs'
                        )
                      : isFullyDelivered
                          ? (
                              AppTone.green,
                              Icons.check_circle_outline,
                              'Delivered'
                            )
                          : (
                              AppTone.neutral,
                              Icons.inventory_2_outlined,
                              'Quantity unrecorded'
                            );

                  return AppPanel(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AppIconTile(icon: icon, tone: tone),
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
                                  Text(
                                    hasActualQuantity
                                        ? '${consumable.actualQuantityDelivered} / ${consumable.quantity} ${consumable.unit}'
                                        : '${consumable.quantity} ${consumable.unit}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: tone.inkFor(context),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            // Menu button
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showEditConsumableDialog(
                                      context, ref, consumable);
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
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete,
                                          size: 20,
                                          color: AppPalette.of(context).error),
                                      const SizedBox(width: 12),
                                      Text('Delete',
                                          style: TextStyle(
                                              color: AppPalette.of(context)
                                                  .error)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        AppStatusPill(label: status, tone: tone),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
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
                                      content: Text(
                                          '${consumable.itemName} marked as complete'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.check_circle_outline,
                                  size: 18),
                              label: const Text('Complete'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTone.green.inkFor(context),
                                side: BorderSide(
                                    color: AppPalette.of(context).outline),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                _showSetActualConsumableDialog(
                                    context, ref, consumable);
                              },
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Set Qty'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTone.yellow.inkFor(context),
                                side: BorderSide(
                                    color: AppPalette.of(context).outline),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 24),

          // Photos
          _PhotosSection(
            schoolId: schoolId,
            yearLevelId: yearLevelId,
            classroomId: classroomId,
            deliveryId: deliveryId,
          ),

          const SizedBox(height: 24),

          AppSectionHeading(
            title: 'Notes',
            trailing: TextButton.icon(
              onPressed: () => _showNoteDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
          const SizedBox(height: 8),

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
                      style: TextStyle(
                          color: AppPalette.of(context).error,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Error: $error',
                      style: TextStyle(
                          color: AppPalette.of(context).error, fontSize: 12),
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
                            color: AppPalette.of(context).muted,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No notes yet',
                            style: TextStyle(
                              color: AppPalette.of(context).muted,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add notes about this classroom',
                            style: TextStyle(
                              color: AppPalette.of(context).muted,
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
                                    _showNoteDialog(context, ref, note: note);
                                  } else if (value == 'delete') {
                                    _showDeleteNoteConfirmation(
                                        context, ref, note);
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
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete,
                                            size: 20,
                                            color:
                                                AppPalette.of(context).error),
                                        const SizedBox(width: 12),
                                        Text('Delete',
                                            style: TextStyle(
                                                color: AppPalette.of(context)
                                                    .error)),
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
                                Icon(Icons.person,
                                    size: 14,
                                    color: AppPalette.of(context).muted),
                                const SizedBox(width: 4),
                                Text(
                                  note.author!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppPalette.of(context).muted,
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Icon(Icons.access_time,
                                  size: 14,
                                  color: AppPalette.of(context).muted),
                              const SizedBox(width: 4),
                              Text(
                                _formatDate(note.createdAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppPalette.of(context).muted,
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

  Widget _buildPacksPanel(
    BuildContext context,
    WidgetRef ref, {
    required AsyncValue<List<Classroom>> classroomsAsync,
    required AsyncValue<PackTotal?> packTotalAsync,
    required bool canEditExpected,
  }) {
    final typography = Theme.of(context).textTheme;
    final colors = AppPalette.of(context);
    final classroom = classroomsAsync.asData?.value
        .where((room) => room.id == classroomId)
        .firstOrNull;
    final actual = classroom?.actualPacksDelivered;
    final expected = packTotalAsync.asData?.value;

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeading(
            title: 'Packs',
            trailing: canEditExpected
                ? IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Update Pack Total',
                    onPressed: () => _showUpdatePackTotalDialog(
                      context,
                      ref,
                      expected?.total,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          Text('Expected packs', style: typography.bodySmall),
          packTotalAsync.when(
            data: (total) => Text(
              total == null ? 'Not set' : '${total.total}',
              style: typography.titleLarge,
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => Text('Expected packs unavailable',
                style: TextStyle(color: colors.error)),
          ),
          if (expected != null)
            Text('Updated ${_formatDate(expected.createdAt)}',
                style: typography.bodySmall),
          if (deliveryId != null) ...[
            const Divider(height: 24),
            Text('Recorded packs', style: typography.bodySmall),
            Text(
              classroom == null
                  ? (classroomsAsync.isLoading ? 'Loading…' : 'Unavailable')
                  : actual?.toString() ?? 'Unrecorded',
              style: typography.titleLarge,
            ),
            if (classroom != null) ...[
              const SizedBox(height: 12),
              Text('Pack delivery status', style: typography.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildStatusOption(
                    context,
                    ref,
                    classroom,
                    ClassroomCompletionStatus.notAttended,
                    'Not Attended',
                    Icons.remove_circle_outline,
                    AppTone.neutral,
                  ),
                  _buildStatusOption(
                    context,
                    ref,
                    classroom,
                    ClassroomCompletionStatus.incomplete,
                    'Incomplete',
                    Icons.warning_amber_rounded,
                    AppTone.yellow,
                  ),
                  _buildStatusOption(
                    context,
                    ref,
                    classroom,
                    ClassroomCompletionStatus.complete,
                    'Complete',
                    Icons.check_circle_outline,
                    AppTone.green,
                  ),
                ],
              ),
              if (classroom.completionStatus ==
                      ClassroomCompletionStatus.incomplete &&
                  actual != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => _showActualQuantityDialog(
                      context,
                      ref,
                      classroom,
                      yearLevelId,
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit recorded quantity'),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStatusOption(
    BuildContext context,
    WidgetRef ref,
    Classroom classroom,
    ClassroomCompletionStatus status,
    String label,
    IconData icon,
    AppTone tone,
  ) {
    final selected = classroom.completionStatus == status;
    final colors = AppPalette.of(context);

    return Semantics(
      selected: selected,
      child: OutlinedButton.icon(
        onPressed: () {
          if (status == ClassroomCompletionStatus.incomplete) {
            _showActualQuantityDialog(context, ref, classroom, yearLevelId);
          } else {
            _saveClassroomStatus(context, ref, status);
          }
        },
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: selected ? tone.inkFor(context) : colors.ink,
          backgroundColor: selected ? tone.tintFor(context) : colors.surface,
          side: BorderSide(
              color: selected ? tone.inkFor(context) : colors.outline),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }

  FieldDraftTarget _draftTarget(String form, {String? entityId}) {
    return FieldDraftTarget(
      schoolId: schoolId,
      deliveryId: deliveryId,
      yearLevelId: yearLevelId,
      classroomId: classroomId,
      form: form,
      entityId: entityId,
    );
  }

  static String? _validateCount(String value, {bool optional = false}) {
    if (value.trim().isEmpty) {
      return optional ? null : 'Enter a quantity.';
    }
    final count = int.tryParse(value.trim());
    if (count == null || count < 0 || count > 1000000) {
      return 'Enter a whole number from 0 to 1,000,000.';
    }
    return null;
  }

  void _showActualQuantityDialog(
    BuildContext context,
    WidgetRef ref,
    Classroom classroom,
    String yearLevelId,
  ) {
    final expected = ref
        .read(packTotalProvider((
          schoolId: schoolId,
          yearLevelId: yearLevelId,
          classroomId: classroom.id,
        )))
        .valueOrNull
        ?.total;
    final schools = ref.read(schoolsNotifierProvider.notifier);
    showFieldDraftDialog(
      context: context,
      ref: ref,
      target: _draftTarget('actualPacks'),
      title: 'Actual packs delivered',
      savedLabel: 'Classroom status',
      description: expected == null ? null : 'Expected $expected packs',
      inputs: [
        FieldDraftInput(
          id: 'quantity',
          label: 'Packs delivered',
          initialText: classroom.actualPacksDelivered?.toString() ?? '',
          keyboardType: TextInputType.number,
          validator: _validateCount,
        ),
      ],
      onSave: (draft) => schools.updateClassroomStatus(
        schoolId,
        yearLevelId,
        classroomId,
        status: ClassroomCompletionStatus.incomplete,
        actualPacksDelivered: int.parse(draft.values['quantity']!.trim()),
        editId: draft.revision,
      ),
    );
  }

  Future<void> _saveClassroomStatus(
    BuildContext context,
    WidgetRef ref,
    ClassroomCompletionStatus status,
  ) async {
    final result =
        await ref.read(schoolsNotifierProvider.notifier).updateClassroomStatus(
              schoolId,
              yearLevelId,
              classroomId,
              status: status,
              actualPacksDelivered: null,
            );
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.when(
          success: (progress) =>
              fieldEditFeedback('Classroom status', progress),
          failure: (message, _) => message,
        )),
      ),
    );
  }

  void _showUpdatePackTotalDialog(
    BuildContext context,
    WidgetRef ref,
    int? currentTotal,
  ) {
    final schools = ref.read(schoolsNotifierProvider.notifier);
    showFieldDraftDialog(
      context: context,
      ref: ref,
      target: _draftTarget('packTotal'),
      title: currentTotal == null ? 'Set pack total' : 'Update pack total',
      savedLabel: 'Pack total',
      inputs: [
        FieldDraftInput(
          id: 'quantity',
          label: 'Number of packs',
          initialText: currentTotal?.toString() ?? '',
          keyboardType: TextInputType.number,
          validator: _validateCount,
        ),
      ],
      onSave: (draft) => schools.saveClassroomPackTotal(
        schoolId,
        yearLevelId,
        classroomId,
        int.parse(draft.values['quantity']!.trim()),
        editId: draft.revision,
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
    BuildContext context,
    WidgetRef ref,
    Consumable consumable,
  ) {
    final schools = ref.read(schoolsNotifierProvider.notifier);
    showFieldDraftDialog(
      context: context,
      ref: ref,
      target: _draftTarget('actualConsumable', entityId: consumable.id),
      title: 'Actual quantity delivered',
      savedLabel: 'Quantity',
      description: '${consumable.itemName} · Expected ${consumable.quantity} '
          '${consumable.unit}\n\nLeave the quantity blank to clear it.',
      inputs: [
        FieldDraftInput(
          id: 'quantity',
          label: 'Delivered quantity',
          initialText: consumable.actualQuantityDelivered?.toString() ?? '',
          keyboardType: TextInputType.number,
          validator: (value) => _validateCount(value, optional: true),
        ),
      ],
      onSave: (draft) => schools.saveClassroomActualQuantity(
        schoolId,
        yearLevelId,
        classroomId,
        consumable.id,
        int.tryParse(draft.values['quantity']!.trim()),
        editId: draft.revision,
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
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showNoteDialog(BuildContext context, WidgetRef ref, {Note? note}) {
    final schools = ref.read(schoolsNotifierProvider.notifier);
    final staffName = ref.read(currentStaffProvider).valueOrNull?.name;
    showFieldDraftDialog(
      context: context,
      ref: ref,
      target: _draftTarget('note', entityId: note?.id),
      title: note == null ? 'Add note' : 'Edit note',
      savedLabel: 'Note',
      inputs: [
        FieldDraftInput(
          id: 'content',
          label: 'Note',
          initialText: note?.content ?? '',
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          validator: (value) {
            final content = value.trim();
            if (content.isEmpty) return 'Enter a note.';
            if (content.length > 20000) {
              return 'Use 20,000 characters or fewer.';
            }
            return null;
          },
        ),
      ],
      onSave: (draft) {
        final content = draft.values['content']!.trim();
        return schools.saveClassroomNote(
          schoolId,
          yearLevelId,
          classroomId,
          note?.copyWith(content: content) ??
              Note(
                id: '',
                content: content,
                author: staffName,
                createdAt: DateTime.now(),
              ),
          editId: draft.revision,
        );
      },
    );
  }

  Future<void> _showDeleteNoteConfirmation(
    BuildContext context,
    WidgetRef ref,
    Note note,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This removes the note from this classroom.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref
        .read(schoolsNotifierProvider.notifier)
        .saveClassroomNoteDeletion(schoolId, yearLevelId, classroomId, note);
    if (!context.mounted) return;
    final message = result.when(
      success: (status) => switch (status) {
        ClassroomEditStatus.saved => 'Note deleted',
        ClassroomEditStatus.pending =>
          'Note removal saved on this device · Sync pending',
        ClassroomEditStatus.unconfirmed =>
          'Deletion request saved on this device. Review it when connected.',
      },
      failure: (message, _) => message,
    );
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
                  color: AppPalette.of(context).surfaceQuiet,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.school, color: AppPalette.of(context).muted),
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
              if (!context.mounted ||
                  !(formKey.currentState?.validate() ?? false)) {
                return;
              }

              final updated = breakdown.copyWith(
                studentCount: int.parse(studentCountController.text),
              );

              Navigator.pop(dialogContext);
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
              if (!context.mounted) return;
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
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
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
    final owner = ref.watch(offlineMediaOwnerProvider(schoolId));
    final canRemove = owner != null &&
        (ref.watch(isAdminProvider) ||
            ref.watch(isManagerProvider) ||
            photo.uploadedBy == owner);
    final source = asset;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (owner != null && source != null)
            Semantics(
              button: true,
              label: 'Open classroom photo',
              child: InkWell(
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
              ),
            )
          else
            const Center(child: Icon(Icons.broken_image_outlined)),
          if (source?.visit != null)
            Positioned(
              top: 4,
              left: 4,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                shape: const CircleBorder(),
                child: OfflineMediaDownloadButton(asset: source!),
              ),
            ),
          if (canRemove)
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  tooltip: 'Remove from classroom',
                  onPressed: onRemove,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotosSection extends ConsumerStatefulWidget {
  const _PhotosSection({
    required this.schoolId,
    required this.yearLevelId,
    required this.classroomId,
    this.deliveryId,
  });

  final String schoolId;
  final String yearLevelId;
  final String classroomId;
  final String? deliveryId;

  @override
  ConsumerState<_PhotosSection> createState() => _PhotosSectionState();
}

class _PhotosSectionState extends ConsumerState<_PhotosSection> {
  bool _saving = false;

  ({
    String schoolId,
    String yearLevelId,
    String classroomId,
    String? deliveryId
  }) get _classroom => (
        schoolId: widget.schoolId,
        yearLevelId: widget.yearLevelId,
        classroomId: widget.classroomId,
        deliveryId: widget.deliveryId,
      );

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(classroomPhotosProvider(_classroom));
    final mediaBucket = photos.valueOrNull?.isNotEmpty == true
        ? ref.watch(offlineMediaBucketProvider)
        : null;
    final uploads = ref.watch(evidenceUploadsProvider);
    final status = uploads.valueOrNull;
    final worker = ref.watch(evidenceUploadWorkerProvider).valueOrNull;
    final pending = status?.items
            .where((item) =>
                item.kind == EvidenceKind.photo &&
                item.schoolId == widget.schoolId &&
                item.yearLevelId == widget.yearLevelId &&
                item.classroomId == widget.classroomId &&
                item.deliveryId == widget.deliveryId)
            .toList() ??
        [];
    final pendingIds = pending.map((item) => item.id).toSet();
    final remote = photos.valueOrNull
            ?.where((item) => !pendingIds.contains(item.id))
            .toList() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Photos', style: Theme.of(context).textTheme.titleLarge),
            FilledButton.icon(
              onPressed: _saving || worker == null ? null : _handleAddPhoto,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(_saving ? 'Saving…' : 'Add photo'),
            ),
          ],
        ),
        if (uploads.hasError || status?.localError == true)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Saved photos need attention'),
            trailing: TextButton(
              onPressed: () => SyncStatusDetailSheet.show(context),
              child: const Text('Review'),
            ),
          ),
        if (worker != null)
          for (final item in pending)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  worker.localFile(item),
                  cacheWidth: 144,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                      width: 52, child: Icon(Icons.broken_image)),
                ),
              ),
              title: const Text('Classroom photo'),
              subtitle: Text(
                  item.id == status?.activeId ? 'Syncing' : item.statusText),
              trailing: item.id == status?.activeId
                  ? null
                  : EvidenceUploadActions(item: item),
            ),
        if (photos.isLoading && remote.isEmpty && pending.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        if (photos.hasError)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Could not load synced photos'),
            trailing: TextButton(
              onPressed: () =>
                  ref.invalidate(classroomPhotosProvider(_classroom)),
              child: const Text('Retry'),
            ),
          ),
        if (photos.hasValue && remote.isEmpty && pending.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No photos yet'),
          ),
        if (remote.isNotEmpty && pending.isNotEmpty)
          Text('Synced photos', style: Theme.of(context).textTheme.titleSmall),
        if (remote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: remote.length,
              itemBuilder: (context, index) {
                final photo = remote[index];
                final deliveryId = widget.deliveryId;
                final visit = deliveryId == null
                    ? null
                    : DeliveryVisit(
                        deliveryId: deliveryId, schoolId: widget.schoolId);
                final asset = OfflineMediaAsset.classroomPhoto(
                  bucket: mediaBucket!,
                  schoolId: widget.schoolId,
                  yearLevelId: widget.yearLevelId,
                  classroomId: widget.classroomId,
                  photoId: photo.id,
                  reference: photo.storagePath,
                  visit: visit,
                );
                return _PhotoCard(
                  key: ValueKey(photo.id),
                  photo: photo,
                  asset: asset,
                  schoolId: widget.schoolId,
                  onRemove: () => _handleRemovePhoto(photo),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _handleAddPhoto() async {
    final worker = ref.read(evidenceUploadWorkerProvider).valueOrNull;
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (worker == null || uid == null) return;

    final photoService = ref.read(photoServiceProvider);
    final classroom = _classroom;
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo saved on this device')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the photo. Try again.')),
        );
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
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final success = await ref
        .read(schoolsNotifierProvider.notifier)
        .deleteClassroomPhoto(
            widget.schoolId, widget.yearLevelId, widget.classroomId, photo.id,
            deliveryId: widget.deliveryId);

    if (success && mounted) {
      ref.invalidate(classroomPhotosProvider(_classroom));
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Photo removed from classroom'
                : 'Could not remove the photo from the classroom',
          ),
        ),
      );
    }
  }
}
