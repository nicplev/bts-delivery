import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/school_timer.dart';
import '../providers/school_timer_providers.dart';
import '../app/theme/brand_colors.dart';

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
        setState(() => _displayedElapsed = DateTime.now().difference(startedAt));
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
    final activeTimerAsync = ref.watch(activeSchoolTimerProvider(widget.schoolId));
    final canControl = ref.watch(canControlTimerProvider);
    final notifierState = ref.watch(schoolTimerNotifierProvider);

    return activeTimerAsync.when(
      data: (activeTimer) {
        if (activeTimer != null && activeTimer.isActive) {
          final session = (id: activeTimer.id, startedAt: activeTimer.startedAt);
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

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: BrandColors.gray10,
            border: Border(
              bottom: BorderSide(color: BrandColors.gray8, width: 1),
            ),
          ),
          child: Row(
            children: [
              // Timer icon
              Icon(
                activeTimer != null ? Icons.timer : Icons.timer_outlined,
                size: 20,
                color: activeTimer != null
                    ? BrandColors.kakaGreen
                    : BrandColors.gray5,
              ),
              const SizedBox(width: 12),

              // Timer display
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      activeTimer != null
                          ? _formatDuration(_displayedElapsed)
                          : '00:00:00',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: activeTimer != null
                            ? BrandColors.kakaGreen
                            : BrandColors.gray5,
                      ),
                    ),
                    if (activeTimer != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Started by ${activeTimer.startedByName}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: BrandColors.gray5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Start/Stop button (only for managers/admins)
              if (canControl)
                _buildControlButton(
                  context,
                  activeTimer: activeTimer,
                  isLoading: notifierState.isLoading,
                ),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: BrandColors.gray10,
          border: Border(
            bottom: BorderSide(color: BrandColors.gray8, width: 1),
          ),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.timer_outlined,
              size: 20,
              color: BrandColors.gray5,
            ),
            SizedBox(width: 12),
            Text(
              '00:00:00',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
                color: BrandColors.gray5,
              ),
            ),
          ],
        ),
      ),
      error: (error, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: BrandColors.gray10,
          border: Border(
            bottom: BorderSide(color: BrandColors.gray8, width: 1),
          ),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.error_outline,
              size: 20,
              color: BrandColors.error,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Timer unavailable',
                style: TextStyle(
                  fontSize: 14,
                  color: BrandColors.gray5,
                ),
              ),
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

    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: isLoading
            ? null
            : () async {
                final notifier = ref.read(schoolTimerNotifierProvider.notifier);
                if (isRunning) {
                  final success = await notifier.stopTimer(widget.schoolId, activeTimer.id);
                  if (!success && context.mounted) {
                    final error = ref.read(schoolTimerNotifierProvider).error;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(error?.toString() ?? 'Failed to stop timer'),
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
                        content: Text(error?.toString() ?? 'Failed to start timer'),
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
                  color: Colors.white,
                ),
              )
            : Icon(
                isRunning ? Icons.stop : Icons.play_arrow,
                size: 20,
              ),
        label: Text(isRunning ? 'Stop' : 'Start'),
        style: ElevatedButton.styleFrom(
          backgroundColor: isRunning ? BrandColors.error : BrandColors.kakaGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
