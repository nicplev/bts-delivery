import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';
import 'package:uuid/uuid.dart';
import '../models/checklist_item.dart';
import '../models/delivery_visit.dart';
import '../models/offline/evidence_upload.dart';
import '../models/signoff_snapshot.dart';
import '../providers/schools_providers.dart';
import '../providers/auth_providers.dart';
import '../providers/delivery_visit_provider.dart';
import '../providers/repository_providers.dart';
import '../providers/checklist_providers.dart';
import '../providers/offline_delivery_providers.dart';
import '../services/offline/connectivity_service.dart';
import '../services/offline/evidence_upload_worker.dart';
import 'sync_status_detail_sheet.dart';
import 'delivery_visit_gate.dart';
import '../services/date_utils.dart';
import '../services/excel_export_service.dart';
import '../models/school.dart';
import 'design/design.dart';

part 'signoff/pack_progress.dart';
part 'signoff/signature_capture.dart';

final _signedEvidenceProvider = StreamProvider.autoDispose
    .family<SignedEvidence?, ({String schoolId, String? deliveryId})>(
        (ref, scope) {
  return ref
      .watch(baseSchoolsRepositoryProvider)
      .watchSignedEvidence(scope.schoolId, scope.deliveryId);
});

final _signatureUrlProvider =
    FutureProvider.autoDispose.family<String?, String>(
  (ref, path) async {
    final result =
        await ref.watch(storageRepositoryProvider).getDownloadUrl(path);
    return result.dataOrNull;
  },
);

class SignOffTab extends ConsumerStatefulWidget {
  const SignOffTab({
    super.key,
    required this.schoolId,
    required this.schoolName,
    this.deliveryId,
    this.visitDate,
  });

  final String schoolId;
  final String schoolName;
  final String? deliveryId;
  final DateTime? visitDate;

  @override
  ConsumerState<SignOffTab> createState() => _SignOffTabState();
}

class _SignOffTabState extends ConsumerState<SignOffTab> {
  final _nameController = TextEditingController();
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  final Map<String, GlobalKey> _noteKeys =
      {}; // Map of yearLevelId_classroomId -> GlobalKey
  MaterialPageRoute<void>? _captureRoute;
  DialogRoute<bool>? _reviewRoute;
  bool _isCorrecting = false;
  bool _showBreakdown = false;

