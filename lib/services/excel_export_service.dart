import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../models/school.dart';
import 'package:intl/intl.dart';

/// Professional Excel export service for signed school summaries
///
/// Uses Syncfusion Flutter XlsIO to create beautifully formatted
/// Excel files with proper styling, colors, and organization.
class ExcelExportService {
  /// Export a signed school summary to a formatted Excel file
  static Future<String?> exportSummaryToExcel(
      SignedSchoolSummary summary) async {
    try {
      // Create a new Excel document
      final Workbook workbook = Workbook();
      final Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'Delivery Summary';

      int currentRow = 1;

      // === HEADER SECTION ===
      currentRow = _addHeaderSection(sheet, summary, currentRow);

      // === PACK TOTALS SUMMARY ===
      currentRow = _addPackTotalsSummary(sheet, summary, currentRow);

      // === PACK TOTALS BY YEAR LEVEL ===
      currentRow = _addPackTotalsByYearLevel(sheet, summary, currentRow);

      // === PACK TOTALS BY CLASSROOM ===
      currentRow = _addPackTotalsByClassroom(sheet, summary, currentRow);

      // === CLASSROOM DELIVERY STATUS ===
      if (summary.classroomDeliveryDetails.isNotEmpty) {
        currentRow = _addClassroomDeliveryStatus(sheet, summary, currentRow);
      }

      // === CONSUMABLES SUMMARY ===
      if (summary.consumablesTotals.isNotEmpty) {
        currentRow = _addConsumablesSummary(sheet, summary, currentRow);
      }

      // === CONSUMABLES BY YEAR LEVEL ===
      if (summary.consumablesByYearLevel.isNotEmpty) {
        currentRow = _addConsumablesByYearLevel(sheet, summary, currentRow);
      }

      // === CONSUMABLES BY CLASSROOM ===
      if (summary.consumablesByClassroom.isNotEmpty) {
        currentRow = _addConsumablesByClassroom(sheet, summary, currentRow);
      }

      // === PHOTOS SECTION ===
      if (summary.photoUrls.isNotEmpty) {
        currentRow = _addPhotosSection(sheet, summary, currentRow);
      }

      // === NOTES SECTION ===
      if (summary.notes != null && summary.notes!.isNotEmpty) {
        currentRow = _addNotesSection(sheet, summary, currentRow);
      }

      // === CLASSROOM NOTES SECTION ===
      if (summary.notesByClassroom.isNotEmpty) {
        currentRow = _addClassroomNotesSection(sheet, summary, currentRow);
      }

      // === SIGNATURE SECTION ===
      currentRow = _addSignatureSection(sheet, summary, currentRow);

      // Auto-fit columns for better readability
      sheet.autoFitColumn(1);
      sheet.autoFitColumn(2);
      sheet.autoFitColumn(3);
      sheet.autoFitColumn(4);
      sheet.autoFitColumn(5);

      // Save the file
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      // Get directory and create file
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          '${summary.schoolName.replaceAll(' ', '_')}_Summary_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final filePath = '${directory.path}/$fileName';

      final file = File(filePath);
      await file.writeAsBytes(bytes);

      debugPrint('✓ Excel file created: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('✗ Error exporting Excel: $e');
      rethrow;
    }
  }

  /// Share the Excel file using native share dialog
  static Future<void> shareExcelFile(String filePath, String schoolName) async {
    try {
      final file = XFile(
        filePath,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: filePath.split('/').last,
      );

      final result = await Share.shareXFiles(
        [file],
        subject: '$schoolName Delivery Summary',
        text: 'Signed delivery summary for $schoolName',
      );

      if (kDebugMode) {
        debugPrint('Share result: ${result.status}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('✗ Error sharing Excel file: $e');
      }
      rethrow;
    }
  }

  /// Open the Excel file with the default application
  /// On iOS, this uses share dialog instead since iOS doesn't allow direct file opening
  static Future<void> openExcelFile(String filePath, String schoolName) async {
    try {
      // On iOS, use share dialog as opening files directly is not supported
      if (Platform.isIOS) {
        await shareExcelFile(filePath, schoolName);
      } else {
        // On Android and other platforms, try to open the file
        final result = await OpenFile.open(filePath);
        if (kDebugMode) {
          debugPrint('Open file result: ${result.message}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('✗ Error opening Excel file: $e');
      }
      rethrow;
    }
  }

  // === SECTION BUILDERS ===

  static int _addHeaderSection(
      Worksheet sheet, SignedSchoolSummary summary, int row) {
    // Title
    final titleCell = sheet.getRangeByIndex(row, 1, row, 5);
    titleCell.merge();
    titleCell.setText('DELIVERY SUMMARY REPORT');
    titleCell.cellStyle.bold = true;
    titleCell.cellStyle.fontSize = 18;
    titleCell.cellStyle.hAlign = HAlignType.center;
    titleCell.cellStyle.backColor = '#1976D2'; // Blue
    titleCell.cellStyle.fontColor = '#FFFFFF';
    titleCell.rowHeight = 30;
    row += 2;

    // School information
    _addKeyValue(sheet, row++, 'School Name:', summary.schoolName,
        isBold: true);
    if (summary.schoolAddress != null && summary.schoolAddress!.isNotEmpty) {
      _addKeyValue(sheet, row++, 'Address:', summary.schoolAddress!);
    }
    _addKeyValue(sheet, row++, 'Signed By:', summary.signedBy, isBold: true);
    _addKeyValue(
        sheet, row++, 'Signed Date:', _formatDateTime(summary.signedDate));
    _addKeyValue(
        sheet, row++, 'Generated At:', _formatDateTime(summary.createdAt));

    row++; // Spacer
    return row;
  }

  static int _addPackTotalsSummary(
      Worksheet sheet, SignedSchoolSummary summary, int row) {
    // Section header
    _addSectionHeader(sheet, row++, 'PACK TOTALS SUMMARY', '#4CAF50'); // Green

    // Total packs highlight
    final totalPacksRange = sheet.getRangeByIndex(row, 1, row, 2);
    totalPacksRange.merge();
    totalPacksRange.setText('Total Packs Delivered');
    totalPacksRange.cellStyle.bold = true;
    totalPacksRange.cellStyle.fontSize = 14;
    totalPacksRange.cellStyle.backColor = '#E8F5E9';

    final totalValueCell = sheet.getRangeByIndex(row, 3);
    totalValueCell.setNumber(summary.totalPacks.toDouble());
    totalValueCell.cellStyle.bold = true;
    totalValueCell.cellStyle.fontSize = 14;
    totalValueCell.cellStyle.backColor = '#E8F5E9';
    totalValueCell.cellStyle.hAlign = HAlignType.center;
    row += 2;

    return row;
  }

  static int _addPackTotalsByYearLevel(
      Worksheet sheet, SignedSchoolSummary summary, int row) {
    _addSectionHeader(sheet, row++, 'PACK TOTALS BY YEAR LEVEL', '#FF9800');

    // Table headers
    _addTableHeader(sheet, row, ['Year Level', 'Total Packs']);
    row++;

    // Data rows with year level color coding
    for (final entry in summary.packTotalsByYearLevel.entries) {
      final yearLevel = entry.key;
      final color = _getYearLevelColor(yearLevel);

      sheet.getRangeByIndex(row, 1).setText(yearLevel);
      sheet.getRangeByIndex(row, 1).cellStyle.backColor = color;
      sheet.getRangeByIndex(row, 1).cellStyle.borders.all.lineStyle =
          LineStyle.thin;

      sheet.getRangeByIndex(row, 2).setNumber(entry.value.toDouble());
      sheet.getRangeByIndex(row, 2).cellStyle.hAlign = HAlignType.center;
      sheet.getRangeByIndex(row, 2).cellStyle.backColor = color;
      sheet.getRangeByIndex(row, 2).cellStyle.borders.all.lineStyle =
          LineStyle.thin;
      row++;
    }

    row++; // Spacer
    return row;
  }

  static int _addPackTotalsByClassroom(
      Worksheet sheet, SignedSchoolSummary summary, int row) {
    _addSectionHeader(sheet, row++, 'PACK TOTALS BY CLASSROOM', '#9C27B0');

    // Table headers
    _addTableHeader(sheet, row, ['Year Level', 'Classroom', 'Packs']);
    row++;

    // Data rows with year level color coding
    for (final yearEntry in summary.packTotalsByClassroom.entries) {
      final yearLevel = yearEntry.key;
      final color = _getYearLevelColor(yearLevel);

      for (final classEntry in yearEntry.value.entries) {
        // Apply year level color to entire row
        sheet.getRangeByIndex(row, 1).setText(yearLevel);
        sheet.getRangeByIndex(row, 1).cellStyle.backColor = color;
        sheet.getRangeByIndex(row, 1).cellStyle.borders.all.lineStyle =
            LineStyle.thin;

        sheet.getRangeByIndex(row, 2).setText(classEntry.key);
        sheet.getRangeByIndex(row, 2).cellStyle.backColor = color;
        sheet.getRangeByIndex(row, 2).cellStyle.borders.all.lineStyle =
            LineStyle.thin;

        sheet.getRangeByIndex(row, 3).setNumber(classEntry.value.toDouble());
        sheet.getRangeByIndex(row, 3).cellStyle.hAlign = HAlignType.center;
        sheet.getRangeByIndex(row, 3).cellStyle.backColor = color;
        sheet.getRangeByIndex(row, 3).cellStyle.borders.all.lineStyle =
            LineStyle.thin;
        row++;
      }
    }

    row++; // Spacer
    return row;
  }

  static int _addClassroomDeliveryStatus(
      Worksheet sheet, SignedSchoolSummary summary, int row) {
    _addSectionHeader(
        sheet, row++, 'CLASSROOM DELIVERY STATUS', '#E91E63'); // Pink

    // Table headers with more columns
    _addTableHeader(sheet, row,
        ['Year Level', 'Classroom', 'Status', 'Packs', 'Consumables', 'Notes']);
    row++;

    // Data rows with status color coding
    for (final detail in summary.classroomDeliveryDetails) {
      final yearLevelColor = _getYearLevelColor(detail.yearLevel);
      final statusColor = _getStatusColor(detail.status);
      final statusText = _getStatusText(detail.status);

      // Year Level
      sheet.getRangeByIndex(row, 1).setText(detail.yearLevel);
      sheet.getRangeByIndex(row, 1).cellStyle.backColor = yearLevelColor;
      sheet.getRangeByIndex(row, 1).cellStyle.borders.all.lineStyle =
          LineStyle.thin;

      // Classroom
      sheet.getRangeByIndex(row, 2).setText(detail.classroomName);
      sheet.getRangeByIndex(row, 2).cellStyle.backColor = yearLevelColor;
      sheet.getRangeByIndex(row, 2).cellStyle.borders.all.lineStyle =
          LineStyle.thin;

      // Status (with color coding)
      sheet.getRangeByIndex(row, 3).setText(statusText);
      sheet.getRangeByIndex(row, 3).cellStyle.backColor = statusColor;
      sheet.getRangeByIndex(row, 3).cellStyle.bold = true;
      sheet.getRangeByIndex(row, 3).cellStyle.hAlign = HAlignType.center;
      sheet.getRangeByIndex(row, 3).cellStyle.borders.all.lineStyle =
          LineStyle.thin;

      // Packs (Expected vs Actual)
      final packsText = _getPacksStatusText(
          detail.expectedPacks, detail.actualPacksDelivered);
      sheet.getRangeByIndex(row, 4).setText(packsText);
      sheet.getRangeByIndex(row, 4).cellStyle.hAlign = HAlignType.center;
      sheet.getRangeByIndex(row, 4).cellStyle.borders.all.lineStyle =
          LineStyle.thin;
      if (detail.actualPacksDelivered != null &&
          detail.actualPacksDelivered != detail.expectedPacks) {
        sheet.getRangeByIndex(row, 4).cellStyle.backColor =
            '#FFE0B2'; // Light orange for partial
      }

      // Consumables summary
      final consumablesText = _getConsumablesStatusText(detail.consumables);
      sheet.getRangeByIndex(row, 5).setText(consumablesText);
      sheet.getRangeByIndex(row, 5).cellStyle.wrapText = true;
      sheet.getRangeByIndex(row, 5).cellStyle.borders.all.lineStyle =
          LineStyle.thin;
      sheet.getRangeByIndex(row, 5).cellStyle.vAlign = VAlignType.top;

      // Notes (from notesByClassroom if available)
      final notes =
          summary.notesByClassroom[detail.yearLevel]?[detail.classroomName];
      if (notes != null && notes.isNotEmpty) {
        final notesText = '• ${notes.join('\n• ')}';
        sheet.getRangeByIndex(row, 6).setText(notesText);
        sheet.getRangeByIndex(row, 6).cellStyle.wrapText = true;
        sheet.getRangeByIndex(row, 6).cellStyle.backColor =
            '#FFF9C4'; // Light yellow
        sheet.getRangeByIndex(row, 6).cellStyle.borders.all.lineStyle =
            LineStyle.thin;
        sheet.getRangeByIndex(row, 6).cellStyle.vAlign = VAlignType.top;
        sheet.getRangeByIndex(row, 6).rowHeight =
            30 + (notes.length * 15).toDouble();
      } else {
        sheet.getRangeByIndex(row, 6).setText('-');
        sheet.getRangeByIndex(row, 6).cellStyle.hAlign = HAlignType.center;
        sheet.getRangeByIndex(row, 6).cellStyle.borders.all.lineStyle =
            LineStyle.thin;
      }

      row++;
    }

    row++; // Spacer
    return row;
  }

  static int _addConsumablesSummary(
      Worksheet sheet, SignedSchoolSummary summary, int row) {
    _addSectionHeader(sheet, row++, 'CONSUMABLES SUMMARY', '#00BCD4'); // Cyan

    // Table headers
    _addTableHeader(sheet, row, ['Item', 'Quantity', 'Unit']);
    row++;

    // Data rows
    for (final entry in summary.consumablesTotals.entries) {
      final consumable = entry.value;
      sheet.getRangeByIndex(row, 1).setText(consumable.itemName);
      sheet.getRangeByIndex(row, 2).setNumber(consumable.quantity.toDouble());
      sheet.getRangeByIndex(row, 2).cellStyle.hAlign = HAlignType.center;
      sheet.getRangeByIndex(row, 3).setText(consumable.unit);
      _addAlternatingRowColor(sheet, row, 3);
      row++;
    }

    row++; // Spacer
    return row;
  }

  static int _addConsumablesByYearLevel(
      Worksheet sheet, SignedSchoolSummary summary, int row) {
    _addSectionHeader(sheet, row++, 'CONSUMABLES BY YEAR LEVEL', '#3F51B5');

    // Table headers
    _addTableHeader(sheet, row, ['Year Level', 'Item', 'Quantity', 'Unit']);
    row++;

    // Data rows with year level color coding
    for (final yearEntry in summary.consumablesByYearLevel.entries) {
      final yearLevel = yearEntry.key;
      final color = _getYearLevelColor(yearLevel);

      for (final itemEntry in yearEntry.value.entries) {
        final consumable = itemEntry.value;

        // Apply year level color to entire row
        sheet.getRangeByIndex(row, 1).setText(yearLevel);
        sheet.getRangeByIndex(row, 1).cellStyle.backColor = color;
        sheet.getRangeByIndex(row, 1).cellStyle.borders.all.lineStyle =
            LineStyle.thin;

        sheet.getRangeByIndex(row, 2).setText(consumable.itemName);
        sheet.getRangeByIndex(row, 2).cellStyle.backColor = color;
        sheet.getRangeByIndex(row, 2).cellStyle.borders.all.lineStyle =
            LineStyle.thin;

        sheet.getRangeByIndex(row, 3).setNumber(consumable.quantity.toDouble());
        sheet.getRangeByIndex(row, 3).cellStyle.hAlign = HAlignType.center;
        sheet.getRangeByIndex(row, 3).cellStyle.backColor = color;
        sheet.getRangeByIndex(row, 3).cellStyle.borders.all.lineStyle =
            LineStyle.thin;

        sheet.getRangeByIndex(row, 4).setText(consumable.unit);
        sheet.getRangeByIndex(row, 4).cellStyle.backColor = color;
        sheet.getRangeByIndex(row, 4).cellStyle.borders.all.lineStyle =
            LineStyle.thin;
        row++;
      }
    }

    row++; // Spacer
    return row;
  }

  static int _addConsumablesByClassroom(
      Worksheet sheet, SignedSchoolSummary summary, int row) {
    _addSectionHeader(sheet, row++, 'CONSUMABLES BY CLASSROOM', '#795548');

    // Table headers
    _addTableHeader(
        sheet, row, ['Year Level', 'Classroom', 'Item', 'Quantity', 'Unit']);
    row++;

    // Data rows with year level color coding
    for (final yearEntry in summary.consumablesByClassroom.entries) {
      final yearLevel = yearEntry.key;
      final color = _getYearLevelColor(yearLevel);

      for (final classEntry in yearEntry.value.entries) {
        final classroom = classEntry.key;
        for (final itemEntry in classEntry.value.entries) {
          final consumable = itemEntry.value;

          // Apply year level color to entire row
          sheet.getRangeByIndex(row, 1).setText(yearLevel);
          sheet.getRangeByIndex(row, 1).cellStyle.backColor = color;
          sheet.getRangeByIndex(row, 1).cellStyle.borders.all.lineStyle =
              LineStyle.thin;

          sheet.getRangeByIndex(row, 2).setText(classroom);
          sheet.getRangeByIndex(row, 2).cellStyle.backColor = color;
          sheet.getRangeByIndex(row, 2).cellStyle.borders.all.lineStyle =
              LineStyle.thin;

          sheet.getRangeByIndex(row, 3).setText(consumable.itemName);
          sheet.getRangeByIndex(row, 3).cellStyle.backColor = color;
          sheet.getRangeByIndex(row, 3).cellStyle.borders.all.lineStyle =
              LineStyle.thin;

          sheet
              .getRangeByIndex(row, 4)
              .setNumber(consumable.quantity.toDouble());
          sheet.getRangeByIndex(row, 4).cellStyle.hAlign = HAlignType.center;
          sheet.getRangeByIndex(row, 4).cellStyle.backColor = color;
          sheet.getRangeByIndex(row, 4).cellStyle.borders.all.lineStyle =
              LineStyle.thin;

          sheet.getRangeByIndex(row, 5).setText(consumable.unit);
          sheet.getRangeByIndex(row, 5).cellStyle.backColor = color;
          sheet.getRangeByIndex(row, 5).cellStyle.borders.all.lineStyle =
              LineStyle.thin;
          row++;
        }
      }
    }

    row++; // Spacer
    return row;
  }

  static int _addPhotosSection(
      Worksheet sheet, SignedSchoolSummary summary, int row) {
    _addSectionHeader(sheet, row++, 'DELIVERY PHOTOS', '#607D8B'); // Blue Grey

    _addKeyValue(
        sheet, row++, 'Total Photos:', summary.photoUrls.length.toString(),
        isBold: true);
    row++;

    // Photo URLs
    sheet.getRangeByIndex(row, 1).setText('Photo URLs:');
    sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
    row++;

    for (int i = 0; i < summary.photoUrls.length; i++) {
      final urlCell = sheet.getRangeByIndex(row, 1, row, 5);
      urlCell.merge();

      final hyperlink = sheet.hyperlinks
          .add(urlCell, HyperlinkType.url, summary.photoUrls[i]);
      hyperlink.screenTip = 'Click to view photo ${i + 1}';
      hyperlink.textToDisplay = 'Photo ${i + 1}';

      urlCell.cellStyle.fontColor = '#1976D2';
      urlCell.cellStyle.underline = true;
      row++;
    }

    row++; // Spacer
    return row;
  }

  static int _addNotesSection(
      Worksheet sheet, SignedSchoolSummary summary, int row) {
    _addSectionHeader(sheet, row++, 'DELIVERY NOTES', '#FFC107'); // Amber

    final notesCell = sheet.getRangeByIndex(row, 1, row, 5);
    notesCell.merge();
    notesCell.setText(summary.notes!);
    notesCell.cellStyle.wrapText = true;
    notesCell.cellStyle.backColor = '#FFF9C4';
    notesCell.cellStyle.borders.all.lineStyle = LineStyle.thin;
    notesCell.rowHeight = 60;
    row += 2;

    return row;
  }

  static int _addClassroomNotesSection(
      Worksheet sheet, SignedSchoolSummary summary, int row) {
    _addSectionHeader(sheet, row++, 'CLASSROOM NOTES', '#FFC107'); // Amber

    // Table headers
    _addTableHeader(sheet, row, ['Year Level', 'Classroom', 'Notes']);
    row++;

    // Data rows grouped by year level
    for (final yearEntry in summary.notesByClassroom.entries) {
      final yearLevel = yearEntry.key;
      final color = _getYearLevelColor(yearLevel);

      for (final classEntry in yearEntry.value.entries) {
        final classroom = classEntry.key;
        final notes = classEntry.value;

        if (notes.isEmpty) continue;

        // Combine all notes for this classroom into a single cell with line breaks
        final notesText = notes.map((note) {
          // Parse note format: "content (by author)" or just "content"
          return note;
        }).join('\n• ');

        // Apply year level color to entire row
        sheet.getRangeByIndex(row, 1).setText(yearLevel);
        sheet.getRangeByIndex(row, 1).cellStyle.backColor = color;
        sheet.getRangeByIndex(row, 1).cellStyle.borders.all.lineStyle =
            LineStyle.thin;
        sheet.getRangeByIndex(row, 1).cellStyle.vAlign = VAlignType.top;

        sheet.getRangeByIndex(row, 2).setText(classroom);
        sheet.getRangeByIndex(row, 2).cellStyle.backColor = color;
        sheet.getRangeByIndex(row, 2).cellStyle.borders.all.lineStyle =
            LineStyle.thin;
        sheet.getRangeByIndex(row, 2).cellStyle.vAlign = VAlignType.top;

        final notesCell = sheet.getRangeByIndex(row, 3, row, 5);
        notesCell.merge();
        notesCell.setText('• $notesText');
        notesCell.cellStyle.wrapText = true;
        notesCell.cellStyle.backColor = '#FFF9C4'; // Light yellow for notes
        notesCell.cellStyle.borders.all.lineStyle = LineStyle.thin;
        notesCell.cellStyle.vAlign = VAlignType.top;

        // Set row height based on number of notes (minimum 30, +20 per note)
        notesCell.rowHeight = 30 + (notes.length * 20).toDouble();

        row++;
      }
    }

    row++; // Spacer
    return row;
  }

  static int _addSignatureSection(
      Worksheet sheet, SignedSchoolSummary summary, int row) {
    row++; // Extra spacer

    final signatureRange = sheet.getRangeByIndex(row, 1, row, 5);
    signatureRange.merge();
    signatureRange.setText('This document was electronically signed');
    signatureRange.cellStyle.italic = true;
    signatureRange.cellStyle.hAlign = HAlignType.center;
    signatureRange.cellStyle.backColor = '#F5F5F5';
    row++;

    if (summary.signatureUrl != null) {
      final urlCell = sheet.getRangeByIndex(row, 1, row, 5);
      urlCell.merge();

      final hyperlink = sheet.hyperlinks
          .add(urlCell, HyperlinkType.url, summary.signatureUrl!);
      hyperlink.screenTip = 'Click to view signature';
      hyperlink.textToDisplay = 'View Digital Signature';

      urlCell.cellStyle.fontColor = '#1976D2';
      urlCell.cellStyle.underline = true;
      urlCell.cellStyle.hAlign = HAlignType.center;
      row++;
    }

    return row;
  }

  // === HELPER METHODS ===

  /// Get color for year level based on coding system
  /// Prep = White, Year 1 = Red, Year 2 = Blue, Year 3 = Green,
  /// Year 4 = Purple, Year 5 = Yellow, Year 6 = Orange
  /// For composite classes (e.g. Year 1/2), uses the upper year level color
  static String _getYearLevelColor(String yearLevel) {
    final yearLevelLower = yearLevel.toLowerCase();

    // For composite year levels, extract the highest year number
    if (yearLevelLower.contains('/')) {
      final parts = yearLevelLower.split('/');
      final numbers = parts
          .map((p) {
            final match = RegExp(r'\d+').firstMatch(p);
            return match != null ? int.tryParse(match.group(0)!) : null;
          })
          .where((n) => n != null)
          .toList();

      if (numbers.isNotEmpty) {
        final maxYear = numbers.reduce((a, b) => (a! > b!) ? a : b);
        yearLevel = 'year $maxYear';
      }
    }

    // Match year level to color
    if (yearLevelLower.contains('prep') ||
        yearLevelLower.contains('foundation')) {
      return '#FFFFFF'; // White (with border for visibility)
    } else if (yearLevelLower.contains('year 1') ||
        yearLevelLower.contains('year1')) {
      return '#FFCDD2'; // Light Red
    } else if (yearLevelLower.contains('year 2') ||
        yearLevelLower.contains('year2')) {
      return '#BBDEFB'; // Light Blue
    } else if (yearLevelLower.contains('year 3') ||
        yearLevelLower.contains('year3')) {
      return '#C8E6C9'; // Light Green
    } else if (yearLevelLower.contains('year 4') ||
        yearLevelLower.contains('year4')) {
      return '#E1BEE7'; // Light Purple
    } else if (yearLevelLower.contains('year 5') ||
        yearLevelLower.contains('year5')) {
      return '#FFF9C4'; // Light Yellow
    } else if (yearLevelLower.contains('year 6') ||
        yearLevelLower.contains('year6')) {
      return '#FFE0B2'; // Light Orange
    }

    return '#FFFFFF'; // Default white
  }

  static void _addSectionHeader(
      Worksheet sheet, int row, String title, String color) {
    final headerRange = sheet.getRangeByIndex(row, 1, row, 5);
    headerRange.merge();
    headerRange.setText(title);
    headerRange.cellStyle.bold = true;
    headerRange.cellStyle.fontSize = 12;
    headerRange.cellStyle.backColor = '#424242'; // Dark grey
    headerRange.cellStyle.fontColor = '#FFFFFF';
    headerRange.cellStyle.hAlign = HAlignType.left;
    headerRange.rowHeight = 25;
  }

  static void _addTableHeader(Worksheet sheet, int row, List<String> headers) {
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(row, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#E0E0E0';
      cell.cellStyle.borders.all.lineStyle = LineStyle.thin;
      cell.cellStyle.hAlign = HAlignType.center;
    }
  }

  static void _addKeyValue(Worksheet sheet, int row, String key, String value,
      {bool isBold = false}) {
    final keyCell = sheet.getRangeByIndex(row, 1);
    keyCell.setText(key);
    keyCell.cellStyle.bold = true;

    final valueCell = sheet.getRangeByIndex(row, 2, row, 5);
    valueCell.merge();
    valueCell.setText(value);
    if (isBold) {
      valueCell.cellStyle.bold = true;
    }
  }

  static void _addAlternatingRowColor(Worksheet sheet, int row, int columnCount,
      {int startIndex = 0}) {
    final actualIndex = row - startIndex;
    if (actualIndex % 2 == 0) {
      for (int col = 1; col <= columnCount; col++) {
        sheet.getRangeByIndex(row, col).cellStyle.backColor = '#F9F9F9';
      }
    }

    // Add borders to all cells
    for (int col = 1; col <= columnCount; col++) {
      sheet.getRangeByIndex(row, col).cellStyle.borders.all.lineStyle =
          LineStyle.thin;
      sheet.getRangeByIndex(row, col).cellStyle.borders.all.color = '#E0E0E0';
    }
  }

  static String _formatDateTime(DateTime date) {
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  /// Get color for classroom completion status
  static String _getStatusColor(ClassroomCompletionStatus status) {
    switch (status) {
      case ClassroomCompletionStatus.complete:
        return '#C8E6C9'; // Light green
      case ClassroomCompletionStatus.incomplete:
        return '#FFE0B2'; // Light orange
      case ClassroomCompletionStatus.notAttended:
        return '#FFCDD2'; // Light red
    }
  }

  /// Get text for classroom completion status
  static String _getStatusText(ClassroomCompletionStatus status) {
    switch (status) {
      case ClassroomCompletionStatus.complete:
        return 'COMPLETE';
      case ClassroomCompletionStatus.incomplete:
        return 'INCOMPLETE';
      case ClassroomCompletionStatus.notAttended:
        return 'NOT ATTENDED';
    }
  }

  /// Get pack status text showing expected vs actual
  static String _getPacksStatusText(int expected, int? actual) {
    if (actual == null) {
      return '$expected (not set)';
    } else if (actual == expected) {
      return '$actual/$expected ✓';
    } else {
      return '$actual/$expected';
    }
  }

  /// Get consumables status summary text
  static String _getConsumablesStatusText(
      Map<String, ConsumableDeliveryDetail> consumables) {
    if (consumables.isEmpty) {
      return 'No consumables';
    }

    final items = <String>[];
    for (final consumable in consumables.values) {
      final actual = consumable.actualQuantityDelivered;
      final expected = consumable.expectedQuantity;

      if (actual == null) {
        items.add(
            '${consumable.itemName}: $expected ${consumable.unit} (not set)');
      } else if (actual == expected) {
        items.add(
            '${consumable.itemName}: $actual/$expected ${consumable.unit} ✓');
      } else {
        items.add(
            '${consumable.itemName}: $actual/$expected ${consumable.unit}');
      }
    }

    return items.join('\n');
  }
}
