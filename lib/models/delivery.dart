import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'staff.dart';

part 'delivery.freezed.dart';
part 'delivery.g.dart';

@freezed
class Delivery with _$Delivery {
  const factory Delivery({
    required String id,
    required String schoolId,
    required String schoolName,
    @TimestampConverter() required DateTime date,
    @TimestampConverter() DateTime? time,
    @Default([]) List<String> staffIds,
    @Default([]) List<String> staffNames,
    String? notes,
    int? vehicleCount,
    int? palletCount,
    @TimestampConverter() required DateTime createdAt,
  }) = _Delivery;

  factory Delivery.fromJson(Map<String, dynamic> json) => _$DeliveryFromJson(json);

  const Delivery._();

  bool isAssignedToStaff(String staffId) => staffIds.contains(staffId);

  DateTime get effectiveDateTime => time ?? date;
}