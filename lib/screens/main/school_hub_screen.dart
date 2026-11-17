import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_providers.dart';
import '../../providers/schools_providers.dart';
import '../../providers/delivery_visit_provider.dart';
import '../../services/delivery_visit_access.dart';
import '../../services/offline/connectivity_service.dart';
import '../../widgets/connectivity_indicator.dart';
import '../../widgets/design/design.dart';
import '../../widgets/delivery_day_list.dart';
import '../../widgets/records_tab.dart';
import '../../widgets/signoff_tab.dart';
import '../../widgets/info_tab.dart';
import '../forms/year_levels_screen.dart';

class SchoolHubScreen extends ConsumerStatefulWidget {
  const SchoolHubScreen({
    super.key,
    required this.schoolId,
    this.deliveryId,
    this.visitDate,
  });

  final String schoolId;
  final String? deliveryId;
  final DateTime? visitDate;

  @override
  ConsumerState<SchoolHubScreen> createState() => _SchoolHubScreenState();
}

class _SchoolHubScreenState extends ConsumerState<SchoolHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// "Tue 17 Nov 2026 · Delivery visit" (time added when the visit has one).
  String _visitSubtitle() {
    final date = widget.visitDate;
    if (date == null) return 'Delivery visit';
    final hasTime = date.hour != 0 || date.minute != 0;
    return [
      DateFormat('EEE d MMM yyyy').format(date),
      if (hasTime) DateFormat('h:mm a').format(date),
      'Delivery visit',
    ].join(' · ');
  }

  void _showOptions({required bool isVisit, required bool canEdit}) {
    showAppGlassSheet<void>(
      context: context,
      title: isVisit ? 'Visit options' : 'School options',
      builder: (sheetContext) {
        void run(void Function() action) {
          Navigator.of(sheetContext).pop();
          if (mounted) action();
        }

        return SingleChildScrollView(
          child: AppGroupedList(
            separatorIndent: 57,
            children: [
              if (canEdit)
                AppListRow(
                  key: const ValueKey('hub-option-add-year-level'),
                  icon: AppIcons.add,
                  title: 'Add year level',
                  onTap: () => run(() =>
                      showAddYearLevelDialog(context, ref, widget.schoolId)),
                ),
              AppListRow(
                key: const ValueKey('hub-option-manage-classrooms'),
                icon: AppIcons.classroom,
                title: 'Manage classrooms',
                subtitle: 'Add, rename or delete classrooms',
                onTap: () => run(() =>
                    showManageClassroomsSheet(context, ref, widget.schoolId)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVisit = widget.deliveryId != null;
    final visit = ref.watch(activeDeliveryVisitProvider);
    if (isVisit &&
        (visit?.deliveryId != widget.deliveryId ||
            visit?.schoolId != widget.schoolId)) {
      return const Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppNavBar(),
        body: Center(child: Text('Couldn’t open the records for this visit.')),
      );
    }
    final schoolProvider = schoolByIdProvider(widget.schoolId);
    final readiness = visit == null
        ? null
        : ref.watch(deliveryVisitReadinessProvider(visit)).valueOrNull?.status;
    final canEditTemplate = ref.watch(canEditSchoolDataProvider);
    final schoolAsync = ref.watch(schoolProvider);
    final offline = ref.watch(connectivityStatusProvider).valueOrNull ==
        ConnectivityStatus.offline;
    final school = schoolAsync.asData?.value;
    final showOptions = school != null && (isVisit || canEditTemplate);

    Widget message(Widget child) => Builder(
          builder: (context) => Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top,
              bottom: AppInsets.bottom(context, extra: 0),
            ),
            child: Column(
              children: [
                const ConnectivityIndicator(),
                Expanded(child: Center(child: child)),
              ],
            ),
          ),
        );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppNavBar(
        actions: [
          if (showOptions)
            AppGlassIconButton(
              key: const ValueKey('hub-options'),
              icon: AppIcons.more,
              semanticLabel: isVisit ? 'Visit options' : 'School options',
              onPressed: () =>
                  _showOptions(isVisit: isVisit, canEdit: canEditTemplate),
            ),
        ],
      ),
      body: schoolAsync.when(
        loading: () => message(
          offline
              ? const DeliveryMessage(
                  icon: AppIcons.offline,
                  title: 'Checking saved school records',
                  description:
                      'A connection may be needed to open this school.',
                )
              : const CircularProgressIndicator(),
        ),
        error: (_, __) => message(
          DeliveryMessage(
            icon: AppIcons.error,
            title: 'Couldn’t load the school',
            action: AppSecondaryButton(
              label: 'Retry',
              icon: AppIcons.retry,
              expand: false,
              large: false,
              onPressed: () {
                if (ref.read(currentStaffProvider).hasError) {
                  ref.invalidate(currentStaffProvider);
                }
                ref.invalidate(schoolProvider);
              },
            ),
          ),
        ),
        data: (school) {
          if (school == null) {
            return message(
              DeliveryMessage(
                icon: offline ? AppIcons.offline : AppIcons.school,
                title: offline
                    ? 'School unavailable offline'
                    : 'School unavailable',
                description: offline
                    ? 'Reconnect to load this school.'
                    : 'This school may no longer be assigned to your account.',
              ),
            );
          }
          final tabs = [
            isVisit ? 'Records' : 'Template',
            isVisit ? 'Sign-off' : 'History',
            'Info',
          ];
          return NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppTokens.gutter,
                    MediaQuery.paddingOf(context).top + 8,
                    AppTokens.gutter,
                    8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppLargeTitle(
                        title: school.name,
                        subtitleWidget: isVisit
                            ? _VisitSubtitle(
                                subtitle: _visitSubtitle(),
                                readiness: readiness,
                              )
                            : null,
                      ),
                      const SizedBox(height: 8),
                      const ConnectivityIndicator(),
                      const SizedBox(height: 8),
                      _HubSegmentedControl(
                        controller: _tabController,
                        labels: tabs,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // The header already clears the status bar and nav buttons.
            body: Builder(
              builder: (context) => MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    if (isVisit || canEditTemplate)
                      RecordsTab(schoolId: widget.schoolId)
                    else
                      const Center(
                        child: SingleChildScrollView(
                          primary: true,
                          child: DeliveryMessage(
                            icon: AppIcons.deliveries,
                            title: 'Open a delivery to record your visit',
                            description:
                                'Classroom records are kept separately for each scheduled delivery.',
                          ),
                        ),
                      ),
                    SignOffTab(
                      schoolId: widget.schoolId,
                      schoolName: school.name,
                      deliveryId: widget.deliveryId,
                      visitDate: widget.visitDate,
                    ),
                    InfoTab(schoolId: widget.schoolId),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Visit date line plus whether the classroom records are on this device.
class _VisitSubtitle extends StatelessWidget {
  const _VisitSubtitle({required this.subtitle, required this.readiness});

  final String subtitle;
  final DeliveryVisitReadiness? readiness;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final ready = readiness == DeliveryVisitReadiness.ready;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subtitle,
          style: AppTypography.subheadline.copyWith(color: colors.muted),
        ),
        if (readiness != null) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                ready ? AppIcons.savedOnDevice : HeroiconsOutline.cloud,
                size: 16,
                color: ready ? colors.ink : colors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ready
                      ? 'Classroom records ready on this device'
                      : 'Classroom records available while connected',
                  style: AppTypography.footnote.copyWith(color: colors.muted),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The hub's three-way switch: grey track, white selected capsule, ink label.
/// Drives the existing [TabController] (tabs still swipe).
class _HubSegmentedControl extends StatelessWidget {
  const _HubSegmentedControl({required this.controller, required this.labels});

  final TabController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Semantics(
      container: true,
      label: 'Visit section',
      explicitChildNodes: true,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => DecoratedBox(
          decoration: BoxDecoration(
            color: colors.fill,
            borderRadius: BorderRadius.circular(AppTokens.pillRadius),
            border: colors.highContrast
                ? Border.all(color: colors.outline, width: 1.5)
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: AppPressable(
                      key: ValueKey('hub-tab-$i'),
                      onTap: () => controller.animateTo(i),
                      semanticLabel: labels[i],
                      selected: controller.index == i,
                      excludeChildSemantics: true,
                      child: _segment(
                        context,
                        colors,
                        labels[i],
                        selected: controller.index == i,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    AppPalette colors,
    String label, {
    required bool selected,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? colors.surface : null,
          borderRadius: BorderRadius.circular(AppTokens.pillRadius),
          border: selected && colors.highContrast
              ? Border.all(color: colors.ink, width: 1.5)
              : null,
          boxShadow: selected && !colors.highContrast
              ? const [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Center(
            // A single word at very large text sizes scales down rather
            // than breaking mid-word.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: AppTypography.subheadline.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? colors.ink : colors.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
