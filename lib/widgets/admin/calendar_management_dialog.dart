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
import '../../app/theme/brand_colors.dart';

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

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Calendar subscription created successfully'),
              ],
            ),
            backgroundColor: BrandColors.greenDarker,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Regenerate Calendar Link?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will create a new calendar subscription link and revoke the old one.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTone.yellow.tint,
                borderRadius: BorderRadius.circular(AppTokens.controlRadius),
                border: Border.all(color: AppTokens.outline),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: AppTone.yellow.ink),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${widget.staff.name} will need to re-subscribe in their calendar app.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTone.yellow.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTone.yellow.accent,
              foregroundColor: AppTokens.ink,
            ),
            child: const Text('Regenerate'),
          ),
        ],
      ),
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

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Calendar link regenerated successfully'),
              ],
            ),
            backgroundColor: BrandColors.greenDarker,
            behavior: SnackBarBehavior.floating,
          ),
        );
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

    return AlertDialog(
      title: Row(
        children: [
          const AppIconTile(icon: Icons.calendar_month_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Calendar Management'),
                Text(
                  widget.staff.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTokens.muted,
                      ),
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTone.pink.tint,
                    borderRadius:
                        BorderRadius.circular(AppTokens.controlRadius),
                    border: Border.all(color: AppTokens.outline),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: AppTone.pink.ink),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: AppTone.pink.ink),
                        ),
                      ),
                    ],
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
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Generate Link'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTone.blue.accent,
                    foregroundColor: AppTokens.ink,
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: _regenerateToken,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Regenerate'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTone.yellow.accent,
                    foregroundColor: AppTokens.ink,
                  ),
                ),
            ],
    );
  }

  Widget _buildStatusSection(AsyncValue<CalendarMetadata?> metadataAsync) {
    if (_subscriptionUrl == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTokens.surfaceQuiet,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTokens.outline),
        ),
        child: const Row(
          children: [
            Icon(Icons.calendar_month_outlined,
                color: AppTokens.muted, size: 32),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Calendar Subscription',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: AppTokens.ink,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Generate a link to enable calendar sync',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTokens.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return metadataAsync.when(
      data: (metadata) {
        final isActive = metadata?.isActive ?? false;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isActive ? AppTone.green.tint : AppTone.yellow.tint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? AppTokens.outline : AppTokens.outline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isActive ? Icons.check_circle : Icons.schedule,
                color: isActive ? AppTone.green.ink : AppTone.yellow.ink,
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive ? 'Calendar Active' : 'Calendar Inactive',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color:
                            isActive ? AppTone.green.ink : AppTone.yellow.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      metadata?.lastAccessedText ?? 'Never accessed',
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            isActive ? AppTone.green.ink : AppTone.yellow.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTone.green.tint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTokens.outline),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month, color: AppTone.green.ink, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Calendar Active',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: AppTone.green.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Subscription link generated',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTone.green.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrlSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Subscription URL',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTokens.ink,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTone.blue.tint,
            borderRadius: BorderRadius.circular(AppTokens.controlRadius),
            border: Border.all(color: AppTokens.outline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _subscriptionUrl!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: _copyUrl,
                tooltip: 'Copy URL',
                color: AppTone.blue.ink,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Share this URL with ${widget.staff.name} to subscribe',
          style: const TextStyle(
            fontSize: 12,
            color: AppTokens.muted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticsSection(AsyncValue<CalendarMetadata?> metadataAsync) {
    return metadataAsync.when(
      data: (metadata) {
        if (metadata == null) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTokens.surfaceQuiet,
              borderRadius: BorderRadius.circular(AppTokens.controlRadius),
              border: Border.all(color: AppTokens.outline),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppTokens.muted, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No usage data yet',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTokens.muted,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Usage Statistics',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTokens.ink,
              ),
            ),
            const SizedBox(height: 12),
            _buildStatRow(
              'Total Accesses',
              metadata.accessCount.toString(),
              Icons.visibility,
            ),
            const Divider(height: 24),
            _buildStatRow(
              'Last Accessed',
              metadata.lastAccessed != null
                  ? DateFormat('MMM d, y • h:mm a')
                      .format(metadata.lastAccessed!)
                  : 'Never',
              Icons.access_time,
            ),
            if (metadata.lastDeliveryChange != null) ...[
              const Divider(height: 24),
              _buildStatRow(
                'Last Delivery Update',
                DateFormat('MMM d, y • h:mm a')
                    .format(metadata.lastDeliveryChange!),
                Icons.update,
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
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTone.blue.ink),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTokens.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
