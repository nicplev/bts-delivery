import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/school_timer.dart';
import '../providers/school_timer_providers.dart';
import '../app/theme/brand_colors.dart';
import 'design/design.dart';

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
        return _buildTimerPanel(
          context,
          tone: running ? AppTone.green : AppTone.neutral,
          icon: running ? Icons.timer : Icons.timer_outlined,
          label: running
              ? 'Started by ${activeTimer!.startedByName}'
              : 'Visit timer',
          elapsed: _formatDuration(_displayedElapsed),
          action: canControl
              ? _buildControlButton(
                  context,
                  activeTimer: activeTimer,
                  isLoading: notifierState.isLoading,
                )
              : null,
        );
      },
      loading: () => _buildTimerPanel(
        context,
        icon: Icons.timer_outlined,
        label: 'Loading visit timer…',
      ),
      error: (error, _) => _buildTimerPanel(
        context,
        tone: AppTone.pink,
        icon: Icons.error_outline,
        label: 'Timer unavailable',
      ),
    );
  }

  Widget _buildTimerPanel(
    BuildContext context, {
    required IconData icon,
    required String label,
    AppTone tone = AppTone.neutral,
    String? elapsed,
    Widget? action,
  }) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.gutter,
        4,
        AppTokens.gutter,
        8,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackAction = constraints.maxWidth <
              MediaQuery.textScalerOf(context).scale(240);
          final display = Row(
            children: [
              Icon(icon, size: 20, color: tone.ink),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (elapsed != null)
                      Text(
                        elapsed,
                        style: textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w700,
                          color: tone.ink,
                        ),
                      ),
                    Text(
                      label,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppTokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (action == null) return display;
          if (stackAction) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [display, const SizedBox(height: 8), action],
            );
          }
          return Row(
            children: [
              Expanded(child: display),
              const SizedBox(width: 8),
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _buildControlButton(
    BuildContext context, {
    required SchoolTimer? activeTimer,
    required bool isLoading,
  }) {
    final isRunning = activeTimer != null && activeTimer.isActive;

    return FilledButton.icon(
      onPressed: isLoading
          ? null
          : () async {
              final notifier = ref.read(schoolTimerNotifierProvider.notifier);
              if (isRunning) {
                final success =
                    await notifier.stopTimer(widget.schoolId, activeTimer.id);
                if (!success && context.mounted) {
                  final error = ref.read(schoolTimerNotifierProvider).error;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text(error?.toString() ?? 'Failed to stop timer'),
                      backgroundColor: BrandColors.error,
                    ),
                  );
                }
              } else {
                final success = await notifier.startTimer(widget.schoolId);
                if (!success && context.mounted) {
                  final error = ref.read(schoolTimerNotifierProvider).error;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text(error?.toString() ?? 'Failed to start timer'),
                      backgroundColor: BrandColors.error,
                    ),
                  );
                }
              }
            },
      icon: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTokens.muted,
              ),
            )
          : Icon(
              isRunning ? Icons.stop : Icons.play_arrow,
              size: 20,
            ),
      label: Text(isRunning ? 'Stop' : 'Start'),
      style: FilledButton.styleFrom(
        backgroundColor: isRunning ? AppTone.pink.tint : AppTone.green.accent,
        foregroundColor: isRunning ? AppTone.pink.ink : AppTokens.ink,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        minimumSize: const Size(64, 48),
      ),
    );
  }
}
