import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/school_timer.dart';
import '../providers/school_timer_providers.dart';
import '../providers/auth_providers.dart';
import '../app/theme/app_tokens.dart';

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

    return historyAsync.when(
      data: (timers) {
        if (timers.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history,
                    size: 48,
                    color: AppPalette.of(context).muted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No timer history yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppPalette.of(context).muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Completed timers will appear here',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppPalette.of(context).muted,
                    ),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => _showAddEditDialog(context, ref, null),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Manual Entry'),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: timers.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            color: AppPalette.of(context).outline,
          ),
          itemBuilder: (context, index) {
            final timer = timers[index];
            return _TimerHistoryTile(
              timer: timer,
              schoolId: schoolId,
              formatDuration: _formatDuration,
              isAdmin: isAdmin,
              onEdit: () => _showAddEditDialog(context, ref, timer),
              onDelete: () => _showDeleteConfirmation(context, ref, timer),
            );
          },
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(24),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, _) => Container(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                'Failed to load timer history',
                style: TextStyle(
                  fontSize: 16,
                  color: AppPalette.of(context).muted,
                ),
              ),
            ],
          ),
        ),
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
        title: const Text('Delete Timer Entry'),
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
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError),
            child: const Text('Delete'),
          ),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date column
          SizedBox(
            width: 90,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateFormat.format(timer.startedAt),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppPalette.of(context).ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeFormat.format(timer.startedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppPalette.of(context).muted,
                  ),
                ),
              ],
            ),
          ),

          // Duration column
          SizedBox(
            width: 80,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTone.green.tintFor(context),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                formatDuration(timer.elapsed),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: AppTone.green.inkFor(context),
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Staff info column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.play_arrow,
                      size: 14,
                      color: AppTone.green.inkFor(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        timer.startedByName,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppPalette.of(context).muted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (timer.stoppedByName != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.stop,
                        size: 14,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          timer.stoppedByName!,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppPalette.of(context).muted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Admin menu
          if (isAdmin)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 20,
                color: AppPalette.of(context).muted,
              ),
              onSelected: (value) {
                if (value == 'edit') {
                  onEdit();
                } else if (value == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete,
                          size: 18, color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 8),
                      Text('Delete',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                  ),
                ),
              ],
            ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    final isEditing = widget.timer != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Timer Entry' : 'Add Timer Entry'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Start Time
            Text(
              'Start Time',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppPalette.of(context).muted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectDate(context, true),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(dateFormat.format(_startDate)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectTime(context, true),
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(timeFormat
                        .format(_combineDateAndTime(_startDate, _startTime))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stop Time
            Text(
              'Stop Time',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppPalette.of(context).muted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectDate(context, false),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(dateFormat.format(_stopDate)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectTime(context, false),
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(timeFormat
                        .format(_combineDateAndTime(_stopDate, _stopTime))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Duration
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _duration.isNegative
                    ? AppTone.pink.tintFor(context)
                    : AppTone.green.tintFor(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Duration: ',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppPalette.of(context).muted,
                    ),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: _duration.isNegative
                          ? Theme.of(context).colorScheme.error
                          : AppTone.green.inkFor(context),
                    ),
                  ),
                ],
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
          onPressed: _isLoading || _duration.isNegative ? null : _save,
          child: _isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppPalette.of(context).ink),
                )
              : Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
