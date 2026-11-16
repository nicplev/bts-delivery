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
      final schoolsData = await SchoolCsvImportService.parseSchoolsCsv(csvContent);

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
        _successMessage = 'Successfully imported $successCount school${successCount != 1 ? 's' : ''}';
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
      appBar: AppBar(
        title: const Text('Bulk Import Schools'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Instructions Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        const Text(
                          'How to Import Schools',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Download the CSV template\n'
                      '2. Fill in school details (only School Name is required)\n'
                      '3. Copy the CSV data\n'
                      '4. Paste it below and import',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _downloadTemplate,
                      icon: const Icon(Icons.download),
                      label: const Text('Download CSV Template'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // CSV Format Info
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.table_chart, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'CSV Format',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Required: School Name\n'
                      'Optional: Address, Contact Name, Contact Phone, Contact Email',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'School Name,Address,Contact Name,Contact Phone,Contact Email\n'
                        'BPS,99 Dalgetty Rd,John,0412345678,john@bps.edu.au\n'
                        'BRPS,71 Arkaringa Cres,,,',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // CSV Input Field
            TextField(
              controller: _csvController,
              decoration: InputDecoration(
                labelText: 'CSV Data',
                hintText: 'Paste your CSV data here...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  onPressed: _pasteFromClipboard,
                  tooltip: 'Paste from clipboard',
                ),
              ),
              maxLines: 10,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),

            const SizedBox(height: 16),

            // Import Button
            FilledButton.icon(
              onPressed: _isLoading ? null : _importSchools,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload),
              label: Text(_isLoading ? 'Importing...' : 'Import Schools'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 16),

            // Success Message
            if (_successMessage != null)
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Import Successful',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(_successMessage!),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          context.go('/schools');
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Done'),
                      ),
                    ],
                  ),
                ),
              ),

            // Error Message
            if (_errorMessage != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          const Text(
                            'Import Failed',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 14),
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
