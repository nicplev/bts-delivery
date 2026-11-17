import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../widgets/design/design.dart';
import 'admin_page.dart';

/// Display data for one checklist item row.
typedef ChecklistAdminEntry = ({
  String id,
  String title,
  String? subtitle,
  bool isActive,
});

enum _ItemChoice { edit, toggle, delete }

/// Checklist items as one grouped card that can be reordered by the drag
/// handle (or a long press, or the screen reader's move up / move down
/// actions), with per-item options for edit, enable/disable and delete.
///
/// A sliver: use it in [AdminPage.slivers].
class ChecklistAdminList extends StatelessWidget {
  const ChecklistAdminList({
    super.key,
    required this.entries,
    required this.onReorder,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final List<ChecklistAdminEntry> entries;

  /// newIndex is counted before the moved item is removed (the classic
  /// `ReorderableListView.onReorder` contract).
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onToggle;
  final ValueChanged<int> onDelete;

  Future<void> _showOptions(BuildContext context, int index) async {
    final entry = entries[index];
    final choice = await showAdminActionSheet<_ItemChoice>(
      context,
      title: entry.title,
      actions: [
        const AdminSheetAction(
            value: _ItemChoice.edit, label: 'Edit', icon: AppIcons.edit),
        AdminSheetAction(
          value: _ItemChoice.toggle,
          label: entry.isActive ? 'Disable' : 'Enable',
          icon: entry.isActive ? AppIcons.paused : AppIcons.play,
        ),
        const AdminSheetAction(
            value: _ItemChoice.delete,
            label: 'Delete',
            icon: AppIcons.delete,
            destructive: true),
      ],
    );
    if (choice == null) return;
    switch (choice) {
      case _ItemChoice.edit:
        onEdit(index);
      case _ItemChoice.toggle:
        onToggle(index);
      case _ItemChoice.delete:
        onDelete(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    const radius = Radius.circular(AppTokens.cardRadius);
    return SliverReorderableList(
      itemCount: entries.length,
      // Translate back to the [ReorderableListView.onReorder] contract the
      // screens use (newIndex counted before the item is removed).
      onReorderItem: (oldIndex, newIndex) =>
          onReorder(oldIndex, newIndex > oldIndex ? newIndex + 1 : newIndex),
      proxyDecorator: (child, index, animation) => Material(
        color: colors.surface,
        elevation: 6,
        shadowColor: colors.shadow,
        borderRadius: const BorderRadius.all(radius),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final first = index == 0;
        final last = index == entries.length - 1;
        return Material(
          key: ValueKey(entry.id),
          color: colors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: colors.highContrast
                ? BorderSide(color: colors.outline)
                : BorderSide.none,
            borderRadius: BorderRadius.vertical(
              top: first ? radius : Radius.zero,
              bottom: last ? radius : Radius.zero,
            ),
          ),
          child: Semantics(
            customSemanticsActions: {
              if (index > 0)
                const CustomSemanticsAction(label: 'Move up'): () =>
                    onReorder(index, index - 1),
              if (!last)
                const CustomSemanticsAction(label: 'Move down'): () =>
                    onReorder(index, index + 2),
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!first)
                  Divider(
                      height: 1,
                      thickness: 1,
                      indent: 60,
                      color: colors.separator),
                _ChecklistRow(
                  index: index,
                  entry: entry,
                  onOptions: () => _showOptions(context, index),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.index,
    required this.entry,
    required this.onOptions,
  });

  final int index;
  final ChecklistAdminEntry entry;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              label: 'Reorder item',
              child: SizedBox.square(
                dimension: AppTokens.minTouchTarget,
                child: Center(
                  child: Icon(AppIcons.dragHandle,
                      size: 22, color: colors.chevron),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Long press on the text also picks the item up. (Not around the
          // whole row: a second start listener would replace the handle's
          // immediate drag.)
          Expanded(
            child: ReorderableDelayedDragStartListener(
              index: index,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: AppTypography.body.copyWith(
                        color: entry.isActive ? colors.ink : colors.muted),
                  ),
                  if (entry.subtitle != null)
                    Text(entry.subtitle!,
                        style: AppTypography.subheadline
                            .copyWith(color: colors.muted)),
                  if (!entry.isActive)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: AppStatusPill(
                        label: 'Disabled',
                        icon: AppIcons.paused,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          AdminOptionsButton(
            semanticLabel: 'Checklist item actions',
            onPressed: onOptions,
          ),
        ],
      ),
    );
  }
}
