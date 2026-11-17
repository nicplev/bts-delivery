import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import '../../services/csv_import_service.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/design/design.dart';
import '../../utils/notification_utils.dart';

class BulkImportScreen extends ConsumerStatefulWidget {
  const BulkImportScreen(
      {super.key, required this.schoolId, required this.schoolName});

  final String schoolId;
  final String schoolName;

  @override
  ConsumerState<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends ConsumerState<BulkImportScreen> {
  final _csvController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  List<String> _validationErrors = [];
  bool _isValidCSV = false;

  @override
  void dispose() {
    _csvController.dispose();
    super.dispose();
  }

  /// Validates CSV data and updates validation state
  void _validateCSV(String content) {
    final errors = <String>[];

    if (content.trim().isEmpty) {
      setState(() {
        _validationErrors = [];
        _isValidCSV = false;
      });
      return;
    }

    // Normalize line endings
    final normalizedContent =
        content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalizedContent
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      errors.add('No data found');
      setState(() {
        _validationErrors = errors;
        _isValidCSV = false;
      });
      return;
    }

    // Check header row
    final headers = lines[0].split(',').map((e) => e.trim()).toList();

    if (headers.length < 3) {
      errors.add(
          'Header must have at least 3 columns: Year Level, Classroom, Packs');
    } else {
      // Validate header names
      final firstHeader = headers[0].toLowerCase().replaceAll(' ', '');
      if (!firstHeader.contains('year') && !firstHeader.contains('level')) {
        errors.add('First column should be "Year Level" (got "${headers[0]}")');
      }
      if (!headers[1].toLowerCase().contains('class')) {
        errors.add('Second column should be "Classroom" (got "${headers[1]}")');
      }
      if (!headers[2].toLowerCase().contains('pack')) {
        errors.add('Third column should be "Packs" (got "${headers[2]}")');
      }
    }

    // Check data rows
    int validRows = 0;
    for (int i = 1; i < lines.length; i++) {
      final cells = lines[i].split(',').map((e) => e.trim()).toList();

      if (cells.isEmpty || cells.every((c) => c.isEmpty)) {
        continue; // Skip empty rows
      }

      if (cells.length < 3) {
        errors.add(
            'Row ${i + 1}: Missing required columns (need Year Level, Classroom, Packs)');
        continue;
      }

      if (cells[0].isEmpty) {
        errors.add('Row ${i + 1}: Year Level is empty');
      }
      if (cells[1].isEmpty) {
        errors.add('Row ${i + 1}: Classroom name is empty');
      }
      if (cells[2].isEmpty) {
        errors.add('Row ${i + 1}: Packs value is empty');
      } else if (int.tryParse(cells[2]) == null) {
        errors.add('Row ${i + 1}: Packs must be a number (got "${cells[2]}")');
      }

      // Check numeric columns after Packs
      for (int j = 3; j < cells.length && j < headers.length; j++) {
        if (cells[j].isNotEmpty && int.tryParse(cells[j]) == null) {
          errors.add(
              'Row ${i + 1}: "${headers[j]}" must be a number (got "${cells[j]}")');
        }
      }

      if (cells[0].isNotEmpty &&
          cells[1].isNotEmpty &&
          int.tryParse(cells[2]) != null) {
        validRows++;
      }
    }

    if (validRows == 0 && errors.isEmpty) {
      errors.add('No valid data rows found (only header detected)');
    }

    setState(() {
      _validationErrors = errors.take(5).toList(); // Limit to first 5 errors
      if (errors.length > 5) {
        _validationErrors.add('... and ${errors.length - 5} more errors');
      }
      _isValidCSV = errors.isEmpty && validRows > 0;
    });
  }

