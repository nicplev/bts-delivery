import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import '../../services/school_csv_import_service.dart';
import '../../providers/repository_providers.dart';
import '../../providers/schools_providers.dart';
import '../../models/school.dart';
import '../../widgets/design/design.dart';
import '../admin/admin_page.dart';

class SchoolsBulkImportScreen extends ConsumerStatefulWidget {
  const SchoolsBulkImportScreen({super.key});

  @override
  ConsumerState<SchoolsBulkImportScreen> createState() =>
      _SchoolsBulkImportScreenState();
}

class _SchoolsBulkImportScreenState
    extends ConsumerState<SchoolsBulkImportScreen> {
  final _csvController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _csvController.dispose();
    super.dispose();
  }

  Future<void> _downloadTemplate() async {
    try {
      final template = SchoolCsvImportService.generateTemplate();
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/schools_template.csv');
      await file.writeAsString(template);

      final result = await Share.shareXFiles(
        [XFile(file.path)],
        text: 'School import template',
      );

      if (mounted && result.status == ShareResultStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template shared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing template: $e')),
        );
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      setState(() {
        _csvController.text = data!.text!;
        _errorMessage = null;
        _successMessage = null;
      });
    }
  }

  Future<void> _importSchools() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final csvContent = _csvController.text.trim();
      if (csvContent.isEmpty) {
        throw Exception('Please paste CSV data or enter school information');
      }

      // Parse CSV
      final schoolsData =
          await SchoolCsvImportService.parseSchoolsCsv(csvContent);

      if (schoolsData.isEmpty) {
        throw Exception('No valid schools found in CSV');
      }

      // Import each school
      final repository = ref.read(schoolsRepositoryProvider);
      int successCount = 0;

      for (final schoolData in schoolsData) {
        final school = School(
          id: '', // Will be set by Firestore
          name: schoolData.name,
          address: schoolData.address,
          contactName: schoolData.contactName,
          contactPhone: schoolData.contactPhone,
          contactEmail: schoolData.contactEmail,
          createdAt: DateTime.now(),
          isSignedOff: false,
        );

        final result = await repository.createSchool(school);
        result.when(
          success: (_) => successCount++,
          failure: (message, _) {
            // Log error but continue with other schools
            debugPrint('Failed to import ${school.name}: $message');
          },
        );
      }

      // Refresh the schools list
      ref.invalidate(schoolsProvider);

      setState(() {
        _isLoading = false;
        _successMessage =
            'Successfully imported $successCount school${successCount != 1 ? 's' : ''}';
        if (successCount < schoolsData.length) {
          _successMessage = '$_successMessage\n'
              '${schoolsData.length - successCount} school${schoolsData.length - successCount != 1 ? 's' : ''} failed to import';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 13);
    return AdminPage(
      backLabel: 'Back to schools',
      title: 'Import schools',
      subtitle: 'Add many schools at once from CSV data.',
      action: AppGlassPrimaryButton(
        label: _isLoading ? 'Importing...' : 'Import schools',
        icon: AppIcons.upload,
        loading: _isLoading,
        onPressed: _importSchools,
      ),
      children: [
        AdminSection(
          first: true,
          label: 'Template',
          child: AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'School Name is required. Address, Contact Name, Contact Phone and Contact Email are optional.',
                  style: AppTypography.subheadline.copyWith(color: colors.ink),
                ),
                const SizedBox(height: 12),
                AppSecondaryButton(
                  label: 'Download CSV template',
                  icon: AppIcons.download,
                  onPressed: _downloadTemplate,
                ),
              ],
            ),
          ),
        ),
        AdminSection(
          label: 'CSV data',
          child: AppPanel(
            child: TextField(
              controller: _csvController,
              decoration: InputDecoration(
                hintText: 'Paste CSV data',
                suffixIcon: IconButton(
                  icon: const Icon(AppIcons.paste, size: 20),
                  onPressed: _pasteFromClipboard,
                  tooltip: 'Paste from clipboard',
                ),
              ),
              minLines: 5,
              maxLines: 10,
              style: mono.copyWith(color: colors.ink),
            ),
          ),
        ),
        if (_successMessage != null) ...[
          const SizedBox(height: AppTokens.sectionGap),
          AppPanel(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const AppIconTile(icon: AppIcons.complete),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Import successful',
                            style: AppTypography.headline
                                .copyWith(color: colors.ink)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_successMessage!,
                      style: AppTypography.subheadline
                          .copyWith(color: colors.ink)),
                  const SizedBox(height: 12),
                  AppSecondaryButton(
                    label: 'Done',
                    icon: AppIcons.check,
                    onPressed: () => context.go('/schools'),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: AppTokens.sectionGap),
          AppPanel(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(AppIcons.error, color: colors.error, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Import failed',
                            style: AppTypography.headline
                                .copyWith(color: colors.error)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_errorMessage!,
                      style: AppTypography.subheadline
                          .copyWith(color: colors.ink)),
                ],
              ),
            ),
          ),
        ],
        AdminSection(
          label: 'CSV format',
          child: AppPanel(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceQuiet,
                borderRadius: BorderRadius.circular(AppTokens.controlRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  'School Name,Address,Contact Name,Contact Phone,Contact Email\n'
                  'Example School,10 Example St,Alex,0400000000,alex@example.test\n'
                  'North Campus,20 Example St,,,',
                  style: mono.copyWith(color: colors.ink),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
