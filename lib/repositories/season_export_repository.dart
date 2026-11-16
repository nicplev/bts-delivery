import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/season_export_models.dart';
import '../models/school.dart';
import '../models/school_timer.dart';
import '../models/delivery.dart';
import '../models/delivery_visit.dart';
import '../models/signoff_snapshot.dart';
import '../services/result.dart';
import 'staff_repository.dart';

typedef SeasonReportData = ({
  SeasonData data,
  List<SignedEvidence> visitEvidence,
  List<({String deliveryId, TimerDetail timer})> visitTimers,
});

/// Repository for fetching and aggregating season export data
class SeasonExportRepository {
  SeasonExportRepository(this._staffRepository);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StaffRepository _staffRepository;

  /// Get preview data counts for the export screen
  Future<Result<SeasonExportPreview>> getExportPreview({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final staffRequest = _staffRepository.getAllStaff();
      final results = await Future.wait([
        _firestore
            .collection('schools')
            .get(const GetOptions(source: Source.server)),
        _getDeliveriesQuery(startDate, endDate)
            .get(const GetOptions(source: Source.server)),
        _legacySummariesQuery(startDate, endDate)
            .get(const GetOptions(source: Source.server)),
      ]);

      final schoolsSnapshot = results[0];
      final deliveriesSnapshot = results[1];
      final staff = (await staffRequest).dataOrNull;
      if (staff == null) {
        return const Result.failure('Could not load the staff directory.');
      }
      final summariesSnapshot = results[2];
      final visits = deliveriesSnapshot.docs.map((doc) {
        return Delivery.fromJson({...doc.data(), 'id': doc.id});
      }).toList();
      var visitEvidenceCount = 0;
      for (final query in _visitEvidenceQueries(visits)) {
        visitEvidenceCount += (await query.count().get()).count ?? 0;
      }

      int timerCount = 0;
      for (final visit in visits) {
        final root = await _readyVisitRoot(visit);
        if (root != null) {
          timerCount += (await _timerHistory(root).count().get()).count ?? 0;
        }
      }
      for (final schoolDoc in schoolsSnapshot.docs) {
        final query = _dated(
          _timerHistory(_firestore.collection('schools').doc(schoolDoc.id)),
          'startedAt',
          startDate,
          endDate,
        );
        timerCount += (await query.count().get()).count ?? 0;
      }

      // Get date range from deliveries
      DateTime? earliest;
      DateTime? latest;
      for (final doc in deliveriesSnapshot.docs) {
        final data = doc.data();
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
        staffCount: staff.length,
        signedSummaryCount: summariesSnapshot.docs.length + visitEvidenceCount,
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
  Future<Result<SeasonReportData>> aggregateSeasonData({
    DateTime? startDate,
    DateTime? endDate,
    void Function(double progress, String message)? onProgress,
  }) async {
    try {
      onProgress?.call(0.0, 'Starting data aggregation...');

      // Phase 1: Fetch all schools (10%)
      onProgress?.call(0.05, 'Fetching schools...');
      final schoolsSnapshot = await _firestore
          .collection('schools')
          .orderBy('name')
          .get(const GetOptions(source: Source.server));
      final schools = schoolsSnapshot.docs.map((doc) {
        final data = doc.data();
        data.remove('id');
        return School.fromJson({'id': doc.id, ...data});
      }).toList();
      onProgress?.call(0.10, 'Fetched ${schools.length} schools');

      // Phase 2: Fetch all deliveries (20%)
      onProgress?.call(0.15, 'Fetching deliveries...');
      final deliveriesSnapshot = await _getDeliveriesQuery(startDate, endDate)
          .get(const GetOptions(source: Source.server));
      final deliveries = deliveriesSnapshot.docs.map((doc) {
        final data = doc.data();
        data.remove('id');
        return Delivery.fromJson({'id': doc.id, ...data});
      }).toList();
      onProgress?.call(0.20, 'Fetched ${deliveries.length} deliveries');

      // Phase 3: Fetch all signed summaries (30%)
      onProgress?.call(0.25, 'Fetching signed summaries...');
      final visitEvidence = await _visitEvidence(deliveries);
      final summariesSnapshot = await _legacySummariesQuery(startDate, endDate)
          .get(const GetOptions(source: Source.server));

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
          signedSummaries
              .add(SignedSchoolSummary.fromJson({'id': doc.id, ...data}));
        } catch (_) {
          return const Result.failure(
              'An earlier signed summary could not be read.');
        }
      }
      onProgress?.call(
          0.30, 'Fetched ${signedSummaries.length} signed summaries');

      // Phase 4: Fetch all staff (35%)
      onProgress?.call(0.32, 'Fetching staff...');
      final directory = await _staffRepository.getAllStaff();
      final staffList = directory.dataOrNull;
      if (staffList == null) {
        return const Result.failure('Could not load the staff directory.');
      }
      onProgress?.call(0.35, 'Fetched ${staffList.length} staff members');

      // Phase 5: Fetch timer history for all schools (35-60%)
      onProgress?.call(0.36, 'Fetching timer history...');
      final Map<String, List<SchoolTimer>> timersBySchool = {};
      final List<TimerDetail> allTimerDetails = [];

      for (int i = 0; i < schools.length; i++) {
        final school = schools[i];
        final historySnapshot = await _dated(
          _timerHistory(_firestore.collection('schools').doc(school.id)),
          'startedAt',
          startDate,
          endDate,
        ).get(const GetOptions(source: Source.server));
        final timers = _parseTimers(historySnapshot);

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
        onProgress?.call(
            progress, 'Processing timer data (${i + 1}/${schools.length})');
      }
      final schoolNames = {
        for (final school in schools) school.id: school.name
      };
      final visitTimers = <({String deliveryId, TimerDetail timer})>[];
      for (final visit in deliveries) {
        final root = await _readyVisitRoot(visit);
        if (root == null) continue;
        final history = await _timerHistory(root)
            .orderBy('stoppedAt', descending: true)
            .get(const GetOptions(source: Source.server));
        for (final timer in _parseTimers(history)) {
          if (timer.stoppedAt == null) continue;
          visitTimers.add((
            deliveryId: visit.id,
            timer: TimerDetail(
              schoolName: schoolNames[visit.schoolId] ?? 'Unknown school',
              visitDate: visit.date,
              startTime: timer.startedAt,
              endTime: timer.stoppedAt,
              duration: timer.elapsed,
              startedBy: timer.startedByName,
              stoppedBy: timer.stoppedByName,
              dayOfWeek: _getDayOfWeek(visit.date),
            ),
          ));
        }
      }
      onProgress?.call(0.60, 'Timer data processed');

      // Phase 6: Aggregate school data (60-75%)
      onProgress?.call(0.61, 'Aggregating school data...');
      final List<SchoolSeasonData> schoolSeasonData = [];
      final Map<String, int> schoolNotesCount = {};

      for (final school in schools) {
        final notes = await _firestore
            .collection('schools')
            .doc(school.id)
            .collection('notes')
            .count()
            .get();
        schoolNotesCount[school.id] = notes.count ?? 0;
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
        final avgTime = visitCount > 0 ? totalTime.inMinutes / visitCount : 0.0;

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
        onProgress?.call(
            progress, 'Aggregating school data (${i + 1}/${schools.length})');
      }
      onProgress?.call(0.75, 'School data aggregated');

      // Phase 7: Aggregate staff performance (75-80%)
      onProgress?.call(0.76, 'Calculating staff performance...');
      final List<StaffPerformance> staffPerformance = [];

      for (final staff in staffList) {
        final staffDeliveries = deliveries
            .where(
              (d) => d.staffIds.contains(staff.id),
            )
            .toList();

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
        final max = quantities.isNotEmpty
            ? quantities.reduce((a, b) => a > b ? a : b)
            : 0;

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
        final totalTime =
            durations.fold<Duration>(Duration.zero, (acc, d) => acc + d);
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
      final totalPacks =
          signedSummaries.fold<int>(0, (acc, s) => acc + s.totalPacks);

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

      final data = SeasonData(
        overview: overview,
        schools: schoolSeasonData,
        deliveries: deliveries,
        staffPerformance: staffPerformance,
        classroomVariances: classroomVariances,
        consumableAggregates: consumableAggregates,
        timerAggregates: timerAggregates,
        timerDetails: allTimerDetails,
        signedSummaries: signedSummaries,
      );
      return Result.success((
        data: data,
        visitEvidence: visitEvidence,
        visitTimers: visitTimers,
      ));
    } catch (e) {
      debugPrint('Error aggregating season data: $e');
      return Result.failure('Failed to aggregate season data: $e');
    }
  }

  Query<Map<String, dynamic>> _getDeliveriesQuery(
          DateTime? startDate, DateTime? endDate) =>
      _dated(_firestore.collection('deliveries'), 'date', startDate, endDate);

  Query<Map<String, dynamic>> _legacySummariesQuery(
          DateTime? startDate, DateTime? endDate) =>
      _dated(_firestore.collection('signed_school_summaries'), 'signedDate',
          startDate, endDate);

  Query<Map<String, dynamic>> _dated(
    CollectionReference<Map<String, dynamic>> collection,
    String field,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    Query<Map<String, dynamic>> query = collection.orderBy(field);
    if (startDate != null) {
      query = query.where(field,
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }
    if (endDate != null) {
      final nextDay = DateTime(endDate.year, endDate.month, endDate.day + 1);
      query = query.where(field, isLessThan: Timestamp.fromDate(nextDay));
    }
    return query;
  }

  /// Use the selected deliveries' dates. A late signature or subsequent
  /// correction still belongs to its original visit and is exported once.
  Future<List<SignedEvidence>> _visitEvidence(List<Delivery> deliveries) async {
    final evidence = <SignedEvidence>[];
    for (final query in _visitEvidenceQueries(deliveries)) {
      final result = await query.get(const GetOptions(source: Source.server));
      evidence.addAll(
          result.docs.map((doc) => SignedEvidence.fromDocument(doc.data())));
    }
    return evidence..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  }

  Iterable<Query<Map<String, dynamic>>> _visitEvidenceQueries(
    List<Delivery> deliveries,
  ) sync* {
    final bySchool = <String, List<String>>{};
    for (final delivery in deliveries) {
      bySchool.putIfAbsent(delivery.schoolId, () => []).add(delivery.id);
    }
    for (final entry in bySchool.entries) {
      final history = _firestore
          .collection('schools')
          .doc(entry.key)
          .collection('signoffs');
      final ids = entry.value;
      for (var index = 0; index < ids.length; index += 30) {
        final last = index + 30 < ids.length ? index + 30 : ids.length;
        yield history.where('deliveryId', whereIn: ids.sublist(index, last));
      }
    }
  }

  Future<DocumentReference<Map<String, dynamic>>?> _readyVisitRoot(
    Delivery delivery,
  ) async {
    final visit =
        DeliveryVisit(deliveryId: delivery.id, schoolId: delivery.schoolId);
    final root = _firestore.doc(visit.workspacePath);
    final manifest = await root.get(const GetOptions(source: Source.server));
    if (manifest.data()?['status'] != 'ready') return null;
    return root;
  }

  CollectionReference<Map<String, dynamic>> _timerHistory(
    DocumentReference<Map<String, dynamic>> root,
  ) =>
      root.collection('timers').doc('active').collection('history');

  List<SchoolTimer> _parseTimers(
          QuerySnapshot<Map<String, dynamic>> snapshot) =>
      snapshot.docs
          .map(
            (doc) => SchoolTimer.fromJson({...doc.data(), 'id': doc.id}),
          )
          .toList();

  String _getDayOfWeek(DateTime date) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
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
