import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'calendar_metadata.freezed.dart';
part 'calendar_metadata.g.dart';

/// Metadata for calendar subscription access tracking
@freezed
class CalendarMetadata with _$CalendarMetadata {
  const factory CalendarMetadata({
    required String staffId,
    required String token,
    @TimestampConverter() DateTime? lastAccessed,
    @Default(0) int accessCount,
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() DateTime? lastDeliveryChange,
  }) = _CalendarMetadata;

  factory CalendarMetadata.fromJson(Map<String, dynamic> json) =>
      _$CalendarMetadataFromJson(json);

  const CalendarMetadata._();

  /// Check if calendar has been accessed recently (within last 7 days)
  bool get isActive {
    if (lastAccessed == null) return false;
    final daysSinceAccess = DateTime.now().difference(lastAccessed!).inDays;
    return daysSinceAccess <= 7;
  }

  /// Get human-readable last accessed text
  String get lastAccessedText {
    if (lastAccessed == null) return 'Never accessed';

    final now = DateTime.now();
    final difference = now.difference(lastAccessed!);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inDays < 30) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else {
      return 'Over a month ago';
    }
  }
}

/// Timestamp converter for Firestore timestamps
class TimestampConverter implements JsonConverter<DateTime, Timestamp> {
  const TimestampConverter();

  @override
  DateTime fromJson(Timestamp timestamp) {
    return timestamp.toDate();
  }

  @override
  Timestamp toJson(DateTime date) => Timestamp.fromDate(date);
}
