import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/delivery_visit.dart';
import '../../models/offline/evidence_upload.dart';
import '../../models/offline/offline_media.dart';
import '../../models/offline/saved_edit.dart';
import '../../models/school.dart';
import '../../providers/auth_providers.dart';
import '../../providers/delivery_visit_provider.dart';
import '../../providers/offline_delivery_providers.dart';
import '../../providers/offline_media_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/saved_edit_providers.dart';
import '../../providers/schools_providers.dart';
import '../../repositories/classroom_edit.dart';
import '../../services/offline/connectivity_service.dart';
import '../../services/offline/field_draft_store.dart';
import '../../widgets/design/design.dart';
import '../../widgets/field_draft_dialog.dart';
import '../../widgets/offline_media_view.dart';
import '../../widgets/sync_status_detail_sheet.dart';

part 'classroom_detail/common.dart';
part 'classroom_detail/packs_card.dart';
part 'classroom_detail/record_packs_sheet.dart';
part 'classroom_detail/distribution_section.dart';
part 'classroom_detail/consumables_section.dart';
part 'classroom_detail/photos_section.dart';
part 'classroom_detail/notes_section.dart';

/// Classroom records: the year-coloured header, the packs card with its one
/// floating "Record packs" action, and the consumables, photos, notes and
/// student distribution work surfaces.
class ClassroomDetailScreen extends ConsumerWidget {
  const ClassroomDetailScreen({
    super.key,
    required this.schoolId,
    required this.yearLevelId,
    required this.classroomId,
    this.deliveryId,
  });

  final String schoolId;
  final String yearLevelId;
  final String classroomId;
  final String? deliveryId;

