import 'package:freezed_annotation/freezed_annotation.dart';
import 'school.dart';
import 'delivery.dart';
import 'staff.dart';

part 'season_export_models.freezed.dart';
part 'season_export_models.g.dart';

/// Options for configuring season export
@freezed
class SeasonExportOptions with _$SeasonExportOptions {
  const factory SeasonExportOptions({
    DateTime? startDate,
    DateTime? endDate,
    @Default(true) bool includeOverview,
    @Default(true) bool includeSchools,
    @Default(true) bool includeDeliveries,
    @Default(true) bool includeStaff,
    @Default(true) bool includeClassrooms,
    @Default(true) bool includeConsumables,
    @Default(true) bool includeTimerAggregate,
    @Default(true) bool includeTimerDetails,
  }) = _SeasonExportOptions;

  factory SeasonExportOptions.fromJson(Map<String, dynamic> json) =>
      _$SeasonExportOptionsFromJson(json);
}

/// High-level season overview statistics
@freezed
class SeasonOverview with _$SeasonOverview {
  const factory SeasonOverview({
    required int totalSchools,
    required int totalDeliveries,
    required int totalPacksDelivered,
    required Map<String, int> totalConsumablesByType,
    required DateTime? firstDeliveryDate,
    required DateTime? lastDeliveryDate,
    required int totalStaffInvolved,
    required int schoolsSignedOff,
    required int totalClassrooms,
    required int classroomsComplete,
    required int classroomsIncomplete,
    required int classroomsNotAttended,
  }) = _SeasonOverview;

  factory SeasonOverview.fromJson(Map<String, dynamic> json) =>
      _$SeasonOverviewFromJson(json);

  const SeasonOverview._();

  double get completionRate =>
      totalClassrooms > 0 ? classroomsComplete / totalClassrooms : 0;

