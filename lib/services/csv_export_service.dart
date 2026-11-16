import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/school.dart';

class CsvExportService {
  static Future<void> exportSummaryToCsv(SignedSchoolSummary summary) async {
    try {
      // Generate CSV content
      final csvData = _generateCsvData(summary);
      final csvString = const ListToCsvConverter().convert(csvData);

      // Get temporary directory
      final directory = await getTemporaryDirectory();
      final fileName = '${summary.schoolName.replaceAll(' ', '_')}_Summary_${DateTime.now().millisecondsSinceEpoch}.csv';
      final filePath = '${directory.path}/$fileName';

      // Write CSV to file
      final file = File(filePath);
      await file.writeAsString(csvString);

      // Share the file using native share dialog
      await Share.shareXFiles(
        [XFile(filePath, mimeType: 'text/csv')],
        subject: '${summary.schoolName} Delivery Summary',
        text: 'Signed delivery summary for ${summary.schoolName}',
      );
    } catch (e) {
      debugPrint('Error exporting CSV: $e');
      rethrow;
    }
  }

  static List<List<dynamic>> _generateCsvData(SignedSchoolSummary summary) {
    final List<List<dynamic>> rows = [];

    // Header section
    rows.add(['School Delivery Summary']);
    rows.add([]);
    rows.add(['School Name', summary.schoolName]);
    if (summary.schoolAddress != null) {
      rows.add(['Address', summary.schoolAddress]);
    }
    rows.add(['Signed By', summary.signedBy]);
    rows.add(['Signed Date', _formatDate(summary.signedDate)]);
    rows.add(['Generated At', _formatDate(summary.createdAt)]);
    rows.add([]);

    // Pack Totals Summary
    rows.add(['PACK TOTALS SUMMARY']);
    rows.add(['Total Packs', summary.totalPacks]);
    rows.add([]);

    // Pack totals by year level
    rows.add(['Year Level', 'Total Packs']);
    for (final entry in summary.packTotalsByYearLevel.entries) {
      rows.add([entry.key, entry.value]);
    }
    rows.add([]);

    // Pack totals by classroom
    rows.add(['PACK TOTALS BY CLASSROOM']);
    rows.add(['Year Level', 'Classroom', 'Packs']);
    for (final yearEntry in summary.packTotalsByClassroom.entries) {
      final yearLevel = yearEntry.key;
      for (final classEntry in yearEntry.value.entries) {
        rows.add([yearLevel, classEntry.key, classEntry.value]);
      }
    }
    rows.add([]);

    // Consumables Summary
    rows.add(['CONSUMABLES SUMMARY']);
    rows.add(['Item', 'Quantity', 'Unit']);
    for (final entry in summary.consumablesTotals.entries) {
      final consumable = entry.value;
      rows.add([consumable.itemName, consumable.quantity, consumable.unit]);
    }
    rows.add([]);

    // Consumables by year level
    rows.add(['CONSUMABLES BY YEAR LEVEL']);
    rows.add(['Year Level', 'Item', 'Quantity', 'Unit']);
    for (final yearEntry in summary.consumablesByYearLevel.entries) {
      final yearLevel = yearEntry.key;
      for (final itemEntry in yearEntry.value.entries) {
        final consumable = itemEntry.value;
        rows.add([yearLevel, consumable.itemName, consumable.quantity, consumable.unit]);
      }
    }
    rows.add([]);

    // Consumables by classroom
    rows.add(['CONSUMABLES BY CLASSROOM']);
    rows.add(['Year Level', 'Classroom', 'Item', 'Quantity', 'Unit']);
    for (final yearEntry in summary.consumablesByClassroom.entries) {
      final yearLevel = yearEntry.key;
      for (final classEntry in yearEntry.value.entries) {
        final classroom = classEntry.key;
        for (final itemEntry in classEntry.value.entries) {
          final consumable = itemEntry.value;
          rows.add([yearLevel, classroom, consumable.itemName, consumable.quantity, consumable.unit]);
        }
      }
    }
    rows.add([]);

    // Photos section
    if (summary.photoUrls.isNotEmpty) {
      rows.add(['PHOTOS']);
      rows.add(['Total Photos', summary.photoUrls.length]);
      rows.add(['Photo URLs']);
      for (final url in summary.photoUrls) {
        rows.add([url]);
      }
      rows.add([]);
    }

    // Notes section
    if (summary.notes != null && summary.notes!.isNotEmpty) {
      rows.add(['NOTES']);
      rows.add([summary.notes]);
      rows.add([]);
    }

    // Footer
    rows.add([]);
    rows.add(['This document was electronically signed']);
    if (summary.signatureUrl != null) {
      rows.add(['Signature URL', summary.signatureUrl]);
    }

    return rows;
  }

  static String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
