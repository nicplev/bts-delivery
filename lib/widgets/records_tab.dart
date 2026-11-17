import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/delivery_visit.dart';
import '../models/offline/offline_media.dart';
import '../models/school.dart';
import '../providers/auth_providers.dart';
import '../providers/delivery_visit_provider.dart';
import '../providers/offline_media_providers.dart';
import '../providers/schools_providers.dart';
import '../screens/forms/year_levels_screen.dart';
import 'classroom_record_row.dart';
import 'delivery_day_list.dart';
import 'design/design.dart';
import 'offline_media_view.dart';
import 'offline_visit_media_panel.dart';
import 'school_timer_widget.dart';

/// Visit hub › Records: pack summary (with the visit timer and offline files),
/// the school map in place (when the school has one), the year filter and one
/// list of classrooms across year levels.
class RecordsTab extends ConsumerStatefulWidget {
  const RecordsTab({super.key, required this.schoolId});

  final String schoolId;

  @override
  ConsumerState<RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends ConsumerState<RecordsTab> {
  /// 'year:<SchoolYear.name>' or 'level:<yearLevelId>'; null = no filter.
  String? _filter;

  String get _filterStorageId => 'records-year-filter-${widget.schoolId}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The tab is rebuilt when the hub switches tabs: keep the filter for the
    // life of the screen in the route's page storage.
    final stored = PageStorage.maybeOf(context)
        ?.readState(context, identifier: _filterStorageId);
    if (stored is String?) _filter = stored;
  }

  void _toggle(String key) {
    setState(() => _filter = _filter == key ? null : key);
    PageStorage.maybeOf(context)
        ?.writeState(context, _filter, identifier: _filterStorageId);
  }

  @override
  Widget build(BuildContext context) {
    final schoolId = widget.schoolId;
    final visit = ref.watch(activeDeliveryVisitProvider);
    final isVisit = visit != null;
    final canEdit = ref.watch(canEditSchoolDataProvider);
    final yearLevelsAsync = ref.watch(yearLevelsProvider(schoolId));
    final school = visit == null
        ? null
        : ref.watch(schoolByIdProvider(schoolId)).valueOrNull;
    final mapReference = school?.schoolMapStoragePath ?? school?.schoolMapUrl;

    final children = <Widget>[
      _RecordsSummary(
        schoolId: schoolId,
        isVisit: isVisit,
        footer: visit == null
            ? null
            : _VisitTools(schoolId: schoolId, visit: visit, school: school),
      ),
      if (visit != null && school != null && mapReference != null) ...[
        const SizedBox(height: 16),
        _SchoolMapCard(
          school: school,
          visit: visit,
          reference: mapReference,
        ),
      ],
      const SizedBox(height: 16),
      ...yearLevelsAsync.when(
        loading: () => const [
          AppPanel(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
        error: (_, __) => [
          AppPanel(
            child: DeliveryMessage(
              icon: AppIcons.error,
              title: 'Couldn’t load year levels',
              action: AppSecondaryButton(
                label: 'Retry',
                icon: AppIcons.retry,
                expand: false,
                large: false,
                onPressed: () => ref.invalidate(yearLevelsProvider(schoolId)),
              ),
            ),
          ),
        ],
        data: (levels) => _buildLevels(
          sortYearLevels(levels),
          isVisit: isVisit,
          canEdit: canEdit,
        ),
      ),
    ];

    return CustomScrollView(
      key: const PageStorageKey('school-records'),
      primary: true,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppTokens.gutter,
            8,
            AppTokens.gutter,
            AppInsets.bottom(context),
          ),
          sliver: SliverList.list(children: children),
        ),
      ],
    );
  }

  List<Widget> _buildLevels(
    List<YearLevel> levels, {
    required bool isVisit,
    required bool canEdit,
  }) {
    final schoolId = widget.schoolId;
    if (levels.isEmpty) {
      return [
        AppPanel(
          child: DeliveryMessage(
            icon: AppIcons.classroom,
            title: 'No year levels found',
            description: canEdit
                ? 'Add a year level, then add its classrooms.'
                : 'Classrooms appear here once the school’s year levels are set up.',
            action: canEdit
                ? AppSecondaryButton(
                    label: 'Add year level',
                    icon: AppIcons.add,
                    large: false,
                    onPressed: () =>
                        showAddYearLevelDialog(context, ref, schoolId),
                  )
                : null,
          ),
        ),
      ];
    }

    final years = <SchoolYear>[];
    final others = <YearLevel>[];
    for (final level in levels) {
      final year = SchoolYear.parse(level.label);
      if (year == null) {
        others.add(level);
      } else if (!years.contains(year)) {
        years.add(year);
      }
    }
    final keys = {
      for (final year in years) 'year:${year.name}',
      for (final level in others) 'level:${level.id}',
    };
    final filter = keys.contains(_filter) ? _filter : null;
    bool matches(YearLevel level) {
      if (filter == null) return true;
      if (filter.startsWith('level:')) return filter == 'level:${level.id}';
      return filter == 'year:${SchoolYear.parse(level.label)?.name}';
    }

    final shown = levels.where(matches).toList();
    return [
      if (levels.length > 1) ...[
        _YearFilterRow(
          years: years,
          others: others,
          selected: filter,
          onToggle: _toggle,
        ),
        const SizedBox(height: 16),
      ],
      AppPanel(
        key: const ValueKey('records-classroom-list'),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < shown.length; i++)
              _YearSection(
                key: ValueKey('records-year-${shown[i].id}'),
                schoolId: schoolId,
                level: shown[i],
                isVisit: isVisit,
                first: i == 0,
              ),
          ],
        ),
      ),
      if (isVisit || canEdit) ...[
        const SizedBox(height: 12),
        AppSecondaryButton(
          key: const ValueKey('records-manage-classrooms'),
          label: 'Manage classrooms',
          icon: AppIcons.edit,
          large: false,
          onPressed: () => showManageClassroomsSheet(context, ref, schoolId),
        ),
      ],
    ];
  }
}

