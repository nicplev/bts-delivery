import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/schools_providers.dart';
import '../providers/repository_providers.dart';
import '../providers/checklist_providers.dart';
import '../services/image_service.dart';
import '../services/date_utils.dart';
import '../services/excel_export_service.dart';
import '../models/school.dart';
import '../app/theme/brand_colors.dart';

class SignOffTab extends ConsumerStatefulWidget {
  const SignOffTab({super.key, required this.schoolId});

  final String schoolId;

  @override
  ConsumerState<SignOffTab> createState() => _SignOffTabState();
}

class _SignOffTabState extends ConsumerState<SignOffTab> {
  final _nameController = TextEditingController();
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _noteKeys =
      {}; // Map of yearLevelId_classroomId -> GlobalKey
  bool _isUploading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _signatureController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToNote(String yearLevelId, String classroomId) {
    final key = '${yearLevelId}_$classroomId';
    final globalKey = _noteKeys[key];

    if (globalKey?.currentContext != null) {
      Scrollable.ensureVisible(
        globalKey!.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.1, // Position near the top of the viewport
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final signOffAsync = ref.watch(signOffProvider(widget.schoolId));

    return LayoutBuilder(
      builder: (context, constraints) {
        return SafeArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildOverviewCard(),
                const SizedBox(height: 16),
                _buildNotesCard(),
                const SizedBox(height: 16),
                _buildSignOffCard(signOffAsync),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverviewCard() {
    final schoolTotalAsync = ref.watch(schoolTotalProvider(widget.schoolId));
    final schoolConsumablesTotalsAsync =
        ref.watch(schoolConsumablesTotalsProvider(widget.schoolId));

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.summarize, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Delivery Overview',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              // Use IconButton instead of OutlinedButton
              IconButton(
                onPressed: _refreshTotals,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 12),
          // School-wide total summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Packs Delivered',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                schoolTotalAsync.when(
                  data: (total) => Text(
                    '$total',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                  ),
                  loading: () => const CircularProgressIndicator(),
                  error: (error, _) => const Text(
                    '?',
                    style: TextStyle(fontSize: 18, color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Consumables Totals Summary
          schoolConsumablesTotalsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (totals) {
              if (totals.isEmpty) {
                return const SizedBox.shrink();
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Consumables Totals',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: BrandColors.kakaBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: BrandColors.kakaBlue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: totals.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              Text(
                                '${entry.value.quantity} ${entry.value.unit}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
          _buildDeliveryBreakdown(),
        ],
      ),
    );
  }

  Widget _buildDeliveryBreakdown() {
    final yearLevelsAsync = ref.watch(yearLevelsProvider(widget.schoolId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Classroom Totals',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Color Legend
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegendItem(Icons.check_circle, Colors.green, 'Complete'),
              _buildLegendItem(Icons.warning, Colors.orange, 'Incomplete'),
              _buildLegendItem(Icons.cancel, Colors.red, 'Not Attended'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        yearLevelsAsync.when(
          data: (yearLevels) => yearLevels.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  ),
                  child: const Center(
                    child: Text('No year levels found'),
                  ),
                )
              : Column(
                  children: yearLevels
                      .map((yearLevel) => _buildYearLevelCard(yearLevel))
                      .toList(),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Text('Error loading year levels: $error'),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildYearLevelCard(YearLevel yearLevel) {
    final classroomsAsync = ref.watch(classroomsProvider(
        (schoolId: widget.schoolId, yearLevelId: yearLevel.id)));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            yearLevel.label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          classroomsAsync.when(
            data: (classrooms) => classrooms.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'No classrooms found',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  )
                : Column(
                    children: classrooms
                        .map((classroom) =>
                            _buildClassroomRow(classroom, yearLevel.id))
                        .toList(),
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Error loading classrooms: $error',
                style: const TextStyle(fontSize: 14, color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassroomRow(Classroom classroom, String yearLevelId) {
    final packTotalAsync = ref.watch(packTotalProvider((
      schoolId: widget.schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroom.id
    )));

    final consumablesAsync = ref.watch(classroomConsumablesProvider((
      schoolId: widget.schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroom.id,
    )));

    final notesAsync = ref.watch(classroomNotesProvider((
      schoolId: widget.schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroom.id,
    )));

    final breakdownsAsync = ref.watch(yearLevelBreakdownsProvider((
      schoolId: widget.schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroom.id,
    )));

    // Get color based on completion status - must check consumables too
    Color getStatusColor(List<Consumable> consumables) {
      // If not attended, return red immediately
      if (classroom.completionStatus == ClassroomCompletionStatus.notAttended) {
        return Colors.red;
      }

      // If classroom is marked complete, verify all consumables are actually complete
      if (classroom.completionStatus == ClassroomCompletionStatus.complete) {
        // Check if any consumables are incomplete (partial delivery)
        final hasPartialConsumables = consumables.any((consumable) {
          return consumable.actualQuantityDelivered != null &&
              consumable.actualQuantityDelivered != consumable.quantity;
        });

        // Check if any consumables are not attended (no actual quantity set)
        final hasUnattendedConsumables = consumables.any((consumable) {
          return consumable.actualQuantityDelivered == null;
        });

        // If any consumables are incomplete or not attended, show orange
        if (hasPartialConsumables || hasUnattendedConsumables) {
          return Colors.orange;
        }

        // All consumables are complete, show green
        return Colors.green;
      }

      // Otherwise use the classroom's status
      switch (classroom.completionStatus) {
        case ClassroomCompletionStatus.complete:
          return Colors.green;
        case ClassroomCompletionStatus.incomplete:
          return Colors.orange;
        case ClassroomCompletionStatus.notAttended:
          return Colors.red;
      }
    }

    IconData getStatusIcon(List<Consumable> consumables) {
      // If not attended, return cancel icon immediately
      if (classroom.completionStatus == ClassroomCompletionStatus.notAttended) {
        return Icons.cancel;
      }

      // If classroom is marked complete, verify all consumables are actually complete
      if (classroom.completionStatus == ClassroomCompletionStatus.complete) {
        // Check if any consumables are incomplete (partial delivery)
        final hasPartialConsumables = consumables.any((consumable) {
          return consumable.actualQuantityDelivered != null &&
              consumable.actualQuantityDelivered != consumable.quantity;
        });

        // Check if any consumables are not attended (no actual quantity set)
        final hasUnattendedConsumables = consumables.any((consumable) {
          return consumable.actualQuantityDelivered == null;
        });

        // If any consumables are incomplete or not attended, show warning
        if (hasPartialConsumables || hasUnattendedConsumables) {
          return Icons.warning;
        }

        // All consumables are complete, show check circle
        return Icons.check_circle;
      }

      // Otherwise use the classroom's status
      switch (classroom.completionStatus) {
        case ClassroomCompletionStatus.complete:
          return Icons.check_circle;
        case ClassroomCompletionStatus.incomplete:
          return Icons.warning;
        case ClassroomCompletionStatus.notAttended:
          return Icons.cancel;
      }
    }

    return consumablesAsync.when(
      data: (consumables) {
        final statusColor = getStatusColor(consumables);
        final statusIcon = getStatusIcon(consumables);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: statusColor,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Classroom name and pack total row
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          statusIcon,
                          color: statusColor,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          classroom.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        // Composite class indicator badge only
                        breakdownsAsync.when(
                          data: (breakdowns) {
                            if (breakdowns.length <= 1) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Composite',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.teal.shade700,
                                  ),
                                ),
                              ),
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  packTotalAsync.when(
                    data: (packTotal) {
                      final expectedTotal = packTotal?.total ?? 0;
                      final isIncomplete = classroom.completionStatus ==
                          ClassroomCompletionStatus.incomplete;
                      final hasActualQuantity =
                          classroom.actualPacksDelivered != null;

                      // Determine display color based on status
                      final displayColor = isIncomplete
                          ? Colors.orange
                          : Theme.of(context).primaryColor;
                      final backgroundColor = isIncomplete
                          ? Colors.orange.withValues(alpha: 0.15)
                          : Theme.of(context)
                              .primaryColor
                              .withValues(alpha: 0.15);

                      String displayText;
                      if (isIncomplete && hasActualQuantity) {
                        // Show actual/expected for incomplete deliveries
                        displayText =
                            '${classroom.actualPacksDelivered}/$expectedTotal packs';
                      } else {
                        // Show total for complete or not attended
                        displayText = '$expectedTotal packs';
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inventory_2,
                              size: 14,
                              color: displayColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              displayText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: displayColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    loading: () => const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    error: (error, _) => const Text(
                      '?',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
              ),

              // Second row: year level distribution + note badge
              breakdownsAsync.when(
                data: (breakdowns) {
                  return notesAsync.when(
                    data: (notes) {
                      final isComposite = breakdowns.length > 1;
                      final hasNotes = notes.isNotEmpty;

                      if (!isComposite && !hasNotes) {
                        return const SizedBox.shrink();
                      }

                      // Build distribution text if composite
                      String? distributionText;
                      if (isComposite) {
                        distributionText = breakdowns.map((b) {
                          final label = b.yearLevelLabel.replaceAll('Year ', 'Y');
                          return '$label: ${b.studentCount}';
                        }).join('  •  ');
                      }

                      return Padding(
                        padding: const EdgeInsets.only(top: 4, left: 24),
                        child: Row(
                          children: [
                            if (distributionText != null)
                              Text(
                                distributionText,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.teal.shade600,
                                ),
                              ),
                            if (hasNotes) ...[
                              if (isComposite) const SizedBox(width: 12),
                              InkWell(
                                onTap: () => _scrollToNote(yearLevelId, classroom.id),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.pink.shade400,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'note',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              // Consumables section
              consumablesAsync.when(
                data: (consumables) {
                  if (consumables.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      ...consumables.map((consumable) {
                        final hasActualQuantity =
                            consumable.actualQuantityDelivered != null;
                        final isPartialDelivery = hasActualQuantity &&
                            consumable.actualQuantityDelivered !=
                                consumable.quantity;

                        // Determine icon and color based on delivery status
                        final icon = _getConsumableIcon(consumable.itemName);
                        final iconColor = isPartialDelivery
                            ? Colors.orange
                            : BrandColors.kakaBlue;

                        // Format quantity text
                        String quantityText;
                        Color quantityColor;
                        if (hasActualQuantity) {
                          quantityText =
                              '${consumable.actualQuantityDelivered}/${consumable.quantity} ${consumable.unit}';
                          quantityColor =
                              isPartialDelivery ? Colors.orange : Colors.green;
                        } else {
                          quantityText =
                              '${consumable.quantity} ${consumable.unit}';
                          quantityColor = BrandColors.kakaBlue;
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                size: 14,
                                color: iconColor,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  consumable.itemName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                              Text(
                                quantityText,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: quantityColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (error, _) => const SizedBox.shrink(),
              ),

              // Last updated info
              if (classroom.lastUpdatedBy != null &&
                  classroom.lastUpdatedAt != null) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.update,
                      size: 12,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Last updated by ${classroom.lastUpdatedBy} on ${DateTimeUtils.formatDateTime(classroom.lastUpdatedAt!)}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
      loading: () => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300, width: 2),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300, width: 2),
        ),
        child: const Text('Error loading classroom'),
      ),
    );
  }

  Widget _buildNotesCard() {
    final yearLevelsAsync = ref.watch(yearLevelsProvider(widget.schoolId));

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.note_outlined, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              Text(
                'Classroom Notes',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          yearLevelsAsync.when(
            data: (yearLevels) {
              if (yearLevels.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text('No year levels found'),
                  ),
                );
              }

              return Column(
                children: yearLevels.map((yearLevel) {
                  return _buildYearLevelNotes(yearLevel);
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error loading notes: $error'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearLevelNotes(YearLevel yearLevel) {
    final classroomsAsync = ref.watch(classroomsProvider((
      schoolId: widget.schoolId,
      yearLevelId: yearLevel.id,
    )));

    return classroomsAsync.when(
      data: (classrooms) {
        if (classrooms.isEmpty) return const SizedBox.shrink();

        // Build widgets for classrooms with notes
        final classroomNoteWidgets = <Widget>[];

        for (final classroom in classrooms) {
          final notesAsync = ref.watch(classroomNotesProvider((
            schoolId: widget.schoolId,
            yearLevelId: yearLevel.id,
            classroomId: classroom.id,
          )));

          notesAsync.whenData((notes) {
            if (notes.isNotEmpty) {
              classroomNoteWidgets.add(_buildClassroomNoteSection(
                yearLevel.label,
                classroom,
                yearLevel.id,
                classroom.id,
                notes,
              ));
            }
          });
        }

        return Column(children: classroomNoteWidgets);
      },
      loading: () => const SizedBox.shrink(),
      error: (error, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildClassroomNoteSection(
    String yearLevelLabel,
    Classroom classroom,
    String yearLevelId,
    String classroomId,
    List<Note> notes,
  ) {
    if (notes.isEmpty) return const SizedBox.shrink();

    // Create or retrieve the GlobalKey for this classroom
    final key = '${yearLevelId}_$classroomId';
    _noteKeys.putIfAbsent(key, () => GlobalKey());

    return Container(
      key: _noteKeys[key],
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BrandColors.kakaYellow.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: BrandColors.kakaYellow.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.class_,
                    size: 16,
                    color: BrandColors.kakaYellow,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$yearLevelLabel - ${classroom.name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: BrandColors.kakaYellow.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${notes.length} ${notes.length == 1 ? 'note' : 'notes'}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (classroom.lastUpdatedBy != null &&
                  classroom.lastUpdatedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Last updated by ${classroom.lastUpdatedBy} on ${DateTimeUtils.formatDateTime(classroom.lastUpdatedAt!)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ...notes.map((note) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.note,
                        size: 12,
                        color: BrandColors.kakaYellow,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.content,
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (note.author != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'by ${note.author}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSignOffCard(AsyncValue<SignOff?> signOffAsync) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: signOffAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (error, _) => Center(
          child: Text('Error loading sign-off: $error'),
        ),
        data: (signOff) {
          if (signOff != null) {
            return _buildCompletedSignOff(signOff);
          } else {
            return _buildSignOffForm();
          }
        },
      ),
    );
  }

  Widget _buildSignOffForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.edit, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sign-off',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Enter your full name',
            prefixIcon: Icon(Icons.person),
          ),
          enabled: !_isUploading,
        ),
        const SizedBox(height: 16),
        Text(
          'Signature',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 2.0,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Signature(
                    controller: _signatureController,
                    backgroundColor: Colors.white,
                  ),
                  if (_isUploading)
                    Container(
                      color: Colors.white.withOpacity(0.7),
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Flexible(
              child: TextButton.icon(
                onPressed:
                    _isUploading ? null : () => _signatureController.clear(),
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: FilledButton.icon(
                onPressed: _isUploading ? null : _handleSignOff,
                icon: _isUploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_isUploading ? 'Uploading...' : 'Sign-off'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompletedSignOff(SignOff signOff) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Signed Off',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
              ),
            ),
            // Use IconButton instead of OutlinedButton
            IconButton(
              onPressed: () => _showEditDialog(signOff),
              icon: const Icon(Icons.edit),
              tooltip: 'Edit',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.person, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Signed by:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(signOff.typedName),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.access_time, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Signed at:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(DateTimeUtils.formatDateTime(signOff.createdAt)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: 2.5,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                signOff.signatureURL,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (context, error, stackTrace) {
                  debugPrint(
                      'Failed to load signature from URL: ${signOff.signatureURL}');
                  debugPrint('Error: $error');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.red),
                        const Text('Failed to load signature'),
                        const SizedBox(height: 8),
                        Text(
                          error.toString(),
                          style:
                              const TextStyle(fontSize: 10, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Export Summary Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _exportSummary,
            icon: const Icon(Icons.table_chart),
            label: const Text('Export to Excel'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  /// Returns an appropriate icon based on the consumable item name
  IconData _getConsumableIcon(String itemName) {
    final lowerName = itemName.toLowerCase();

    if (lowerName.contains('headphone') || lowerName.contains('earphone')) {
      return Icons.headphones;
    } else if (lowerName.contains('tissue')) {
      return Icons.inbox;
    } else if (lowerName.contains('paper')) {
      return Icons.content_copy;
    } else if (lowerName.contains('pencil') || lowerName.contains('pen')) {
      return Icons.edit;
    } else if (lowerName.contains('glue') || lowerName.contains('adhesive')) {
      return Icons.format_paint;
    } else if (lowerName.contains('eraser')) {
      return Icons.remove_circle_outline;
    } else if (lowerName.contains('ruler')) {
      return Icons.straighten;
    } else if (lowerName.contains('scissors')) {
      return Icons.content_cut;
    } else if (lowerName.contains('marker') || lowerName.contains('crayon')) {
      return Icons.brush;
    } else if (lowerName.contains('notebook') || lowerName.contains('book')) {
      return Icons.menu_book;
    } else if (lowerName.contains('folder') || lowerName.contains('binder')) {
      return Icons.folder;
    } else {
      // Default icon for unknown items
      return Icons.check_circle_outline;
    }
  }

  void _refreshTotals() {
    ref.invalidate(yearLevelsProvider(widget.schoolId));
    ref.invalidate(consumablesProvider(widget.schoolId));
    ref.invalidate(classroomTotalsProvider(widget.schoolId));
    ref.invalidate(schoolTotalProvider(widget.schoolId));
    ref.invalidate(signOffProvider(widget.schoolId));
  }

  Future<void> _handleSignOff() async {
    debugPrint('=== SIGN-OFF HANDLER STARTED ===');

    if (_nameController.text.trim().isEmpty) {
      debugPrint('ERROR: Name is empty');
      _showError('Please enter your name');
      return;
    }

    if (_signatureController.isEmpty) {
      debugPrint('ERROR: Signature is empty');
      _showError('Please provide your signature');
      return;
    }

    // Show pre-signoff dialog for optional notes
    final shouldProceed = await _showPreSignoffDialog();
    if (!shouldProceed) {
      debugPrint('User cancelled sign-off');
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      debugPrint('Step 1: Capturing signature bytes...');
      final signatureBytes = await _signatureController.toPngBytes();
      if (signatureBytes == null) {
        debugPrint('ERROR: Failed to capture signature bytes');
        _showError('Failed to capture signature');
        return;
      }
      debugPrint('Signature bytes captured: ${signatureBytes.length} bytes');

      debugPrint('Step 2: Compressing image...');
      final compressResult =
          await ImageService.compressImageBytes(signatureBytes);
      if (!compressResult.isSuccess) {
        debugPrint(
            'ERROR: Image compression failed: ${compressResult.errorOrNull}');
        _showError(compressResult.errorOrNull!);
        return;
      }
      debugPrint('Image compressed successfully');

      debugPrint('Step 3: Uploading to storage...');
      // Use simple 'current.png' path that was working before
      final storagePath = 'schools/${widget.schoolId}/signoffs/current.png';
      final storageRepository = ref.read(storageRepositoryProvider);
      final uploadResult = await storageRepository.uploadImageBytes(
          storagePath, compressResult.dataOrNull!);

      if (!uploadResult.isSuccess) {
        debugPrint('ERROR: Upload failed: ${uploadResult.errorOrNull}');
        _showError(uploadResult.errorOrNull!);
        return;
      }
      debugPrint('Upload successful: ${uploadResult.dataOrNull}');

      debugPrint('Step 4: Creating SignOff object...');
      final signOff = SignOff(
        typedName: _nameController.text.trim(),
        signatureURL: uploadResult.dataOrNull!,
        createdAt: DateTime.now(),
      );
      debugPrint('SignOff object created');

      debugPrint('Step 5: Saving sign-off to Firestore...');
      final success = await ref
          .read(schoolsNotifierProvider.notifier)
          .createOrUpdateSignOff(widget.schoolId, signOff);
      debugPrint('Sign-off save result: $success');

      if (success) {
        // Create the signed school summary document
        debugPrint('Sign-off saved, now generating summary...');
        final summarySuccess = await ref
            .read(schoolsNotifierProvider.notifier)
            .createSignedSchoolSummary(
              widget.schoolId,
              _nameController.text.trim(),
              uploadResult.dataOrNull,
            );

        debugPrint('Summary generation result: $summarySuccess');

        _nameController.clear();
        _signatureController.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(summarySuccess
                  ? 'Sign-off completed and summary generated successfully'
                  : 'Sign-off completed but summary generation failed'),
              backgroundColor:
                  summarySuccess ? BrandColors.kakaGreen : BrandColors.kakaBlue,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        _showError('Failed to save sign-off');
      }
    } catch (e) {
      _showError('Unexpected error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _showEditDialog(SignOff signOff) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign-off Actions'),
        content: const Text('Choose an action for the current sign-off:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearSignOff();
            },
            child: const Text('Clear Sign-off',
                style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _nameController.text = signOff.typedName;
              _signatureController.clear();
            },
            child: const Text('Create New'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearSignOff() async {
    try {
      debugPrint('=== CLEAR SIGN-OFF STARTED ===');

      // Delete the sign-off document
      debugPrint(
          'Step 1: Deleting sign-off document from schools/${widget.schoolId}/meta/signoff');
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('meta')
          .doc('signoff')
          .delete();
      debugPrint('✓ Sign-off document deleted');

      // Delete the signed school summary
      debugPrint(
          'Step 2: Deleting signed school summary from signed_school_summaries/${widget.schoolId}');
      await FirebaseFirestore.instance
          .collection('signed_school_summaries')
          .doc(widget.schoolId)
          .delete();
      debugPrint('✓ Signed school summary deleted');

      // Update the school document to remove sign-off status
      debugPrint('Step 3: Updating school document to clear sign-off flags');
      try {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolId)
            .update({
          'isSignedOff': false,
          'lastSignOffDate': FieldValue.delete(),
          'signedBy': FieldValue.delete(),
        });
        debugPrint('✓ School document updated');
      } catch (updateError) {
        debugPrint(
            'Warning: Could not update school document (this is optional): $updateError');
        // Continue anyway - the important deletions are done
      }

      debugPrint('=== CLEAR SIGN-OFF COMPLETED SUCCESSFULLY ===');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign-off cleared successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('✗ ERROR in _clearSignOff: $e');
      debugPrint('Error type: ${e.runtimeType}');
      _showError('Failed to clear sign-off: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportSummary() async {
    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 16),
                Text('Generating Excel file...'),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // Fetch the signed summary from Firestore
      final schoolsRepository = ref.read(schoolsRepositoryProvider);
      final result =
          await schoolsRepository.getSignedSchoolSummary(widget.schoolId);

      if (!result.isSuccess) {
        _showError('Failed to fetch summary: ${result.errorOrNull}');
        return;
      }

      final summary = result.dataOrNull;
      if (summary == null) {
        _showError('No signed summary found for this school');
        return;
      }

      // Export to Excel
      debugPrint('Exporting summary to Excel...');
      final filePath = await ExcelExportService.exportSummaryToExcel(summary);

      if (filePath == null) {
        _showError('Failed to create Excel file');
        return;
      }

      debugPrint('Excel file created at: $filePath');

      // Show options dialog
      if (mounted) {
        _showExportOptionsDialog(filePath, summary.schoolName);
      }
    } catch (e) {
      debugPrint('Error exporting summary: $e');
      _showError('Failed to export summary: $e');
    }
  }

  void _showExportOptionsDialog(String filePath, String schoolName) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export Successful'),
        content: Text(
          Platform.isIOS
              ? 'Your Excel file has been created and is ready to share.'
              : 'Your Excel file has been created. What would you like to do?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);

              // Wait a frame for dialog to fully close
              await Future.delayed(const Duration(milliseconds: 100));

              if (!mounted) return;

              try {
                // On iOS this will share, on other platforms it will try to open
                await ExcelExportService.openExcelFile(filePath, schoolName);
              } catch (e) {
                if (mounted) {
                  _showError('Could not open file: $e');
                }
              }
            },
            icon: Icon(Platform.isIOS ? Icons.share : Icons.open_in_new),
            label: Text(Platform.isIOS ? 'Share File' : 'Open File'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showPreSignoffDialog() async {
    // Get active checklist items from Firestore
    final checklistItemsAsync =
        await ref.read(activeChecklistItemsProvider.future);

    // If no checklist items, proceed directly
    if (checklistItemsAsync.isEmpty) {
      return true;
    }

    // Track checked state for each item
    final Map<String, bool> checkedItems = {};
    for (var item in checklistItemsAsync) {
      checkedItems[item.id] = false;
    }

    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          // Check if all items are checked
          final allChecked = checkedItems.values.every((checked) => checked);
          final checkedCount =
              checkedItems.values.where((checked) => checked).length;
          final totalItems = checkedItems.length;

          // Auto-close dialog when all items are checked
          if (allChecked) {
            // Use Future.delayed to avoid calling Navigator during build
            Future.delayed(Duration.zero, () {
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop(true);
              }
            });
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.checklist, color: BrandColors.kakaGreen),
                SizedBox(width: 8),
                Text('Pre-Signoff Checklist'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Please confirm the following items before signing off:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  // Dynamic checklist items
                  ...checklistItemsAsync.map((item) {
                    return CheckboxListTile(
                      value: checkedItems[item.id] ?? false,
                      onChanged: (value) {
                        setState(() {
                          checkedItems[item.id] = value ?? false;
                        });
                      },
                      title: Text(
                        item.title,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: item.subtitle != null
                          ? Text(
                              item.subtitle!,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            )
                          : null,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  }),
                  if (!allChecked) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: checkedCount / totalItems,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          BrandColors.kakaGreen),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$checkedCount of $totalItems items completed',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              if (!allChecked)
                TextButton(
                  onPressed: null,
                  child: Text(
                    'Complete all items to continue',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                ),
            ],
          );
        },
      ),
    );

    return result ?? false;
  }
}
