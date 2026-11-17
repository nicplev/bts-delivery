import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/date_utils.dart';
import '../../providers/season_export_providers.dart';
import '../../models/season_export_models.dart';
import '../../widgets/design/design.dart';
import 'admin_page.dart';

class SeasonExportScreen extends ConsumerStatefulWidget {
  const SeasonExportScreen({super.key});

  @override
  ConsumerState<SeasonExportScreen> createState() => _SeasonExportScreenState();
}

class _SeasonExportScreenState extends ConsumerState<SeasonExportScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  bool _useDateFilter = false;

  // Sheet options
  bool _includeOverview = true;
  bool _includeSchools = true;
  bool _includeDeliveries = true;
  bool _includeStaff = true;
  bool _includeClassrooms = true;
  bool _includeConsumables = true;
  bool _includeTimerAggregate = true;
  bool _includeTimerDetails = true;

  @override
  Widget build(BuildContext context) {
    final exportState = ref.watch(seasonExportNotifierProvider);
    final previewParams = (
      startDate: _useDateFilter ? _startDate : null,
      endDate: _useDateFilter ? _endDate : null
    );
    final previewAsync = ref.watch(seasonExportPreviewProvider(previewParams));
    final colors = AppPalette.of(context);
    final idle = !exportState.isExporting &&
        exportState.filePath == null &&
        exportState.error == null;

    return AdminPage(
      backLabel: 'Back to profile',
      title: 'Season report',
      subtitle: 'Export deliveries, signed records and timer history.',
      action: idle || exportState.isExporting
          ? AppGlassPrimaryButton(
              label: exportState.isExporting
                  ? 'Generating report…'
                  : 'Generate report',
              icon: AppIcons.download,
              loading: exportState.isExporting,
              onPressed: _startExport,
            )
          : null,
      children: [
        if (!idle) ...[
          _buildResult(exportState, colors),
          const SizedBox(height: AppTokens.sectionGap),
        ],

        // Date range
        AdminSection(
          first: true,
          label: 'Date range',
          child: AppGroupedList(
            children: [
              MergeSemantics(
                child: AppListRow(
                  title: 'Filter by date range',
                  subtitle: 'Leave off to export all data',
                  trailing: Switch(
                    value: _useDateFilter,
                    onChanged: (value) {
                      setState(() {
                        _useDateFilter = value;
                        if (!value) {
                          _startDate = null;
                          _endDate = null;
                        }
                      });
                    },
                  ),
                ),
              ),
              if (_useDateFilter) ...[
                AppListRow(
                  icon: AppIcons.calendar,
                  title: 'Start date',
                  subtitle: _startDate != null
                      ? DateTimeUtils.formatDate(_startDate!)
                      : 'Not set',
                  onTap: () => _selectDate(true),
                ),
                AppListRow(
                  icon: AppIcons.calendar,
                  title: 'End date',
                  subtitle: _endDate != null
                      ? DateTimeUtils.formatDate(_endDate!)
                      : 'Not set',
                  onTap: () => _selectDate(false),
                ),
              ],
            ],
          ),
        ),

        // Preview
        AdminSection(
          label: 'Data preview',
          child: previewAsync.when(
            loading: () => const AppPanel(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => AppPanel(
              child: Text('Error: $error',
                  style:
                      AppTypography.subheadline.copyWith(color: colors.error)),
            ),
            data: (preview) => AppGroupedList(
              children: [
                _PreviewRow('Schools', preview.schoolCount.toString()),
                _PreviewRow('Deliveries', preview.deliveryCount.toString()),
                _PreviewRow('Staff members', preview.staffCount.toString()),
                _PreviewRow('Signed snapshots and earlier summaries',
                    preview.signedSummaryCount.toString()),
                _PreviewRow(
                    'Timer entries', preview.timerEntryCount.toString()),
                if (preview.earliestDate != null && preview.latestDate != null)
                  _PreviewRow(
                    'Date range',
                    '${DateTimeUtils.formatDate(preview.earliestDate!)} – ${DateTimeUtils.formatDate(preview.latestDate!)}',
                  ),
              ],
            ),
          ),
        ),

        // Sheets
        AdminSection(
          label: 'Include sheets',
          child: AppGroupedList(
            children: [
              _buildSheetOption('Season Overview', _includeOverview,
                  (v) => setState(() => _includeOverview = v)),
              _buildSheetOption('Schools', _includeSchools,
                  (v) => setState(() => _includeSchools = v)),
              _buildSheetOption('Deliveries', _includeDeliveries,
                  (v) => setState(() => _includeDeliveries = v)),
              _buildSheetOption('Staff Performance', _includeStaff,
                  (v) => setState(() => _includeStaff = v)),
              _buildSheetOption('Classroom Details', _includeClassrooms,
                  (v) => setState(() => _includeClassrooms = v)),
              _buildSheetOption('Consumables', _includeConsumables,
                  (v) => setState(() => _includeConsumables = v)),
              _buildSheetOption('Timer Summary', _includeTimerAggregate,
                  (v) => setState(() => _includeTimerAggregate = v)),
              _buildSheetOption('Timer Details', _includeTimerDetails,
                  (v) => setState(() => _includeTimerDetails = v)),
            ],
          ),
        ),
      ],
    );
  }

  /// Progress, result or failure of the current export (shown above the
  /// options so it is visible right after starting).
  Widget _buildResult(SeasonExportState exportState, AppPalette colors) {
    if (exportState.isExporting) {
      final percent = (exportState.progress * 100).toInt();
      return AppPanel(
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(exportState.progressMessage ?? 'Exporting...',
                  style: AppTypography.headline.copyWith(color: colors.ink)),
              const SizedBox(height: 12),
              AppProgressBar(
                value: exportState.progress,
                semanticLabel: 'Export progress',
              ),
              const SizedBox(height: 8),
              Text('$percent%',
                  style: AppTypography.footnote.copyWith(color: colors.muted)),
            ],
          ),
        ),
      );
    }
    if (exportState.filePath != null) {
      return AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AppIconTile(icon: AppIcons.complete),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Report ready',
                      style:
                          AppTypography.headline.copyWith(color: colors.ink)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppPrimaryButton(
              label: 'Share',
              icon: AppIcons.share,
              onPressed: () =>
                  ref.read(seasonExportNotifierProvider.notifier).shareFile(),
            ),
            const SizedBox(height: 8),
            AppSecondaryButton(
              label: 'New export',
              icon: AppIcons.retry,
              onPressed: () =>
                  ref.read(seasonExportNotifierProvider.notifier).reset(),
            ),
          ],
        ),
      );
    }
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.error, color: colors.error, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Export failed',
                      style:
                          AppTypography.headline.copyWith(color: colors.error)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(exportState.error!,
              style: AppTypography.subheadline.copyWith(color: colors.ink)),
          const SizedBox(height: 12),
          AppSecondaryButton(
            label: 'Try again',
            icon: AppIcons.retry,
            onPressed: () =>
                ref.read(seasonExportNotifierProvider.notifier).reset(),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetOption(
      String title, bool value, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      title: Text(title),
      value: value,
      onChanged: (v) => onChanged(v ?? false),
    );
  }

  Future<void> _selectDate(bool isStartDate) async {
    final initialDate = isStartDate
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _startExport() {
    final options = SeasonExportOptions(
      startDate: _useDateFilter ? _startDate : null,
      endDate: _useDateFilter ? _endDate : null,
      includeOverview: _includeOverview,
      includeSchools: _includeSchools,
      includeDeliveries: _includeDeliveries,
      includeStaff: _includeStaff,
      includeClassrooms: _includeClassrooms,
      includeConsumables: _includeConsumables,
      includeTimerAggregate: _includeTimerAggregate,
      includeTimerDetails: _includeTimerDetails,
    );

    ref.read(seasonExportNotifierProvider.notifier).generateReport(
          startDate: _useDateFilter ? _startDate : null,
          endDate: _useDateFilter ? _endDate : null,
          options: options,
        );
  }
}

/// Label–value preview row; the value moves under the label when space is
/// tight (narrow screen or large text).
class _PreviewRow extends StatelessWidget {
  const _PreviewRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final valueStyle = AppTypography.headline.copyWith(color: colors.ink);
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 340 ||
          MediaQuery.textScalerOf(context).scale(17) > 22;
      final labelText =
          Text(label, style: AppTypography.body.copyWith(color: colors.muted));
      final valueText = Text(value,
          textAlign: stacked ? TextAlign.start : TextAlign.end,
          style: valueStyle);
      return MergeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [labelText, valueText],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: labelText),
                    const SizedBox(width: 12),
                    Flexible(child: valueText),
                  ],
                ),
        ),
      );
    });
  }
}
