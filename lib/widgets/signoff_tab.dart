import 'dart:async';
import 'dart:io';

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
    Scrollable.maybeOf(target)?.position.ensureVisible(
          renderObject,
          duration: const Duration(milliseconds: 400),
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
    return SingleChildScrollView(
      key: const PageStorageKey('school-signoff'),
      primary: true,
      padding: EdgeInsets.fromLTRB(
        AppTokens.gutter,
        16,
        AppTokens.gutter,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOverviewCard(
            showForm: showForm,
            signatureStatusLoading: signatureStatusLoading,
            signatureStatusUnavailable: signatureStatusUnavailable,
          ),
          const SizedBox(height: AppTokens.sectionGap),
          _buildNotesCard(),
          const SizedBox(height: AppTokens.sectionGap),
          _buildSignOffCard(signed, pending, uploads?.activeId),
          if (legacy != null) ...[
            const SizedBox(height: 16),
            AppPanel(
              child: ExpansionTile(
                title: const Text('Earlier school sign-off'),
                subtitle: const Text('No delivery visit was recorded'),
                children: [_buildCompletedSignOff(legacy)],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewCard({
    required bool showForm,
    required bool signatureStatusLoading,
    required bool signatureStatusUnavailable,
  }) {
    final schoolTotalAsync = ref.watch(schoolTotalProvider(widget.schoolId));
    final schoolConsumablesTotalsAsync =
        ref.watch(schoolConsumablesTotalsProvider(widget.schoolId));

    final typography = Theme.of(context).textTheme;
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeading(
            title: 'Delivery Overview',
            trailing: IconButton(
              onPressed: _refreshTotals,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ),
          if (widget.deliveryId != null && signatureStatusUnavailable)
            const Text(
                'Signature status unavailable. Saved work may need attention.')
          else if (widget.deliveryId != null && signatureStatusLoading)
            const Text('Checking signature status…')
          else if (showForm)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: _openCapture,
                icon: const Icon(Icons.draw_outlined),
                label: const Text('Capture signature'),
              ),
            ),
          const Divider(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Expected pack total'),
              schoolTotalAsync.when(
                data: (total) => Text(
                  '$total',
                  style: typography.headlineMedium
                      ?.copyWith(color: AppTone.blue.inkFor(context)),
                ),
                loading: () => const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, __) => const Text('Pack total unavailable'),
              ),
            ],
          ),
          schoolConsumablesTotalsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Loading consumables totals…'),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Consumables totals unavailable'),
            ),
            data: (totals) {
              if (totals.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Consumables Totals', style: typography.titleMedium),
                    const SizedBox(height: 8),
                    for (final entry in totals.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Text(entry.key)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${entry.value.quantity} ${entry.value.unit}',
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildDeliveryBreakdown(),
        ],
      ),
    );
  }

  Widget _buildDeliveryBreakdown() {
    final yearLevelsAsync = ref.watch(yearLevelsProvider(widget.schoolId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Classroom Totals',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        yearLevelsAsync.when(
          data: (yearLevels) => yearLevels.isEmpty
              ? const Text('No year levels found')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final yearLevel in yearLevels)
                      _buildYearLevelGroup(yearLevel),
                  ],
                ),
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Couldn’t load year levels'),
        ),
      ],
    );
  }

  Widget _buildYearLevelGroup(YearLevel yearLevel) {
    final classroomsAsync = ref.watch(classroomsProvider(
      (schoolId: widget.schoolId, yearLevelId: yearLevel.id),
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 20),
        Text(
          yearLevel.label,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        classroomsAsync.when(
          data: (classrooms) => classrooms.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No classrooms found'),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < classrooms.length; index++) ...[
                      if (index > 0) const Divider(height: 1),
                      _buildClassroomRow(classrooms[index], yearLevel.id),
                    ],
                  ],
                ),
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Couldn’t load classrooms'),
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

    final typography = Theme.of(context).textTheme;
    final notes = notesAsync.asData?.value;
    final breakdowns = breakdownsAsync.asData?.value;

    return consumablesAsync.when(
      data: (consumables) {
        final allConsumablesDelivered = consumables.every(
          (item) => item.actualQuantityDelivered == item.quantity,
        );
        final (status, icon, tone) = switch (classroom.completionStatus) {
          ClassroomCompletionStatus.notAttended => (
              'Not Attended',
              Icons.remove_circle_outline,
              AppTone.neutral
            ),
          ClassroomCompletionStatus.complete when allConsumablesDelivered => (
              'Complete',
              Icons.check_circle_outline,
              AppTone.green
            ),
          _ => ('Incomplete', Icons.warning_amber_rounded, AppTone.yellow),
        };
        final actual = classroom.actualPacksDelivered;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(classroom.name, style: typography.titleMedium),
                  AppStatusPill(label: status, icon: icon, tone: tone),
                ],
              ),
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
                style: typography.bodyMedium,
              ),
              if (breakdowns != null && breakdowns.length > 1)
                Text(
                  'Composite · ${breakdowns.map((item) => '${item.yearLevelLabel}: ${item.studentCount}').join(' · ')}',
                  style: typography.bodySmall,
                ),
              if (notes != null && notes.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _scrollToNote(yearLevelId, classroom.id),
                  icon: const Icon(Icons.notes_outlined),
                  label: const Text('View notes'),
                ),
              if (consumables.isNotEmpty) ...[
                const Divider(height: 16),
                for (final item in consumables)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_getConsumableIcon(item.itemName),
                            size: 16, color: AppTone.blue.inkFor(context)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(item.itemName)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            item.actualQuantityDelivered == null
                                ? '${item.quantity} ${item.unit} expected'
                                : '${item.actualQuantityDelivered} / ${item.quantity} ${item.unit}',
                            textAlign: TextAlign.end,
                            style: typography.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (classroom.lastUpdatedBy != null &&
                  classroom.lastUpdatedAt != null) ...[
                const Divider(height: 16),
                Text(
                  'Last updated by ${classroom.lastUpdatedBy} on ${DateTimeUtils.formatDateTime(classroom.lastUpdatedAt!)}',
                  style: typography.bodySmall
                      ?.copyWith(color: AppPalette.of(context).muted),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => Text('Error loading classroom: ${classroom.name}'),
    );
  }

  Widget _buildNotesCard() {
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

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeading(title: 'Classroom Notes'),
          const SizedBox(height: 12),
          if (loading) const Text('Loading classroom notes…'),
          if (unavailable) const Text('Some classroom notes are unavailable.'),
          if (sections.isEmpty && !loading && !unavailable)
            const Text('No classroom notes recorded.'),
          ...sections,
        ],
      ),
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

    final typography = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 12),
          Text(
            '$yearLevelLabel – ${classroom.name}',
            style: typography.titleMedium,
          ),
          if (classroom.lastUpdatedBy != null &&
              classroom.lastUpdatedAt != null)
            Text(
              'Last updated by ${classroom.lastUpdatedBy} on ${DateTimeUtils.formatDateTime(classroom.lastUpdatedAt!)}',
              style: typography.bodySmall,
            ),
          for (final (index, note) in notes.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.content, key: index == 0 ? _noteKeys[key] : null),
                  if (note.author != null)
                    Text('by ${note.author}', style: typography.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSignOffCard(
    AsyncValue<SignedEvidence?> signed,
    EvidenceUpload? pending,
    String? activeId,
  ) {
    final latest = signed.valueOrNull;
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pending != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppStatusPill(
                  label: 'Signature saved on this device',
                  icon: Icons.cloud_upload_outlined,
                  tone: AppTone.blue,
                ),
                const SizedBox(height: 8),
                Text(pending.id == activeId ? 'Syncing' : pending.statusText),
                if (pending.id != activeId)
                  EvidenceUploadActions(item: pending),
              ],
            ),
          if (latest != null && !_isCorrecting) _buildSignedEvidence(latest),
          if (widget.deliveryId == null && latest == null && pending == null)
            const Text('Open a scheduled delivery to create a sign-off.'),
          if (signed.hasError)
            const Text('Could not load earlier signed snapshots.'),
          if (pending == null && _isCorrecting)
            TextButton(
              onPressed: () => setState(() => _isCorrecting = false),
              child: const Text('Cancel correction'),
            ),
          TextButton.icon(
            onPressed: _showSignOffHistory,
            icon: const Icon(Icons.history),
            label: const Text('Recent signed snapshots'),
          ),
        ],
      ),
    );
  }

  Widget _buildSignedEvidence(SignedEvidence evidence) {
    final reviewed = evidence.snapshot.serverReviewed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          reviewed ? 'Signed snapshot' : 'Synced signature needs review',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          '${evidence.typedName} · ${DateTimeUtils.formatDateTime(evidence.capturedAt.toLocal())}',
        ),
        Text(reviewed
            ? 'Covers the delivery details reviewed at signing.'
            : 'Captured with incomplete or cached delivery details. Sign again after review.'),
        ref.watch(_signatureUrlProvider(evidence.signaturePath)).when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Signature image unavailable'),
              data: (url) => url == null
                  ? const Text('Signature image unavailable')
                  : Image.network(
                      url,
                      height: 90,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Text('Signature image unavailable'),
                    ),
            ),
        Wrap(
          spacing: 8,
          children: [
            if (reviewed)
              OutlinedButton.icon(
                onPressed: () => _exportSummary(evidence: evidence),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Export snapshot'),
              ),
            if (widget.deliveryId != null)
              TextButton(
                onPressed: () => setState(() => _isCorrecting = true),
                child: const Text('Sign a correction'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _showSignOffHistory() async {
    final repository = ref.read(baseSchoolsRepositoryProvider);
    final history = repository
        .readSignOffHistory(widget.schoolId, widget.deliveryId)
        .timeout(const Duration(seconds: 12));
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recent signed snapshots'),
        content: FutureBuilder<List<SignedEvidence>>(
          future: history,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Could not load history. Try again.');
            }
            final records = snapshot.data;
            if (records == null) return const LinearProgressIndicator();
            if (records.isEmpty) {
              return const Text('No signed snapshots found.');
            }
            return SizedBox(
              width: 380,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final evidence in records)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(evidence.typedName),
                      subtitle: Text(
                        '${DateTimeUtils.formatDateTime(evidence.capturedAt.toLocal())}'
                        '${evidence.snapshot.serverReviewed ? '' : ' · Review required'}',
                      ),
                      trailing: evidence.snapshot.serverReviewed
                          ? IconButton(
                              tooltip: 'Export snapshot',
                              onPressed: () {
                                Navigator.of(context).pop();
                                _exportSummary(evidence: evidence);
                              },
                              icon: const Icon(Icons.download_outlined),
                            )
                          : null,
                    ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedSignOff(SignOff signOff) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: AppTone.green.inkFor(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'School-level record',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTone.green.inkFor(context),
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.person, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Signed by:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(signOff.typedName),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.access_time, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Signed at:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(DateTimeUtils.formatDateTime(signOff.createdAt)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: 2.5,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppPalette.of(context).muted),
              borderRadius: BorderRadius.circular(AppTokens.controlRadius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.controlRadius),
              child: Image.network(
                signOff.signatureURL,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (_, __, ___) =>
                    const Center(child: Text('Signature image unavailable')),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Export Summary Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _exportSummary,
            icon: const Icon(Icons.table_chart),
            label: const Text('Export to Excel'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  /// Returns an appropriate icon based on the consumable item name
  IconData _getConsumableIcon(String itemName) {
    final lowerName = itemName.toLowerCase();

    if (lowerName.contains('headphone') || lowerName.contains('earphone')) {
      return Icons.headphones;
    } else if (lowerName.contains('tissue')) {
      return Icons.inbox;
    } else if (lowerName.contains('paper')) {
      return Icons.content_copy;
    } else if (lowerName.contains('pencil') || lowerName.contains('pen')) {
      return Icons.edit;
    } else if (lowerName.contains('glue') || lowerName.contains('adhesive')) {
      return Icons.format_paint;
    } else if (lowerName.contains('eraser')) {
      return Icons.remove_circle_outline;
    } else if (lowerName.contains('ruler')) {
      return Icons.straighten;
    } else if (lowerName.contains('scissors')) {
      return Icons.content_cut;
    } else if (lowerName.contains('marker') || lowerName.contains('crayon')) {
      return Icons.brush;
    } else if (lowerName.contains('notebook') || lowerName.contains('book')) {
      return Icons.menu_book;
    } else if (lowerName.contains('folder') || lowerName.contains('binder')) {
      return Icons.folder;
    } else {
      // Default icon for unknown items
      return Icons.check_circle_outline;
    }
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
        builder: (context, setState) => AlertDialog(
          title: const Text('Review delivery details'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (changed) ...[
                  const Text(
                      'Delivery information changed. Review the updated details.'),
                  const SizedBox(height: 8),
                ],
                if (draft.serverReviewed)
                  Text(
                      'Data read ${DateTimeUtils.formatDateTime(draft.sourceReadAt.toLocal())}.')
                else
                  const Text(
                    'Some delivery information is cached or unavailable. '
                    'This signature will need another review after syncing.',
                  ),
                const SizedBox(height: 12),
                if (schoolNotes?.isNotEmpty == true) ...[
                  Text('School notes',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(schoolNotes!),
                  const SizedBox(height: 8),
                ],
                if (photoCount > 0 || photosChanged) ...[
                  Text('$photoCount classroom photo attachments'),
                  if (photosChanged)
                    const Text(
                      'Photo attachments changed. Return to the classroom to inspect them.',
                    ),
                  const SizedBox(height: 8),
                ],
                if (draft.classrooms.isEmpty)
                  const Text(
                      'No classroom quantities are available in this snapshot.')
                else ...[
                  Text(
                    '${draft.classrooms.length} classrooms · ${draft.totalPacks} expected packs',
                  ),
                  for (final row in draft.classrooms)
                    _buildSnapshotClassroom(row as Map, notesByRoom),
                ],
                for (final item in checklist)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
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
              child: Text(
                  draft.serverReviewed ? 'Save signature' : 'Save for review'),
            ),
          ],
        ),
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

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('$level · $name'),
      subtitle: Text(
        '$status\n$expected · ${actual == null ? 'No recorded pack count' : '$actual recorded packs'}',
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(note as String),
          ),
        for (final item in (row['consumables'] as Map).values)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(item['itemName'] as String),
            subtitle: Text(
              '${item['actualQuantityDelivered'] ?? 'Unrecorded'} '
              'of ${item['expectedQuantity']} ${item['unit']}',
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
        title: const Text('Export Successful'),
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
            icon: Icon(Platform.isIOS ? Icons.share : Icons.open_in_new),
            label: Text(Platform.isIOS ? 'Share File' : 'Open File'),
          ),
        ],
      ),
    );
  }
}

class _SignatureCaptureScreen extends StatefulWidget {
  const _SignatureCaptureScreen({
    required this.schoolName,
    required this.visitId,
    required this.visitDate,
    required this.name,
    required this.signature,
    required this.onReview,
  });

  final String schoolName;
  final String visitId;
  final DateTime? visitDate;
  final TextEditingController name;
  final SignatureController signature;
  final Future<bool> Function(BuildContext context) onReview;

  @override
  State<_SignatureCaptureScreen> createState() =>
      _SignatureCaptureScreenState();
}

class _SignatureCaptureScreenState extends State<_SignatureCaptureScreen> {
  bool _reviewing = false;

  Future<void> _reviewAndSave(BuildContext captureContext) async {
    if (_reviewing) return;
    FocusScope.of(context).unfocus();
    setState(() => _reviewing = true);
    final saved = await widget.onReview(captureContext);
    if (!mounted) return;
    setState(() => _reviewing = false);
    if (saved && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final typography = Theme.of(context).textTheme;
    final colors = AppPalette.of(context);
    final visitDate = widget.visitDate;
    return PopScope(
      canPop: !_reviewing,
      child: ScaffoldMessenger(
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            toolbarHeight: MediaQuery.textScalerOf(context).scale(16) * 2 + 32,
            titleSpacing: 8,
            title: TextButton.icon(
              onPressed: _reviewing ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to review'),
            ),
          ),
          body: Builder(
              builder: (captureContext) => SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppTokens.gutter),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  'Capture signature',
                                  style: typography.headlineMedium,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(widget.schoolName,
                                  style: typography.titleMedium),
                              Text(
                                visitDate == null
                                    ? 'Delivery visit'
                                    : DateTimeUtils.formatDate(visitDate),
                                style: typography.bodyMedium
                                    ?.copyWith(color: colors.muted),
                              ),
                              Text('Visit ${widget.visitId}',
                                  style: typography.bodySmall),
                              const SizedBox(height: AppTokens.sectionGap),
                              Semantics(
                                container: true,
                                child: TextField(
                                  controller: widget.name,
                                  enabled: !_reviewing,
                                  maxLength: 200,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.done,
                                  decoration:
                                      const InputDecoration(labelText: 'Name'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text('Signature', style: typography.titleMedium),
                              const SizedBox(height: 8),
                              Semantics(
                                container: true,
                                label: 'Signature drawing area',
                                child: AbsorbPointer(
                                  absorbing: _reviewing,
                                  child: AspectRatio(
                                    aspectRatio: 2,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                          AppTokens.controlRadius),
                                      child: DecoratedBox(
                                        position: DecorationPosition.foreground,
                                        decoration: BoxDecoration(
                                          border:
                                              Border.all(color: colors.outline),
                                          borderRadius: BorderRadius.circular(
                                            AppTokens.controlRadius,
                                          ),
                                        ),
                                        child: Signature(
                                          controller: widget.signature,
                                          backgroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: _reviewing
                                        ? null
                                        : widget.signature.clear,
                                    icon: const Icon(Icons.clear),
                                    label: const Text('Clear'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: _reviewing
                                        ? null
                                        : () => _reviewAndSave(captureContext),
                                    icon: _reviewing
                                        ? const SizedBox.square(
                                            dimension: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(Icons.check),
                                    label: Text(
                                      _reviewing
                                          ? 'Checking…'
                                          : 'Review and save',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )),
        ),
      ),
    );
  }
}
