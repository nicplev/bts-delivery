import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'pre_delivery_completion.freezed.dart';
part 'pre_delivery_completion.g.dart';

class TimestampOrNullConverter implements JsonConverter<DateTime?, Timestamp?> {
  const TimestampOrNullConverter();

  @override
  DateTime? fromJson(Timestamp? timestamp) {
    return timestamp?.toDate();
  }

  @override
  Timestamp? toJson(DateTime? date) {
    return date != null ? Timestamp.fromDate(date) : null;
  }
}

@freezed
class PreDeliveryCompletion with _$PreDeliveryCompletion {
  const factory PreDeliveryCompletion({
    required String itemId,
    @Default(false) bool isCompleted,
    String? completedBy,
    @TimestampOrNullConverter() DateTime? completedAt,
  }) = _PreDeliveryCompletion;

  factory PreDeliveryCompletion.fromJson(Map<String, dynamic> json) =>
      _$PreDeliveryCompletionFromJson(json);
}