/// The year chips for real year levels, followed by neutral chips for
/// specialist / composite / other year levels.
class _YearFilterRow extends StatelessWidget {
  const _YearFilterRow({
    required this.years,
    required this.others,
    required this.selected,
    required this.onToggle,
  });

  final List<SchoolYear> years;
  final List<YearLevel> others;
  final String? selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return AppYearFilter(
      years: years,
      selected: {
        for (final year in years)
          if (selected == 'year:${year.name}') year,
      },
      onToggle: (year) => onToggle('year:${year.name}'),
      extras: [
        for (final level in others)
          AppYearFilterExtra(
            id: 'level-${level.id}',
            label: level.label,
            semanticLabel: yearLevelWords(level.label),
            selected: selected == 'level:${level.id}',
            onTap: () => onToggle('level:${level.id}'),
          ),
      ],
    );
  }
}

/// The rows of one year level inside the shared classroom card. Each year
/// level watches its own classrooms stream, so it loads and fails on its own.
class _YearSection extends ConsumerWidget {
  const _YearSection({
    super.key,
    required this.schoolId,
    required this.level,
    required this.isVisit,
    required this.first,
  });

  final String schoolId;
  final YearLevel level;
  final bool isVisit;
  final bool first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = (schoolId: schoolId, yearLevelId: level.id);
    final classroomsAsync = ref.watch(classroomsProvider(params));
    final words = yearLevelWords(level.label);
    final badge = AppYearBadge(label: level.label);

