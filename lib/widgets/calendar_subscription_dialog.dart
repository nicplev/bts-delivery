import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/staff.dart';
import '../providers/calendar_sync_providers.dart';
import '../app/theme/app_tokens.dart';

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

      final result = await service.getSubscriptionUrl(widget.staff);
      if (!mounted) return;
      final url = result.dataOrNull;
      setState(() {
        _isLoading = false;
        _errorMessage = result.errorOrNull;
        _subscriptionUrl = url;
        _httpsUrl = url?.replaceFirst('webcals://', 'https://');
      });
    } catch (e) {
      if (!mounted) return;
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
      final service = ref.read(calendarSubscriptionServiceProvider);
      final result = await service.openSubscriptionInCalendar(widget.staff);

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
                Icon(Icons.check_circle),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Calendar subscription opened in Calendar app'),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
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
                backgroundColor: AppTone.yellow.accent,
                foregroundColor: AppPalette.of(context).actionInk),
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
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
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
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer),
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
                  color: AppTone.blue.tintFor(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppPalette.of(context).outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: AppTone.blue.inkFor(context), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Auto-updates every hour',
                            style: TextStyle(
                              color: AppTone.blue.inkFor(context),
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
                        color: AppTone.blue.inkFor(context),
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
                    color: AppPalette.of(context).surfaceQuiet,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppPalette.of(context).outline),
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
                    foregroundColor: AppTone.yellow.inkFor(context),
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
            color: AppTone.blue.tintFor(context),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: AppTone.blue.inkFor(context),
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
