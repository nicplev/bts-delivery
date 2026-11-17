import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../providers/auth_providers.dart';
import '../../providers/deliveries_providers.dart';
import '../../providers/calendar_sync_providers.dart';
import '../../services/offline/connectivity_service.dart';
import '../../widgets/connectivity_indicator.dart';
import '../../widgets/deliveries_calendar_view.dart';
import '../../widgets/delivery_day_list.dart';
import '../../widgets/design/design.dart';
import '../../widgets/calendar_subscription_dialog.dart';

class DeliveriesScreen extends ConsumerStatefulWidget {
  const DeliveriesScreen({super.key});

  @override
  ConsumerState<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends ConsumerState<DeliveriesScreen> {
  bool _isRefreshing = false;
  bool _showCalendar = false;
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  late DateTime _calendarFirstDay;
  late DateTime _calendarLastDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedDay = _selectedDay = now;
    _calendarFirstDay = DateTime(now.year, now.month, now.day - 365);
    _calendarLastDay = DateTime(now.year, now.month, now.day + 365);
  }

  @override
  Widget build(BuildContext context) {
    // Administrators always see all schools. Managers can filter to their own.
    final isAdmin = ref.watch(isAdminProvider);
    final canFilter = !isAdmin && ref.watch(canViewAllDeliveriesProvider);
    final canAssignDeliveries = ref.watch(canAssignDeliveriesProvider);
    final showAllDeliveries = ref.watch(allDeliveriesProvider);
    final connectivity = ref.watch(connectivityStatusProvider).valueOrNull;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppNavBar(
        showBack: false,
        actions: [
          if (connectivity != null)
            AppGlassIconButton(
              icon: connectivity == ConnectivityStatus.offline
                  ? AppIcons.offline
                  : AppIcons.retry,
              semanticLabel: _connectionLabel(connectivity),
              tooltip: _connectionLabel(connectivity),
              loading: _isRefreshing,
              onPressed: _refreshConnectivity,
            ),
          if (canFilter)
            AppGlassMenuButton<String>(
              tooltip: showAllDeliveries
                  ? 'Filter deliveries (all schools)'
                  : 'Filter deliveries (my schools)',
              icon: AppIcons.filter,
              onSelected: (value) {
                if (value == 'toggle_filter') {
                  ref.read(allDeliveriesProvider.notifier).state =
                      !showAllDeliveries;
                }
              },
              itemBuilder: (context) => [
                appMenuItem(
                  context,
                  'toggle_filter',
                  showAllDeliveries
                      ? 'Show my deliveries'
                      : 'Show all deliveries',
                ),
              ],
            ),
          if (canAssignDeliveries)
            AppGlassIconButton(
              icon: AppIcons.add,
              iconSize: 22,
              semanticLabel: 'Add delivery',
              tooltip: 'Add delivery',
              onPressed: () => context.push('/deliveries/add'),
            ),
          AppGlassMenuButton<String>(
            tooltip: 'Delivery options',
            onSelected: (value) {
              if (value == 'subscribe') {
                _showCalendarSubscriptionDialog();
              } else if (value == 'manual_sync') {
                _showCalendarSyncDialog(context);
              }
            },
            itemBuilder: (context) => [
              appMenuItem(
                  context, 'subscribe', 'Subscribe to delivery calendar',
                  icon: AppIcons.calendar),
              appMenuItem(
                  context, 'manual_sync', 'Sync external calendar (legacy)',
                  icon: AppIcons.retry),
            ],
          ),
        ],
      ),
      body: _buildDeliveries(isAdmin),
    );
  }

  static String _connectionLabel(ConnectivityStatus status) =>
      status == ConnectivityStatus.offline
          ? 'Reconnect to WiFi'
          : 'Refresh connection';

  /// Large title, connection status and the Today / Calendar switcher; it
  /// scrolls with the content.
  Widget _header(String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppLargeTitle(title: 'Deliveries', subtitle: subtitle),
        const SizedBox(height: 8),
        const ConnectivityIndicator(),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: AppSegmentedControl<bool>(
              semanticLabel: 'Deliveries view',
              segments: const [
                AppSegment(value: false, label: 'Today'),
                AppSegment(value: true, label: 'Calendar'),
              ],
              selected: _showCalendar,
              onChanged: (value) => setState(() => _showCalendar = value),
            ),
          ),
        ),
      ],
    );
  }

  /// A staff-account state below the header.
  Widget _message(String subtitle, Widget message) => CustomScrollView(
        slivers: [
          SliverPadding(
            padding: AppInsets.scroll(context),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _header(subtitle),
                const SizedBox(height: 24),
                message,
              ]),
            ),
          ),
        ],
      );

  Widget _buildDeliveries(bool isAdmin) {
    final today = ref.watch(deliveryTodayProvider);
    final dayLine = deliveryDayLabel(today);
    if (!isAdmin) {
      final staff = ref.watch(currentStaffProvider);
      if (staff.hasError) {
        return _message(
          dayLine,
          DeliveryMessage(
            icon: AppIcons.error,
            title: 'Couldn’t load your staff account',
            action: AppSecondaryButton(
              label: 'Retry',
              icon: AppIcons.retry,
              expand: false,
              onPressed: () => ref.invalidate(currentStaffProvider),
            ),
          ),
        );
      }
      if (staff.isLoading && !staff.hasValue) {
        final isOffline = ref.watch(connectivityStatusProvider).valueOrNull ==
            ConnectivityStatus.offline;
        return _message(
          dayLine,
          isOffline
              ? const DeliveryMessage(
                  icon: AppIcons.offline,
                  title: 'Checking your saved staff account',
                  description:
                      'A connection may be needed to load your deliveries.',
                )
              : const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
        );
      }
      if (staff.valueOrNull == null) {
        return _message(
          dayLine,
          DeliveryMessage(
            icon: AppIcons.person,
            title: 'Link your staff account',
            description: 'A linked staff account is needed to view deliveries.',
            action: AppPrimaryButton(
              label: 'Link account',
              onPressed: () => context.push('/staff-link'),
            ),
          ),
        );
      }
    }

    if (_showCalendar) {
      return DeliveriesCalendarView(
        header: _header(dayLine),
        firstDay: _calendarFirstDay,
        lastDay: _calendarLastDay,
        focusedDay: _focusedDay,
        selectedDay: _selectedDay,
        format: _calendarFormat,
        onDaySelected: (selected, focused) {
          setState(() {
            _selectedDay = selected;
            _focusedDay = focused;
          });
        },
        onPageChanged: (focused) => setState(() => _focusedDay = focused),
        onFormatChanged: (format) => setState(() => _calendarFormat = format),
      );
    }

    final deliveries = ref.watch(todayDeliveriesProvider);
    final count = deliveries.asData?.value.length;
    return DeliveryDayList(
      header: _header(
        count == null ? dayLine : '$dayLine · ${deliveryVisitCount(count)}',
      ),
      date: today,
      deliveries: deliveries,
      onRetry: () => ref.invalidate(todayDeliveriesProvider),
    );
  }

  Future<void> _refreshConnectivity() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      final connectivityService = ref.read(connectivityServiceProvider);

      // Force a connectivity check
      await connectivityService.checkConnectivity();

      // Show feedback
      if (mounted) {
        final status = connectivityService.currentStatus;
        final isOnline = status == ConnectivityStatus.online;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  isOnline ? AppIcons.online : AppIcons.offline,
                  color: AppPalette.of(context).canvas,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      isOnline ? 'Connected to internet' : 'Still offline'),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(AppIcons.error,
                    size: 20, color: AppPalette.of(context).canvas),
                const SizedBox(width: 12),
                Expanded(child: Text('Error checking connection: $e')),
              ],
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _showCalendarSyncDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _CalendarSyncDialog(),
    );
  }

  Future<void> _showCalendarSubscriptionDialog() async {
    try {
      final staff = await ref.read(currentStaffProvider.future);
      if (!mounted) return;

      if (staff == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Link a staff account to subscribe to the calendar.')),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => CalendarSubscriptionDialog(staff: staff),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Couldn’t load your calendar subscription.')),
      );
    }
  }
}

