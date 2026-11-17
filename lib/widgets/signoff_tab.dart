import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';
import 'package:uuid/uuid.dart';
import '../models/checklist_item.dart';
import '../models/offline/evidence_upload.dart';
import '../models/signoff_snapshot.dart';
import '../providers/schools_providers.dart';
import '../providers/repository_providers.dart';
import '../providers/checklist_providers.dart';
import '../providers/offline_delivery_providers.dart';
import '../services/offline/connectivity_service.dart';
import 'sync_status_detail_sheet.dart';
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

final _serverSigningDraftProvider = FutureProvider.autoDispose
    .family<SignOffSnapshot?, ({String schoolId, String? deliveryId})>(
        (ref, scope) {
  if (!ref.watch(isOnlineProvider)) return null;
  return ref
      .watch(baseSchoolsRepositoryProvider)
      .readSignOffDraft(scope.schoolId,
          server: true, deliveryId: scope.deliveryId)
      .timeout(const Duration(seconds: 20));
});

class SignOffTab extends ConsumerStatefulWidget {
  const SignOffTab({super.key, required this.schoolId, this.deliveryId});

  final String schoolId;
  final String? deliveryId;

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
  final _signerName = GlobalKey();
  final Map<String, GlobalKey> _noteKeys =
      {}; // Map of yearLevelId_classroomId -> GlobalKey
  bool _isUploading = false;
  bool _isCorrecting = false;

  ({String schoolId, String? deliveryId}) get _scope =>
      (schoolId: widget.schoolId, deliveryId: widget.deliveryId);

