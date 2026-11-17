part of '../classroom_detail_screen.dart';

/// Year-level / student distribution for composite classes. Hidden from
/// non-admins while empty; only admins add, edit or remove year levels.
class _DistributionSection extends ConsumerWidget {
  const _DistributionSection({
    required this.room,
    required this.breakdownsAsync,
  });

  final _Room room;
  final AsyncValue<List<YearLevelBreakdown>> breakdownsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final colors = AppPalette.of(context);

    return breakdownsAsync.when(
      loading: () => const _Section(
        label: 'Student distribution',
        child: AppGroupedList(children: [
          _MessageRow(title: 'Loading student distribution...', loading: true),
        ]),
      ),
      error: (error, _) => _Section(
        label: 'Student distribution',
        child: AppGroupedList(children: [
          _MessageRow(
            title: 'Error loading student distribution',
            subtitle: 'Error: $error',
            isError: true,
          ),
        ]),
      ),
      data: (breakdowns) {
        if (breakdowns.isEmpty && !isAdmin) return const SizedBox.shrink();
        final add = isAdmin
            ? _AddButton(
                label: 'Add',
                semanticLabel: 'Add year level',
                onPressed: () => _showAddDialog(context, ref),
              )
            : null;
        if (breakdowns.isEmpty) {
          return _Section(
            label: 'Student distribution',
            action: add,
            child: AppGroupedList(children: [
              AppListRow(
                icon: AppIcons.people,
                title: 'No student distribution set',
                subtitle: 'Add year level breakdowns for composite classes.',
                onTap: () => _showAddDialog(context, ref),
                showChevron: false,
                trailing: Icon(AppIcons.add, size: 20, color: colors.ink),
              ),
            ]),
          );
        }

        final totalStudents =
            breakdowns.fold<int>(0, (sum, b) => sum + b.studentCount);
        return _Section(
          label: 'Student distribution',
          action: add,
          caption: breakdowns.length > 1
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Composite class',
                      style:
                          AppTypography.footnote.copyWith(color: colors.muted)),
                )
              : null,
          child: AppGroupedList(
            separatorIndent: 64,
            children: [
              for (final breakdown in breakdowns)
                AppListRow(
                  leading: AppYearBadge(label: breakdown.yearLevelLabel),
                  title: breakdown.yearLevelLabel,
                  detail: _plural(breakdown.studentCount, 'student'),
                  trailing: isAdmin
                      ? AppMenuButton<bool>(
                          tooltip: '${breakdown.yearLevelLabel} options',
                          onSelected: (edit) {
                            if (!context.mounted) return;
                            if (edit) {
                              _showEditDialog(context, ref, breakdown);
                            } else {
                              _delete(context, ref, breakdown);
                            }
                          },
                          itemBuilder: (context) => [
                            appMenuItem(context, true, 'Edit',
                                icon: AppIcons.edit),
                            appMenuItem(context, false, 'Delete',
                                icon: AppIcons.delete, destructive: true),
                          ],
                        )
                      : null,
                ),
              AppListRow(
                title: 'Total students',
                titleStyle: AppTypography.headline.copyWith(color: colors.ink),
                trailing: Text(
                  '$totalStudents',
                  style: AppTypography.headline.copyWith(color: colors.ink),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
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
        scrollable: true,
        title: const Text('Add year level'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Year level'),
                icon: const Icon(AppIcons.chevronDown),
                items: standardYearLevels.map((label) {
                  return DropdownMenuItem(
                    value: label,
                    child: Row(
                      children: [
                        AppYearBadge(label: label, size: 24),
                        const SizedBox(width: 10),
                        Flexible(child: Text(label)),
                      ],
                    ),
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
                  labelText: 'Student count',
                  hintText: 'Enter number of students',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
                validator: _validateStudents,
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
                  .createYearLevelBreakdown(room.schoolId, room.yearLevelId,
                      room.classroomId, breakdown);

              if (context.mounted) {
                _showMessage(
                    context,
                    success
                        ? 'Year level added successfully'
                        : 'Failed to add year level');
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
      BuildContext context, WidgetRef ref, YearLevelBreakdown breakdown) {
    final studentCountController = TextEditingController(
      text: breakdown.studentCount.toString(),
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Edit year level'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppYearBadge(label: breakdown.yearLevelLabel),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      breakdown.yearLevelLabel,
                      style: AppTypography.headline
                          .copyWith(color: AppPalette.of(dialogContext).ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: studentCountController,
                decoration: const InputDecoration(
                  labelText: 'Student count',
                  hintText: 'Enter number of students',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
                validator: _validateStudents,
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
                  .updateYearLevelBreakdown(room.schoolId, room.yearLevelId,
                      room.classroomId, updated);

              if (context.mounted) {
                _showMessage(
                    context,
                    success
                        ? 'Year level updated successfully'
                        : 'Failed to update year level');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _delete(
      BuildContext context, WidgetRef ref, YearLevelBreakdown breakdown) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete year level?'),
        content: Text(
          'Are you sure you want to remove ${breakdown.yearLevelLabel} (${breakdown.studentCount} students) from this classroom?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          _destructiveButton(
            dialogContext,
            label: 'Delete',
            onPressed: () async {
              if (!context.mounted) return;
              Navigator.pop(dialogContext);

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .deleteYearLevelBreakdown(room.schoolId, room.yearLevelId,
                      room.classroomId, breakdown.id);

              if (context.mounted) {
                _showMessage(
                    context,
                    success
                        ? 'Year level removed successfully'
                        : 'Failed to remove year level');
              }
            },
          ),
        ],
      ),
    );
  }
}

String? _validateStudents(String? value) {
  if (value?.trim().isEmpty ?? true) {
    return 'Please enter student count';
  }
  final count = int.tryParse(value!);
  if (count == null || count <= 0) {
    return 'Please enter a valid number';
  }
  return null;
}
