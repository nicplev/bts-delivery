import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/season_export_models.dart';
import '../models/school.dart';
import '../models/school_timer.dart';
import '../models/delivery.dart';
import '../models/staff.dart';
import '../services/result.dart';

/// Repository for fetching and aggregating season export data
class SeasonExportRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get preview data counts for the export screen
  Future<Result<SeasonExportPreview>> getExportPreview({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // Get counts in parallel
      final results = await Future.wait([
        _firestore.collection('schools').get(),
        _getDeliveriesQuery(startDate, endDate).get(),
        _firestore.collection('staff').get(),
        _firestore.collection('signed_school_summaries').get(),
      ]);

      final schoolsSnapshot = results[0];
      final deliveriesSnapshot = results[1];
      final staffSnapshot = results[2];
      final summariesSnapshot = results[3];

      // Count timer entries across all schools
      int timerCount = 0;
      for (final schoolDoc in schoolsSnapshot.docs) {
        final historySnapshot = await _firestore
            .collection('schools')
            .doc(schoolDoc.id)
            .collection('timers')
            .doc('active')
            .collection('history')
            .get();
        timerCount += historySnapshot.docs.length;
      }

      // Get date range from deliveries
      DateTime? earliest;
      DateTime? latest;
      for (final doc in deliveriesSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final date = (data['date'] as Timestamp).toDate();
        if (earliest == null || date.isBefore(earliest)) {
          earliest = date;
        }
        if (latest == null || date.isAfter(latest)) {
          latest = date;
        }
      }

      return Result.success(SeasonExportPreview(
        schoolCount: schoolsSnapshot.docs.length,
        deliveryCount: deliveriesSnapshot.docs.length,
        staffCount: staffSnapshot.docs.length,
        signedSummaryCount: summariesSnapshot.docs.length,
        timerEntryCount: timerCount,
        earliestDate: earliest,
        latestDate: latest,
      ));
    } catch (e) {
      debugPrint('Error getting export preview: $e');
      return Result.failure('Failed to get export preview: $e');
    }
  }

  /// Aggregate all season data for export
  Future<Result<SeasonData>> aggregateSeasonData({
    DateTime? startDate,
    DateTime? endDate,
    void Function(double progress, String message)? onProgress,
  }) async {
    try {
      onProgress?.call(0.0, 'Starting data aggregation...');

      // Phase 1: Fetch all schools (10%)
      onProgress?.call(0.05, 'Fetching schools...');
      final schoolsSnapshot = await _firestore.collection('schools').orderBy('name').get();
      final schools = schoolsSnapshot.docs.map((doc) {
        final data = doc.data();
        data.remove('id');
        return School.fromJson({'id': doc.id, ...data});
      }).toList();
      onProgress?.call(0.10, 'Fetched ${schools.length} schools');

      // Phase 2: Fetch all deliveries (20%)
      onProgress?.call(0.15, 'Fetching deliveries...');
      final deliveriesSnapshot = await _getDeliveriesQuery(startDate, endDate).get();
      final deliveries = deliveriesSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data.remove('id');
        return Delivery.fromJson({'id': doc.id, ...data});
      }).toList();
      onProgress?.call(0.20, 'Fetched ${deliveries.length} deliveries');

      // Phase 3: Fetch all signed summaries (30%)
      onProgress?.call(0.25, 'Fetching signed summaries...');
      final summariesSnapshot = await _firestore.collection('signed_school_summaries').get();
      final signedSummaries = <SignedSchoolSummary>[];
      for (final doc in summariesSnapshot.docs) {
        try {
          final data = doc.data();
          data.remove('id');
          // Ensure required Map fields have default values if null
          data['packTotalsByYearLevel'] ??= <String, dynamic>{};
          data['packTotalsByClassroom'] ??= <String, dynamic>{};
          data['consumablesTotals'] ??= <String, dynamic>{};
          data['consumablesByYearLevel'] ??= <String, dynamic>{};
          data['consumablesByClassroom'] ??= <String, dynamic>{};
          data['notesByClassroom'] ??= <String, dynamic>{};
          data['photoUrls'] ??= <String>[];
          data['classroomDeliveryDetails'] ??= <dynamic>[];
          signedSummaries.add(SignedSchoolSummary.fromJson({'id': doc.id, ...data}));
        } catch (e) {
          debugPrint('Error parsing signed summary ${doc.id}: $e');
          // Skip malformed documents
        }
      }
      onProgress?.call(0.30, 'Fetched ${signedSummaries.length} signed summaries');

      // Phase 4: Fetch all staff (35%)
      onProgress?.call(0.32, 'Fetching staff...');
      final staffSnapshot = await _firestore.collection('staff').orderBy('name').get();
      final staffList = staffSnapshot.docs.map((doc) {
        final data = doc.data();
        data.remove('id');
        return Staff.fromJson({'id': doc.id, ...data});
      }).toList();
      onProgress?.call(0.35, 'Fetched ${staffList.length} staff members');

      // Phase 5: Fetch timer history for all schools (35-60%)
      onProgress?.call(0.36, 'Fetching timer history...');
      final Map<String, List<SchoolTimer>> timersBySchool = {};
      final List<TimerDetail> allTimerDetails = [];

      for (int i = 0; i < schools.length; i++) {
        final school = schools[i];
        final historySnapshot = await _firestore
            .collection('schools')
            .doc(school.id)
            .collection('timers')
            .doc('active')
            .collection('history')
            .orderBy('stoppedAt', descending: true)
            .get();

        final timers = <SchoolTimer>[];
        for (final doc in historySnapshot.docs) {
          try {
            final data = doc.data();
            data.remove('id');
            timers.add(SchoolTimer.fromJson({'id': doc.id, ...data}));
          } catch (e) {
            debugPrint('Error parsing timer ${doc.id}: $e');
          }
        }

        timersBySchool[school.id] = timers;

        // Convert to timer details
        for (final timer in timers) {
          if (timer.stoppedAt != null) {
            allTimerDetails.add(TimerDetail(
              schoolName: school.name,
              visitDate: timer.startedAt,
              startTime: timer.startedAt,
              endTime: timer.stoppedAt,
              duration: timer.elapsed,
              startedBy: timer.startedByName,
              stoppedBy: timer.stoppedByName,
              dayOfWeek: _getDayOfWeek(timer.startedAt),
            ));
          }
        }

        final progress = 0.36 + (0.24 * (i + 1) / schools.length);
        onProgress?.call(progress, 'Processing timer data (${i + 1}/${schools.length})');
      }
      onProgress?.call(0.60, 'Timer data processed');

      // Phase 6: Aggregate school data (60-75%)
      onProgress?.call(0.61, 'Aggregating school data...');
      final List<SchoolSeasonData> schoolSeasonData = [];
      final Map<String, int> schoolNotesCount = {};

      // First, count notes for each school
      for (final school in schools) {
        try {
          int notesCount = 0;
          // Count school-level notes
          final notesSnapshot = await _firestore
              .collection('schools')
              .doc(school.id)
              .collection('notes')
              .get();
          notesCount += notesSnapshot.docs.length;
          schoolNotesCount[school.id] = notesCount;
        } catch (e) {
          debugPrint('Error counting notes for school ${school.id}: $e');
          schoolNotesCount[school.id] = 0;
        }
      }

      for (int i = 0; i < schools.length; i++) {
        final school = schools[i];
        final summary = signedSummaries.firstWhere(
          (s) => s.schoolId == school.id,
          orElse: () => _createEmptySummary(school),
        );
        final timers = timersBySchool[school.id] ?? [];

        // Calculate timer aggregates
        final totalTime = timers.fold<Duration>(
          Duration.zero,
          (acc, t) => acc + t.elapsed,
        );
        final visitCount = timers.length;
        final avgTime = visitCount > 0
            ? totalTime.inMinutes / visitCount
            : 0.0;

        // Get classroom counts from year levels
        int yearLevelCount = 0;
        int classroomCount = 0;
        int completeCount = 0;
        int incompleteCount = 0;
        int notAttendedCount = 0;

        for (final detail in summary.classroomDeliveryDetails) {
          classroomCount++;
          switch (detail.status) {
            case ClassroomCompletionStatus.complete:
              completeCount++;
              break;
            case ClassroomCompletionStatus.incomplete:
              incompleteCount++;
              break;
            case ClassroomCompletionStatus.notAttended:
              notAttendedCount++;
              break;
          }
        }

        // Count year levels
        try {
          final yearLevelsSnapshot = await _firestore
              .collection('schools')
              .doc(school.id)
              .collection('yearLevels')
              .get();
          yearLevelCount = yearLevelsSnapshot.docs.length;
        } catch (e) {
          debugPrint('Error counting year levels for school ${school.id}: $e');
          yearLevelCount = 0;
        }

        // Aggregate consumables
        final Map<String, int> consumableTotals = {};
        for (final entry in summary.consumablesTotals.entries) {
          consumableTotals[entry.value.itemName] = entry.value.quantity;
        }

        schoolSeasonData.add(SchoolSeasonData(
          school: school,
          totalPacks: summary.totalPacks,
          yearLevelCount: yearLevelCount,
          classroomCount: classroomCount,
          totalTimeOnSite: totalTime,
          visitCount: visitCount,
          averageTimePerVisit: avgTime,
          completeCount: completeCount,
          incompleteCount: incompleteCount,
          notAttendedCount: notAttendedCount,
          isSignedOff: school.isSignedOff,
          signOffDate: school.lastSignOffDate,
          notesCount: schoolNotesCount[school.id] ?? 0,
          consumableTotals: consumableTotals,
        ));

        final progress = 0.61 + (0.14 * (i + 1) / schools.length);
        onProgress?.call(progress, 'Aggregating school data (${i + 1}/${schools.length})');
      }
      onProgress?.call(0.75, 'School data aggregated');

      // Phase 7: Aggregate staff performance (75-80%)
      onProgress?.call(0.76, 'Calculating staff performance...');
      final List<StaffPerformance> staffPerformance = [];

      for (final staff in staffList) {
        final staffDeliveries = deliveries.where(
          (d) => d.staffIds.contains(staff.id),
        ).toList();

        // Calculate total time for this staff
        Duration totalTime = Duration.zero;
        final Set<String> schoolsServiced = {};
        int schoolsCompleted = 0;

        for (final delivery in staffDeliveries) {
          schoolsServiced.add(delivery.schoolName);
          final timers = timersBySchool[delivery.schoolId] ?? [];
          for (final timer in timers) {
            // Check if timer was on the same date as delivery
            if (_isSameDay(timer.startedAt, delivery.date)) {
              totalTime += timer.elapsed;
            }
          }
          // Check if school is signed off
          final school = schools.firstWhere(
            (s) => s.id == delivery.schoolId,
            orElse: () => schools.first,
          );
          if (school.isSignedOff) {
            schoolsCompleted++;
          }
        }

        staffPerformance.add(StaffPerformance(
          staff: staff,
          assignedSchoolsCount: staff.assignedSchoolIds.length,
          deliveriesParticipated: staffDeliveries.length,
          totalTimeOnDeliveries: totalTime,
          schoolsCompleted: schoolsCompleted,
          schoolNamesServiced: schoolsServiced.toList(),
        ));
      }
      onProgress?.call(0.80, 'Staff performance calculated');

      // Phase 8: Build classroom variance data (80-85%)
      onProgress?.call(0.81, 'Building classroom variance data...');
      final List<ClassroomVariance> classroomVariances = [];

      for (final summary in signedSummaries) {
        for (final detail in summary.classroomDeliveryDetails) {
          final Map<String, ConsumableVariance> consumableVariances = {};

          for (final entry in detail.consumables.entries) {
            final consumable = entry.value;
            consumableVariances[entry.key] = ConsumableVariance(
              itemName: consumable.itemName,
              expectedQuantity: consumable.expectedQuantity,
              actualQuantity: consumable.actualQuantityDelivered,
              unit: consumable.unit,
            );
          }

          classroomVariances.add(ClassroomVariance(
            schoolName: summary.schoolName,
            yearLevel: detail.yearLevel,
            classroomName: detail.classroomName,
            expectedPacks: detail.expectedPacks,
            actualPacks: detail.actualPacksDelivered,
            status: detail.status,
            consumableVariances: consumableVariances,
          ));
        }
      }
      onProgress?.call(0.85, 'Classroom variance data built');

      // Phase 9: Aggregate consumables across all schools (85-90%)
      onProgress?.call(0.86, 'Aggregating consumables...');
      final Map<String, List<int>> consumableQuantities = {};

      for (final summary in signedSummaries) {
        for (final entry in summary.consumablesTotals.entries) {
          final itemName = entry.value.itemName;
          consumableQuantities.putIfAbsent(itemName, () => []);
          consumableQuantities[itemName]!.add(entry.value.quantity);
        }
      }

      final List<ConsumableAggregate> consumableAggregates = [];
      for (final entry in consumableQuantities.entries) {
        final quantities = entry.value;
        final total = quantities.fold<int>(0, (acc, q) => acc + q);
        final average = quantities.isNotEmpty ? total / quantities.length : 0.0;
        final max = quantities.isNotEmpty ? quantities.reduce((a, b) => a > b ? a : b) : 0;

        // Find the unit for this item
        String unit = '';
        for (final summary in signedSummaries) {
          final consumable = summary.consumablesTotals[entry.key];
          if (consumable != null) {
            unit = consumable.unit;
            break;
          }
        }

        consumableAggregates.add(ConsumableAggregate(
          itemName: entry.key,
          unit: unit,
          totalQuantity: total,
          schoolsUsingCount: quantities.length,
          averagePerSchool: average,
          maxAtSingleSchool: max,
        ));
      }
      onProgress?.call(0.90, 'Consumables aggregated');

      // Phase 10: Build timer aggregates (90-95%)
      onProgress?.call(0.91, 'Building timer aggregates...');
      final List<TimerAggregate> timerAggregates = [];

      for (final school in schools) {
        final timers = timersBySchool[school.id] ?? [];
        if (timers.isEmpty) continue;

        final durations = timers.map((t) => t.elapsed).toList();
        final totalTime = durations.fold<Duration>(Duration.zero, (acc, d) => acc + d);
        final avgTime = Duration(
          milliseconds: totalTime.inMilliseconds ~/ durations.length,
        );

        durations.sort((a, b) => a.compareTo(b));
        final minDuration = durations.first;
        final maxDuration = durations.last;

        timerAggregates.add(TimerAggregate(
          schoolId: school.id,
          schoolName: school.name,
          totalVisits: timers.length,
          totalTimeSpent: totalTime,
          averageTimePerVisit: avgTime,
          minVisitDuration: minDuration,
          maxVisitDuration: maxDuration,
        ));
      }
      onProgress?.call(0.95, 'Timer aggregates built');

      // Phase 11: Build overview (95-100%)
      onProgress?.call(0.96, 'Building overview...');

      // Calculate totals
      final totalPacks = signedSummaries.fold<int>(0, (acc, s) => acc + s.totalPacks);

      // Aggregate consumables by type
      final Map<String, int> totalConsumablesByType = {};
      for (final agg in consumableAggregates) {
        totalConsumablesByType[agg.itemName] = agg.totalQuantity;
      }

      // Get unique staff involved
      final Set<String> staffInvolved = {};
      for (final delivery in deliveries) {
        staffInvolved.addAll(delivery.staffIds);
      }

      // Get date range
      DateTime? firstDate;
      DateTime? lastDate;
      for (final delivery in deliveries) {
        if (firstDate == null || delivery.date.isBefore(firstDate)) {
          firstDate = delivery.date;
        }
        if (lastDate == null || delivery.date.isAfter(lastDate)) {
          lastDate = delivery.date;
        }
      }

      // Count classroom statuses
      int totalClassrooms = 0;
      int classroomsComplete = 0;
      int classroomsIncomplete = 0;
      int classroomsNotAttended = 0;

      for (final variance in classroomVariances) {
        totalClassrooms++;
        switch (variance.status) {
          case ClassroomCompletionStatus.complete:
            classroomsComplete++;
            break;
          case ClassroomCompletionStatus.incomplete:
            classroomsIncomplete++;
            break;
          case ClassroomCompletionStatus.notAttended:
            classroomsNotAttended++;
            break;
        }
      }

      final overview = SeasonOverview(
        totalSchools: schools.length,
        totalDeliveries: deliveries.length,
        totalPacksDelivered: totalPacks,
        totalConsumablesByType: totalConsumablesByType,
        firstDeliveryDate: firstDate,
        lastDeliveryDate: lastDate,
        totalStaffInvolved: staffInvolved.length,
        schoolsSignedOff: schools.where((s) => s.isSignedOff).length,
        totalClassrooms: totalClassrooms,
        classroomsComplete: classroomsComplete,
        classroomsIncomplete: classroomsIncomplete,
        classroomsNotAttended: classroomsNotAttended,
      );

      onProgress?.call(1.0, 'Data aggregation complete');

      return Result.success(SeasonData(
        overview: overview,
        schools: schoolSeasonData,
        deliveries: deliveries,
        staffPerformance: staffPerformance,
        classroomVariances: classroomVariances,
        consumableAggregates: consumableAggregates,
        timerAggregates: timerAggregates,
        timerDetails: allTimerDetails,
        signedSummaries: signedSummaries,
      ));
    } catch (e) {
      debugPrint('Error aggregating season data: $e');
      return Result.failure('Failed to aggregate season data: $e');
    }
  }

  Query _getDeliveriesQuery(DateTime? startDate, DateTime? endDate) {
    Query query = _firestore.collection('deliveries').orderBy('date');

    if (startDate != null) {
      query = query.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }
    if (endDate != null) {
      query = query.where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
    }

    return query;
  }

  String _getDayOfWeek(DateTime date) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[date.weekday - 1];
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  SignedSchoolSummary _createEmptySummary(School school) {
    return SignedSchoolSummary(
      id: '',
      schoolId: school.id,
      schoolName: school.name,
      schoolAddress: school.address,
      signedBy: '',
      signedDate: DateTime.now(),
      totalPacks: 0,
      packTotalsByYearLevel: {},
      packTotalsByClassroom: {},
      consumablesTotals: {},
      consumablesByYearLevel: {},
      consumablesByClassroom: {},
      classroomDeliveryDetails: [],
      photoUrls: [],
      notesByClassroom: {},
      createdAt: DateTime.now(),
    );
  }
}