    final rows = classroomsAsync.when<List<Widget>>(
      loading: () => [
        AppListRow(
          leading: badge,
          title: words,
          subtitle: 'Loading classrooms…',
          trailing: const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
      error: (_, __) => [
        AppListRow(
          leading: badge,
          title: words,
          subtitle: 'Couldn’t load classrooms',
          trailing: AppSecondaryButton(
            label: 'Retry',
            expand: false,
            large: false,
            onPressed: () => ref.invalidate(classroomsProvider(params)),
          ),
        ),
      ],
      data: (classrooms) => classrooms.isEmpty
          ? [
              AppListRow(
                leading: badge,
                title: words,
                subtitle: 'No classrooms yet',
                semanticLabel: '$words, no classrooms yet. Manage classrooms',
                onTap: () =>
                    openYearLevelClassrooms(context, ref, schoolId, level.id),
              ),
            ]
          : [
              for (final classroom in classrooms)
                ClassroomRecordRow(
                  key: ValueKey('records-classroom-${classroom.id}'),
                  schoolId: schoolId,
                  yearLevelId: level.id,
                  yearLevelLabel: level.label,
                  classroom: classroom,
                  isVisit: isVisit,
                  onTap: () => context.push(schoolWorkPath(
                    schoolId,
                    visit: ref.read(activeDeliveryVisitProvider),
                    suffix: '/year/${Uri.encodeComponent(level.id)}'
                        '/classrooms/${Uri.encodeComponent(classroom.id)}',
                  )),
                ),
            ],
    );

    final separator = Divider(
      height: 1,
      thickness: 1,
      indent: 64,
      color: AppPalette.of(context).separator,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (!first || i > 0) separator,
          rows[i],
        ],
      ],
    );
  }
}

/// "151 of 174 packs recorded" with the ink progress bar, derived from the
/// same year level / classroom / pack total streams the list watches.
class _RecordsSummary extends ConsumerWidget {
  const _RecordsSummary({
    required this.schoolId,
    required this.isVisit,
    this.footer,
  });

  final String schoolId;
  final bool isVisit;
  final Widget? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppPalette.of(context);
    final totals = _SummaryTotals.watch(ref, schoolId);

    Widget headline(String number, String rest) => Text.rich(
          TextSpan(children: [
            TextSpan(
              text: number,
              style: const TextStyle(
                fontSize: 28,
                height: 34 / 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.38,
                fontFeatures: [FontFeature.tabularFigures()],
              ).copyWith(color: colors.ink),
            ),
            TextSpan(
              text: ' $rest',
              style: AppTypography.body.copyWith(color: colors.muted),
            ),
          ]),
        );
    Widget note(String text) => Text(
          text,
          style: AppTypography.footnote.copyWith(color: colors.muted),
        );

    final content = <Widget>[];
    if (totals.loadingLevels) {
      content.add(Text('Loading records…',
          style: AppTypography.body.copyWith(color: colors.muted)));
    } else if (totals.levelsFailed) {
      content.add(Text('Records unavailable',
          style: AppTypography.body.copyWith(color: colors.muted)));
    } else if (totals.classroomsLoading) {
      content.add(Text('Loading classrooms…',
          style: AppTypography.body.copyWith(color: colors.muted)));
    } else if (totals.classrooms == 0) {
      content.add(Text(
          totals.classroomsFailed
              ? 'Classrooms unavailable'
              : 'No classrooms yet',
          style: AppTypography.body.copyWith(color: colors.muted)));
    } else if (!isVisit) {
      if (totals.packsKnown) {
        content
          ..add(headline('${totals.expected}', 'expected packs'))
          ..add(const SizedBox(height: 4))
          ..add(note(
              '${totals.classrooms} classroom${totals.classrooms == 1 ? '' : 's'}'));
      } else {
        content
          ..add(headline('${totals.classrooms}',
              'classroom${totals.classrooms == 1 ? '' : 's'}'))
          ..add(const SizedBox(height: 4))
          ..add(note(totals.partialReason));
      }
    } else if (totals.packsKnown && totals.expected > 0) {
      content
        ..add(headline(
            '${totals.recorded}', 'of ${totals.expected} packs recorded'))
        ..add(const SizedBox(height: 10))
        ..add(AppProgressBar(
          value: totals.recorded / totals.expected,
          semanticLabel: 'Packs recorded',
        ));
    } else {
      // Pack totals are not all known: report classrooms instead of
      // inventing a pack number.
      content
        ..add(headline('${totals.complete}',
            'of ${totals.classrooms} classrooms complete'))
        ..add(const SizedBox(height: 10))
        ..add(AppProgressBar(
          value: totals.complete / totals.classrooms,
          semanticLabel: 'Classrooms complete',
        ))
        ..add(const SizedBox(height: 8))
        ..add(note(totals.partialReason));
    }