  _Room get _room => _Room(
        schoolId: schoolId,
        yearLevelId: yearLevelId,
        classroomId: classroomId,
        deliveryId: deliveryId,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = ref.watch(activeDeliveryVisitProvider);
    if (deliveryId != null &&
        (visit?.deliveryId != deliveryId || visit?.schoolId != schoolId)) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: const AppNavBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.gutter),
            child: Text(
              'Couldn’t open the records for this visit.',
              textAlign: TextAlign.center,
              style: AppTypography.body
                  .copyWith(color: AppPalette.of(context).ink),
            ),
          ),
        ),
      );
    }
    final room = _room;
    final classroomsAsync = ref.watch(classroomsProvider((
      schoolId: schoolId,
      yearLevelId: yearLevelId,
    )));
    final packTotalAsync = ref.watch(packTotalProvider(room.packKey));
    final breakdownsAsync =
        ref.watch(yearLevelBreakdownsProvider(room.packKey));
    final isAdmin = ref.watch(isAdminProvider);
    final offline = ref.watch(connectivityStatusProvider).valueOrNull ==
        ConnectivityStatus.offline;

    final classroom = classroomsAsync.valueOrNull
        ?.where((c) => c.id == classroomId)
        .firstOrNull;
    final yearLevel = ref
        .watch(yearLevelsProvider(schoolId))
        .valueOrNull
        ?.where((level) => level.id == yearLevelId)
        .firstOrNull;
    final schoolName =
        ref.watch(schoolByIdProvider(schoolId)).valueOrNull?.name;
    final composite = (breakdownsAsync.valueOrNull?.length ?? 0) > 1;
    final subtitle = [
      if (yearLevel != null) yearLevel.label,
      if (composite) 'Composite class',
      if (schoolName != null) schoolName,
    ].join(' · ');
    final canRecord = deliveryId != null && classroom != null;
    final expected = packTotalAsync.valueOrNull;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppNavBar(
        actions: [
          if (offline)
            const AppGlassStatus(label: 'Offline', icon: AppIcons.offline),
          if (isAdmin)
            AppGlassIconButton(
              icon: AppIcons.more,
              semanticLabel: 'Classroom options',
              onPressed: () => _showOptions(context, ref, expected?.total),
            ),
        ],
      ),
      body: AppFloatingActionArea(
        action: canRecord
            ? AppGlassPrimaryButton(
                key: const ValueKey('record-packs'),
                label: 'Record packs',
                onPressed: () => _showRecordPacksSheet(
                  context,
                  ref,
                  classroom: classroom,
                  yearLabel: yearLevel?.label,
                  composite: composite,
                ),
              )
            : null,
        child: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.only(bottom: AppInsets.bottom(context)),
            children: [
              AppYearHeader(
                title: classroom?.name ?? 'Classroom',
                // Composite and unknown year levels get the neutral header.
                yearLabel: composite ? '' : yearLevel?.label ?? '',
                subtitle: subtitle.isEmpty ? null : subtitle,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.gutter, 16, AppTokens.gutter, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PacksCard(
                      classroomsAsync: classroomsAsync,
                      classroom: classroom,
                      packTotalAsync: packTotalAsync,
                      showRecorded: deliveryId != null,
                      onStatusSelected: (status) {
                        if (status == ClassroomCompletionStatus.incomplete) {
                          _showRecordPacksSheet(
                            context,
                            ref,
                            classroom: classroom!,
                            yearLabel: yearLevel?.label,
                            composite: composite,
                          );
                        } else {
                          _saveClassroomStatus(context, ref, status);
                        }
                      },
                    ),
                    _DistributionSection(
                        room: room, breakdownsAsync: breakdownsAsync),
                    _ConsumablesSection(room: room),
                    _PhotosSection(room: room),
                    _NotesSection(room: room),
                    _SavedStateLine(room: room, offline: offline),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Admin-only options. Updating the expected total is deliberately a
  /// separate action from recording delivered packs.
  void _showOptions(BuildContext context, WidgetRef ref, int? currentTotal) {
    showAppGlassSheet<void>(
      context: context,
      title: 'Classroom options',
      builder: (sheetContext) => AppGroupedList(
        separatorIndent: 57,
        children: [
          AppListRow(
            icon: AppIcons.packs,
            title:
                currentTotal == null ? 'Set pack total' : 'Update pack total',
            subtitle: currentTotal == null
                ? 'Expected packs for this classroom'
                : 'Currently $currentTotal expected packs',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _showUpdatePackTotalDialog(context, ref, currentTotal);
            },
          ),
        ],
      ),
    );
  }

  void _showRecordPacksSheet(
    BuildContext context,
    WidgetRef ref, {
    required Classroom classroom,
    required String? yearLabel,
    required bool composite,
  }) {
    final expected = ref
        .read(packTotalProvider((
          schoolId: schoolId,
          yearLevelId: yearLevelId,
          classroomId: classroom.id,
        )))
        .valueOrNull
        ?.total;
    final schools = ref.read(schoolsNotifierProvider.notifier);
    showFieldDraftSheet(
      context: context,
      ref: ref,
      target: _room.draftTarget('actualPacks'),
      title: 'Record packs',
      savedLabel: 'Classroom status',
      saveLabel: 'Save packs',
      inputs: [
        FieldDraftInput(
          id: 'quantity',
          label: 'Packs delivered',
          initialText: classroom.actualPacksDelivered?.toString() ?? '',
          keyboardType: TextInputType.number,
          validator: _validateCount,
        ),
      ],
      builder: (context, fields) => _RecordPacksBody(
        fields: fields,
        classroomName: classroom.name,
        yearLabel: composite ? null : yearLabel,
        yearWords: yearLabel,
        expected: expected,
      ),
      onSave: (draft) => schools.updateClassroomStatus(
        schoolId,
        yearLevelId,
        classroomId,
        status: ClassroomCompletionStatus.incomplete,
        actualPacksDelivered: int.parse(draft.values['quantity']!.trim()),
        editId: draft.revision,
      ),
    );
  }

  Future<void> _saveClassroomStatus(
    BuildContext context,
    WidgetRef ref,
    ClassroomCompletionStatus status,
  ) async {
    final result =
        await ref.read(schoolsNotifierProvider.notifier).updateClassroomStatus(
              schoolId,
              yearLevelId,
              classroomId,
              status: status,
              actualPacksDelivered: null,
            );
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.when(
          success: (progress) =>
              fieldEditFeedback('Classroom status', progress),
          failure: (message, _) => message,
        )),
      ),
    );
  }

  void _showUpdatePackTotalDialog(
    BuildContext context,
    WidgetRef ref,
    int? currentTotal,
  ) {
    final schools = ref.read(schoolsNotifierProvider.notifier);
    showFieldDraftDialog(
      context: context,
      ref: ref,
      target: _room.draftTarget('packTotal'),
      title: currentTotal == null ? 'Set pack total' : 'Update pack total',
      savedLabel: 'Pack total',
      inputs: [
        FieldDraftInput(
          id: 'quantity',
          label: 'Number of packs',
          initialText: currentTotal?.toString() ?? '',
          keyboardType: TextInputType.number,
          validator: _validateCount,
        ),
      ],
      onSave: (draft) => schools.saveClassroomPackTotal(
        schoolId,
        yearLevelId,
        classroomId,
        int.parse(draft.values['quantity']!.trim()),
        editId: draft.revision,
      ),
    );
  }
}
