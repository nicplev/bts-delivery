part of '../classroom_detail_screen.dart';

/// Classroom consumables: each item with its expected and delivered
/// quantity, "Complete" and "Set quantity" inline, edit/delete in a menu.
class _ConsumablesSection extends ConsumerWidget {
  const _ConsumablesSection({required this.room});

  final _Room room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consumablesAsync =
        ref.watch(classroomConsumablesProvider(room.packKey));
    final count = consumablesAsync.valueOrNull?.length;

    return _Section(
      label: 'Consumables',
      action: _AddButton(
        label: 'Add',
        semanticLabel: 'Add consumable',
        onPressed: () => _showConsumableDialog(context, ref, null),
      ),
      caption: count == null || count == 0
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(_plural(count, 'item'),
                  style: AppTypography.footnote
                      .copyWith(color: AppPalette.of(context).muted)),
            ),
      child: consumablesAsync.when(
        loading: () => const AppGroupedList(children: [
          _MessageRow(title: 'Loading consumables…', loading: true),
        ]),
        error: (_, __) => const AppGroupedList(children: [
          _MessageRow(title: 'Error loading consumables', isError: true),
        ]),
        data: (consumables) {
          if (consumables.isEmpty) {
            return AppGroupedList(children: [
              AppListRow(
                icon: AppIcons.consumables,
                title: 'No consumables yet',
                subtitle: 'Add items like tissues, paper, etc.',
                showChevron: false,
                trailing: Icon(AppIcons.add,
                    size: 20, color: AppPalette.of(context).ink),
                onTap: () => _showConsumableDialog(context, ref, null),
                semanticLabel: 'No consumables yet. Add consumable',
              ),
            ]);
          }
          return AppGroupedList(
            separatorIndent: 57,
            children: [
              for (final consumable in consumables)
                _ConsumableRow(
                  key: ValueKey(consumable.id),
                  consumable: consumable,
                  onComplete: () => _markComplete(context, ref, consumable),
                  onSetQuantity: () =>
                      _showSetActualDialog(context, ref, consumable),
                  onEdit: () => _showConsumableDialog(context, ref, consumable),
                  onDelete: () => _confirmDelete(context, ref, consumable),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _markComplete(
      BuildContext context, WidgetRef ref, Consumable consumable) async {
    if (!context.mounted) return;

    final updatedConsumable = consumable.copyWith(
      actualQuantityDelivered: consumable.quantity,
    );

    final success = await ref
        .read(schoolsNotifierProvider.notifier)
        .updateClassroomConsumable(room.schoolId, room.yearLevelId,
            room.classroomId, updatedConsumable);

    if (!context.mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${consumable.itemName} marked as complete'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showSetActualDialog(
    BuildContext context,
    WidgetRef ref,
    Consumable consumable,
  ) {
    final schools = ref.read(schoolsNotifierProvider.notifier);
    showFieldDraftDialog(
      context: context,
      ref: ref,
      target: room.draftTarget('actualConsumable', entityId: consumable.id),
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
        room.schoolId,
        room.yearLevelId,
        room.classroomId,
        consumable.id,
        int.tryParse(draft.values['quantity']!.trim()),
        editId: draft.revision,
      ),
    );
  }

  /// Add (when [consumable] is null) or edit a classroom consumable.
  void _showConsumableDialog(
      BuildContext context, WidgetRef ref, Consumable? consumable) {
    final editing = consumable != null;
    final itemNameController =
        TextEditingController(text: consumable?.itemName ?? '');
    final quantityController =
        TextEditingController(text: consumable?.quantity.toString() ?? '');
    final unitController =
        TextEditingController(text: consumable?.unit ?? 'boxes');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(editing ? 'Edit consumable' : 'Add consumable'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: itemNameController,
                decoration: const InputDecoration(
                  labelText: 'Item name',
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

              final schools = ref.read(schoolsNotifierProvider.notifier);
              final bool success;
              if (editing) {
                success = await schools.updateClassroomConsumable(
                  room.schoolId,
                  room.yearLevelId,
                  room.classroomId,
                  Consumable(
                    id: consumable.id,
                    itemName: itemNameController.text.trim(),
                    quantity: int.parse(quantityController.text.trim()),
                    unit: unitController.text.trim(),
                    createdAt: consumable.createdAt,
                  ),
                );
              } else {
                success = await schools.createClassroomConsumable(
                  room.schoolId,
                  room.yearLevelId,
                  room.classroomId,
                  Consumable(
                    id: '',
                    itemName: itemNameController.text.trim(),
                    quantity: int.parse(quantityController.text.trim()),
                    unit: unitController.text.trim(),
                    createdAt: DateTime.now(),
                  ),
                );
              }

              if (context.mounted) {
                _showMessage(
                  context,
                  editing
                      ? (success
                          ? 'Consumable updated successfully'
                          : 'Failed to update consumable')
                      : (success
                          ? 'Consumable added successfully'
                          : 'Failed to add consumable'),
                );
              }
            },
            child: Text(editing ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  /// Shows a confirmation dialog before deleting a consumable item from the classroom.
  void _confirmDelete(
      BuildContext context, WidgetRef ref, Consumable consumable) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete consumable?'),
        content: Text(
          'Are you sure you want to delete "${consumable.itemName}"? This action cannot be undone.',
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
              Navigator.pop(dialogContext);

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .deleteClassroomConsumable(room.schoolId, room.yearLevelId,
                      room.classroomId, consumable.id);

              if (context.mounted) {
                _showMessage(
                    context,
                    success
                        ? 'Consumable deleted successfully'
                        : 'Failed to delete consumable');
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ConsumableRow extends StatelessWidget {
  const _ConsumableRow({
    super.key,
    required this.consumable,
    required this.onComplete,
    required this.onSetQuantity,
    required this.onEdit,
    required this.onDelete,
  });

  final Consumable consumable;
  final VoidCallback onComplete;
  final VoidCallback onSetQuantity;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final actual = consumable.actualQuantityDelivered;
    final differs = actual != null && actual != consumable.quantity;
    final (completion, status) = actual == null
        ? (AppCompletion.notStarted, 'Quantity unrecorded')
        : !differs
            ? (AppCompletion.complete, 'Delivered')
            : (AppCompletion.partial, 'Quantity differs');
    final amount = actual == null
        ? '${consumable.quantity} ${consumable.unit}'
        : '$actual / ${consumable.quantity} ${consumable.unit}';
    // A differing quantity needs a decision before sign-off: amber pill.
    final Widget statusLine = differs
        ? Semantics(
            label: status,
            excludeSemantics: true,
            child: const AppQuantityDiffersPill(
                key: ValueKey('consumable-quantity-differs')),
          )
        : Row(
            children: [
              AppStatusRing(
                status: completion,
                size: 16,
                semanticLabel: status,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: ExcludeSemantics(
                  child: Text(status,
                      style:
                          AppTypography.footnote.copyWith(color: colors.muted)),
                ),
              ),
            ],
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: AppIconTile(icon: AppIcons.consumables, size: 29),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(consumable.itemName,
                        style:
                            AppTypography.headline.copyWith(color: colors.ink)),
                    const SizedBox(height: 2),
                    Text(amount,
                        style: AppTypography.body.copyWith(color: colors.ink)),
                    SizedBox(height: differs ? 6 : 2),
                    statusLine,
                  ],
                ),
              ),
              AppMenuButton<String>(
                tooltip: '${consumable.itemName} options',
                onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (context) => [
                  appMenuItem(context, 'edit', 'Edit', icon: AppIcons.edit),
                  appMenuItem(context, 'delete', 'Delete',
                      icon: AppIcons.delete, destructive: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 41, right: 12),
            child: _InlineActions(actions: [
              (
                label: 'Complete',
                icon: AppIcons.completeOutline,
                onPressed: onComplete
              ),
              (
                label: 'Set quantity',
                icon: AppIcons.edit,
                onPressed: onSetQuantity
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
