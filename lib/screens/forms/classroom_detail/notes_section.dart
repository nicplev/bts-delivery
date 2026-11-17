part of '../classroom_detail_screen.dart';

/// Classroom notes with author and time; add, edit (tap or menu) and delete.
class _NotesSection extends ConsumerWidget {
  const _NotesSection({required this.room});

  final _Room room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(classroomNotesProvider(room.packKey));
    final colors = AppPalette.of(context);

    return _Section(
      label: 'Notes',
      action: _AddButton(
        label: 'Add',
        semanticLabel: 'Add note',
        onPressed: () => _showNoteDialog(context, ref),
      ),
      child: notesAsync.when(
        loading: () => const AppGroupedList(children: [
          _MessageRow(title: 'Loading notes…', loading: true),
        ]),
        error: (error, _) => AppGroupedList(children: [
          _MessageRow(
            title: 'Error loading notes',
            subtitle: 'Error: $error',
            isError: true,
          ),
        ]),
        data: (notes) {
          if (notes.isEmpty) {
            return AppGroupedList(children: [
              AppListRow(
                icon: AppIcons.notes,
                title: 'No notes yet',
                subtitle: 'Add notes about this classroom',
                showChevron: false,
                trailing: Icon(AppIcons.add, size: 20, color: colors.ink),
                onTap: () => _showNoteDialog(context, ref),
                semanticLabel: 'No notes yet. Add note',
              ),
            ]);
          }
          return AppGroupedList(
            separatorIndent: 57,
            children: [
              for (final note in notes)
                _NoteRow(
                  key: ValueKey(note.id),
                  note: note,
                  onEdit: () => _showNoteDialog(context, ref, note: note),
                  onDelete: () => _confirmDelete(context, ref, note),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showNoteDialog(BuildContext context, WidgetRef ref, {Note? note}) {
    final schools = ref.read(schoolsNotifierProvider.notifier);
    final staffName = ref.read(currentStaffProvider).valueOrNull?.name;
    showFieldDraftDialog(
      context: context,
      ref: ref,
      target: room.draftTarget('note', entityId: note?.id),
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
          room.schoolId,
          room.yearLevelId,
          room.classroomId,
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

  Future<void> _confirmDelete(
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
          _destructiveButton(
            dialogContext,
            label: 'Delete',
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref
        .read(schoolsNotifierProvider.notifier)
        .saveClassroomNoteDeletion(
            room.schoolId, room.yearLevelId, room.classroomId, note);
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
    _showMessage(context, message);
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    super.key,
    required this.note,
    required this.onEdit,
    required this.onDelete,
  });

  final Note note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final meta = [
      if (note.author != null) note.author!,
      _formatDate(note.createdAt),
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppPressable(
            onTap: onEdit,
            pressedColor: colors.fill,
            semanticLabel: '${note.content}. $meta. Edit note',
            excludeChildSemantics: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: AppIconTile(icon: AppIcons.notes, size: 29),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(note.content,
                            style:
                                AppTypography.body.copyWith(color: colors.ink)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              note.author != null
                                  ? AppIcons.person
                                  : AppIcons.timer,
                              size: 14,
                              color: colors.muted,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(meta,
                                  style: AppTypography.footnote
                                      .copyWith(color: colors.muted)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 4),
          child: _RowMenu<String>(
            tooltip: 'Note options',
            onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
            items: [
              _menuItem(context, 'edit', 'Edit', AppIcons.edit),
              _menuItem(context, 'delete', 'Delete', AppIcons.delete,
                  destructive: true),
            ],
          ),
        ),
      ],
    );
  }
}
