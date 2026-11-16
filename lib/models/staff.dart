import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'staff.freezed.dart';
part 'staff.g.dart';

@freezed
class Staff with _$Staff {
  const factory Staff({
    required String id,
    required String name,
    String? uid,
    @Default('staff') String role, // 'manager', 'admin', or 'staff'
    @Default([]) List<String> assignedSchoolIds, // Schools this staff member is assigned to
    String? linkPin, // 4-digit PIN for account linking verification
    String? calendarToken, // Unique token for calendar subscription URL
    @TimestampConverter() required DateTime createdAt,
  }) = _Staff;

  factory Staff.fromJson(Map<String, dynamic> json) => _$StaffFromJson(json);

  const Staff._();

  bool get isManager => role == 'manager';
  bool get isAdmin => role == 'admin';
  bool get hasManagerAccess => role == 'manager' || role == 'admin';
  bool get hasAssignedSchools => assignedSchoolIds.isNotEmpty;
  bool get isLinked => uid != null;
  bool get hasCalendarToken => calendarToken != null && calendarToken!.isNotEmpty;
}

class TimestampConverter implements JsonConverter<DateTime, Timestamp> {
  const TimestampConverter();

  @override
  DateTime fromJson(Timestamp timestamp) {
    return timestamp.toDate();
  }

  @override
  Timestamp toJson(DateTime date) => Timestamp.fromDate(date);
}