class _CalendarSyncDialog extends ConsumerStatefulWidget {
  const _CalendarSyncDialog();

  @override
  ConsumerState<_CalendarSyncDialog> createState() =>
      _CalendarSyncDialogState();
}

class _CalendarSyncDialogState extends ConsumerState<_CalendarSyncDialog> {
  bool _isSyncing = false;
  String? _resultMessage;
  bool? _isSuccess;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final muted = AppTypography.footnote.copyWith(color: colors.muted);
    return AlertDialog(
      scrollable: true,
      title: const Row(
        children: [
          AppIconTile(icon: AppIcons.calendar),
          SizedBox(width: 12),
          Expanded(child: Text('Sync to Apple Calendar')),
        ],
      ),
      content: _isSyncing
          ? const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Syncing deliveries to your calendar...',
                    textAlign: TextAlign.center),
              ],
            )
          : _resultMessage != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isSuccess ?? false ? AppIcons.complete : AppIcons.error,
                      size: 48,
                      color: _isSuccess ?? false ? colors.ink : colors.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _resultMessage!,
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This will sync all your deliveries to Apple Calendar.',
                      style:
                          AppTypography.subheadline.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'A new calendar called "BTS Deliveries" will be created.',
                      style: muted,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You can view and manage these events in the Apple Calendar app.',
                      style: muted,
                    ),
                  ],
                ),
      actions: _isSyncing
          ? []
          : _resultMessage != null
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
                  FilledButton(
                    onPressed: _syncToCalendar,
                    child: const Text('Sync now'),
                  ),
                ],
    );
  }

  Future<void> _syncToCalendar() async {
    setState(() {
      _isSyncing = true;
      _resultMessage = null;
      _isSuccess = null;
    });

    try {
      final service = ref.read(calendarSyncServiceProvider);

      // Request permissions
      final hasPermissions = await service.requestPermissions();
      if (!hasPermissions) {
        setState(() {
          _isSyncing = false;
          _resultMessage =
              'Calendar permission denied. Please enable it in Settings.';
          _isSuccess = false;
        });
        return;
      }

      // Get all deliveries
      final deliveriesAsync = await ref.read(allDeliveriesListProvider.future);

      // Sync to calendar
      final result = await service.syncDeliveriesToCalendar(deliveriesAsync);

      setState(() {
        _isSyncing = false;
        _resultMessage = result.message;
        _isSuccess = result.allSucceeded ||
            (!result.allFailed && result.successCount > 0);
      });
    } catch (e) {
      setState(() {
        _isSyncing = false;
        _resultMessage = 'Failed to sync: $e';
        _isSuccess = false;
      });
    }
  }
}
