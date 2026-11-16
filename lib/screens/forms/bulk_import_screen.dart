import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import '../../services/csv_import_service.dart';
import '../../providers/repository_providers.dart';
import '../../app/theme/brand_colors.dart';
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
    final normalizedContent = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalizedContent.split('\n').where((line) => line.trim().isNotEmpty).toList();

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
      errors.add('Header must have at least 3 columns: Year Level, Classroom, Packs');
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
        errors.add('Row ${i + 1}: Missing required columns (need Year Level, Classroom, Packs)');
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
          errors.add('Row ${i + 1}: "${headers[j]}" must be a number (got "${cells[j]}")');
        }
      }

      if (cells[0].isNotEmpty && cells[1].isNotEmpty && int.tryParse(cells[2]) != null) {
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info Card
            Card(
              color: BrandColors.kakaBlue.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: BrandColors.kakaBlue),
                        const SizedBox(width: 8),
                        Text(
                          'How It Works',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Download or paste the CSV template\n'
                      '2. Edit the data with your classroom information\n'
                      '3. Paste the CSV data below\n'
                      '4. Click Import to add the data',
                      style: TextStyle(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Template Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _downloadTemplate,
                    icon: const Icon(Icons.download),
                    label: const Text('Download Template'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pasteTemplate,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Paste Template'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // CSV Input Field
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'CSV Data',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        if (_csvController.text.isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              _csvController.clear();
                              setState(() {
                                _errorMessage = null;
                                _successMessage = null;
                                _validationErrors = [];
                                _isValidCSV = false;
                              });
                            },
                            icon: const Icon(Icons.clear, size: 18),
                            label: const Text('Clear'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _csvController,
                      onChanged: (value) {
                        _validateCSV(value);
                      },
                      maxLines: 15,
                      decoration: const InputDecoration(
                        hintText: 'Paste your CSV data here...\n\n'
                            'Year Level,Classroom,Packs,Year 1 Students,Headphones\n'
                            'Year 1,Year 1A,26,26,26\n'
                            'Year 1,Year 1/2A,24,10,24  (composite class)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(12),
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Validation Status
            if (_csvController.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (_validationErrors.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Format Issues Detected',
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...(_validationErrors.map((error) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ',
                                    style: TextStyle(color: Colors.orange)),
                                Expanded(
                                  child: Text(
                                    error,
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ))),
                    ],
                  ),
                )
              else if (_isValidCSV)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'CSV format looks good!',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            const SizedBox(height: 24),

            // Import Button
            ElevatedButton.icon(
              onPressed: _isValidCSV && !_isLoading
                  ? _importData
                  : null,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(_isLoading ? 'Importing...' : 'Import Data'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: BrandColors.kakaBlue,
                foregroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 24),

            // Error Message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),

            // Success Message
            if (_successMessage != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 12),
                        Text(
                          'Success!',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _successMessage!,
                      style: const TextStyle(
                        color: Colors.green,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Navigate back to school hub
                        context.go('/schools/${widget.schoolId}');
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // CSV Format Example
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CSV Format Example',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        'Year Level,Classroom,Packs,Year 1 Students,Year 2 Students,Headphones,Tissues\n'
                        'Prep,Prep A,25,,,25,1\n'
                        'Year 1,Year 1A,26,26,,26,1\n'
                        'Year 1,Year 1/2A,24,10,14,24,1\n'
                        'Year 2,Year 2A,27,,27,27,1',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Notes:\n'
                      '• First row must be the header\n'
                      '• Year Level and Classroom are required\n'
                      '• Packs must be a number\n'
                      '• Additional columns are treated as consumables\n'
                      '• Use 0 or leave empty for items you don\'t need\n\n'
                      'Composite Classes:\n'
                      '• Add columns ending in "Students" for any year level\n'
                      '• Examples: "Year 3 Students", "Year 5 Students", "Prep Students"\n'
                      '• Works for Year 1/2, Year 3/4, Year 5/6, or any combination',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
