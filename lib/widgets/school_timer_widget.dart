import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/school_timer.dart';
import '../providers/school_timer_providers.dart';
import 'design/design.dart';

/// The visit timer condensed to one row ("Timer 00:00:14" + a grey Start /
/// Stop capsule for staff who can control it). History and manual entries
/// live in the hub's Info tab.
class SchoolTimerWidget extends ConsumerStatefulWidget {
  final String schoolId;

  const SchoolTimerWidget({
    super.key,
    required this.schoolId,
  });

  @override
  ConsumerState<SchoolTimerWidget> createState() => _SchoolTimerWidgetState();
}

class _SchoolTimerWidgetState extends ConsumerState<SchoolTimerWidget> {
  Timer? _displayTimer;
  ({String id, DateTime startedAt})? _displaySession;
  Duration _displayedElapsed = Duration.zero;

  @override
  void dispose() {
    _displayTimer?.cancel();
    super.dispose();
  }

  void _startDisplayTimer(DateTime startedAt) {
    _displayTimer?.cancel();
    _displayTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(
            () => _displayedElapsed = DateTime.now().difference(startedAt));
      }
    });
  }

  void _stopDisplayTimer() {
    _displayTimer?.cancel();
    _displayTimer = null;
    _displaySession = null;
    _displayedElapsed = Duration.zero;
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final activeTimerAsync =
        ref.watch(activeSchoolTimerProvider(widget.schoolId));
    final canControl = ref.watch(canControlTimerProvider);
    final notifierState = ref.watch(schoolTimerNotifierProvider);

    return activeTimerAsync.when(
      data: (activeTimer) {
        if (activeTimer != null && activeTimer.isActive) {
          final session =
              (id: activeTimer.id, startedAt: activeTimer.startedAt);
          if (session != _displaySession) {
            _stopDisplayTimer();
            _displaySession = session;
            _displayedElapsed = DateTime.now().difference(session.startedAt);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _displaySession != session) return;
              _startDisplayTimer(session.startedAt);
            });
          }
        } else {
          _stopDisplayTimer();
        }

        final running = activeTimer?.isActive ?? false;
        return _buildTimerRow(
          context,
          elapsed: _formatDuration(_displayedElapsed),
          note: running ? 'Started by ${activeTimer!.startedByName}' : null,
          action: canControl
              ? _buildControlButton(
                  context,
                  activeTimer: activeTimer,
                  isLoading: notifierState.isLoading,
                )
              : null,
        );
      },
      loading: () => _buildTimerRow(context, status: 'Loading visit timer…'),
      error: (error, _) => _buildTimerRow(
        context,
        icon: AppIcons.error,
        status: 'Timer unavailable',
      ),
    );
  }

  /// One condensed row: clock glyph, "Timer", the elapsed time (or a status)
  /// and a grey Start/Stop capsule. Wraps onto two lines when narrow.
  Widget _buildTimerRow(
    BuildContext context, {
    IconData icon = AppIcons.timerMini,
    String? elapsed,
    String? status,
    String? note,
    Widget? action,
  }) {
    final colors = AppPalette.of(context);
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: colors.muted),
        const SizedBox(width: 6),
        Text(
          'Timer',
          style: AppTypography.subheadline.copyWith(color: colors.muted),
        ),
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                label,
                if (elapsed != null)
                  Text(
                    elapsed,
                    key: const ValueKey('visit-timer-elapsed'),
                    style: AppTypography.subheadline.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                if (status != null)
                  Text(
                    status,
                    style:
                        AppTypography.subheadline.copyWith(color: colors.muted),
                  ),
                if (action != null) action,
              ],
            ),
            if (note != null)
              Text(
                note,
                style: AppTypography.footnote.copyWith(color: colors.muted),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(
    BuildContext context, {
    required SchoolTimer? activeTimer,
    required bool isLoading,
  }) {
    final isRunning = activeTimer != null && activeTimer.isActive;

    return AppSecondaryButton(
      key: const ValueKey('visit-timer-control'),
      label: isRunning ? 'Stop' : 'Start',
      icon: isRunning ? AppIcons.stop : AppIcons.play,
      expand: false,
      large: false,
      loading: isLoading,
      onPressed: () async {
        final notifier = ref.read(schoolTimerNotifierProvider.notifier);
        if (isRunning) {
          final success =
              await notifier.stopTimer(widget.schoolId, activeTimer.id);
          if (!success && context.mounted) {
            final error = ref.read(schoolTimerNotifierProvider).error;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(error?.toString() ?? 'Failed to stop timer'),
              ),
            );
          }
        } else {
          final success = await notifier.startTimer(widget.schoolId);
          if (!success && context.mounted) {
            final error = ref.read(schoolTimerNotifierProvider).error;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(error?.toString() ?? 'Failed to start timer'),
              ),
            );
          }
        }
      },
    );
  }
}
