import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/staff.dart';
import '../providers/calendar_sync_providers.dart';
import '../providers/staff_providers.dart';

/// Dialog for subscribing to calendar via webcal:// URL
class CalendarSubscriptionDialog extends ConsumerStatefulWidget {
  final Staff staff;

  const CalendarSubscriptionDialog({
    required this.staff,
    super.key,
  });

  @override
  ConsumerState<CalendarSubscriptionDialog> createState() =>
      _CalendarSubscriptionDialogState();
}

class _CalendarSubscriptionDialogState
    extends ConsumerState<CalendarSubscriptionDialog> {
  bool _isLoading = false;
  String? _subscriptionUrl;
  String? _httpsUrl;
  String? _errorMessage;
  bool _showAdvancedOptions = false;

  @override
  void initState() {
    super.initState();
    _loadSubscriptionUrl();
  }

  Future<void> _loadSubscriptionUrl() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(calendarSubscriptionServiceProvider);

      // Check if service is configured
      if (!service.isConfigured()) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Calendar subscription is not yet configured. Please contact your administrator.';
        });
        return;
      }

      // DEBUG: Log initial staff state
      debugPrint('[CalendarDialog] Initial staff ID: ${widget.staff.id}');
      debugPrint('[CalendarDialog] Initial staff hasToken: ${widget.staff.hasCalendarToken}');
      debugPrint('[CalendarDialog] Initial staff token: ${widget.staff.calendarToken ?? "null"}');

      // Get subscription URL (this may generate a new token)
      final urlResult = await service.getSubscriptionUrl(widget.staff);
      if (urlResult.isFailure) {
        setState(() {
          _isLoading = false;
          _errorMessage = urlResult.errorOrNull ?? 'Failed to generate URL';
        });
        return;
      }

      debugPrint('[CalendarDialog] URL result: ${urlResult.dataOrNull}');

      // IMPORTANT: After token generation, refetch the staff from Firestore
      // to get the latest token that was just saved
      final repository = ref.read(staffRepositoryProvider);
      final freshStaffResult = await repository.getStaffById(widget.staff.id);
      final freshStaff = freshStaffResult.isSuccess
          ? freshStaffResult.dataOrNull ?? widget.staff
          : widget.staff;

      debugPrint('[CalendarDialog] Fresh staff hasToken: ${freshStaff.hasCalendarToken}');
      debugPrint('[CalendarDialog] Fresh staff token: ${freshStaff.calendarToken ?? "null"}');

      // Get HTTPS URL using the fresh staff object with updated token
      final httpsResult = await service.getHttpsUrl(freshStaff);
      final httpsUrl = httpsResult.dataOrNull;

      setState(() {
        _isLoading = false;
        _subscriptionUrl = urlResult.dataOrNull;
        _httpsUrl = httpsUrl;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'An error occurred: $e';
      });
    }
  }

  Future<void> _subscribeToCalendar() async {
    if (_subscriptionUrl == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Refetch staff to ensure we have the latest token
      final repository = ref.read(staffRepositoryProvider);
      final freshStaffResult = await repository.getStaffById(widget.staff.id);
      final freshStaff = freshStaffResult.isSuccess
          ? freshStaffResult.dataOrNull ?? widget.staff
          : widget.staff;

      final service = ref.read(calendarSubscriptionServiceProvider);
      final result = await service.openSubscriptionInCalendar(freshStaff);

      if (result.isFailure && mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = result.errorOrNull ?? 'Failed to open calendar';
        });
        return;
      }

      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        // Show success message and close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Calendar subscription opened in Calendar app'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to open calendar: $e';
      });
    }
  }

  Future<void> _copyUrlToClipboard(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL copied to clipboard'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _regenerateToken() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate Calendar Link?'),
        content: const Text(
          'This will create a new calendar subscription link and revoke the old one. '
          'You will need to re-subscribe in your calendar app.',
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
      final service = ref.read(calendarSubscriptionServiceProvider);
      final result = await service.regenerateToken(widget.staff);

      if (result.isFailure) {
        setState(() {
          _isLoading = false;
          _errorMessage = result.errorOrNull ?? 'Failed to regenerate token';
        });
        return;
      }

      // Reload URLs
      await _loadSubscriptionUrl();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Calendar link regenerated successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to regenerate token: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.calendar_month, size: 24),
          SizedBox(width: 12),
          Text('Subscribe to Calendar'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoading) ...[
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading calendar subscription...'),
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
              Center(
                child: TextButton.icon(
                  onPressed: _loadSubscriptionUrl,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ] else if (_subscriptionUrl != null) ...[
              const Text(
                'Subscribe to automatically sync your deliveries to your calendar app.',
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Auto-updates every hour',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your calendar will automatically update when deliveries are added or changed.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'How to subscribe:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 12),
              _buildInstructionStep(
                '1',
                'Tap "Subscribe Now" below',
              ),
              const SizedBox(height: 8),
              _buildInstructionStep(
                '2',
                'Calendar app will open',
              ),
              const SizedBox(height: 8),
              _buildInstructionStep(
                '3',
                'Tap "Subscribe" to confirm',
              ),
              const SizedBox(height: 8),
              _buildInstructionStep(
                '4',
                'Done! Updates happen automatically',
              ),
              const SizedBox(height: 24),
              // Advanced options
              InkWell(
                onTap: () {
                  setState(() {
                    _showAdvancedOptions = !_showAdvancedOptions;
                  });
                },
                child: Row(
                  children: [
                    Icon(
                      _showAdvancedOptions
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Advanced options',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (_showAdvancedOptions) ...[
                const SizedBox(height: 16),
                const Text(
                  'Calendar URL:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _httpsUrl ?? _subscriptionUrl!,
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
                        onPressed: () =>
                            _copyUrlToClipboard(_httpsUrl ?? _subscriptionUrl!),
                        tooltip: 'Copy URL',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _regenerateToken,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Regenerate link'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: _isLoading || _subscriptionUrl == null
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: _subscribeToCalendar,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: const Text('Subscribe Now'),
              ),
            ],
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}
