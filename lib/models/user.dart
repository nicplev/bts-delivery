import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

@freezed
class AppUser with _$AppUser {
  const factory AppUser({
    required String uid,
    required String email,
    @Default('staff') String role, // 'admin', 'manager', 'staff'
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() DateTime? lastLoginAt,
  }) = _AppUser;

  factory AppUser.fromJson(Map<String, dynamic> json) => _$AppUserFromJson(json);
  
  const AppUser._();

  bool get isAdmin => role == 'admin';
  bool get isManager => role == 'manager';
  bool get hasManagerAccess => role == 'admin' || role == 'manager';
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