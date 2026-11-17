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

  void _clear() {
    _csvController.clear();
    setState(() {
      _errorMessage = null;
      _successMessage = null;
      _validationErrors = [];
      _isValidCSV = false;
    });
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/schools/${widget.schoolId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final imported = _successMessage != null && _csvController.text.isEmpty;
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      color: colors.ink,
    );
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppNavBar(showBack: true, onBack: _goBack),
      body: AppFloatingActionArea(
        action: imported
            ? AppGlassPrimaryButton(
                label: 'Done',
                icon: AppIcons.check,
                onPressed: () => context.go('/schools/${widget.schoolId}'),
              )
            : AppGlassPrimaryButton(
                label: _isLoading ? 'Importing...' : 'Import data',
                icon: AppIcons.upload,
                loading: _isLoading,
                onPressed: _isValidCSV ? _importData : null,
              ),
        child: Builder(
          builder: (context) => ListView(
            padding: AppInsets.scroll(context),
            children: [
              AppLargeTitle(
                title: 'Import classrooms',
                subtitle: widget.schoolName,
              ),
              const SizedBox(height: AppTokens.sectionGap - 4),
              if (_successMessage != null) ...[
                AppPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppStatusPill(
                        label: 'Import successful',
                        icon: AppIcons.complete,
                      ),
                      const SizedBox(height: 10),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _successMessage!,
                          style: AppTypography.subheadline
                              .copyWith(color: colors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.sectionGap - 4),
              ],
              if (_errorMessage != null) ...[
                _ErrorBox(message: _errorMessage!),
                const SizedBox(height: AppTokens.sectionGap - 4),
              ],
              const AppSectionLabel('Classroom template'),
              const SizedBox(height: 8),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Add your classroom details to the CSV template, then paste it here.',
                      style:
                          AppTypography.subheadline.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: 12),
                    AppSecondaryButton(
                      onPressed: _downloadTemplate,
                      icon: AppIcons.download,
                      label: 'Download template',
                      large: false,
                    ),
                    const SizedBox(height: 8),
                    AppSecondaryButton(
                      onPressed: _pasteTemplate,
                      icon: HeroiconsOutline.clipboardDocument,
                      label: 'Paste template',
                      large: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.sectionGap - 4),
              AppSectionLabel(
                'CSV data',
                trailing: _csvController.text.isNotEmpty
                    ? AppSecondaryButton(
                        onPressed: _clear,
                        label: 'Clear',
                        expand: false,
                        large: false,
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _csvController,
                      onChanged: _validateCSV,
                      minLines: 6,
                      maxLines: 10,
                      decoration:
                          const InputDecoration(hintText: 'Paste CSV data'),
                      style: mono,
                    ),
                    if (_csvController.text.isNotEmpty &&
                        _validationErrors.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _ErrorBox(
                        title: 'Format issues detected',
                        message: _validationErrors.join('\n'),
                      ),
                    ] else if (_csvController.text.isNotEmpty &&
                        _isValidCSV) ...[
                      const SizedBox(height: 12),
                      const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: AppStatusPill(
                          label: 'CSV format looks good!',
                          icon: AppIcons.complete,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.sectionGap - 4),
              const AppSectionLabel('CSV format example'),
              const SizedBox(height: 8),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceQuiet,
                        borderRadius:
                            BorderRadius.circular(AppTokens.controlRadius),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          'Year Level,Classroom,Packs,Year 1 Students,Year 2 Students,Headphones,Tissues\n'
                          'Prep,Prep A,25,,,25,1\n'
                          'Year 1,Year 1A,26,26,,26,1\n'
                          'Year 1,Year 1/2A,24,10,14,24,1\n'
                          'Year 2,Year 2A,27,,27,27,1',
                          style: mono,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Use the first row for column headers. Year Level and Classroom are required. '
                      'Packs must be a number. Extra columns represent consumables. Use zero or leave a consumable blank when it is not needed.',
                      style:
                          AppTypography.subheadline.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'For composite classes, add a column ending in “Students” for each year level, such as “Year 3 Students”.',
                      style:
                          AppTypography.subheadline.copyWith(color: colors.ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Validation / import error in the error tokens.
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, this.title});

  final String message;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final style = AppTypography.subheadline.copyWith(color: colors.error);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(AppTokens.controlRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.error, color: colors.error, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(title!,
                          style: style.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                    ],
                    Text(message, style: style),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
