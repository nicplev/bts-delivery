import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/season_export_models.dart';
import '../models/school.dart';

/// Service for generating end-of-season Excel reports
class SeasonExportService {
  /// Generate comprehensive season report Excel file
  static Future<String?> generateSeasonReport(
    SeasonData data,
    SeasonExportOptions options,
  ) async {
    try {
      final Workbook workbook = Workbook();

      // Track if we've used the default sheet
      bool usedDefaultSheet = false;

      Worksheet getOrAddSheet(String name) {
        if (!usedDefaultSheet) {
          usedDefaultSheet = true;
          final sheet = workbook.worksheets[0];
          sheet.name = name;
          return sheet;
        }
        return workbook.worksheets.addWithName(name);
      }

      // Add sheets based on options
      if (options.includeOverview) {
        final sheet = getOrAddSheet('Season Overview');
        _addOverviewSheet(sheet, data);
      }

      if (options.includeSchools) {
        final sheet = getOrAddSheet('Schools');
        _addSchoolsSheet(sheet, data);
      }

      if (options.includeDeliveries) {
        final sheet = getOrAddSheet('Deliveries');
        _addDeliveriesSheet(sheet, data);
      }

      if (options.includeStaff) {
        final sheet = getOrAddSheet('Staff Performance');
        _addStaffSheet(sheet, data);
      }

      if (options.includeClassrooms) {
        final sheet = getOrAddSheet('Classroom Details');
        _addClassroomDetailsSheet(sheet, data);
      }

      if (options.includeConsumables) {
        final sheet = getOrAddSheet('Consumables');
        _addConsumablesSheet(sheet, data);
      }

      if (options.includeTimerAggregate) {
        final sheet = getOrAddSheet('Timer Summary');
        _addTimerAggregateSheet(sheet, data);
      }

      if (options.includeTimerDetails) {
        final sheet = getOrAddSheet('Timer Details');
        _addTimerDetailsSheet(sheet, data);
      }

      // Save the file
      final bytes = workbook.saveAsStream();
      workbook.dispose();

      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'Season_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final filePath = '${directory.path}/$fileName';

      final file = File(filePath);
      await file.writeAsBytes(bytes);

      debugPrint('Season report created: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('Error generating season report: $e');
      rethrow;
    }
  }

  /// Share the Excel file
  static Future<void> shareExcelFile(String filePath) async {
    try {
      final file = XFile(
        filePath,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: filePath.split('/').last,
      );

      await Share.shareXFiles(
        [file],
        subject: 'Season Report',
        text: 'End-of-season delivery report',
      );
    } catch (e) {
      debugPrint('Error sharing Excel file: $e');
      rethrow;
    }
  }

  // === SHEET BUILDERS ===

  static void _addOverviewSheet(Worksheet sheet, SeasonData data) {
    int row = 1;
    final overview = data.overview;

    // Title
    final titleRange = sheet.getRangeByIndex(row, 1, row, 4);
    titleRange.merge();
    titleRange.setText('SEASON OVERVIEW REPORT');
    titleRange.cellStyle.bold = true;
    titleRange.cellStyle.fontSize = 18;
    titleRange.cellStyle.hAlign = HAlignType.center;
    titleRange.cellStyle.backColor = '#1976D2';
    titleRange.cellStyle.fontColor = '#FFFFFF';
    titleRange.rowHeight = 35;
    row += 2;

    // Date range
    _addKeyValue(sheet, row++, 'Report Generated:', DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()));
    if (overview.firstDeliveryDate != null && overview.lastDeliveryDate != null) {
      _addKeyValue(sheet, row++, 'Delivery Period:', overview.deliveryDateRange);
    }
    row++;

    // Key metrics section
    _addSectionHeader(sheet, row++, 'KEY METRICS', '#4CAF50');

    final metrics = [
      ['Total Schools Serviced', overview.totalSchools.toString()],
      ['Total Deliveries Made', overview.totalDeliveries.toString()],
      ['Total Packs Delivered', overview.totalPacksDelivered.toString()],
      ['Total Staff Involved', overview.totalStaffInvolved.toString()],
      ['Schools Signed Off', '${overview.schoolsSignedOff} / ${overview.totalSchools}'],
    ];

    for (final metric in metrics) {
      _addKeyValue(sheet, row++, metric[0], metric[1], isBold: true);
    }
    row++;

    // Completion status section
    _addSectionHeader(sheet, row++, 'CLASSROOM COMPLETION STATUS', '#FF9800');

    final total = overview.totalClassrooms;
    final complete = overview.classroomsComplete;
    final incomplete = overview.classroomsIncomplete;
    final notAttended = overview.classroomsNotAttended;
    final rate = total > 0 ? (complete / total * 100).toStringAsFixed(1) : '0.0';

    _addKeyValue(sheet, row++, 'Total Classrooms', total.toString());
    _addKeyValue(sheet, row++, 'Complete', '$complete (${_percent(complete, total)})');
    _addKeyValue(sheet, row++, 'Incomplete', '$incomplete (${_percent(incomplete, total)})');
    _addKeyValue(sheet, row++, 'Not Attended', '$notAttended (${_percent(notAttended, total)})');
    _addKeyValue(sheet, row++, 'Completion Rate', '$rate%', isBold: true);
    row++;

    // Consumables summary
    if (overview.totalConsumablesByType.isNotEmpty) {
      _addSectionHeader(sheet, row++, 'CONSUMABLES DELIVERED', '#9C27B0');

      for (final entry in overview.totalConsumablesByType.entries) {
        _addKeyValue(sheet, row++, entry.key, entry.value.toString());
      }
    }

    // Auto-fit columns
    for (int col = 1; col <= 4; col++) {
      sheet.autoFitColumn(col);
    }
  }

