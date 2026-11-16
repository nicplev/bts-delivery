import 'package:csv/csv.dart';
import '../repositories/schools_repository.dart'
    show YearLevelImportData, ClassroomImportData, ConsumableImportData, StudentBreakdownImportData;

/// Service for parsing CSV files and importing classroom data
class CSVImportService {
  /// Parse CSV data and convert to structured classroom import data
  ///
  /// Expected CSV format:
  /// Year Level,Classroom,Packs,Headphones,Tissues,Paper
  /// Prep,Prep A,25,25,1,0
  /// Prep,Prep B,23,23,1,0
  ///
  /// Returns a map of year level labels to their classroom data
  static Future<CSVImportResult> parseCSV(String csvContent) async {
    try {
      // Normalize line endings - replace \r\n or \r with \n
      final normalizedContent = csvContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

      // Parse CSV with explicit line ending configuration
      final List<List<dynamic>> rows = const CsvToListConverter(
        eol: '\n',
        shouldParseNumbers: false, // Keep as strings for better error handling
      ).convert(normalizedContent);

      if (rows.isEmpty) {
        return CSVImportResult.failure('CSV file is empty');
      }

      // Extract and validate headers
      final headers = rows[0].map((e) => e.toString().trim()).toList();

      if (headers.length < 3) {
        return CSVImportResult.failure('CSV must have at least 3 columns: Year Level, Classroom, Packs');
      }

      // More flexible header validation - just check that we have reasonable column names
      final firstHeader = headers[0].toLowerCase().replaceAll(' ', '');

      if (!firstHeader.contains('year') && !firstHeader.contains('level')) {
        return CSVImportResult.failure('First column should contain "year" or "level", got "${headers[0]}"');
      }

      if (!headers[1].toLowerCase().contains('class')) {
        return CSVImportResult.failure('Second column should contain "class", got "${headers[1]}"');
      }

      if (!headers[2].toLowerCase().contains('pack')) {
        return CSVImportResult.failure('Third column should contain "pack", got "${headers[2]}"');
      }

      // Categorize columns after first 3: student counts vs consumables
      final remainingHeaders = headers.skip(3).toList();
      final Map<int, String> studentCountColumns = {}; // index -> year level label
      final Map<int, String> consumableColumns = {}; // index -> consumable name

      for (int j = 0; j < remainingHeaders.length; j++) {
        final header = remainingHeaders[j];
        final headerLower = header.toLowerCase().trim();

        // Check if this is a student count column (pattern: "Year 1 Students", "Prep Students", etc.)
        if (headerLower.endsWith(' students') || headerLower.endsWith(' student')) {
          // Extract year level label by removing " students" or " student"
          final yearLevelLabel = header.substring(0, header.lastIndexOf(' ')).trim();
          studentCountColumns[j] = yearLevelLabel;
        } else {
          // It's a consumable column
          consumableColumns[j] = header;
        }
      }

      // Parse data rows
      final Map<String, YearLevelImportData> yearLevels = {};
      final List<String> errors = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        // Skip empty rows
        if (row.isEmpty || row.every((cell) => cell.toString().trim().isEmpty)) {
          continue;
        }

        if (row.length < 3) {
          errors.add('Row ${i + 1}: Must have at least 3 columns');
          continue;
        }

        final yearLevel = row[0].toString().trim();
        final classroomName = row[1].toString().trim();
        final packsStr = row[2].toString().trim();

        if (yearLevel.isEmpty) {
          errors.add('Row ${i + 1}: Year Level cannot be empty');
          continue;
        }

        if (classroomName.isEmpty) {
          errors.add('Row ${i + 1}: Classroom name cannot be empty');
          continue;
        }

        // Parse pack count
        final packs = int.tryParse(packsStr);
        if (packs == null) {
          errors.add('Row ${i + 1}: Packs must be a number, got "$packsStr"');
          continue;
        }

        // Parse student breakdowns
        final List<StudentBreakdownImportData> studentBreakdowns = [];
        for (final entry in studentCountColumns.entries) {
          final columnIndex = 3 + entry.key;
          if (columnIndex >= row.length) continue;

          final countStr = row[columnIndex].toString().trim();
          if (countStr.isEmpty) continue;

          final studentCount = int.tryParse(countStr);
          if (studentCount == null || studentCount == 0) continue;

          studentBreakdowns.add(StudentBreakdownImportData(
            yearLevelLabel: entry.value,
            studentCount: studentCount,
          ));
        }

        // Parse consumables
        final List<ConsumableImportData> consumables = [];
        for (final entry in consumableColumns.entries) {
          final columnIndex = 3 + entry.key;
          if (columnIndex >= row.length) continue;

          final quantityStr = row[columnIndex].toString().trim();
          if (quantityStr.isEmpty) continue;

          final quantity = int.tryParse(quantityStr);
          if (quantity == null || quantity == 0) continue;

          final itemName = entry.value;
          final unit = _guessUnit(itemName);

          consumables.add(ConsumableImportData(
            itemName: itemName,
            quantity: quantity,
            unit: unit,
          ));
        }

        // Add classroom to year level
        if (!yearLevels.containsKey(yearLevel)) {
          yearLevels[yearLevel] = YearLevelImportData(
            label: yearLevel,
            classrooms: [],
          );
        }

        yearLevels[yearLevel]!.classrooms.add(ClassroomImportData(
          name: classroomName,
          packs: packs,
          consumables: consumables,
          studentBreakdowns: studentBreakdowns,
        ));
      }

      if (yearLevels.isEmpty && errors.isEmpty) {
        return CSVImportResult.failure('No valid data found in CSV');
      }

      if (errors.isNotEmpty) {
        return CSVImportResult.failure('CSV parsing errors:\n${errors.join('\n')}');
      }

      return CSVImportResult.success(yearLevels.values.toList());
    } catch (e) {
      return CSVImportResult.failure('Failed to parse CSV: $e');
    }
  }

  /// Guess the unit based on item name
  static String _guessUnit(String itemName) {
    final nameLower = itemName.toLowerCase();

    if (nameLower.contains('tissue') || nameLower.contains('box')) {
      return 'boxes';
    } else if (nameLower.contains('paper') || nameLower.contains('ream')) {
      return 'reams';
    } else if (nameLower.contains('headphone') || nameLower.contains('earphone')) {
      return 'units';
    } else if (nameLower.contains('pencil') || nameLower.contains('pen')) {
      return 'units';
    } else if (nameLower.contains('book')) {
      return 'units';
    } else if (nameLower.contains('glue')) {
      return 'units';
    }

    return 'units'; // Default
  }

  /// Generate a sample CSV template
  static String generateTemplate() {
    return '''Year Level,Classroom,Packs,Year 1 Students,Year 2 Students,Headphones,Tissues,Paper
Prep,Prep A,25,,,25,1,0
Prep,Prep B,23,,,23,1,0
Year 1,Year 1A,26,26,,26,1,2
Year 1,Year 1B,24,24,,24,1,1
Year 1,Year 1/2A,24,10,14,24,1,2
Year 2,Year 2A,27,,27,27,1,2
Year 2,Year 2B,25,,25,25,1,2''';
  }
}

/// Result of CSV import parsing
class CSVImportResult {
  final bool success;
  final String? errorMessage;
  final List<YearLevelImportData>? data;

  CSVImportResult.success(this.data)
      : success = true,
        errorMessage = null;

  CSVImportResult.failure(this.errorMessage)
      : success = false,
        data = null;
}