    return AppPanel(
      key: const ValueKey('records-summary'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: content,
            ),
          ),
          if (footer != null) ...[
            Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              color: colors.separator,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
              child: footer,
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryTotals {
  bool loadingLevels = false;
  bool levelsFailed = false;
  bool classroomsLoading = false;
  bool classroomsFailed = false;
  bool packsLoading = false;
  bool packsFailed = false;
  int classrooms = 0;
  int complete = 0;
  int expected = 0;
  int recorded = 0;

  bool get packsKnown => !classroomsFailed && !packsLoading && !packsFailed;

  String get partialReason {
    if (classroomsFailed) return 'Some year levels couldn’t load.';
    if (packsLoading) return 'Loading pack totals…';
    if (packsFailed) return 'Some pack totals are unavailable.';
    return 'No pack totals set.';
  }

  /// Watches the streams the classroom list already uses (Riverpod shares
  /// them, so nothing is queried twice).
  static _SummaryTotals watch(WidgetRef ref, String schoolId) {
    final totals = _SummaryTotals();
    final levelsAsync = ref.watch(yearLevelsProvider(schoolId));
    final levels = levelsAsync.valueOrNull;
    if (levels == null) {
      if (levelsAsync.hasError) {
        totals.levelsFailed = true;
      } else {
        totals.loadingLevels = true;
      }
      return totals;
    }
    for (final level in levels) {
      final roomsAsync = ref.watch(
          classroomsProvider((schoolId: schoolId, yearLevelId: level.id)));
      final rooms = roomsAsync.valueOrNull;
      if (rooms == null) {
        if (roomsAsync.hasError) {
          totals.classroomsFailed = true;
        } else {
          totals.classroomsLoading = true;
        }
        continue;
      }
      for (final room in rooms) {
        totals.classrooms++;
        if (room.completionStatus == ClassroomCompletionStatus.complete) {
          totals.complete++;
        }
        final packAsync = ref.watch(packTotalProvider((
          schoolId: schoolId,
          yearLevelId: level.id,
          classroomId: room.id,
        )));
        if (packAsync.hasError) {
          totals.packsFailed = true;
          continue;
        }
        if (!packAsync.hasValue) {
          totals.packsLoading = true;
          continue;
        }
        final expected = packAsync.value?.total ?? 0;
        totals.expected += expected;
        totals.recorded += switch (room.completionStatus) {
          ClassroomCompletionStatus.complete => expected,
          ClassroomCompletionStatus.incomplete =>
            room.actualPacksDelivered ?? 0,
          ClassroomCompletionStatus.notAttended => 0,
        };
      }
    }
    return totals;
  }
}

/// The visit timer (one row) and the offline files entry under the summary.
class _VisitTools extends StatelessWidget {
  const _VisitTools({
    required this.schoolId,
    required this.visit,
    required this.school,
  });

  final String schoolId;
  final DeliveryVisit visit;
  final School? school;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        SchoolTimerWidget(schoolId: schoolId),
        if (school != null)
          OfflineVisitMediaPanel(visit: visit, school: school!),
      ],
    );
  }
}