  static void _addSchoolsSheet(Worksheet sheet, SeasonData data) {
    int row = 1;

    // Title
    _addSheetTitle(sheet, row++, 'SCHOOLS DATA');
    row++;

    // Headers
    final headers = [
      'School Name', 'Address', 'Total Packs', 'Year Levels', 'Classrooms',
      'Total Time', 'Visits', 'Avg Time/Visit', 'Complete', 'Incomplete',
      'Not Attended', 'Signed Off', 'Sign-off Date', 'Notes'
    ];
    _addTableHeader(sheet, row++, headers);

    // Data rows
    for (final school in data.schools) {
      int col = 1;
      sheet.getRangeByIndex(row, col++).setText(school.school.name);
      sheet.getRangeByIndex(row, col++).setText(school.school.address ?? '-');
      sheet.getRangeByIndex(row, col++).setNumber(school.totalPacks.toDouble());
      sheet.getRangeByIndex(row, col++).setNumber(school.yearLevelCount.toDouble());
      sheet.getRangeByIndex(row, col++).setNumber(school.classroomCount.toDouble());
      sheet.getRangeByIndex(row, col++).setText(school.formattedTotalTime);
      sheet.getRangeByIndex(row, col++).setNumber(school.visitCount.toDouble());
      sheet.getRangeByIndex(row, col++).setText(school.formattedAverageTime);
      sheet.getRangeByIndex(row, col++).setNumber(school.completeCount.toDouble());
      sheet.getRangeByIndex(row, col++).setNumber(school.incompleteCount.toDouble());
      sheet.getRangeByIndex(row, col++).setNumber(school.notAttendedCount.toDouble());
      sheet.getRangeByIndex(row, col++).setText(school.isSignedOff ? 'Yes' : 'No');
      sheet.getRangeByIndex(row, col++).setText(
        school.signOffDate != null
            ? DateFormat('dd/MM/yyyy').format(school.signOffDate!)
            : '-',
      );
      sheet.getRangeByIndex(row, col++).setNumber(school.notesCount.toDouble());

      // Styling
      _addAlternatingRowColor(sheet, row, headers.length);
      if (school.isSignedOff) {
        sheet.getRangeByIndex(row, 12).cellStyle.backColor = '#C8E6C9';
      }
      row++;
    }

    // Auto-fit columns
    for (int col = 1; col <= headers.length; col++) {
      sheet.autoFitColumn(col);
    }
  }