  @override
  void dispose() {
    final capture = _captureRoute;
    final review = _reviewRoute;
    if (capture == null) {
      _disposeControllers();
    } else {
      // The visit gate can remove this tab while the capture is still on the
      // navigator. Keep the controllers alive through route removal.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (review?.isActive == true) review!.navigator?.removeRoute(review);
        if (capture.isActive) capture.navigator?.removeRoute(capture);
      });
      unawaited(capture.completed.whenComplete(_disposeControllers));
    }
    super.dispose();
  }

  void _disposeControllers() {
    _nameController.dispose();
    _signatureController.dispose();
  }

  void _openCapture() {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    final visit = ref.read(activeDeliveryVisitProvider);
    if (_captureRoute != null) return;
    if (uid == null || visit == null || !_canSaveCapture(uid, visit)) {
      _showError(
          'This visit is unavailable for signing. Check its saved work.');
      return;
    }

    final capture = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          if (ref.watch(authStateProvider).valueOrNull?.uid != uid) {
            return const Scaffold();
          }
          return DeliveryVisitGate(
            visit: visit,
            child: _SignatureCaptureScreen(
              schoolId: widget.schoolId,
              schoolName: widget.schoolName,
              visitId: visit.deliveryId,
              visitDate: widget.visitDate,
              name: _nameController,
              signature: _signatureController,
              onReview: (context) => _handleSignOff(context, uid, visit),
            ),
          );
        },
      ),
    );
    _captureRoute = capture;
    Navigator.of(context, rootNavigator: true).push(capture);
    unawaited(capture.completed.then((_) {
      if (mounted && identical(_captureRoute, capture)) _captureRoute = null;
    }));
  }

  void _scrollToNote(String yearLevelId, String classroomId) {
    final key = '${yearLevelId}_$classroomId';
    final globalKey = _noteKeys[key];

    _scrollToSection(globalKey?.currentContext);
  }

  void _scrollToSection(BuildContext? target) {
    if (target == null) return;
    final renderObject = target.findRenderObject();
    if (renderObject == null) return;
    // The inner position coordinates with the visit header. Scrolling the
    // outer position separately can reset the inner offset during the jump.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Scrollable.maybeOf(target)?.position.ensureVisible(
          renderObject,
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.1,
        );
  }

  @override
  Widget build(BuildContext context) {
    final legacy = ref.watch(signOffProvider(widget.schoolId)).valueOrNull;
    final signed = ref.watch(_signedEvidenceProvider((
      schoolId: widget.schoolId,
      deliveryId: widget.deliveryId,
    )));
    final uploadState = ref.watch(evidenceUploadsProvider);
    final uploads = uploadState.valueOrNull;
    final pending = _pendingSignature(uploads);
    final signatureStatusLoading = !signed.hasValue && signed.isLoading ||
        uploads == null && uploadState.isLoading;
    final signatureStatusUnavailable = signed.hasError || uploadState.hasError;
    ref.watch(activeChecklistItemsProvider);
    final showForm = widget.deliveryId != null &&
        !signatureStatusLoading &&
        !signatureStatusUnavailable &&
        pending == null &&
        (signed.valueOrNull == null || _isCorrecting);
    final latest = signed.valueOrNull;
    final record = _isCorrecting ? null : latest;
    final progress = _watchPackProgress(ref, widget.schoolId);

    final ({String label, IconData icon, VoidCallback onPressed})? primary;
    if (showForm) {
      primary = (
        label: 'Continue to signature',
        icon: AppIcons.signature,
        onPressed: _openCapture,
      );
    } else if (record != null && record.snapshot.serverReviewed) {
      // Builds an Excel file, then offers to share or open it.
      primary = (
        label: 'Export summary',
        icon: AppIcons.exportFile,
        onPressed: () => _exportSummary(evidence: record),
      );
    } else {
      primary = null;
    }
    // At large text sizes the wrapped floating label would cover most of a
    // small screen, so the action sits in the content instead.
    final inline = _largeText(context);
    final action = primary == null || inline
        ? null
        : AppGlassPrimaryButton(
            label: primary.label,
            icon: primary.icon,
            onPressed: primary.onPressed,
          );
    final inlineAction = primary == null || !inline
        ? null
        : AppPrimaryButton(
            label: primary.label,
            icon: primary.icon,
            onPressed: primary.onPressed,
          );

    final status = _buildStatusNotices(
      signed: signed,
      pending: pending,
      activeId: uploads?.activeId,
      signatureStatusLoading: signatureStatusLoading,
      signatureStatusUnavailable: signatureStatusUnavailable,
    );

    return AppFloatingActionArea(
      action: action,
      child: Builder(
        builder: (context) => SingleChildScrollView(
          key: const PageStorageKey('school-signoff'),
          primary: true,
          padding: EdgeInsets.fromLTRB(
            AppTokens.gutter,
            16,
            AppTokens.gutter,
            AppInsets.bottom(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (record != null) ...[
                _buildSignedRecord(record,
                    pending: pending, inlineAction: inlineAction),
                ..._gap(status, before: 16),
                const SizedBox(height: AppTokens.sectionGap),
                const AppSectionLabel('Current visit records'),
                const SizedBox(height: 8),
              ] else ...[
                ..._gap(status, after: 16),
                if (inlineAction != null) ...[
                  inlineAction,
                  const SizedBox(height: 16),
                ],
              ],
              _PackSummaryCard(progress: progress, onRefresh: _refreshTotals),
              const SizedBox(height: 16),
              _buildAttentionCard(progress),
              if (_showBreakdown) ...[
                const SizedBox(height: AppTokens.sectionGap),
                _buildDeliveryBreakdown(),
              ],
              _buildConsumablesTotals(),
              _buildPhotosRow(),
              const SizedBox(height: AppTokens.sectionGap),
              _buildNotesCard(),
              _buildSchoolNotes(),
              if (record == null) ...[
                const SizedBox(height: AppTokens.sectionGap),
                AppSecondaryButton(
                  label: 'View visit history',
                  icon: AppIcons.timer,
                  onPressed: _showSignOffHistory,
                ),
              ],
              if (legacy != null) ...[
                const SizedBox(height: AppTokens.sectionGap),
                AppPanel(
                  padding: EdgeInsets.zero,
                  child: AppDisclosure(
                    icon: AppIcons.signature,
                    title: 'Earlier school sign-off',
                    subtitle: 'No delivery visit was recorded',
                    children: [_buildCompletedSignOff(legacy)],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Spaces a list of notices with 12 pt between them.
  List<Widget> _gap(List<Widget> items, {double before = 0, double after = 0}) {
    if (items.isEmpty) return const [];
    return [
      if (before > 0) SizedBox(height: before),
      for (var index = 0; index < items.length; index++) ...[
        if (index > 0) const SizedBox(height: 12),
        items[index],
      ],
      if (after > 0) SizedBox(height: after),
    ];
  }

  /// Sign-off states: checking, unavailable, saved on this device, correction
  /// in progress, no scheduled delivery, history failure.
  List<Widget> _buildStatusNotices({
    required AsyncValue<SignedEvidence?> signed,
    required EvidenceUpload? pending,
    required String? activeId,
    required bool signatureStatusLoading,
    required bool signatureStatusUnavailable,
  }) {
    final latest = signed.valueOrNull;
    return [
      if (widget.deliveryId != null && signatureStatusUnavailable)
        const AppNotice.warning(
          message:
              'Signature status unavailable. Saved work may need attention.',
        )
      else if (widget.deliveryId != null && signatureStatusLoading)
        const AppNotice(
          icon: AppIcons.timer,
          message: 'Checking signature status…',
        ),
      if (pending != null) _buildPendingSignature(pending, activeId),
      if (widget.deliveryId == null && latest == null && pending == null)
        const AppNotice(
          icon: AppIcons.infoOutline,
          message: 'Open a scheduled delivery to create a sign-off.',
        ),
      if (signed.hasError)
        const AppNotice(
          icon: AppIcons.error,
          message: 'Could not load earlier signed snapshots.',
        ),
      if (pending == null && _isCorrecting)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppNotice(
              icon: AppIcons.edit,
              message: 'Signing a correction. The original record is kept.',
            ),
            const SizedBox(height: 8),
            AppSecondaryButton(
              label: 'Cancel correction',
              large: false,
              onPressed: () => setState(() => _isCorrecting = false),
            ),
          ],
        ),
    ];
  }

  static bool _largeText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(17) > 26;

  Widget _buildPendingSignature(EvidenceUpload pending, String? activeId) {
    final colors = AppPalette.of(context);
    final syncing = pending.id == activeId;
    final attention = !syncing && pending.needsAttention;
    final ink = attention ? colors.warningInk : colors.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: attention ? colors.warningTint : colors.surface,
        borderRadius: BorderRadius.circular(AppTokens.cardRadius),
        border: colors.highContrast ? Border.all(color: colors.outline) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            attention
                ? const AppIconTile.warning(icon: AppIcons.warning, size: 29)
                : const AppIconTile(icon: AppIcons.savedOnDevice, size: 29),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Signature saved on this device',
                    style: AppTypography.headline.copyWith(color: ink),
                  ),
                  Text(
                    syncing ? 'Syncing' : pending.statusText,
                    style: AppTypography.subheadline
                        .copyWith(color: attention ? ink : colors.muted),
                  ),
                ],
              ),
            ),
            if (!syncing) EvidenceUploadActions(item: pending),
          ],
        ),
      ),
    );
  }

  Widget _buildAttentionCard(_PackProgress progress) {
    final colors = AppPalette.of(context);
    final yearLevels = ref.watch(yearLevelsProvider(widget.schoolId));
    final attention = progress.rooms.where((room) => !room.complete).toList();
    final complete = progress.rooms.length - attention.length;
    final Widget? placeholder = yearLevels.when(
      data: (years) =>
          years.isEmpty ? const Text('No year levels found') : null,
      loading: () => const Text('Loading classrooms…'),
      error: (_, __) => const Text('Couldn’t load year levels'),
    );
    final completeLabel = complete == 0
        ? 'No classrooms complete yet'
        : '${_count(complete, 'classroom')} complete';
    final expanded = _showBreakdown;
    final toggle = Semantics(
      expanded: expanded,
      child: AppPressable(
        onTap: () => setState(() => _showBreakdown = !expanded),
        semanticLabel:
            '$completeLabel. ${expanded ? 'Hide' : 'Show'} all classrooms',
        excludeChildSemantics: true,
        pressedColor: colors.fill,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Icon(
                    complete == 0
                        ? AppIcons.completeOutline
                        : AppIcons.complete,
                    size: 26,
                    color: complete == 0 ? colors.inactive : colors.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(completeLabel,
                      style: AppTypography.body.copyWith(color: colors.ink)),
                ),
                const SizedBox(width: 6),
                AppDisclosureChevron(expanded: expanded),
              ],
            ),
          ),
        ),
      ),
    );

    if (placeholder != null) {
      return AppPanel(
        child: DefaultTextStyle.merge(
          style: AppTypography.body.copyWith(color: colors.muted),
          child: placeholder,
        ),
      );
    }
    return AppGroupedList(
      separatorIndent: 64,
      children: [
        for (final room in attention) _AttentionRow(room: room),
        if (progress.loading && progress.rooms.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Loading classrooms…',
                style: AppTypography.body.copyWith(color: colors.muted)),
          ),
        if (progress.rooms.isNotEmpty || !progress.loading) toggle,
      ],
    );
  }

  Widget _buildConsumablesTotals() {
    final colors = AppPalette.of(context);
    final totals = ref.watch(schoolConsumablesTotalsProvider(widget.schoolId));
    Widget message(String text) => AppPanel(
          child: Text(text,
              style: AppTypography.body.copyWith(color: colors.muted)),
        );
    final Widget? body = totals.when(
      loading: () => message('Loading consumables totals…'),
      error: (_, __) => message('Consumables totals unavailable'),
      data: (totals) => totals.isEmpty
          ? null
          : AppGroupedList(
              children: [
                for (final entry in totals.entries)
                  AppListRow(
                    title: entry.key,
                    detail: '${entry.value.quantity} ${entry.value.unit}',
                  ),
              ],
            ),
    );
    if (body == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionLabel('Consumables totals'),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }

  /// Photos attached to this visit's classrooms (count only).
  Widget _buildPhotosRow() {
    final deliveryId = widget.deliveryId;
    if (deliveryId == null) return const SizedBox.shrink();
    final years = ref.watch(yearLevelsProvider(widget.schoolId)).valueOrNull;
    if (years == null) return const SizedBox.shrink();
    var count = 0;
    var loading = false;
    var unavailable = false;
    for (final year in years) {
      final rooms = ref.watch(classroomsProvider(
        (schoolId: widget.schoolId, yearLevelId: year.id),
      ));
      loading = loading || rooms.isLoading;
      for (final room in rooms.valueOrNull ?? <Classroom>[]) {
        final photos = ref.watch(classroomPhotosProvider((
          schoolId: widget.schoolId,
          yearLevelId: year.id,
          classroomId: room.id,
          deliveryId: deliveryId,
        )));
        loading = loading || photos.isLoading;
        unavailable = unavailable || photos.hasError;
        count += photos.valueOrNull?.length ?? 0;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppGroupedList(
        separatorIndent: 57,
        children: [
          AppListRow(
            icon: AppIcons.photos,
            title: 'Photos',
            detail: unavailable
                ? 'Unavailable'
                : loading
                    ? 'Loading…'
                    : count == 0
                        ? 'None attached'
                        : '$count attached',
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryBreakdown() {
    final yearLevelsAsync = ref.watch(yearLevelsProvider(widget.schoolId));
    final colors = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppSectionLabel('All classrooms'),
        const SizedBox(height: 8),
        yearLevelsAsync.when(
          data: (yearLevels) => yearLevels.isEmpty
              ? AppPanel(
                  child: Text('No year levels found',
                      style: AppTypography.body.copyWith(color: colors.muted)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, yearLevel) in yearLevels.indexed) ...[
                      if (index > 0) const SizedBox(height: 16),
                      _buildYearLevelGroup(yearLevel),
                    ],
                  ],
                ),
          loading: () => const AppProgressBar(
              value: 0, semanticLabel: 'Loading year levels'),
          error: (_, __) => AppPanel(
            child: Text('Couldn’t load year levels',
                style: AppTypography.body.copyWith(color: colors.ink)),
          ),
        ),
      ],
    );
  }

  Widget _buildYearLevelGroup(YearLevel yearLevel) {
    final classroomsAsync = ref.watch(classroomsProvider(
      (schoolId: widget.schoolId, yearLevelId: yearLevel.id),
    ));
    final colors = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: AppYearBadge(label: yearLevel.label, size: 24),
            ),
            Expanded(child: AppSectionLabel(yearLevel.label)),
          ],
        ),
        const SizedBox(height: 8),
        classroomsAsync.when(
          data: (classrooms) => classrooms.isEmpty
              ? AppPanel(
                  child: Text('No classrooms found',
                      style: AppTypography.body.copyWith(color: colors.muted)),
                )
              : AppGroupedList(
                  separatorIndent: 50,
                  children: [
                    for (final classroom in classrooms)
                      _buildClassroomRow(classroom, yearLevel.id),
                  ],
                ),
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => AppPanel(
            child: Text('Couldn’t load classrooms',
                style: AppTypography.body.copyWith(color: colors.ink)),
          ),
        ),
      ],
    );
  }

  Widget _buildClassroomRow(Classroom classroom, String yearLevelId) {
    final packTotalAsync = ref.watch(packTotalProvider((
      schoolId: widget.schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroom.id
    )));

    final consumablesAsync = ref.watch(classroomConsumablesProvider((
      schoolId: widget.schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroom.id,
    )));

    final notesAsync = ref.watch(classroomNotesProvider((
      schoolId: widget.schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroom.id,
    )));

    final breakdownsAsync = ref.watch(yearLevelBreakdownsProvider((
      schoolId: widget.schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroom.id,
    )));

    final colors = AppPalette.of(context);
    final notes = notesAsync.asData?.value;
    final breakdowns = breakdownsAsync.asData?.value;
    final muted = AppTypography.subheadline.copyWith(color: colors.muted);

    return consumablesAsync.when(
      data: (consumables) {
        final allConsumablesDelivered = consumables.every(
          (item) => item.actualQuantityDelivered == item.quantity,
        );
        final actual = classroom.actualPacksDelivered;
        final expected = packTotalAsync.valueOrNull?.total;
        final (status, ring) = switch (classroom.completionStatus) {
          ClassroomCompletionStatus.notAttended => (
              'Not attended',
              const AppStatusRing(
                  status: AppCompletion.notStarted,
                  semanticLabel: 'Not attended'),
            ),
          ClassroomCompletionStatus.complete when allConsumablesDelivered => (
              'Complete',
              const AppStatusRing(
                  status: AppCompletion.complete, semanticLabel: 'Complete'),
            ),
          _ => (
              'Incomplete',
              AppStatusRing(
                status: AppCompletion.partial,
                progress: actual != null && expected != null && expected > 0
                    ? actual / expected
                    : 0.5,
                semanticLabel: 'Incomplete',
              ),
            ),
        };

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: ring,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(classroom.name,
                        style:
                            AppTypography.headline.copyWith(color: colors.ink)),
                    Text(status, style: muted),
                    const SizedBox(height: 4),
                    Text(
                      packTotalAsync.when(
                        data: (total) {
                          if (classroom.completionStatus ==
                                  ClassroomCompletionStatus.incomplete &&
                              actual != null) {
                            return total == null
                                ? '$actual packs delivered'
                                : '$actual of ${total.total} packs delivered';
                          }
                          return total == null
                              ? 'No pack total set'
                              : '${total.total} expected packs';
                        },
                        loading: () => 'Loading pack total…',
                        error: (_, __) => 'Pack total unavailable',
                      ),
                      style: AppTypography.body.copyWith(color: colors.ink),
                    ),
                    if (breakdowns != null && breakdowns.length > 1)
                      Text(
                        'Composite · ${breakdowns.map((item) => '${item.yearLevelLabel}: ${item.studentCount}').join(' · ')}',
                        style: muted,
                      ),
                    if (consumables.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final item in consumables)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Icon(AppIcons.consumables,
                                  size: 16, color: colors.muted),
                              Text(item.itemName,
                                  style: AppTypography.subheadline
                                      .copyWith(color: colors.ink)),
                              Text(
                                item.actualQuantityDelivered == null
                                    ? '${item.quantity} ${item.unit} expected'
                                    : '${item.actualQuantityDelivered} / ${item.quantity} ${item.unit}',
                                style: AppTypography.subheadline.copyWith(
                                    color: colors.ink,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                    if (classroom.lastUpdatedBy != null &&
                        classroom.lastUpdatedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last updated by ${classroom.lastUpdatedBy} on ${DateTimeUtils.formatDateTime(classroom.lastUpdatedAt!)}',
                        style: AppTypography.footnote
                            .copyWith(color: colors.muted),
                      ),
                    ],
                    if (notes != null && notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      AppSecondaryButton(
                        label: 'View notes',
                        icon: AppIcons.notes,
                        large: false,
                        // Full width at large text so the label can wrap.
                        expand: _largeText(context),
                        onPressed: () =>
                            _scrollToNote(yearLevelId, classroom.id),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Error loading classroom: ${classroom.name}',
            style: AppTypography.body.copyWith(color: colors.ink)),
      ),
    );
  }

  Widget _buildNotesCard() {
    final colors = AppPalette.of(context);
    final years = ref.watch(yearLevelsProvider(widget.schoolId));
    var loading = years.isLoading;
    var unavailable = years.hasError;
    final sections = <Widget>[];
    for (final year in years.valueOrNull ?? <YearLevel>[]) {
      final rooms = ref.watch(classroomsProvider((
        schoolId: widget.schoolId,
        yearLevelId: year.id,
      )));
      loading = loading || rooms.isLoading;
      unavailable = unavailable || rooms.hasError;
      for (final room in rooms.valueOrNull ?? <Classroom>[]) {
        final notes = ref.watch(classroomNotesProvider((
          schoolId: widget.schoolId,
          yearLevelId: year.id,
          classroomId: room.id,
        )));
        loading = loading || notes.isLoading;
        unavailable = unavailable || notes.hasError;
        final entries = notes.valueOrNull;
        if (entries != null && entries.isNotEmpty) {
          sections.add(_buildClassroomNoteSection(
            year.label,
            room,
            year.id,
            room.id,
            entries,
          ));
        }
      }
    }

    final messages = [
      if (loading) 'Loading classroom notes…',
      if (unavailable) 'Some classroom notes are unavailable.',
      if (sections.isEmpty && !loading && !unavailable)
        'No classroom notes recorded.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionLabel('Classroom notes'),
        const SizedBox(height: 8),
        AppGroupedList(
          separatorIndent: 64,
          children: [
            for (final message in messages)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(message,
                    style: AppTypography.body.copyWith(color: colors.muted)),
              ),
            ...sections,
          ],
        ),
      ],
    );
  }

  Widget _buildClassroomNoteSection(
    String yearLevelLabel,
    Classroom classroom,
    String yearLevelId,
    String classroomId,
    List<Note> notes,
  ) {
    if (notes.isEmpty) return const SizedBox.shrink();

    // Create or retrieve the GlobalKey for this classroom
    final key = '${yearLevelId}_$classroomId';
    _noteKeys.putIfAbsent(key, () => GlobalKey());

    final colors = AppPalette.of(context);
    final muted = AppTypography.footnote.copyWith(color: colors.muted);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // At large text the notes get the full width; the year stays in
          // words in the heading.
          if (!_largeText(context)) ...[
            AppYearBadge(label: yearLevelLabel),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '$yearLevelLabel – ${classroom.name}',
                  style: AppTypography.headline.copyWith(color: colors.ink),
                ),
                if (classroom.lastUpdatedBy != null &&
                    classroom.lastUpdatedAt != null)
                  Text(
                    'Last updated by ${classroom.lastUpdatedBy} on ${DateTimeUtils.formatDateTime(classroom.lastUpdatedAt!)}',
                    style: muted,
                  ),
                for (final (index, note) in notes.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.content,
                          key: index == 0 ? _noteKeys[key] : null,
                          style: AppTypography.body.copyWith(color: colors.ink),
                        ),
                        if (note.author != null)
                          Text('by ${note.author}', style: muted),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// General school notes (they are also part of the signed snapshot).
  Widget _buildSchoolNotes() {
    final colors = AppPalette.of(context);
    final notes = ref.watch(notesProvider(widget.schoolId));
    final Widget? body = notes.when(
      loading: () => null,
      error: (_, __) => Text('School notes unavailable',
          style: AppTypography.body.copyWith(color: colors.muted)),
      data: (notes) => notes.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, note) in notes.indexed) ...[
                  if (index > 0) const SizedBox(height: 10),
                  Text(note.content,
                      style: AppTypography.body.copyWith(color: colors.ink)),
                  if (note.author != null)
                    Text('by ${note.author}',
                        style: AppTypography.footnote
                            .copyWith(color: colors.muted)),
                ],
              ],
            ),
    );
    if (body == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionLabel('School notes'),
          const SizedBox(height: 8),
          AppPanel(child: body),
        ],
      ),
    );
  }

  /// The signed record: status line, record card, footnote and the history /
  /// correction actions. Export is the screen's floating action.
  Widget _buildSignedRecord(
    SignedEvidence evidence, {
    required EvidenceUpload? pending,
    Widget? inlineAction,
  }) {
    final colors = AppPalette.of(context);
    final reviewed = evidence.snapshot.serverReviewed;
    final signedAt =
        DateTimeUtils.formatDateTime(evidence.capturedAt.toLocal());
    // A queued signature for this visit means the newest signature is still
    // only on this device; otherwise the record came from the server.
    final savedToServer = pending == null;
    final packs = _snapshotPacks(evidence.snapshot);
    final photoCount =
        (evidence.snapshot.summary['photoUrls'] as List?)?.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            header: true,
            child: Text('Signed record',
                style: AppTypography.title2.copyWith(color: colors.ink)),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  savedToServer
                      ? AppIcons.savedToServer
                      : AppIcons.savedOnDevice,
                  size: 18,
                  color: colors.ink,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: savedToServer
                            ? 'Saved to server. '
                            : 'Signature saved on this device. ',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: colors.ink),
                      ),
                      TextSpan(text: 'Signed $signedAt'),
                    ],
                  ),
                  style:
                      AppTypography.subheadline.copyWith(color: colors.muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!reviewed) ...[
          const AppNotice.warning(
            message: 'Synced signature needs review. '
                'Captured with incomplete or cached delivery details. '
                'Sign again after review.',
          ),
          const SizedBox(height: 16),
        ],
        AppPanel(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppListRow(
                icon: AppIcons.person,
                title: 'Receiver',
                detail: evidence.typedName,
              ),
              _separator(57),
              AppListRow(
                icon: AppIcons.packs,
                title: 'Packs recorded',
                detail: packs.unavailable
                    ? 'Pack total unavailable'
                    : '${packs.recorded} of ${packs.expected}',
              ),
              if (packs.outstanding > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: AppNotice.warning(
                    message:
                        _outstandingMessage(packs.outstanding, packs.rooms),
                  ),
                ),
              _separator(57),
              AppListRow(
                icon: AppIcons.photos,
                title: 'Photos',
                detail:
                    photoCount == 0 ? 'None included' : '$photoCount included',
              ),
              _separator(57),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const AppIconTile(icon: AppIcons.signature, size: 29),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Signature',
                              style: AppTypography.body
                                  .copyWith(color: colors.ink)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _SignatureImage(
                      child: ref
                          .watch(_signatureUrlProvider(evidence.signaturePath))
                          .when(
                            loading: () => const LinearProgressIndicator(),
                            error: (_, __) =>
                                const Text('Signature image unavailable'),
                            data: (url) => url == null
                                ? const Text('Signature image unavailable')
                                : Image.network(
                                    url,
                                    height: 90,
                                    fit: BoxFit.contain,
                                    semanticLabel:
                                        'Signature of ${evidence.typedName}',
                                    errorBuilder: (_, __, ___) => const Text(
                                        'Signature image unavailable'),
                                  ),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${reviewed ? 'Covers the delivery details reviewed at signing. ' : ''}'
            'The original delivery record is kept. '
            'Corrections are added as a new signed record.',
            style: AppTypography.footnote.copyWith(color: colors.muted),
          ),
        ),
        const SizedBox(height: 16),
        if (inlineAction != null) ...[
          inlineAction,
          const SizedBox(height: 10),
        ],
        AppSecondaryButton(
          label: 'View visit history',
          icon: AppIcons.timer,
          onPressed: _showSignOffHistory,
        ),
        if (widget.deliveryId != null) ...[
          const SizedBox(height: 10),
          AppSecondaryButton(
            label: 'Sign a correction',
            icon: AppIcons.signature,
            onPressed: () => setState(() => _isCorrecting = true),
          ),
        ],
      ],
    );
  }

  Widget _separator(double indent) => Divider(
        height: 1,
        thickness: 1,
        indent: indent,
        color: AppPalette.of(context).separator,
      );

  /// Packs recorded vs expected as captured in a signed snapshot.
  ({int expected, int recorded, int outstanding, int rooms, bool unavailable})
      _snapshotPacks(SignOffSnapshot snapshot) {
    var expected = 0;
    var recorded = 0;
    var outstanding = 0;
    var rooms = 0;
    var unavailable = snapshot.classrooms.isEmpty;
    for (final row in snapshot.classrooms) {
      if (row is! Map) continue;
      if (row['expectedPacksUnavailable'] == true) unavailable = true;
      final roomExpected = (row['expectedPacks'] as num?)?.toInt() ?? 0;
      final actual = (row['actualPacksDelivered'] as num?)?.toInt();
      final roomRecorded =
          actual ?? (row['status'] == 'notAttended' ? 0 : roomExpected);
      expected += roomExpected;
      recorded += roomRecorded;
      final short = math.max(0, roomExpected - roomRecorded);
      outstanding += short;
      if (short > 0) rooms++;
    }
    return (
      expected: expected,
      recorded: recorded,
      outstanding: unavailable ? 0 : outstanding,
      rooms: rooms,
      unavailable: unavailable,
    );
  }

  Future<void> _showSignOffHistory() async {
    final repository = ref.read(baseSchoolsRepositoryProvider);
    final history = repository
        .readSignOffHistory(widget.schoolId, widget.deliveryId)
        .timeout(const Duration(seconds: 12));
    await showAppGlassSheet<void>(
      context: context,
      title: 'Recent signed snapshots',
      builder: (context) => FutureBuilder<List<SignedEvidence>>(
        future: history,
        builder: (context, snapshot) {
          final colors = AppPalette.of(context);
          Widget message(String text) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(text,
                    style: AppTypography.body.copyWith(color: colors.ink)),
              );
          if (snapshot.hasError) {
            return message('Could not load history. Try again.');
          }
          final records = snapshot.data;
          if (records == null) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(),
            );
          }
          if (records.isEmpty) {
            return message('No signed snapshots found.');
          }
          return ListView(
            shrinkWrap: true,
            children: [
              for (final evidence in records)
                AppListRow(
                  icon: evidence.snapshot.serverReviewed
                      ? AppIcons.complete
                      : AppIcons.warningOutline,
                  title: evidence.typedName,
                  subtitle:
                      '${DateTimeUtils.formatDateTime(evidence.capturedAt.toLocal())}'
                      '${evidence.snapshot.serverReviewed ? '' : ' · Review required'}',
                  trailing: evidence.snapshot.serverReviewed
                      ? IconButton(
                          tooltip: 'Export snapshot',
                          onPressed: () {
                            Navigator.of(context).pop();
                            _exportSummary(evidence: evidence);
                          },
                          icon: Icon(AppIcons.download, color: colors.ink),
                        )
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCompletedSignOff(SignOff signOff) {
    final colors = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(AppIcons.complete, color: colors.ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'School-level record',
                style: AppTypography.headline.copyWith(color: colors.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final (icon, label, value) in [
          (AppIcons.person, 'Signed by:', signOff.typedName),
          (
            AppIcons.timer,
            'Signed at:',
            DateTimeUtils.formatDateTime(signOff.createdAt)
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                AppIconTile(icon: icon, size: 29),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: AppTypography.footnote.copyWith(
                              color: colors.muted,
                              fontWeight: FontWeight.w600)),
                      Text(value,
                          style:
                              AppTypography.body.copyWith(color: colors.ink)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        _SignatureImage(
          child: AspectRatio(
            aspectRatio: 2.5,
            child: Image.network(
              signOff.signatureURL,
              fit: BoxFit.contain,
              semanticLabel: 'Signature of ${signOff.typedName}',
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
              errorBuilder: (_, __, ___) =>
                  const Center(child: Text('Signature image unavailable')),
            ),
          ),
        ),
        const SizedBox(height: 16),
        AppSecondaryButton(
          label: 'Export to Excel',
          icon: AppIcons.exportFile,
          onPressed: _exportSummary,
        ),
      ],
    );
  }

  void _refreshTotals() {
    ref.invalidate(yearLevelsProvider(widget.schoolId));
    ref.invalidate(consumablesProvider(widget.schoolId));
    ref.invalidate(classroomTotalsProvider(widget.schoolId));
    ref.invalidate(schoolTotalProvider(widget.schoolId));
    ref.invalidate(signOffProvider(widget.schoolId));
  }

  EvidenceUpload? _pendingSignature(EvidenceUploadStatus? uploads) => uploads
      ?.items
      .where((item) =>
          item.kind == EvidenceKind.signature &&
          item.schoolId == widget.schoolId &&
          item.deliveryId == widget.deliveryId)
      .firstOrNull;

  bool _canSaveCapture(String uid, DeliveryVisit visit) {
    if (!mounted ||
        visit.deliveryId != widget.deliveryId ||
        visit.schoolId != widget.schoolId ||
        ref.read(activeDeliveryVisitProvider) != visit ||
        ref.read(authRepositoryProvider).currentUser?.uid != uid ||
        ref.read(authStateProvider).valueOrNull?.uid != uid) {
      return false;
    }
    final staff = ref.read(currentStaffProvider);
    final access = ref.read(deliveryVisitReadinessProvider(visit));
    final member = staff.valueOrNull;
    final readiness = access.valueOrNull;
    final uploads = ref.read(evidenceUploadsProvider);
    final queue = uploads.valueOrNull ??
        ref.read(evidenceUploadWorkerProvider).valueOrNull?.status;
    final signed = ref.read(_signedEvidenceProvider((
      schoolId: visit.schoolId,
      deliveryId: visit.deliveryId,
    )));
    return member != null &&
        member.uid == uid &&
        !staff.hasError &&
        (member.hasManagerAccess ||
            member.assignedSchoolIds.contains(visit.schoolId)) &&
        readiness != null &&
        !access.hasError &&
        readiness.uid == uid &&
        readiness.status.canOpen(online: ref.read(isOnlineProvider)) &&
        !uploads.hasError &&
        queue != null &&
        _pendingSignature(queue) == null &&
        !signed.hasError &&
        signed.hasValue &&
        (signed.valueOrNull == null || _isCorrecting);
  }

  Future<({SignOffSnapshot snapshot, List<ChecklistItem> checklist})>
      _readSigningReview(DeliveryVisit visit) async {
    final repository = ref.read(baseSchoolsRepositoryProvider);
    final checklist = ref.read(activeChecklistItemsProvider).asData?.value;
    if (checklist != null &&
        checklist.length > SignOffSnapshot.maxReviewChecklistItems) {
      throw const _ReviewChecklistTooLarge();
    }
    SignOffSnapshot? draft;
    if (ref.read(isOnlineProvider)) {
      try {
        draft = await repository
            .readSignOffDraft(visit.schoolId,
                server: true, deliveryId: visit.deliveryId)
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        // A connection does not guarantee that the server read succeeds.
      }
    }
    if (draft == null) {
      try {
        draft = await repository
            .readSignOffDraft(visit.schoolId,
                server: false, deliveryId: visit.deliveryId)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        draft = SignOffSnapshot.incomplete(visit.schoolId);
      }
    }
    return (
      checklist: checklist ?? [],
      snapshot: SignOffSnapshot(
        sourceReadAt: draft.sourceReadAt,
        serverReviewed: draft.serverReviewed && checklist != null,
        summary: {
          ...draft.summary,
          'reviewChecklist': [
            for (final item in checklist ?? <ChecklistItem>[])
              {'id': item.id, 'title': item.title},
          ],
        },
      ),
    );
  }

  Future<bool> _handleSignOff(
    BuildContext captureContext,
    String uid,
    DeliveryVisit visit,
  ) async {
    if (!_canSaveCapture(uid, visit)) {
      _showError('This visit is no longer available for signing.',
          displayContext: captureContext);
      return false;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Please enter your name', displayContext: captureContext);
      return false;
    }
    if (_signatureController.isEmpty) {
      _showError('Please provide your signature',
          displayContext: captureContext);
      return false;
    }
    final worker = ref.read(evidenceUploadWorkerProvider).valueOrNull;
    if (worker == null) {
      _showError('Saved signatures are unavailable. Try again.',
          displayContext: captureContext);
      return false;
    }

    try {
      var review = await _readSigningReview(visit);
      var changed = false;
      var photosChanged = false;
      while (_canSaveCapture(uid, visit)) {
        if (!captureContext.mounted) return false;
        final confirmed = await _reviewSnapshot(
          captureContext,
          review.snapshot,
          review.checklist,
          changed: changed,
          photosChanged: photosChanged,
        );
        if (!confirmed ||
            !captureContext.mounted ||
            !_canSaveCapture(uid, visit)) {
          return false;
        }
        final current = await _readSigningReview(visit);
        if (!captureContext.mounted || !_canSaveCapture(uid, visit)) {
          return false;
        }
        if (!review.snapshot.hasSameReviewContent(current.snapshot) ||
            !listEquals(review.checklist, current.checklist)) {
          photosChanged = !listEquals(
            review.snapshot.summary['photoUrls'] as List?,
            current.snapshot.summary['photoUrls'] as List?,
          );
          review = current;
          changed = true;
          continue;
        }

        final signature = await _signatureController.toPngBytes();
        if (!captureContext.mounted || !_canSaveCapture(uid, visit)) {
          return false;
        }
        if (signature == null) {
          _showError('Could not capture the signature. Try again.',
              displayContext: captureContext);
          return false;
        }
        await worker.enqueueSignature(
          id: const Uuid().v4(),
          ownerUid: uid,
          schoolId: visit.schoolId,
          deliveryId: visit.deliveryId,
          bytes: signature,
          payload: {'typedName': name, 'snapshot': review.snapshot.toJson()},
        );
        if (!mounted || !captureContext.mounted) return false;
        _nameController.clear();
        _signatureController.clear();
        setState(() => _isCorrecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signature saved on this device')),
        );
        return true;
      }
      return false;
    } on _ReviewChecklistTooLarge {
      if (captureContext.mounted) {
        _showError(
          'The signing checklist exceeds ${SignOffSnapshot.maxReviewChecklistItems} items. '
          'Ask a manager to shorten it.',
          displayContext: captureContext,
        );
      }
      return false;
    } catch (_) {
      if (captureContext.mounted) {
        _showError('Could not save the signature. Your entry is still open.',
            displayContext: captureContext);
      }
      return false;
    }
  }

  Future<bool> _reviewSnapshot(
    BuildContext captureContext,
    SignOffSnapshot draft,
    List<ChecklistItem> checklist, {
    required bool changed,
    required bool photosChanged,
  }) async {
    final summary = draft.summary;
    final schoolNotes = summary['notes'] as String?;
    final notesByRoom = summary['notesByClassroom'] as Map?;
    final photoCount = (summary['photoUrls'] as List?)?.length ?? 0;
    final checked = <String>{};
    final route = DialogRoute<bool>(
      context: captureContext,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final colors = AppPalette.of(context);
          return AlertDialog(
            scrollable: true,
            title: const Text('Review delivery details'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (changed) ...[
                  const AppNotice.warning(
                    message:
                        'Delivery information changed. Review the updated details.',
                  ),
                  const SizedBox(height: 8),
                ],
                if (draft.serverReviewed)
                  Text(
                    'Data read ${DateTimeUtils.formatDateTime(draft.sourceReadAt.toLocal())}.',
                    style:
                        AppTypography.subheadline.copyWith(color: colors.muted),
                  )
                else
                  const AppNotice.warning(
                    message:
                        'Some delivery information is cached or unavailable. '
                        'This signature will need another review after syncing.',
                  ),
                const SizedBox(height: 12),
                if (schoolNotes?.isNotEmpty == true) ...[
                  const AppSectionLabel('School notes'),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(schoolNotes!,
                        style: AppTypography.body.copyWith(color: colors.ink)),
                  ),
                  const SizedBox(height: 12),
                ],
                if (photoCount > 0 || photosChanged) ...[
                  Row(
                    children: [
                      const AppIconTile(icon: AppIcons.photos, size: 29),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('$photoCount classroom photo attachments',
                            style:
                                AppTypography.body.copyWith(color: colors.ink)),
                      ),
                    ],
                  ),
                  if (photosChanged) ...[
                    const SizedBox(height: 8),
                    const AppNotice.warning(
                      message:
                          'Photo attachments changed. Return to the classroom to inspect them.',
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                if (draft.classrooms.isEmpty)
                  Text(
                      'No classroom quantities are available in this snapshot.',
                      style: AppTypography.body.copyWith(color: colors.ink))
                else ...[
                  AppSectionLabel(
                    '${draft.classrooms.length} classrooms · ${draft.totalPacks} expected packs',
                  ),
                  for (final row in draft.classrooms)
                    _buildSnapshotClassroom(row as Map, notesByRoom),
                ],
                if (checklist.isNotEmpty) const SizedBox(height: 12),
                for (final item in checklist)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: checked.contains(item.id),
                    title: Text(item.title),
                    subtitle:
                        item.subtitle == null ? null : Text(item.subtitle!),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        checked.add(item.id);
                      } else {
                        checked.remove(item.id);
                      }
                    }),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: checked.length == checklist.length
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: Text(draft.serverReviewed
                    ? 'Save signature'
                    : 'Save for review'),
              ),
            ],
          );
        },
      ),
    );
    _reviewRoute = route;
    try {
      return await Navigator.of(captureContext).push(route) ?? false;
    } finally {
      if (identical(_reviewRoute, route)) _reviewRoute = null;
    }
  }

  Widget _buildSnapshotClassroom(Map row, Map? notesByRoom) {
    final level = row['yearLevel'];
    final name = row['classroomName'];
    final notes = (notesByRoom?[level] as Map?)?[name] as List? ?? const [];
    final status = switch (row['status']) {
      'complete' => 'Complete',
      'incomplete' => 'Incomplete',
      'notAttended' => 'Not attended',
      _ => 'Unknown',
    };
    final expected = row['expectedPacksUnavailable'] == true
        ? 'Expected packs unavailable'
        : '${row['expectedPacks']} expected packs';
    final actual = row['actualPacksDelivered'];

    return AppDisclosure(
      padding: const EdgeInsets.symmetric(vertical: 8),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: AppYearBadge(label: '$level', size: 32),
      title: '$level · $name',
      subtitle:
          '$status\n$expected · ${actual == null ? 'No recorded pack count' : '$actual recorded packs'}',
      children: [
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(note as String),
          ),
        for (final item in (row['consumables'] as Map).values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['itemName'] as String,
                    style: AppTypography.subheadline
                        .copyWith(color: AppPalette.of(context).ink)),
                Text(
                  '${item['actualQuantityDelivered'] ?? 'Unrecorded'} '
                  'of ${item['expectedQuantity']} ${item['unit']}',
                  style: AppTypography.footnote
                      .copyWith(color: AppPalette.of(context).muted),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _showError(String message, {BuildContext? displayContext}) {
    final target = displayContext ?? (mounted ? context : null);
    if (target == null || !target.mounted) return;
    ScaffoldMessenger.of(target).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _exportSummary({SignedEvidence? evidence}) async {
    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppPalette.of(context).canvas,
                  ),
                ),
                const SizedBox(width: 16),
                const Text('Generating Excel file...'),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      final SignedSchoolSummary? summary;
      if (evidence != null) {
        if (!evidence.snapshot.serverReviewed) return;
        final signatureUrl = await ref
            .read(_signatureUrlProvider(evidence.signaturePath).future);
        if (signatureUrl == null) {
          _showError('Could not load the signature for export.');
          return;
        }
        summary = evidence.snapshot.export(
          evidenceId: evidence.id,
          schoolId: evidence.schoolId,
          typedName: evidence.typedName,
          capturedAt: evidence.capturedAt,
          signatureUrl: signatureUrl,
        );
      } else {
        final repository = ref.read(baseSchoolsRepositoryProvider);
        final result = await repository.getSignedSchoolSummary(widget.schoolId);
        if (result.isFailure) {
          _showError('Could not load the earlier signed summary.');
          return;
        }
        summary = result.dataOrNull;
      }
      if (summary == null) {
        _showError('No signed summary found for this school');
        return;
      }

      // Export to Excel
      debugPrint('Exporting summary to Excel...');
      final filePath = await ExcelExportService.exportSummaryToExcel(
        summary,
        snapshotReadAt: evidence?.snapshot.sourceReadAt.toLocal(),
        deliveryId: evidence?.deliveryId,
      );

      if (filePath == null) {
        _showError('Failed to create Excel file');
        return;
      }

      debugPrint('Excel file created at: $filePath');

      // Show options dialog
      if (mounted) {
        _showExportOptionsDialog(filePath, summary.schoolName);
      }
    } catch (e) {
      _showError('Could not export the signed snapshot.');
    }
  }

  void _showExportOptionsDialog(String filePath, String schoolName) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export successful'),
        content: Text(
          Platform.isIOS
              ? 'Your Excel file has been created and is ready to share.'
              : 'Your Excel file has been created. What would you like to do?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);

              // Wait a frame for dialog to fully close
              await Future.delayed(const Duration(milliseconds: 100));

              if (!mounted) return;

              try {
                // On iOS this will share, on other platforms it will try to open
                await ExcelExportService.openExcelFile(filePath, schoolName);
              } catch (e) {
                if (mounted) {
                  _showError('Could not open file: $e');
                }
              }
            },
            icon: Icon(Platform.isIOS ? AppIcons.share : AppIcons.external),
            label: Text(Platform.isIOS ? 'Share file' : 'Open file'),
          ),
        ],
      ),
    );
  }
}

class _ReviewChecklistTooLarge implements Exception {
  const _ReviewChecklistTooLarge();
}

/// White, rounded frame for a saved signature image (the image itself has a
/// white background, so the frame stays white in every theme).
class _SignatureImage extends StatelessWidget {
  const _SignatureImage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.controlRadius),
        border: Border.all(color: colors.separator),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: DefaultTextStyle.merge(
          // Fallback text sits on white in every theme.
          style: AppTypography.subheadline.copyWith(color: Colors.black87),
          child: Center(child: child),
        ),
      ),
    );
  }
}