  @override
  void dispose() {
    _nameController.dispose();
    _signatureController.dispose();
    super.dispose();
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
    final uploads = ref.watch(evidenceUploadsProvider).valueOrNull;
    final pending = uploads?.items
        .where((item) =>
            item.kind == EvidenceKind.signature &&
            item.schoolId == widget.schoolId &&
            item.deliveryId == widget.deliveryId)
        .firstOrNull;
    ref.watch(activeChecklistItemsProvider);
    final showForm = widget.deliveryId != null &&
        pending == null &&
        (signed.valueOrNull == null || _isCorrecting);
    if (showForm) {
      ref.watch(_serverSigningDraftProvider(_scope));
    }

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
          _buildOverviewCard(showForm: showForm),
          const SizedBox(height: AppTokens.sectionGap),
          _buildNotesCard(),
          const SizedBox(height: AppTokens.sectionGap),
          _buildSignOffCard(signed, pending, uploads?.activeId,
              showForm: showForm),
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

  Widget _buildOverviewCard({required bool showForm}) {
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
          if (showForm)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () =>
                    _scrollToSection(_signerName.currentContext),
                icon: const Icon(Icons.arrow_downward_outlined),
                label: const Text('Go to signature'),
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
                      ?.copyWith(color: AppTone.blue.ink),
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
                            size: 16, color: AppTone.blue.ink),
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
                  style: typography.bodySmall?.copyWith(color: AppTokens.muted),
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
    final yearLevelsAsync = ref.watch(yearLevelsProvider(widget.schoolId));

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeading(title: 'Classroom Notes'),
          const SizedBox(height: 16),
          yearLevelsAsync.when(
            data: (yearLevels) {
              if (yearLevels.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text('No year levels found'),
                  ),
                );
              }

              return Column(
                children: yearLevels.map((yearLevel) {
                  return _buildYearLevelNotes(yearLevel);
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error loading notes: $error'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearLevelNotes(YearLevel yearLevel) {
    final classroomsAsync = ref.watch(classroomsProvider((
      schoolId: widget.schoolId,
      yearLevelId: yearLevel.id,
    )));

    return classroomsAsync.when(
      data: (classrooms) {
        if (classrooms.isEmpty) return const SizedBox.shrink();

        // Build widgets for classrooms with notes
        final classroomNoteWidgets = <Widget>[];

        for (final classroom in classrooms) {
          final notesAsync = ref.watch(classroomNotesProvider((
            schoolId: widget.schoolId,
            yearLevelId: yearLevel.id,
            classroomId: classroom.id,
          )));

          notesAsync.whenData((notes) {
            if (notes.isNotEmpty) {
              classroomNoteWidgets.add(_buildClassroomNoteSection(
                yearLevel.label,
                classroom,
                yearLevel.id,
                classroom.id,
                notes,
              ));
            }
          });
        }

        return Column(children: classroomNoteWidgets);
      },
      loading: () => const SizedBox.shrink(),
      error: (error, _) => const SizedBox.shrink(),
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
      key: _noteKeys[key],
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
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.content),
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
    String? activeId, {
    required bool showForm,
  }) {
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
          if (showForm) _buildSignOffForm(),
          if (widget.deliveryId == null && latest == null && pending == null)
            const Text('Open a scheduled delivery to create a sign-off.'),
          if (signed.hasError)
            const Text('Could not load earlier signed snapshots.'),
          if (pending == null && _isCorrecting)
            TextButton(
              onPressed: _isUploading
                  ? null
                  : () => setState(() => _isCorrecting = false),
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

  Widget _buildSignOffForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppSectionHeading(title: 'Sign-off'),
        const SizedBox(height: 8),
        const Text('This signature will be linked to the selected delivery.'),
        const SizedBox(height: 16),
        Semantics(
          container: true,
          child: TextField(
            key: _signerName,
            controller: _nameController,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Enter your full name',
              prefixIcon: Icon(Icons.person),
            ),
            enabled: !_isUploading,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Signature',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          label: 'Signature drawing area',
          child: AspectRatio(
            aspectRatio: 2.0,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTokens.muted),
                borderRadius: BorderRadius.circular(AppTokens.controlRadius),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.controlRadius),
                child: Stack(
                  children: [
                    Signature(
                      controller: _signatureController,
                      backgroundColor: Colors.white,
                    ),
                    if (_isUploading)
                      Container(
                        color: Colors.white.withValues(alpha: 0.7),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed:
                  _isUploading ? null : () => _signatureController.clear(),
              icon: const Icon(Icons.clear),
              label: const Text('Clear'),
            ),
            FilledButton.icon(
              onPressed: _isUploading ? null : _handleSignOff,
              icon: _isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isUploading ? 'Saving…' : 'Review and save'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompletedSignOff(SignOff signOff) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'School-level record',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
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
              border: Border.all(color: AppTokens.muted),
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
    ref.invalidate(_serverSigningDraftProvider(_scope));
  }

  Future<void> _handleSignOff() async {
    final deliveryId = widget.deliveryId;
    if (deliveryId == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Please enter your name');
      return;
    }
    if (_signatureController.isEmpty) {
      _showError('Please provide your signature');
      return;
    }
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    final worker = ref.read(evidenceUploadWorkerProvider).valueOrNull;
    if (uid == null || worker == null) {
      _showError('Saved signatures are unavailable. Try again.');
      return;
    }
    final repository = ref.read(baseSchoolsRepositoryProvider);
    final checklist = ref.read(activeChecklistItemsProvider).valueOrNull;
    setState(() => _isUploading = true);
    try {
      var draft = ref.read(isOnlineProvider)
          ? ref.read(_serverSigningDraftProvider(_scope)).asData?.value
          : null;
      if (draft == null) {
        try {
          draft = await repository.readSignOffDraft(
            widget.schoolId,
            server: false,
            deliveryId: deliveryId,
          );
        } catch (_) {
          draft = SignOffSnapshot.incomplete(widget.schoolId);
        }
      }
      final frozen = SignOffSnapshot(
        sourceReadAt: draft.sourceReadAt,
        serverReviewed: draft.serverReviewed && checklist != null,
        summary: {
          ...draft.summary,
          'reviewChecklist': [
            for (final item in checklist ?? <ChecklistItem>[])
              {'id': item.id, 'title': item.title},
          ],
        },
      );
      if (!mounted || !await _reviewSnapshot(frozen, checklist ?? [])) return;
      if (!mounted) return;
      final signature = await _signatureController.toPngBytes();
      if (signature == null) {
        _showError('Could not capture the signature. Try again.');
        return;
      }
      await worker.enqueueSignature(
        id: const Uuid().v4(),
        ownerUid: uid,
        schoolId: widget.schoolId,
        deliveryId: deliveryId,
        bytes: signature,
        payload: {'typedName': name, 'snapshot': frozen.toJson()},
      );
      if (!mounted) return;
      _nameController.clear();
      _signatureController.clear();
      setState(() => _isCorrecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signature saved on this device')),
      );
    } catch (_) {
      _showError('Could not save the signature. Your entry is still open.');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<bool> _reviewSnapshot(
      SignOffSnapshot draft, List<ChecklistItem> checklist) async {
    final checked = <String>{};
    return await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('Review delivery details'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (draft.serverReviewed)
                      Text(
                          'Data read ${DateTimeUtils.formatDateTime(draft.sourceReadAt.toLocal())}.')
                    else
                      const Text(
                        'Some delivery information is cached or unavailable. '
                        'This signature will need another review after syncing.',
                      ),
                    if (draft.classrooms.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                          '${draft.classrooms.length} classrooms · ${draft.totalPacks} expected packs recorded'),
                      for (final row in draft.classrooms)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                              '${row['yearLevel']} · ${row['classroomName']}'),
                          subtitle: Text(row['expectedPacksUnavailable'] == true
                              ? 'Expected pack count unavailable'
                              : '${row['actualPacksDelivered'] ?? 'Unrecorded'} delivered of ${row['expectedPacks']} packs'),
                          children: [
                            for (final item
                                in (row['consumables'] as Map).values)
                              ListTile(
                                dense: true,
                                title: Text(item['itemName'] as String),
                                subtitle: Text(
                                  '${item['actualQuantityDelivered'] ?? 'Unrecorded'} '
                                  'of ${item['expectedQuantity']} ${item['unit']}',
                                ),
                              ),
                          ],
                        ),
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
                  child: Text(draft.serverReviewed
                      ? 'Save signature'
                      : 'Save for review'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportSummary({SignedEvidence? evidence}) async {
    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 16),
                Text('Generating Excel file...'),
              ],
            ),
            duration: Duration(seconds: 3),
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