  static void _addDeliveriesSheet(Worksheet sheet, SeasonData data) {
    int row = 1;

    _addSheetTitle(sheet, row++, 'DELIVERY LOG');
    row++;

    final headers = [
      'Date', 'Day', 'Time', 'School', 'Staff Assigned',
      'Vehicles', 'Pallets', 'Notes'
    ];
    _addTableHeader(sheet, row++, headers);

    for (final delivery in data.deliveries) {
      int col = 1;
      sheet.getRangeByIndex(row, col++).setText(
        DateFormat('dd/MM/yyyy').format(delivery.date),
      );
      sheet.getRangeByIndex(row, col++).setText(_getDayOfWeek(delivery.date));
      sheet.getRangeByIndex(row, col++).setText(
        delivery.time != null
            ? DateFormat('HH:mm').format(delivery.time!)
            : '-',
      );
      sheet.getRangeByIndex(row, col++).setText(delivery.schoolName);
      sheet.getRangeByIndex(row, col++).setText(
        delivery.staffNames.isNotEmpty ? delivery.staffNames.join(', ') : '-',
      );
      sheet.getRangeByIndex(row, col++).setText(
        delivery.vehicleCount?.toString() ?? '-',
      );
      sheet.getRangeByIndex(row, col++).setText(
        delivery.palletCount?.toString() ?? '-',
      );
      sheet.getRangeByIndex(row, col++).setText(delivery.notes ?? '-');

      _addAlternatingRowColor(sheet, row, headers.length);
      row++;
    }

    for (int col = 1; col <= headers.length; col++) {
      sheet.autoFitColumn(col);
    }
  }

  static void _addStaffSheet(Worksheet sheet, SeasonData data) {
    int row = 1;

    _addSheetTitle(sheet, row++, 'STAFF PERFORMANCE');
    row++;

    final headers = [
      'Staff Name', 'Role', 'Assigned Schools', 'Deliveries Participated',
      'Total Time', 'Schools Completed', 'Schools Serviced'
    ];
    _addTableHeader(sheet, row++, headers);

    for (final staff in data.staffPerformance) {
      int col = 1;
      sheet.getRangeByIndex(row, col++).setText(staff.staff.name);
      sheet.getRangeByIndex(row, col++).setText(
        staff.staff.hasManagerAccess ? 'Manager' : 'Staff',
      );
      sheet.getRangeByIndex(row, col++).setNumber(staff.assignedSchoolsCount.toDouble());
      sheet.getRangeByIndex(row, col++).setNumber(staff.deliveriesParticipated.toDouble());
      sheet.getRangeByIndex(row, col++).setText(staff.formattedTotalTime);
      sheet.getRangeByIndex(row, col++).setNumber(staff.schoolsCompleted.toDouble());
      sheet.getRangeByIndex(row, col++).setText(staff.schoolNamesServiced.join(', '));

      _addAlternatingRowColor(sheet, row, headers.length);
      row++;
    }

    for (int col = 1; col <= headers.length; col++) {
      sheet.autoFitColumn(col);
    }
  }

  static void _addClassroomDetailsSheet(Worksheet sheet, SeasonData data) {
    int row = 1;

    _addSheetTitle(sheet, row++, 'CLASSROOM DETAILS WITH VARIANCE');
    row++;

    final headers = [
      'School', 'Year Level', 'Classroom', 'Status',
      'Expected Packs', 'Actual Packs', 'Pack Variance', 'Has Discrepancy'
    ];
    _addTableHeader(sheet, row++, headers);

    for (final classroom in data.classroomVariances) {
      int col = 1;
      sheet.getRangeByIndex(row, col++).setText(classroom.schoolName);

      // Year level with color coding
      final yearLevelCell = sheet.getRangeByIndex(row, col++);
      yearLevelCell.setText(classroom.yearLevel);
      yearLevelCell.cellStyle.backColor = _getYearLevelColor(classroom.yearLevel);

      sheet.getRangeByIndex(row, col++).setText(classroom.classroomName);

      // Status with color coding
      final statusCell = sheet.getRangeByIndex(row, col++);
      statusCell.setText(_getStatusText(classroom.status));
      statusCell.cellStyle.backColor = _getStatusColor(classroom.status);
      statusCell.cellStyle.bold = true;

      sheet.getRangeByIndex(row, col++).setNumber(classroom.expectedPacks.toDouble());
      sheet.getRangeByIndex(row, col++).setNumber(
        (classroom.actualPacks ?? classroom.expectedPacks).toDouble(),
      );

      // Variance with conditional coloring
      final varianceCell = sheet.getRangeByIndex(row, col++);
      final variance = classroom.packVariance;
      varianceCell.setNumber(variance.toDouble());
      if (variance < 0) {
        varianceCell.cellStyle.backColor = '#FFCDD2'; // Red for shortfall
        varianceCell.cellStyle.fontColor = '#B71C1C';
      } else if (variance > 0) {
        varianceCell.cellStyle.backColor = '#FFE0B2'; // Orange for excess
      } else {
        varianceCell.cellStyle.backColor = '#C8E6C9'; // Green for match
      }

      // Discrepancy indicator
      final discrepancyCell = sheet.getRangeByIndex(row, col++);
      discrepancyCell.setText(classroom.hasAnyDiscrepancy ? 'Yes' : 'No');
      if (classroom.hasAnyDiscrepancy) {
        discrepancyCell.cellStyle.backColor = '#FFCDD2';
        discrepancyCell.cellStyle.bold = true;
      }

      row++;
    }

    for (int col = 1; col <= headers.length; col++) {
      sheet.autoFitColumn(col);
    }
  }