/// Records › "School map": the map in place under the summary, expanded by
/// default. The header row collapses it to a single 44 pt row; the glass
/// control on the map enlarges it in place. Both choices last for the life
/// of the screen (page storage), so they survive switching tabs.
class _SchoolMapCard extends ConsumerStatefulWidget {
  const _SchoolMapCard({
    required this.school,
    required this.visit,
    required this.reference,
  });

  final School school;
  final DeliveryVisit visit;
  final String reference;

  @override
  ConsumerState<_SchoolMapCard> createState() => _SchoolMapCardState();
}

class _SchoolMapCardState extends ConsumerState<_SchoolMapCard> {
  bool _expanded = true;
  bool _enlarged = false;
  final _mapKey = GlobalKey();

  String get _expandedId => 'records-school-map-expanded-${widget.school.id}';
  String get _enlargedId => 'records-school-map-enlarged-${widget.school.id}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final storage = PageStorage.maybeOf(context);
    final expanded = storage?.readState(context, identifier: _expandedId);
    if (expanded is bool) _expanded = expanded;
    final enlarged = storage?.readState(context, identifier: _enlargedId);
    if (enlarged is bool) _enlarged = enlarged;
  }

  void _setExpanded(bool value) {
    setState(() => _expanded = value);
    PageStorage.maybeOf(context)
        ?.writeState(context, value, identifier: _expandedId);
  }

  void _setEnlarged(bool value) {
    setState(() => _enlarged = value);
    PageStorage.maybeOf(context)
        ?.writeState(context, value, identifier: _enlargedId);
    if (!value) return;
    // Bring the enlarged map to the top of the list once it has grown.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Future<void>.delayed(
      reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
      () {
        final target = _mapKey.currentContext;
        if (!mounted || !_enlarged || target == null || !target.mounted) {
          return;
        }
        final scrollable = Scrollable.maybeOf(target);
        final box = target.findRenderObject();
        final viewport = scrollable?.context.findRenderObject();
        if (scrollable == null || box is! RenderBox || viewport is! RenderBox) {
          return;
        }
        // Measured by hand: ensureVisible inside a NestedScrollView only
        // moves the outer (header) scroll.
        final position = scrollable.position;
        final offset = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
        final to = (position.pixels + offset)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
        if (reduceMotion) {
          position.jumpTo(to);
        } else {
          position.animateTo(to,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final visit = widget.visit;
    final asset = OfflineMediaAsset.schoolMap(
      bucket: ref.watch(offlineMediaBucketProvider),
      schoolId: widget.school.id,
      reference: widget.reference,
      visit: visit,
    );
    final header = Semantics(
      button: true,
      expanded: _expanded,
      child: AppPressable(
        key: const ValueKey('records-school-map-toggle'),
        onTap: () => _setExpanded(!_expanded),
        semanticLabel: 'School map',
        excludeChildSemantics: true,
        pressedColor: colors.fill,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: AppTokens.minTouchTarget),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 14, 8),
            child: Row(
              children: [
                Icon(AppIcons.map, size: 20, color: colors.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'School map',
                    style: AppTypography.subheadline.copyWith(
                        color: colors.ink, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                AppDisclosureChevron(expanded: _expanded),
              ],
            ),
          ),
        ),
      ),
    );
    return AppPanel(
      key: const ValueKey('records-school-map'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (_expanded) ...[
            if (asset == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  'This school map cannot be opened from its saved reference',
                  style:
                      AppTypography.subheadline.copyWith(color: colors.muted),
                ),
              )
            else ...[
              // Saved-copy state and the earlier saved map, as on Info.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: OfflineMediaDownloadStatus(asset: asset),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: OfflineEarlierMapButton(
                  visit: visit,
                  currentMap: asset,
                  padding: const EdgeInsets.only(bottom: 8),
                ),
              ),
              KeyedSubtree(
                key: _mapKey,
                child: OfflineMapViewer(
                  key: const ValueKey('records-map-viewer'),
                  asset: asset,
                  height: 220,
                  enlarged: _enlarged,
                  onEnlargedChanged: _setEnlarged,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
