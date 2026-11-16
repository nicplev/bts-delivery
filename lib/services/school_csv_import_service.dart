import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';

class SchoolImportData {
  final String name;
  final String? address;
  final String? contactName;
  final String? contactPhone;
  final String? contactEmail;

  SchoolImportData({
    required this.name,
    this.address,
    this.contactName,
    this.contactPhone,
    this.contactEmail,
  });
}

class SchoolCsvImportService {
  /// Parse CSV content and return list of school import data
  ///
  /// Expected CSV format:
  /// School Name, Address, Contact Name, Contact Phone, Contact Email
  ///
  /// Only School Name is required. All other fields are optional.
  static Future<List<SchoolImportData>> parseSchoolsCsv(String csvContent) async {
    try {
      // Normalize line endings - replace \r\n or \r with \n
      final normalizedContent = csvContent
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');

      // Parse CSV with explicit line ending configuration
      final List<List<dynamic>> rows = const CsvToListConverter(
        eol: '\n',
        shouldParseNumbers: false, // Keep as strings for better error handling
      ).convert(normalizedContent);

      debugPrint('Total rows parsed: ${rows.length}');

      if (rows.isEmpty) {
        throw Exception('CSV file is empty');
      }

      // First row should be headers
      final headers = rows[0].map((h) => h.toString().toLowerCase().trim()).toList();
      debugPrint('Headers: $headers');

      // Validate that we have at least a school name column
      final nameIndex = _findColumnIndex(headers, ['school name', 'name', 'school']);
      if (nameIndex == -1) {
        throw Exception(
          'CSV must have a "School Name" column. Found columns: ${headers.join(", ")}'
        );
      }

      // Find optional column indices
      final addressIndex = _findColumnIndex(headers, ['address', 'school address']);
      final contactNameIndex = _findColumnIndex(headers, ['contact name', 'contact', 'contact person']);
      final contactPhoneIndex = _findColumnIndex(headers, ['contact phone', 'phone', 'phone number']);
      final contactEmailIndex = _findColumnIndex(headers, ['contact email', 'email']);

      final schools = <SchoolImportData>[];
      final errors = <String>[];

      // Process data rows (skip header row)
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];

        // Skip empty rows
        if (row.isEmpty || row.every((cell) => cell.toString().trim().isEmpty)) {
          continue;
        }

        try {
          // Get school name (required)
          final name = _getCellValue(row, nameIndex)?.trim();
          if (name == null || name.isEmpty) {
            errors.add('Row ${i + 1}: School name is required');
            continue;
          }

          // Get optional fields
          final address = _getCellValue(row, addressIndex)?.trim();
          final contactName = _getCellValue(row, contactNameIndex)?.trim();
          final contactPhone = _getCellValue(row, contactPhoneIndex)?.trim();
          final contactEmail = _getCellValue(row, contactEmailIndex)?.trim();

          schools.add(SchoolImportData(
            name: name,
            address: address?.isEmpty == true ? null : address,
            contactName: contactName?.isEmpty == true ? null : contactName,
            contactPhone: contactPhone?.isEmpty == true ? null : contactPhone,
            contactEmail: contactEmail?.isEmpty == true ? null : contactEmail,
          ));

          debugPrint('Parsed school: $name');
        } catch (e) {
          errors.add('Row ${i + 1}: ${e.toString()}');
        }
      }

      if (schools.isEmpty && errors.isNotEmpty) {
        throw Exception('Failed to parse any schools:\n${errors.join('\n')}');
      }

      if (errors.isNotEmpty) {
        debugPrint('Warnings during import:\n${errors.join('\n')}');
      }

      return schools;
    } catch (e) {
      debugPrint('Error parsing CSV: $e');
      rethrow;
    }
  }

  /// Find column index by trying multiple possible names
  static int _findColumnIndex(List<String> headers, List<String> possibleNames) {
    for (var name in possibleNames) {
      final index = headers.indexOf(name);
      if (index != -1) return index;
    }
    return -1;
  }

  /// Get cell value safely, handling out of bounds
  static String? _getCellValue(List<dynamic> row, int index) {
    if (index == -1 || index >= row.length) return null;
    final value = row[index]?.toString();
    return value?.isEmpty == true ? null : value;
  }

  /// Generate a sample CSV template for schools
  static String generateTemplate() {
    return '''School Name,Address,Contact Name,Contact Phone,Contact Email
Beaumaris Primary School,99 Dalgetty Rd Beaumaris VIC 3193,John Smith,0412345678,john@bps.vic.edu.au
Black Rock Primary School,71 Arkaringa Cres Black Rock VIC 3193,,,
Hampton Primary School,2 Holyrood St Hampton VIC 3188,Jane Doe,,jane@hps.vic.edu.au''';
  }
}