  static void _addConsumablesSheet(Worksheet sheet, SeasonData data) {
    int row = 1;

    _addSheetTitle(sheet, row++, 'CONSUMABLES SUMMARY');
    row++;

    final headers = [
      'Item Name', 'Unit', 'Total Quantity', 'Schools Using',
      'Avg per School', 'Max at Single School'
    ];
    _addTableHeader(sheet, row++, headers);

    for (final consumable in data.consumableAggregates) {
      int col = 1;
      sheet.getRangeByIndex(row, col++).setText(consumable.itemName);
      sheet.getRangeByIndex(row, col++).setText(consumable.unit);
      sheet.getRangeByIndex(row, col++).setNumber(consumable.totalQuantity.toDouble());
      sheet.getRangeByIndex(row, col++).setNumber(consumable.schoolsUsingCount.toDouble());
      sheet.getRangeByIndex(row, col++).setNumber(consumable.averagePerSchool);
      sheet.getRangeByIndex(row, col++).setNumber(consumable.maxAtSingleSchool.toDouble());

      _addAlternatingRowColor(sheet, row, headers.length);
      row++;
    }

    for (int col = 1; col <= headers.length; col++) {
      sheet.autoFitColumn(col);
    }
  }

  static void _addTimerAggregateSheet(Worksheet sheet, SeasonData data) {
    int row = 1;

    _addSheetTitle(sheet, row++, 'TIMER SUMMARY BY SCHOOL');
    row++;

    final headers = [
      'School', 'Total Visits', 'Total Time', 'Avg per Visit',
      'Min Duration', 'Max Duration'
    ];
    _addTableHeader(sheet, row++, headers);

    for (final timer in data.timerAggregates) {
      int col = 1;
      sheet.getRangeByIndex(row, col++).setText(timer.schoolName);
      sheet.getRangeByIndex(row, col++).setNumber(timer.totalVisits.toDouble());
      sheet.getRangeByIndex(row, col++).setText(timer.formattedTotalTime);
      sheet.getRangeByIndex(row, col++).setText(timer.formattedAverageTime);
      sheet.getRangeByIndex(row, col++).setText(timer.formattedMinTime ?? '-');
      sheet.getRangeByIndex(row, col++).setText(timer.formattedMaxTime ?? '-');

      _addAlternatingRowColor(sheet, row, headers.length);
      row++;
    }

    for (int col = 1; col <= headers.length; col++) {
      sheet.autoFitColumn(col);
    }
  }

  static void _addTimerDetailsSheet(Worksheet sheet, SeasonData data) {
    int row = 1;

    _addSheetTitle(sheet, row++, 'TIMER DETAILS');
    row++;

    final headers = [
      'School', 'Date', 'Day', 'Start Time', 'End Time',
      'Duration', 'Started By', 'Stopped By'
    ];
    _addTableHeader(sheet, row++, headers);

    for (final timer in data.timerDetails) {
      int col = 1;
      sheet.getRangeByIndex(row, col++).setText(timer.schoolName);
      sheet.getRangeByIndex(row, col++).setText(
        DateFormat('dd/MM/yyyy').format(timer.visitDate),
      );
      sheet.getRangeByIndex(row, col++).setText(timer.dayOfWeek);
      sheet.getRangeByIndex(row, col++).setText(
        DateFormat('HH:mm').format(timer.startTime),
      );
      sheet.getRangeByIndex(row, col++).setText(
        timer.endTime != null
            ? DateFormat('HH:mm').format(timer.endTime!)
            : '-',
      );
      sheet.getRangeByIndex(row, col++).setText(timer.formattedDuration);
      sheet.getRangeByIndex(row, col++).setText(timer.startedBy);
      sheet.getRangeByIndex(row, col++).setText(timer.stoppedBy ?? '-');

      _addAlternatingRowColor(sheet, row, headers.length);
      row++;
    }

    for (int col = 1; col <= headers.length; col++) {
      sheet.autoFitColumn(col);
    }
  }