  String get deliveryDateRange {
    if (firstDeliveryDate == null || lastDeliveryDate == null) {
      return 'No deliveries';
    }
    return '${_formatDate(firstDeliveryDate!)} - ${_formatDate(lastDeliveryDate!)}';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

/// Per-school aggregated data for season reporting
@freezed
class SchoolSeasonData with _$SchoolSeasonData {
  const factory SchoolSeasonData({
    required School school,
    required int totalPacks,
    required int yearLevelCount,
    required int classroomCount,
    required Duration totalTimeOnSite,
    required int visitCount,
    required double averageTimePerVisit,
    required int completeCount,
    required int incompleteCount,
    required int notAttendedCount,
    required bool isSignedOff,
    DateTime? signOffDate,
    required int notesCount,
    required Map<String, int> consumableTotals,
  }) = _SchoolSeasonData;

  factory SchoolSeasonData.fromJson(Map<String, dynamic> json) =>
      _$SchoolSeasonDataFromJson(json);

  const SchoolSeasonData._();

  String get formattedTotalTime {
    final hours = totalTimeOnSite.inHours;
    final minutes = totalTimeOnSite.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  String get formattedAverageTime {
    final minutes = averageTimePerVisit.round();
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '${hours}h ${mins}m';
    }
    return '${minutes}m';
  }
}

/// Per-staff performance metrics
@freezed
class StaffPerformance with _$StaffPerformance {
  const factory StaffPerformance({
    required Staff staff,
    required int assignedSchoolsCount,
    required int deliveriesParticipated,
    required Duration totalTimeOnDeliveries,
    required int schoolsCompleted,
    required List<String> schoolNamesServiced,
  }) = _StaffPerformance;

  factory StaffPerformance.fromJson(Map<String, dynamic> json) =>
      _$StaffPerformanceFromJson(json);

  const StaffPerformance._();

  String get formattedTotalTime {
    final hours = totalTimeOnDeliveries.inHours;
    final minutes = totalTimeOnDeliveries.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }
}

/// Classroom variance data showing expected vs actual
@freezed
class ClassroomVariance with _$ClassroomVariance {
  const factory ClassroomVariance({
    required String schoolName,
    required String yearLevel,
    required String classroomName,
    required int expectedPacks,
    required int? actualPacks,
    required ClassroomCompletionStatus status,
    required Map<String, ConsumableVariance> consumableVariances,
  }) = _ClassroomVariance;

  factory ClassroomVariance.fromJson(Map<String, dynamic> json) =>
      _$ClassroomVarianceFromJson(json);

  const ClassroomVariance._();

  int get packVariance => (actualPacks ?? expectedPacks) - expectedPacks;

  bool get hasPackDiscrepancy =>
      actualPacks != null && actualPacks != expectedPacks;

  bool get hasAnyDiscrepancy {
    if (hasPackDiscrepancy) return true;
    return consumableVariances.values.any((v) => v.hasDiscrepancy);
  }
}

/// Consumable variance showing expected vs actual
@freezed
class ConsumableVariance with _$ConsumableVariance {
  const factory ConsumableVariance({
    required String itemName,
    required int expectedQuantity,
    required int? actualQuantity,
    required String unit,
  }) = _ConsumableVariance;

  factory ConsumableVariance.fromJson(Map<String, dynamic> json) =>
      _$ConsumableVarianceFromJson(json);

  const ConsumableVariance._();

  int get variance => (actualQuantity ?? expectedQuantity) - expectedQuantity;

  bool get hasDiscrepancy =>
      actualQuantity != null && actualQuantity != expectedQuantity;
}

/// Aggregated consumable data across all schools
@freezed
class ConsumableAggregate with _$ConsumableAggregate {
  const factory ConsumableAggregate({
    required String itemName,
    required String unit,
    required int totalQuantity,
    required int schoolsUsingCount,
    required double averagePerSchool,
    required int maxAtSingleSchool,
  }) = _ConsumableAggregate;

  factory ConsumableAggregate.fromJson(Map<String, dynamic> json) =>
      _$ConsumableAggregateFromJson(json);
}

/// Aggregated timer data per school
@freezed
class TimerAggregate with _$TimerAggregate {
  const factory TimerAggregate({
    required String schoolId,
    required String schoolName,
    required int totalVisits,
    required Duration totalTimeSpent,
    required Duration averageTimePerVisit,
    required Duration? minVisitDuration,
    required Duration? maxVisitDuration,
  }) = _TimerAggregate;

  factory TimerAggregate.fromJson(Map<String, dynamic> json) =>
      _$TimerAggregateFromJson(json);

  const TimerAggregate._();

  String get formattedTotalTime {
    final hours = totalTimeSpent.inHours;
    final minutes = totalTimeSpent.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  String get formattedAverageTime {
    final hours = averageTimePerVisit.inHours;
    final minutes = averageTimePerVisit.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String? get formattedMinTime {
    if (minVisitDuration == null) return null;
    final minutes = minVisitDuration!.inMinutes;
    if (minutes >= 60) {
      return '${minutes ~/ 60}h ${minutes % 60}m';
    }
    return '${minutes}m';
  }

  String? get formattedMaxTime {
    if (maxVisitDuration == null) return null;
    final minutes = maxVisitDuration!.inMinutes;
    if (minutes >= 60) {
      return '${minutes ~/ 60}h ${minutes % 60}m';
    }
    return '${minutes}m';
  }
}

/// Detailed timer entry for export
@freezed
class TimerDetail with _$TimerDetail {
  const factory TimerDetail({
    required String schoolName,
    required DateTime visitDate,
    required DateTime startTime,
    required DateTime? endTime,
    required Duration duration,
    required String startedBy,
    required String? stoppedBy,
    required String dayOfWeek,
  }) = _TimerDetail;

  factory TimerDetail.fromJson(Map<String, dynamic> json) =>
      _$TimerDetailFromJson(json);

  const TimerDetail._();

  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Container for all aggregated season data
@freezed
class SeasonData with _$SeasonData {
  const factory SeasonData({
    required SeasonOverview overview,
    required List<SchoolSeasonData> schools,
    required List<Delivery> deliveries,
    required List<StaffPerformance> staffPerformance,
    required List<ClassroomVariance> classroomVariances,
    required List<ConsumableAggregate> consumableAggregates,
    required List<TimerAggregate> timerAggregates,
    required List<TimerDetail> timerDetails,
    required List<SignedSchoolSummary> signedSummaries,
  }) = _SeasonData;

  factory SeasonData.fromJson(Map<String, dynamic> json) =>
      _$SeasonDataFromJson(json);
}

/// Preview data for export screen
@freezed
class SeasonExportPreview with _$SeasonExportPreview {
  const factory SeasonExportPreview({
    required int schoolCount,
    required int deliveryCount,
    required int staffCount,
    required int signedSummaryCount,
    required int timerEntryCount,
    required DateTime? earliestDate,
    required DateTime? latestDate,
  }) = _SeasonExportPreview;

  factory SeasonExportPreview.fromJson(Map<String, dynamic> json) =>
      _$SeasonExportPreviewFromJson(json);
}
