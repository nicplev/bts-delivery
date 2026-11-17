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
        text: 'School Import Template',
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
    return Scaffold(
      appBar: AppBar(title: const Text('Bulk Import Schools')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.gutter,
            10,
            AppTokens.gutter,
            AppTokens.sectionGap,
          ),
          children: [
            AppPanel(
              tone: AppTone.blue,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppSectionHeading(title: 'School template'),
                  const SizedBox(height: 8),
                  const Text(
                    'School Name is required. Address, Contact Name, Contact Phone and Contact Email are optional.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _downloadTemplate,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Download CSV Template'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeading(title: 'CSV Data'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _csvController,
                    decoration: InputDecoration(
                      hintText: 'Paste CSV data',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste_outlined),
                        onPressed: _pasteFromClipboard,
                        tooltip: 'Paste from clipboard',
                      ),
                    ),
                    minLines: 5,
                    maxLines: 10,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isLoading ? null : _importSchools,
              icon: _isLoading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_outlined),
              label: Text(_isLoading ? 'Importing...' : 'Import Schools'),
            ),
            if (_successMessage != null) ...[
              const SizedBox(height: 12),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppStatusPill(
                      label: 'Import Successful',
                      icon: Icons.check_circle_outline,
                      tone: AppTone.green,
                    ),
                    const SizedBox(height: 8),
                    Text(_successMessage!),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => context.go('/schools'),
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              AppPanel(
                tone: AppTone.pink,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionHeading(title: 'Import Failed'),
                    const SizedBox(height: 8),
                    Text(_errorMessage!),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            AppPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeading(title: 'CSV Format'),
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).surfaceQuiet,
                      borderRadius:
                          BorderRadius.circular(AppTokens.controlRadius),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: SelectableText(
                        'School Name,Address,Contact Name,Contact Phone,Contact Email\n'
                        'Example School,10 Example St,Alex,0400000000,alex@example.test\n'
                        'North Campus,20 Example St,,,',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
