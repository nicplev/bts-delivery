import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'school.dart';

part 'school_timer.freezed.dart';
part 'school_timer.g.dart';

@freezed
class SchoolTimer with _$SchoolTimer {
  const factory SchoolTimer({
    required String id,
    required String schoolId,
    @TimestampConverter() required DateTime startedAt,
    @TimestampConverter() DateTime? stoppedAt,
    required String startedByUid,
    required String startedByName,
    String? stoppedByUid,
    String? stoppedByName,
    @Default(true) bool isActive,
    @TimestampConverter() required DateTime createdAt,
  }) = _SchoolTimer;

  factory SchoolTimer.fromJson(Map<String, dynamic> json) =>
      _$SchoolTimerFromJson(json);

  const SchoolTimer._();

  /// Calculate elapsed duration from start to stop (or now if still running)
  Duration get elapsed {
    final endTime = stoppedAt ?? DateTime.now();
    return endTime.difference(startedAt);
  }

  /// Format elapsed duration as HH:MM:SS
  String get formattedElapsed {
    final d = elapsed;
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