  Future<void> _importData() async {
    if (_csvController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please paste CSV data first';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Parse CSV
      final csvContent = _csvController.text;
      final parseResult = await CSVImportService.parseCSV(csvContent);

      if (!parseResult.success) {
        setState(() {
          _errorMessage = parseResult.errorMessage;
          _isLoading = false;
        });
        return;
      }

      // Import data to Firestore
      final repository = ref.read(schoolsRepositoryProvider);
      final importResult = await repository.bulkImportClassrooms(
        widget.schoolId,
        parseResult.data!,
      );

      importResult.when(
        success: (summary) {
          setState(() {
            _successMessage = 'Import completed successfully!\n\n'
                '✓ ${summary.yearLevelsCreated} year levels created\n'
                '✓ ${summary.classroomsCreated} classrooms created\n'
                '✓ ${summary.consumablesCreated} consumables created\n'
                '✓ ${summary.packsAllocated} packs allocated';
            _isLoading = false;
            _csvController.clear();
          });

          // Show notification that sign-off was cleared due to data import
          if (mounted) {
            NotificationUtils.showSignOffClearedNotification(context);
          }
        },
        failure: (message, _) {
          setState(() {
            _errorMessage = message;
            _isLoading = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Import failed: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      // Generate template CSV
      final templateContent = CSVImportService.generateTemplate();

      // Save to temporary file
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/classroom_import_template.csv';
      final file = File(filePath);
      await file.writeAsString(templateContent);

      // Share the file
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'Classroom Import Template',
        text:
            'Use this CSV template to bulk import classrooms for ${widget.schoolName}',
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to download template: $e';
      });
    }
  }

  void _pasteTemplate() {
    final template = CSVImportService.generateTemplate();
    _csvController.text = template;
    _validateCSV(template);
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/schools/${widget.schoolId}');
            }
          },
        ),
        title: const Text('Bulk Import Classrooms'),
      ),
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
                  const AppSectionHeading(title: 'Classroom template'),
                  const SizedBox(height: 8),
                  const Text(
                      'Add your classroom details to the CSV template, then paste it here.'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _downloadTemplate,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Download Template'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pasteTemplate,
                        icon: const Icon(Icons.content_paste_outlined),
                        label: const Text('Paste Template'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSectionHeading(
                    title: 'CSV Data',
                    trailing: _csvController.text.isNotEmpty
                        ? TextButton(
                            onPressed: () {
                              _csvController.clear();
                              setState(() {
                                _errorMessage = null;
                                _successMessage = null;
                                _validationErrors = [];
                                _isValidCSV = false;
                              });
                            },
                            child: const Text('Clear'),
                          )
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _csvController,
                    onChanged: _validateCSV,
                    minLines: 6,
                    maxLines: 10,
                    decoration:
                        const InputDecoration(hintText: 'Paste CSV data'),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                  if (_csvController.text.isNotEmpty &&
                      _validationErrors.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const AppStatusPill(
                      label: 'Format issues detected',
                      icon: Icons.warning_amber_rounded,
                      tone: AppTone.yellow,
                    ),
                    for (final error in _validationErrors)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(error),
                      ),
                  ] else if (_csvController.text.isNotEmpty && _isValidCSV) ...[
                    const SizedBox(height: 12),
                    const AppStatusPill(
                      label: 'CSV format looks good!',
                      icon: Icons.check_circle_outline,
                      tone: AppTone.green,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isValidCSV && !_isLoading ? _importData : null,
              icon: _isLoading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_outlined),
              label: Text(_isLoading ? 'Importing...' : 'Import Data'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              AppPanel(tone: AppTone.pink, child: Text(_errorMessage!)),
            ],
            if (_successMessage != null) ...[
              const SizedBox(height: 12),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppStatusPill(
                      label: 'Import successful',
                      icon: Icons.check_circle_outline,
                      tone: AppTone.green,
                    ),
                    const SizedBox(height: 10),
                    Text(_successMessage!),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () =>
                          context.go('/schools/${widget.schoolId}'),
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            AppPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeading(title: 'CSV Format Example'),
                  const SizedBox(height: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).surfaceQuiet,
                      borderRadius:
                          BorderRadius.circular(AppTokens.controlRadius),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: SelectableText(
                        'Year Level,Classroom,Packs,Year 1 Students,Year 2 Students,Headphones,Tissues\n'
                        'Prep,Prep A,25,,,25,1\n'
                        'Year 1,Year 1A,26,26,,26,1\n'
                        'Year 1,Year 1/2A,24,10,14,24,1\n'
                        'Year 2,Year 2A,27,,27,27,1',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Use the first row for column headers. Year Level and Classroom are required. '
                    'Packs must be a number. Extra columns represent consumables. Use zero or leave a consumable blank when it is not needed.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'For composite classes, add a column ending in “Students” for each year level, such as “Year 3 Students”.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
