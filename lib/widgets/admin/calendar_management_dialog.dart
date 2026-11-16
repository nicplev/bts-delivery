import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/staff.dart';
import '../../models/calendar_metadata.dart';
import '../../providers/calendar_metadata_provider.dart';
import '../../providers/staff_providers.dart';

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
    if (!widget.staff.hasCalendarToken) return;

    try {
      final repository = ref.read(staffRepositoryProvider);
      final result = await repository.getCalendarHttpsUrl(widget.staff.id);

      if (result.isSuccess && mounted) {
        setState(() {
          _subscriptionUrl = result.dataOrNull;
        });
      }
    } catch (e) {
      // Ignore errors, URL will be generated when needed
    }
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

      // Reload URL
      await _loadSubscriptionUrl();

      // Invalidate providers to refresh
      ref.invalidate(calendarMetadataProvider);

      if (mounted) {
        setState(() {
          _isLoading = false;
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
            backgroundColor: Colors.green,
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
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${widget.staff.name} will need to re-subscribe in their calendar app.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade700,
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
              backgroundColor: Colors.orange,
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

      // Reload URL
      await _loadSubscriptionUrl();

      // Invalidate providers to refresh
      ref.invalidate(calendarMetadataProvider);

      if (mounted) {
        setState(() {
          _isLoading = false;
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
            backgroundColor: Colors.green,
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
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.calendar_month,
              color: Colors.deepPurple.shade700,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Calendar Management'),
                Text(
                  widget.staff.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
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
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
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
                if (widget.staff.hasCalendarToken && _subscriptionUrl != null) ...[
                  _buildUrlSection(),
                  const SizedBox(height: 24),
                ],

                // Statistics
                if (widget.staff.hasCalendarToken) _buildStatisticsSection(metadataAsync),
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
              if (!widget.staff.hasCalendarToken)
                FilledButton.icon(
                  onPressed: _generateToken,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Generate Link'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: _regenerateToken,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Regenerate'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
            ],
    );
  }

  Widget _buildStatusSection(AsyncValue<CalendarMetadata?> metadataAsync) {
    if (!widget.staff.hasCalendarToken) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined,
              color: Colors.grey.shade600, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Calendar Subscription',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Generate a link to enable calendar sync',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
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
            color: isActive ? Colors.green.shade50 : Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? Colors.green.shade200 : Colors.amber.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isActive ? Icons.check_circle : Icons.schedule,
                color: isActive ? Colors.green.shade700 : Colors.amber.shade700,
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
                        color: isActive
                            ? Colors.green.shade800
                            : Colors.amber.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      metadata?.lastAccessedText ?? 'Never accessed',
                      style: TextStyle(
                        fontSize: 13,
                        color: isActive
                            ? Colors.green.shade700
                            : Colors.amber.shade700,
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
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month,
              color: Colors.green.shade700, size: 32),
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
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Subscription link generated',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.green.shade700,
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
        Text(
          'Subscription URL',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.deepPurple.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.deepPurple.shade200),
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
                color: Colors.deepPurple.shade700,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Share this URL with ${widget.staff.name} to subscribe',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
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
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey.shade600, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No usage data yet',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
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
            Text(
              'Usage Statistics',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
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
                  ? DateFormat('MMM d, y • h:mm a').format(metadata.lastAccessed!)
                  : 'Never',
              Icons.access_time,
            ),
            if (metadata.lastDeliveryChange != null) ...[
              const Divider(height: 24),
              _buildStatRow(
                'Last Delivery Update',
                DateFormat('MMM d, y • h:mm a').format(metadata.lastDeliveryChange!),
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
        Icon(icon, size: 18, color: Colors.deepPurple.shade700),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
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
