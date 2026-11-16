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
    final connectivityAsync = ref.watch(connectivityStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deliveries'),
        actions: [
          // Refresh connectivity button
          connectivityAsync.when(
            data: (status) {
              final isOffline = status == ConnectivityStatus.offline;
              return IconButton(
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        isOffline ? Icons.wifi_off : Icons.refresh,
                        color: isOffline ? Colors.orange : null,
                      ),
                tooltip: isOffline ? 'Reconnect to WiFi' : 'Refresh connection',
                onPressed: _isRefreshing ? null : () => _refreshConnectivity(),
              );
            },
            loading: () => const SizedBox(width: 48),
            error: (_, __) => const SizedBox(width: 48),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Calendar options',
            onSelected: (value) {
              if (value == 'subscribe') {
                _showCalendarSubscriptionDialog();
              } else if (value == 'manual_sync') {
                _showCalendarSyncDialog(context);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'subscribe',
                child: Text('Subscribe to Calendar'),
              ),
              PopupMenuItem(
                value: 'manual_sync',
                child: Text('Manual Sync (Legacy)'),
              ),
            ],
          ),
          if (canFilter)
            PopupMenuButton<String>(
              icon: const Icon(Icons.filter_list),
              tooltip: showAllDeliveries
                  ? 'Filter deliveries (all schools)'
                  : 'Filter deliveries (my schools)',
              onSelected: (value) {
                if (value == 'toggle_filter') {
                  ref.read(allDeliveriesProvider.notifier).state =
                      !showAllDeliveries;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggle_filter',
                  child: Text(showAllDeliveries
                      ? 'Show My Deliveries'
                      : 'Show All Deliveries'),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          const ConnectivityIndicator(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.today_outlined),
                  label: Text('Today'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.calendar_month_outlined),
                  label: Text('Calendar'),
                ),
              ],
              selected: {_showCalendar},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _showCalendar = selection.single);
              },
            ),
          ),
          Expanded(child: _buildDeliveries(isAdmin)),
        ],
      ),
      floatingActionButton: canAssignDeliveries
          ? FloatingActionButton(
              onPressed: () => context.push('/deliveries/add'),
              tooltip: 'Add delivery',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildDeliveries(bool isAdmin) {
    if (!isAdmin) {
      final staff = ref.watch(currentStaffProvider);
      if (staff.hasError) {
        return Center(
          child: DeliveryMessage(
            icon: Icons.error_outline,
            title: 'Couldn’t load your staff account',
            action: TextButton(
              onPressed: () => ref.invalidate(currentStaffProvider),
              child: const Text('Retry'),
            ),
          ),
        );
      }
      if (staff.isLoading && !staff.hasValue) {
        final isOffline = ref.watch(connectivityStatusProvider).valueOrNull ==
            ConnectivityStatus.offline;
        return Center(
          child: isOffline
              ? const DeliveryMessage(
                  icon: Icons.cloud_off_outlined,
                  title: 'Checking your saved staff account',
                  description:
                      'A connection may be needed to load your deliveries.',
                )
              : const CircularProgressIndicator(),
        );
      }
      if (staff.valueOrNull == null) {
        return Center(
          child: DeliveryMessage(
            icon: Icons.link_off,
            title: 'Link your staff account',
            description: 'A linked staff account is needed to view deliveries.',
            action: FilledButton(
              onPressed: () => context.push('/staff-link'),
              child: const Text('Link account'),
            ),
          ),
        );
      }
    }

    if (_showCalendar) {
      return DeliveriesCalendarView(
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

    final today = ref.watch(deliveryTodayProvider);
    return DeliveryDayList(
      date: today,
      deliveries: ref.watch(todayDeliveriesProvider),
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
                  isOnline ? Icons.wifi : Icons.wifi_off,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(isOnline ? 'Connected to internet' : 'Still offline'),
              ],
            ),
            backgroundColor: isOnline ? Colors.green : Colors.orange,
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
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text('Error checking connection: $e'),
              ],
            ),
            backgroundColor: Colors.red,
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
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.calendar_month, size: 24),
          SizedBox(width: 12),
          Text('Sync to Apple Calendar'),
        ],
      ),
      content: _isSyncing
          ? const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Syncing deliveries to your calendar...'),
              ],
            )
          : _resultMessage != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isSuccess ?? false ? Icons.check_circle : Icons.error,
                      size: 48,
                      color: _isSuccess ?? false ? Colors.green : Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _resultMessage!,
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This will sync all your deliveries to Apple Calendar.',
                      style: TextStyle(fontSize: 15),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'A new calendar called "BTS Deliveries" will be created.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'You can view and manage these events in the Apple Calendar app.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
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
                    child: const Text('Sync Now'),
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
