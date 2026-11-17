import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/school_timer.dart';
import '../providers/school_timer_providers.dart';
import '../providers/auth_providers.dart';
import 'design/design.dart';

/// Completed visit timers as neutral rows (admins can edit, delete and add
/// manual entries). Sized to its content; place it inside a card.
class SchoolTimerHistory extends ConsumerWidget {
  final String schoolId;
  final bool readOnly;
  final VoidCallback? onAddPressed;

  const SchoolTimerHistory({
    super.key,
    required this.schoolId,
    this.onAddPressed,
    this.readOnly = false,
  });

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(schoolTimerHistoryProvider(schoolId));
    final isAdmin = !readOnly && ref.watch(isAdminProvider);
    final colors = AppPalette.of(context);

    return historyAsync.when(
      data: (timers) {
        if (timers.isEmpty) {
          return _Message(
            icon: AppIcons.timer,
            title: 'No timer history yet',
            description: 'Completed timers will appear here',
            action: isAdmin
                ? AppSecondaryButton(
                    key: const ValueKey('add-manual-timer-entry'),
                    label: 'Add manual entry',
                    icon: AppIcons.add,
                    large: false,
                    onPressed: () => _showAddEditDialog(context, ref, null),
                  )
                : null,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < timers.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 57,
                  color: colors.separator,
                ),
              _TimerHistoryTile(
                timer: timers[index],
                schoolId: schoolId,
                formatDuration: _formatDuration,
                isAdmin: isAdmin,
                onEdit: () => _showAddEditDialog(context, ref, timers[index]),
                onDelete: () =>
                    _showDeleteConfirmation(context, ref, timers[index]),
              ),
            ],
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => const _Message(
        icon: AppIcons.error,
        title: 'Failed to load timer history',
      ),
    );
  }

  void _showAddEditDialog(
      BuildContext context, WidgetRef ref, SchoolTimer? timer) {
    showDialog(
      context: context,
      builder: (dialogContext) => TimerEntryDialog(
        schoolId: schoolId,
        timer: timer,
        ref: ref,
      ),
    );
  }

  void _showDeleteConfirmation(
      BuildContext context, WidgetRef ref, SchoolTimer timer) {
    final dateFormat = DateFormat('MMM d, yyyy h:mm a');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete timer entry'),
        content: Text(
          'Are you sure you want to delete the timer entry from ${dateFormat.format(timer.startedAt)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final notifier = ref.read(schoolTimerNotifierProvider.notifier);
              final success =
                  await notifier.deleteTimerEntry(schoolId, timer.id);
              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to delete timer entry'),
                  ),
                );
              }
            },
            style: appDestructiveButtonStyle(context),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconTile(icon: icon, size: 48),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.headline.copyWith(color: colors.ink),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: AppTypography.footnote.copyWith(color: colors.muted),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

