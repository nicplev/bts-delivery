import 'package:flutter/material.dart';

/// Utility class for year level color coding
class YearLevelColors {
  /// Get color based on year level name
  ///
  /// Color scheme:
  /// - Prep/Foundation: White
  /// - Year 1: Red
  /// - Year 2: Blue
  /// - Year 3: Green
  /// - Year 4: Purple
  /// - Year 5: Yellow
  /// - Year 6: Orange
  /// - Specialists: Grey
  static Color getBackgroundColor(String label) {
    final lowerLabel = label.toLowerCase();

    if (lowerLabel.contains('prep') || lowerLabel.contains('foundation')) {
      return Colors.white; // White for Prep
    } else if (lowerLabel.contains('year 1') || lowerLabel.contains('year1') || lowerLabel.contains('grade 1')) {
      return Colors.red; // Red for Year 1
    } else if (lowerLabel.contains('year 2') || lowerLabel.contains('year2') || lowerLabel.contains('grade 2')) {
      return Colors.blue; // Blue for Year 2
    } else if (lowerLabel.contains('year 3') || lowerLabel.contains('year3') || lowerLabel.contains('grade 3')) {
      return Colors.green; // Green for Year 3
    } else if (lowerLabel.contains('year 4') || lowerLabel.contains('year4') || lowerLabel.contains('grade 4')) {
      return Colors.purple; // Purple for Year 4
    } else if (lowerLabel.contains('year 5') || lowerLabel.contains('year5') || lowerLabel.contains('grade 5')) {
      return Colors.yellow; // Yellow for Year 5
    } else if (lowerLabel.contains('year 6') || lowerLabel.contains('year6') || lowerLabel.contains('grade 6')) {
      return Colors.orange; // Orange for Year 6
    } else if (lowerLabel.contains('specialist')) {
      return Colors.grey; // Grey for Specialists
    }

    return const Color(0xFF4CAF50); // Default green color
  }

  /// Get icon color based on background color
  /// Uses black for white/yellow backgrounds for better visibility
  static Color getIconColor(String label) {
    final lowerLabel = label.toLowerCase();

    // Use black icon for white/yellow backgrounds (for visibility)
    if (lowerLabel.contains('prep') || lowerLabel.contains('foundation') ||
        lowerLabel.contains('year 5') || lowerLabel.contains('year5') || lowerLabel.contains('grade 5')) {
      return Colors.black;
    }

    return Colors.white; // White icon for all other colors
  }

  /// Check if year level needs a border (for white backgrounds)
  static bool needsBorder(String label) {
    final lowerLabel = label.toLowerCase();
    return lowerLabel.contains('prep') || lowerLabel.contains('foundation');
  }
}
