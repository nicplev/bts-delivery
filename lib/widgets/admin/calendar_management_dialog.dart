import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/staff.dart';
import '../../models/calendar_metadata.dart';
import '../../repositories/staff_repository.dart';
import '../../providers/calendar_metadata_provider.dart';
import '../../providers/staff_providers.dart';
import '../design/design.dart';

/// Dialog for admins to manage calendar subscriptions for staff members
class CalendarManagementDialog extends ConsumerStatefulWidget {
  final Staff staff;

  const CalendarManagementDialog({
    required this.staff,
    super.key,
  });

  @override
  ConsumerState<CalendarManagementDialog> createState() =>
      _CalendarManagementDialogState();
}

class _CalendarManagementDialogState
    extends ConsumerState<CalendarManagementDialog> {
  bool _isLoading = false;
  String? _errorMessage;
  String? _subscriptionUrl;

  @override
  void initState() {
    super.initState();
    _loadSubscriptionUrl();
  }

  Future<void> _loadSubscriptionUrl() async {
    if (!widget.staff.isLinked) return;
    final repository = ref.read(staffRepositoryProvider);
    final result =
        await repository.getExistingCalendarHttpsUrl(widget.staff.id);
    if (!mounted || _isLoading) return;
    setState(() {
      _subscriptionUrl = result.dataOrNull;
      _errorMessage = result.errorOrNull;
    });
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(AppIcons.complete, color: AppPalette.of(context).canvas),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _generateToken() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(staffRepositoryProvider);
      final result = await repository.generateCalendarToken(widget.staff.id);

      if (result.isFailure && mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = result.errorOrNull;
        });
        return;
      }

      if (!mounted) return;
      final url = calendarUrl(result.dataOrNull!);

      // Invalidate providers to refresh
      ref.invalidate(calendarMetadataProvider);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _subscriptionUrl = url;
        });

        _showSuccess('Calendar subscription created successfully');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to generate token: $e';
        });
      }
    }
  }

  Future<void> _regenerateToken() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = AppPalette.of(context);
        return AlertDialog(
          scrollable: true,
          title: const Text('Regenerate calendar link?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will create a new calendar subscription link and revoke the old one.',
              ),
              const SizedBox(height: 16),
              AppNotice(
                icon: AppIcons.infoOutline,
                message:
                    '${widget.staff.name} will need to re-subscribe in their calendar app.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            // Revokes the current link: a destructive action.
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: const Text('Regenerate'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(staffRepositoryProvider);
      final result = await repository.regenerateCalendarToken(widget.staff.id);

      if (result.isFailure && mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = result.errorOrNull;
        });
        return;
      }

      if (!mounted) return;
      final url = calendarUrl(result.dataOrNull!);

      // Invalidate providers to refresh
      ref.invalidate(calendarMetadataProvider);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _subscriptionUrl = url;
        });

        _showSuccess('Calendar link regenerated successfully');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to regenerate token: $e';
        });
      }
    }
  }

  Future<void> _copyUrl() async {
    if (_subscriptionUrl == null) return;

    await Clipboard.setData(ClipboardData(text: _subscriptionUrl!));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Calendar URL copied to clipboard'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final metadataAsync = ref.watch(calendarMetadataProvider(widget.staff.id));
    final colors = AppPalette.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const AppIconTile(icon: AppIcons.calendar),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Calendar management'),
                Text(
                  widget.staff.name,
                  style:
                      AppTypography.subheadline.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading) ...[
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Processing...'),
                    ],
                  ),
                ),
              ] else if (_errorMessage != null) ...[
                Semantics(
                  liveRegion: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius:
                          BorderRadius.circular(AppTokens.controlRadius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(AppIcons.error, color: colors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: AppTypography.subheadline
                                  .copyWith(color: colors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                // Calendar Status
                _buildStatusSection(metadataAsync),
                const SizedBox(height: 24),

                // Subscription URL
                if (_subscriptionUrl != null) ...[
                  _buildUrlSection(),
                  const SizedBox(height: 24),
                ],

                // Statistics
                if (_subscriptionUrl != null)
                  _buildStatisticsSection(metadataAsync),
              ],
            ],
          ),
        ),
      ),
      actions: _isLoading
          ? []
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              if (_subscriptionUrl == null)
                FilledButton.icon(
                  onPressed: widget.staff.isLinked ? _generateToken : null,
                  icon: const Icon(AppIcons.add, size: 18),
                  label: const Text('Generate link'),
                )
              else
                FilledButton.icon(
                  onPressed: _regenerateToken,
                  icon: const Icon(AppIcons.retry, size: 18),
                  label: const Text('Regenerate'),
                ),
            ],
    );
  }

  /// Neutral status tile: icon, title and detail line.
  Widget _statusTile({
    required Widget icon,
    required String title,
    required String detail,
  }) {
    final colors = AppPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceQuiet,
        borderRadius: BorderRadius.circular(AppTokens.controlRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.headline.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: AppTypography.footnote.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection(AsyncValue<CalendarMetadata?> metadataAsync) {
    final colors = AppPalette.of(context);
    if (_subscriptionUrl == null) {
      return _statusTile(
        icon: Icon(AppIcons.calendar, color: colors.muted, size: 28),
        title: 'No calendar subscription',
        detail: 'Generate a link to enable calendar sync',
      );
    }

    return metadataAsync.when(
      data: (metadata) {
        final isActive = metadata?.isActive ?? false;
        return _statusTile(
          icon: isActive
              ? const AppStatusRing(
                  status: AppCompletion.complete,
                  size: 28,
                  semanticLabel: 'Active',
                )
              : Icon(AppIcons.paused, color: colors.muted, size: 28),
          title: isActive ? 'Calendar active' : 'Calendar inactive',
          detail: metadata?.lastAccessedText ?? 'Never accessed',
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _statusTile(
        icon: Icon(AppIcons.calendar, color: colors.ink, size: 28),
        title: 'Calendar active',
        detail: 'Subscription link generated',
      ),
    );
  }

  Widget _buildUrlSection() {
    final colors = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Subscription URL',
          style: AppTypography.headline.copyWith(color: colors.ink),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceQuiet,
            borderRadius: BorderRadius.circular(AppTokens.controlRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _subscriptionUrl!,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: colors.ink,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(HeroiconsOutline.documentDuplicate, size: 20),
                  onPressed: _copyUrl,
                  tooltip: 'Copy URL',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Share this URL with ${widget.staff.name} to subscribe',
          style: AppTypography.footnote.copyWith(color: colors.muted),
        ),
      ],
    );
  }

  Widget _buildStatisticsSection(AsyncValue<CalendarMetadata?> metadataAsync) {
    final colors = AppPalette.of(context);
    return metadataAsync.when(
      data: (metadata) {
        if (metadata == null) {
          return const AppNotice(message: 'No usage data yet');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usage statistics',
              style: AppTypography.headline.copyWith(color: colors.ink),
            ),
            const SizedBox(height: 12),
            _buildStatRow(
              'Total accesses',
              metadata.accessCount.toString(),
              HeroiconsOutline.eye,
            ),
            Divider(height: 24, color: colors.separator),
            _buildStatRow(
              'Last accessed',
              metadata.lastAccessed != null
                  ? DateFormat('MMM d, y • h:mm a')
                      .format(metadata.lastAccessed!)
                  : 'Never',
              AppIcons.timer,
            ),
            if (metadata.lastDeliveryChange != null) ...[
              Divider(height: 24, color: colors.separator),
              _buildStatRow(
                'Last delivery update',
                DateFormat('MMM d, y • h:mm a')
                    .format(metadata.lastDeliveryChange!),
                AppIcons.retry,
              ),
            ],
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    final colors = AppPalette.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.footnote.copyWith(color: colors.muted),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTypography.subheadline
                    .copyWith(color: colors.ink, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