class _TimerHistoryTile extends StatelessWidget {
  final SchoolTimer timer;
  final String schoolId;
  final String Function(Duration) formatDuration;
  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TimerHistoryTile({
    required this.timer,
    required this.schoolId,
    required this.formatDuration,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    final colors = AppPalette.of(context);
    final people = [
      'Started by ${timer.startedByName}',
      if (timer.stoppedByName != null) 'Stopped by ${timer.stoppedByName}',
    ].join(' · ');

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 68),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppIconTile(icon: AppIcons.timer, size: 29),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${dateFormat.format(timer.startedAt)} · ${timeFormat.format(timer.startedAt)}',
                    style: AppTypography.body.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatDuration(timer.elapsed),
                    style: AppTypography.subheadline.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    people,
                    style: AppTypography.footnote.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
            if (isAdmin)
              AppMenuButton<String>(
                tooltip: 'Timer entry options',
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (context) => [
                  appMenuItem(context, 'edit', 'Edit', icon: AppIcons.edit),
                  appMenuItem(context, 'delete', 'Delete',
                      icon: AppIcons.delete, destructive: true),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class TimerEntryDialog extends StatefulWidget {
  final String schoolId;
  final SchoolTimer? timer;
  final WidgetRef ref;

  const TimerEntryDialog({
    super.key,
    required this.schoolId,
    required this.timer,
    required this.ref,
  });

  @override
  State<TimerEntryDialog> createState() => _TimerEntryDialogState();
}

class _TimerEntryDialogState extends State<TimerEntryDialog> {
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _stopDate;
  late TimeOfDay _stopTime;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.timer != null) {
      _startDate = widget.timer!.startedAt;
      _startTime = TimeOfDay.fromDateTime(widget.timer!.startedAt);
      _stopDate = widget.timer!.stoppedAt ?? DateTime.now();
      _stopTime =
          TimeOfDay.fromDateTime(widget.timer!.stoppedAt ?? DateTime.now());
    } else {
      final now = DateTime.now();
      _startDate = now;
      _startTime =
          TimeOfDay.fromDateTime(now.subtract(const Duration(hours: 1)));
      _stopDate = now;
      _stopTime = TimeOfDay.fromDateTime(now);
    }
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Duration get _duration {
    final start = _combineDateAndTime(_startDate, _startTime);
    final stop = _combineDateAndTime(_stopDate, _stopTime);
    return stop.difference(start);
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return '--:--:--';
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final initialDate = isStart ? _startDate : _stopDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _stopDate = picked;
        }
      });
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final initialTime = isStart ? _startTime : _stopTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _stopTime = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    final startDateTime = _combineDateAndTime(_startDate, _startTime);
    final stopDateTime = _combineDateAndTime(_stopDate, _stopTime);

    if (stopDateTime.isBefore(startDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stop time must be after start time'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final notifier = widget.ref.read(schoolTimerNotifierProvider.notifier);
    bool success;

    if (widget.timer != null) {
      success = await notifier.updateTimerEntry(
        widget.schoolId,
        widget.timer!,
        startDateTime,
        stopDateTime,
      );
    } else {
      success = await notifier.createTimerEntry(
        widget.schoolId,
        startDateTime,
        stopDateTime,
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to ${widget.timer != null ? 'update' : 'create'} timer entry'),
          ),
        );
      }
    }
  }

  /// A labelled pair of date and time picker buttons.
  Widget _dateTimeFields({
    required String label,
    required String date,
    required String time,
    required VoidCallback onDate,
    required VoidCallback onTime,
  }) {
    final colors = AppPalette.of(context);
    final dateButton = OutlinedButton.icon(
      onPressed: onDate,
      icon: const Icon(AppIcons.calendar, size: 18),
      label: Text(date),
    );
    final timeButton = OutlinedButton.icon(
      onPressed: onTime,
      icon: const Icon(AppIcons.timer, size: 18),
      label: Text(time),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: AppTypography.footnote
              .copyWith(color: colors.muted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        // Stacked: the dialog sizes itself intrinsically, and two pickers side
        // by side do not fit large text on narrow screens.
        dateButton,
        const SizedBox(height: 8),
        timeButton,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    final isEditing = widget.timer != null;
    final colors = AppPalette.of(context);
    final invalid = _duration.isNegative;

    return AlertDialog(
      title: Text(isEditing ? 'Edit timer entry' : 'Add timer entry'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dateTimeFields(
              label: 'Start time',
              date: dateFormat.format(_startDate),
              time: timeFormat
                  .format(_combineDateAndTime(_startDate, _startTime)),
              onDate: () => _selectDate(context, true),
              onTime: () => _selectTime(context, true),
            ),
            const SizedBox(height: 16),
            _dateTimeFields(
              label: 'Stop time',
              date: dateFormat.format(_stopDate),
              time:
                  timeFormat.format(_combineDateAndTime(_stopDate, _stopTime)),
              onDate: () => _selectDate(context, false),
              onTime: () => _selectTime(context, false),
            ),
            const SizedBox(height: 20),
            DecoratedBox(
              decoration: BoxDecoration(
                color: invalid ? colors.errorContainer : colors.surfaceQuiet,
                borderRadius: BorderRadius.circular(AppTokens.controlRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Duration: ',
                      style: AppTypography.subheadline.copyWith(
                          color: invalid ? colors.error : colors.muted),
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: AppTypography.headline.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: invalid ? colors.error : colors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading || invalid ? null : _save,
          child: _isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: colors.muted),
                )
              : Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
