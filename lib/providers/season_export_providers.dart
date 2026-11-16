import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/season_export_repository.dart';
import '../models/season_export_models.dart';
import '../services/season_export_service.dart';

/// Provider for season export repository
final seasonExportRepositoryProvider = Provider<SeasonExportRepository>((ref) {
  return SeasonExportRepository();
});

/// Provider for export preview data
final seasonExportPreviewProvider = FutureProvider.family<SeasonExportPreview, ({DateTime? startDate, DateTime? endDate})>((ref, params) async {
  final repository = ref.watch(seasonExportRepositoryProvider);
  final result = await repository.getExportPreview(
    startDate: params.startDate,
    endDate: params.endDate,
  );
  if (result.isSuccess) {
    return result.dataOrNull!;
  }
  throw Exception(result.errorOrNull ?? 'Failed to get export preview');
});

/// State for season export operation
class SeasonExportState {
  final bool isExporting;
  final double progress;
  final String? progressMessage;
  final String? filePath;
  final String? error;

  const SeasonExportState({
    this.isExporting = false,
    this.progress = 0,
    this.progressMessage,
    this.filePath,
    this.error,
  });

  SeasonExportState copyWith({
    bool? isExporting,
    double? progress,
    String? progressMessage,
    String? filePath,
    String? error,
  }) {
    return SeasonExportState(
      isExporting: isExporting ?? this.isExporting,
      progress: progress ?? this.progress,
      progressMessage: progressMessage ?? this.progressMessage,
      filePath: filePath,
      error: error,
    );
  }
}

/// Notifier for managing season export operations
class SeasonExportNotifier extends StateNotifier<SeasonExportState> {
  final SeasonExportRepository _repository;

  SeasonExportNotifier(this._repository) : super(const SeasonExportState());

  /// Generate the season export report
  Future<void> generateReport({
    DateTime? startDate,
    DateTime? endDate,
    SeasonExportOptions? options,
  }) async {
    state = const SeasonExportState(
      isExporting: true,
      progress: 0,
      progressMessage: 'Preparing export...',
    );

    try {
      // Aggregate data with progress updates
      final result = await _repository.aggregateSeasonData(
        startDate: startDate,
        endDate: endDate,
        onProgress: (progress, message) {
          state = state.copyWith(
            progress: progress * 0.8, // 80% for data aggregation
            progressMessage: message,
          );
        },
      );

      if (result.isFailure) {
        state = SeasonExportState(
          isExporting: false,
          error: result.errorOrNull ?? 'Failed to aggregate data',
        );
        return;
      }

      state = state.copyWith(
        progress: 0.85,
        progressMessage: 'Generating Excel file...',
      );

      // Generate Excel file
      final exportOptions = options ?? const SeasonExportOptions();
      final filePath = await SeasonExportService.generateSeasonReport(
        result.dataOrNull!,
        exportOptions,
      );

      if (filePath == null) {
        state = const SeasonExportState(
          isExporting: false,
          error: 'Failed to generate Excel file',
        );
        return;
      }

      state = SeasonExportState(
        isExporting: false,
        progress: 1.0,
        filePath: filePath,
      );
    } catch (e) {
      state = SeasonExportState(
        isExporting: false,
        error: 'Export failed: $e',
      );
    }
  }

  /// Share the generated file
  Future<void> shareFile() async {
    if (state.filePath != null) {
      await SeasonExportService.shareExcelFile(state.filePath!);
    }
  }

  /// Reset state for a new export
  void reset() {
    state = const SeasonExportState();
  }
}

/// Provider for season export notifier
final seasonExportNotifierProvider =
    StateNotifierProvider<SeasonExportNotifier, SeasonExportState>((ref) {
  final repository = ref.watch(seasonExportRepositoryProvider);
  return SeasonExportNotifier(repository);
});
