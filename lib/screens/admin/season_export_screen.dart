import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/season_export_providers.dart';
import '../../models/season_export_models.dart';
import '../../widgets/design/design.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Season Report'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(AppTokens.gutter, 10, AppTokens.gutter,
            MediaQuery.paddingOf(context).bottom + AppTokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppPanel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIconTile(icon: Icons.summarize_outlined),
                  SizedBox(width: 12),
                  Expanded(
                      child: Text(
                          'Export deliveries, signed records and timer history.')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Date Range Section
            _buildSection(
              title: 'Date Range',
              icon: Icons.date_range,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Filter by date range'),
                    subtitle: const Text('Leave off to export all data'),
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
                  if (_useDateFilter) ...[
                    const Divider(),
                    ListTile(
                      title: const Text('Start Date'),
                      subtitle: Text(
                        _startDate != null
                            ? DateFormat('dd/MM/yyyy').format(_startDate!)
                            : 'Not set',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () => _selectDate(true),
                    ),
                    ListTile(
                      title: const Text('End Date'),
                      subtitle: Text(
                        _endDate != null
                            ? DateFormat('dd/MM/yyyy').format(_endDate!)
                            : 'Not set',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () => _selectDate(false),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Preview Section
            _buildSection(
              title: 'Data Preview',
              icon: Icons.preview,
              child: previewAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error: $error',
                      style: TextStyle(color: AppTone.pink.inkFor(context))),
                ),
                data: (preview) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildPreviewRow(
                          'Schools', preview.schoolCount.toString()),
                      _buildPreviewRow(
                          'Deliveries', preview.deliveryCount.toString()),
                      _buildPreviewRow(
                          'Staff Members', preview.staffCount.toString()),
                      _buildPreviewRow('Signed snapshots and earlier summaries',
                          preview.signedSummaryCount.toString()),
                      _buildPreviewRow(
                          'Timer Entries', preview.timerEntryCount.toString()),
                      if (preview.earliestDate != null &&
                          preview.latestDate != null) ...[
                        const Divider(),
                        _buildPreviewRow(
                          'Date Range',
                          '${DateFormat('dd/MM/yyyy').format(preview.earliestDate!)} - ${DateFormat('dd/MM/yyyy').format(preview.latestDate!)}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sheets Selection
            _buildSection(
              title: 'Include Sheets',
              icon: Icons.table_chart,
              child: Column(
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
            const SizedBox(height: 24),

            if (exportState.isExporting)
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(exportState.progressMessage ?? 'Exporting...'),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: exportState.progress),
                    const SizedBox(height: 8),
                    Text('${(exportState.progress * 100).toInt()}%'),
                  ],
                ),
              )
            else if (exportState.filePath != null)
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppStatusPill(
                      label: 'Report ready',
                      icon: Icons.check_circle_outline,
                      tone: AppTone.green,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => ref
                              .read(seasonExportNotifierProvider.notifier)
                              .shareFile(),
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Share'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => ref
                              .read(seasonExportNotifierProvider.notifier)
                              .reset(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('New Export'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else if (exportState.error != null)
              AppPanel(
                tone: AppTone.pink,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionHeading(title: 'Export Failed'),
                    const SizedBox(height: 8),
                    Text(exportState.error!),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => ref
                          .read(seasonExportNotifierProvider.notifier)
                          .reset(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _startExport,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Generate Report'),
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return AppPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AppIconTile(icon: icon),
                const SizedBox(width: 12),
                Expanded(child: AppSectionHeading(title: title)),
              ],
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(color: AppPalette.of(context).muted))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
