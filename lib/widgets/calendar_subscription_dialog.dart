import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/staff.dart';
import '../providers/calendar_sync_providers.dart';
import 'design/design.dart';

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
          SnackBar(
            content: Row(
              children: [
                Icon(AppIcons.complete, color: AppPalette.of(context).canvas),
                const SizedBox(width: 12),
                const Expanded(
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
      builder: (context) {
        return AlertDialog(
          scrollable: true,
          title: const Text('Regenerate calendar link?'),
          content: const Text(
            'This will create a new calendar subscription link and revoke the old one. '
            'You will need to re-subscribe in your calendar app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            // Revokes the current link: a destructive action.
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: appDestructiveButtonStyle(context),
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
    final colors = AppPalette.of(context);
    final body = AppTypography.subheadline.copyWith(color: colors.ink);
    final muted = AppTypography.footnote.copyWith(color: colors.muted);
    return AlertDialog(
      title: const Row(
        children: [
          AppIconTile(icon: AppIcons.calendar),
          SizedBox(width: 12),
          Expanded(child: Text('Subscribe to calendar')),
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
                    Text('Loading calendar subscription...',
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ] else if (_errorMessage != null) ...[
              _ErrorBox(message: _errorMessage!),
              const SizedBox(height: 16),
              Center(
                child: AppSecondaryButton(
                  onPressed: _loadSubscriptionUrl,
                  icon: AppIcons.retry,
                  label: 'Retry',
                  expand: false,
                  large: false,
                ),
              ),
            ] else if (_subscriptionUrl != null) ...[
              Text(
                'Subscribe to automatically sync your deliveries to your calendar app.',
                style: body,
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceQuiet,
                  borderRadius: BorderRadius.circular(AppTokens.controlRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(AppIcons.info, color: colors.muted, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Auto-updates every hour',
                              style: body.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Your calendar will automatically update when deliveries are added or changed.',
                              style: muted,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(
                  'How to subscribe:',
                  style: AppTypography.headline.copyWith(color: colors.ink),
                ),
              ),
              const SizedBox(height: 12),
              _buildInstructionStep('1', 'Tap "Subscribe now" below'),
              const SizedBox(height: 8),
              _buildInstructionStep('2', 'Calendar app will open'),
              const SizedBox(height: 8),
              _buildInstructionStep('3', 'Tap "Subscribe" to confirm'),
              const SizedBox(height: 8),
              _buildInstructionStep('4', 'Done! Updates happen automatically'),
              const SizedBox(height: 16),
              // Advanced options
              AppPressable(
                onTap: () {
                  setState(() {
                    _showAdvancedOptions = !_showAdvancedOptions;
                  });
                },
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: AppTokens.minTouchTarget),
                  child: Row(
                    children: [
                      Icon(
                        _showAdvancedOptions
                            ? AppIcons.chevronUp
                            : AppIcons.chevronDown,
                        size: 20,
                        color: colors.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Advanced options',
                          style: AppTypography.footnote.copyWith(
                            color: colors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showAdvancedOptions) ...[
                const SizedBox(height: 8),
                Text(
                  'Calendar URL:',
                  style: AppTypography.footnote.copyWith(
                      color: colors.muted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _UrlBox(
                  url: _httpsUrl ?? _subscriptionUrl!,
                  onCopy: () =>
                      _copyUrlToClipboard(_httpsUrl ?? _subscriptionUrl!),
                ),
                const SizedBox(height: 12),
                AppSecondaryButton(
                  onPressed: _regenerateToken,
                  icon: AppIcons.retry,
                  label: 'Regenerate link',
                  large: false,
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
                icon: const Icon(AppIcons.calendar, size: 18),
                label: const Text('Subscribe now'),
              ),
            ],
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    final colors = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: colors.surfaceQuiet,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: AppTypography.footnote.copyWith(
                color: colors.ink,
                fontWeight: FontWeight.w700,
                height: 1,
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
              style: AppTypography.subheadline.copyWith(color: colors.ink),
            ),
          ),
        ),
      ],
    );
  }
}

/// Error tokens box for a failed load or action.
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(AppTokens.controlRadius),
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
                  message,
                  style:
                      AppTypography.subheadline.copyWith(color: colors.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Monospace URL on a grey tile with a copy button.
class _UrlBox extends StatelessWidget {
  const _UrlBox({required this.url, required this.onCopy});

  final String url;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return DecoratedBox(
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
                url,
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
              icon: const Icon(AppIcons.copy, size: 20),
              onPressed: onCopy,
              tooltip: 'Copy URL',
            ),
          ],
        ),
      ),
    );
  }
}
