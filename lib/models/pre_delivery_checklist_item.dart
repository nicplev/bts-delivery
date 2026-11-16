import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'pre_delivery_checklist_item.freezed.dart';
part 'pre_delivery_checklist_item.g.dart';

class TimestampConverter implements JsonConverter<DateTime, Timestamp> {
  const TimestampConverter();

  @override
  DateTime fromJson(Timestamp timestamp) {
    return timestamp.toDate();
  }

  @override
  Timestamp toJson(DateTime date) {
    return Timestamp.fromDate(date);
  }
}

@freezed
class PreDeliveryChecklistItem with _$PreDeliveryChecklistItem {
  const factory PreDeliveryChecklistItem({
    required String id,
    required String title,
    String? subtitle,
    required int order, // For sorting items
    @Default(true) bool isActive, // Can be disabled without deleting
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() DateTime? updatedAt,
    String? createdBy,
  }) = _PreDeliveryChecklistItem;

  factory PreDeliveryChecklistItem.fromJson(Map<String, dynamic> json) =>
      _$PreDeliveryChecklistItemFromJson(json);
}