  // === HELPER METHODS ===

  static void _addSheetTitle(Worksheet sheet, int row, String title) {
    final titleRange = sheet.getRangeByIndex(row, 1, row, 8);
    titleRange.merge();
    titleRange.setText(title);
    titleRange.cellStyle.bold = true;
    titleRange.cellStyle.fontSize = 16;
    titleRange.cellStyle.hAlign = HAlignType.center;
    titleRange.cellStyle.backColor = '#1976D2';
    titleRange.cellStyle.fontColor = '#FFFFFF';
    titleRange.rowHeight = 30;
  }

  static void _addSectionHeader(Worksheet sheet, int row, String title, String color) {
    final headerRange = sheet.getRangeByIndex(row, 1, row, 4);
    headerRange.merge();
    headerRange.setText(title);
    headerRange.cellStyle.bold = true;
    headerRange.cellStyle.fontSize = 12;
    headerRange.cellStyle.backColor = '#424242';
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

  static void _addKeyValue(Worksheet sheet, int row, String key, String value, {bool isBold = false}) {
    final keyCell = sheet.getRangeByIndex(row, 1);
    keyCell.setText(key);
    keyCell.cellStyle.bold = true;

    final valueCell = sheet.getRangeByIndex(row, 2, row, 4);
    valueCell.merge();
    valueCell.setText(value);
    if (isBold) {
      valueCell.cellStyle.bold = true;
    }
  }

  static void _addAlternatingRowColor(Worksheet sheet, int row, int columnCount) {
    if (row % 2 == 0) {
      for (int col = 1; col <= columnCount; col++) {
        sheet.getRangeByIndex(row, col).cellStyle.backColor = '#F9F9F9';
      }
    }
    for (int col = 1; col <= columnCount; col++) {
      sheet.getRangeByIndex(row, col).cellStyle.borders.all.lineStyle = LineStyle.thin;
      sheet.getRangeByIndex(row, col).cellStyle.borders.all.color = '#E0E0E0';
    }
  }

  static String _getYearLevelColor(String yearLevel) {
    final yearLevelLower = yearLevel.toLowerCase();

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
        return _getYearColor(maxYear!);
      }
    }

    final match = RegExp(r'\d+').firstMatch(yearLevelLower);
    if (match != null) {
      final year = int.tryParse(match.group(0)!);
      if (year != null) {
        return _getYearColor(year);
      }
    }

    if (yearLevelLower.contains('prep') || yearLevelLower.contains('foundation')) {
      return '#FFFFFF';
    }

    return '#FFFFFF';
  }

  static String _getYearColor(int year) {
    switch (year) {
      case 1:
        return '#FFCDD2'; // Light Red
      case 2:
        return '#BBDEFB'; // Light Blue
      case 3:
        return '#C8E6C9'; // Light Green
      case 4:
        return '#E1BEE7'; // Light Purple
      case 5:
        return '#FFF9C4'; // Light Yellow
      case 6:
        return '#FFE0B2'; // Light Orange
      default:
        return '#FFFFFF';
    }
  }

  static String _getStatusColor(ClassroomCompletionStatus status) {
    switch (status) {
      case ClassroomCompletionStatus.complete:
        return '#C8E6C9';
      case ClassroomCompletionStatus.incomplete:
        return '#FFE0B2';
      case ClassroomCompletionStatus.notAttended:
        return '#FFCDD2';
    }
  }

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

  static String _getDayOfWeek(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  static String _percent(int value, int total) {
    if (total == 0) return '0%';
    return '${(value / total * 100).toStringAsFixed(1)}%';
  }
}
