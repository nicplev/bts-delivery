import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_providers.dart';
import '../../services/date_utils.dart';
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
import '../../widgets/offline_visit_media_panel.dart';
import '../../widgets/school_timer_widget.dart';

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

  @override
  Widget build(BuildContext context) {
    final isVisit = widget.deliveryId != null;
    final colors = AppPalette.of(context);
    final visit = ref.watch(activeDeliveryVisitProvider);
    if (isVisit &&
        (visit?.deliveryId != widget.deliveryId ||
            visit?.schoolId != widget.schoolId)) {
      return const Scaffold(
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

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(24) * 2 + 12,
        title: Tooltip(
          message: school?.name ?? 'School',
          excludeFromSemantics: true,
          child: Text(
            school?.name ?? 'School',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        bottom: school == null
            ? null
            : PreferredSize(
                preferredSize: Size.fromHeight(
                  MediaQuery.textScalerOf(context).scale(14) * 2 + 26,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceQuiet,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      dividerHeight: 0,
                      padding: const EdgeInsets.all(4),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                      labelColor: colors.ink,
                      unselectedLabelColor: colors.muted,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: AppTokens.panelShadow,
                      ),
                      tabs: [
                        for (final label in [
                          isVisit ? 'Records' : 'Template',
                          isVisit ? 'Sign-Off' : 'History',
                          'Info',
                        ])
                          Tab(
                            height:
                                MediaQuery.textScalerOf(context).scale(14) * 2 +
                                    10,
                            child: Text(label, textAlign: TextAlign.center),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
      body: Column(
        children: [
          const ConnectivityIndicator(),
          Expanded(
            child: schoolAsync.when(
              loading: () => Center(
                child: offline
                    ? const SingleChildScrollView(
                        child: DeliveryMessage(
                          icon: Icons.cloud_off_outlined,
                          title: 'Checking saved school records',
                          description:
                              'A connection may be needed to open this school.',
                        ),
                      )
                    : const CircularProgressIndicator(),
              ),
              error: (_, __) => Center(
                child: SingleChildScrollView(
                  child: DeliveryMessage(
                    icon: Icons.error_outline,
                    title: 'Couldn’t load the school',
                    action: TextButton(
                      onPressed: () {
                        if (ref.read(currentStaffProvider).hasError) {
                          ref.invalidate(currentStaffProvider);
                        }
                        ref.invalidate(schoolProvider);
                      },
                      child: const Text('Retry'),
                    ),
                  ),
                ),
              ),
              data: (school) {
                if (school == null) {
                  return Center(
                    child: SingleChildScrollView(
                      child: DeliveryMessage(
                        icon: offline
                            ? Icons.cloud_off_outlined
                            : Icons.school_outlined,
                        title: offline
                            ? 'School unavailable offline'
                            : 'School unavailable',
                        description: offline
                            ? 'Reconnect to load this school.'
                            : 'This school may no longer be assigned to your account.',
                      ),
                    ),
                  );
                }
                return NestedScrollView(
                  headerSliverBuilder: (context, _) => [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (isVisit)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppTokens.gutter,
                                12,
                                AppTokens.gutter,
                                4,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.visitDate == null
                                        ? 'Delivery visit'
                                        : DateTimeUtils.formatDate(
                                            widget.visitDate!),
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  if (readiness != null) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          readiness ==
                                                  DeliveryVisitReadiness.ready
                                              ? Icons.offline_pin_outlined
                                              : Icons.cloud_outlined,
                                          size: 18,
                                          color: readiness ==
                                                  DeliveryVisitReadiness.ready
                                              ? AppTone.green.inkFor(context)
                                              : colors.muted,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            readiness ==
                                                    DeliveryVisitReadiness.ready
                                                ? 'Classroom records ready on this device'
                                                : 'Classroom records available while connected',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          if (visit != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppTokens.gutter),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: OfflineVisitMediaPanel(
                                    visit: visit, school: school),
                              ),
                            ),
                          if (isVisit)
                            SchoolTimerWidget(schoolId: widget.schoolId),
                        ],
                      ),
                    ),
                  ],
                  body: TabBarView(
                    controller: _tabController,
                    children: [
                      if (isVisit || canEditTemplate)
                        RecordsTab(schoolId: widget.schoolId)
                      else
                        const Center(
                          child: SingleChildScrollView(
                            primary: true,
                            child: DeliveryMessage(
                              icon: Icons.local_shipping_outlined,
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
