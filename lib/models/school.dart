import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'school.freezed.dart';
part 'school.g.dart';

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
class School with _$School {
  const factory School({
    required String id,
    required String name,
    String? address,
    String? contactName,
    String? contactPhone,
    String? contactEmail,
    @TimestampConverter() required DateTime createdAt,
    @Default(false) bool isSignedOff,
    @TimestampConverter() DateTime? lastSignOffDate,
    String? signedBy,
    String? schoolMapUrl, // URL to school map image/PDF in Firebase Storage
    String? schoolMapStoragePath, // Storage path for deletion
    /// Optional school logo shown in place of the default school icon.
    /// Written only by `SchoolsRepository.updateSchoolLogo`.
    String? logoUrl, // Download URL of the logo JPEG in Firebase Storage
    String? logoStoragePath, // schools/{schoolId}/logo/{uuid}.jpg, for deletion
  }) = _School;

  factory School.fromJson(Map<String, dynamic> json) => _$SchoolFromJson(json);
}

@freezed
class YearLevel with _$YearLevel {
  const factory YearLevel({
    required String id,
    required String label,
    @TimestampConverter() required DateTime createdAt,
  }) = _YearLevel;

  factory YearLevel.fromJson(Map<String, dynamic> json) =>
      _$YearLevelFromJson(json);
}

/// Completion status for classroom deliveries
enum ClassroomCompletionStatus {
  /// Classroom has not been attended yet (red)
  notAttended,
  /// Classroom partially complete or incomplete (yellow)
  incomplete,
  /// Classroom fully complete with correct packs and consumables (green)
  complete,
}

@freezed
class YearLevelBreakdown with _$YearLevelBreakdown {
  const factory YearLevelBreakdown({
    required String id,
    required String yearLevelId,
    required String yearLevelLabel,
    required int studentCount,
    int? packAllocation,
    @TimestampConverter() required DateTime createdAt,
  }) = _YearLevelBreakdown;

  factory YearLevelBreakdown.fromJson(Map<String, dynamic> json) =>
      _$YearLevelBreakdownFromJson(json);
}

@freezed
class Classroom with _$Classroom {
  const Classroom._();

  const factory Classroom({
    required String id,
    required String name,
    @TimestampConverter() required DateTime createdAt,
    @Default(ClassroomCompletionStatus.notAttended) ClassroomCompletionStatus completionStatus,
    /// Actual number of packs delivered (null if not specified, used for incomplete deliveries)
    int? actualPacksDelivered,
    /// Name of the last person who updated this classroom
    String? lastUpdatedBy,
    /// When this classroom was last updated
    @TimestampConverter() DateTime? lastUpdatedAt,
    /// Year level breakdowns for composite classes (e.g., Year 1/2A with 10 Year 1s and 14 Year 2s)
    @Default([]) List<YearLevelBreakdown> yearLevelBreakdowns,
  }) = _Classroom;

  factory Classroom.fromJson(Map<String, dynamic> json) =>
      _$ClassroomFromJson(json);

  /// Total number of students across all year levels
  int get totalStudents => yearLevelBreakdowns.fold(
        0,
        (sum, breakdown) => sum + breakdown.studentCount,
      );

  /// Whether this is a composite class (multiple year levels)
  bool get isComposite => yearLevelBreakdowns.length > 1;

  /// Total pack allocation across all year level breakdowns
  int? get totalPackAllocation {
    if (yearLevelBreakdowns.isEmpty) return null;
    final allocations = yearLevelBreakdowns
        .where((b) => b.packAllocation != null)
        .map((b) => b.packAllocation!)
        .toList();
    if (allocations.isEmpty) return null;
    return allocations.reduce((a, b) => a + b);
  }
}

@freezed
class Photo with _$Photo {
  const factory Photo({
    required String id,
    required String storagePath,
    String? uploadedBy, // UID of the user who uploaded this photo
    @TimestampConverter() required DateTime uploadedAt,
  }) = _Photo;

  factory Photo.fromJson(Map<String, dynamic> json) => _$PhotoFromJson(json);
}

@freezed
class PackTotal with _$PackTotal {
  const factory PackTotal({
    required String id,
    required int total,
    @TimestampConverter() required DateTime createdAt,
  }) = _PackTotal;

  factory PackTotal.fromJson(Map<String, dynamic> json) =>
      _$PackTotalFromJson(json);
}

@freezed
class Consumable with _$Consumable {
  const factory Consumable({
    required String id,
    required String itemName,
    required int quantity,
    required String unit,
    @TimestampConverter() required DateTime createdAt,
    /// Actual quantity delivered (null if not specified, used for partial deliveries)
    int? actualQuantityDelivered,
  }) = _Consumable;

  factory Consumable.fromJson(Map<String, dynamic> json) =>
      _$ConsumableFromJson(json);
}

@freezed
class SignOff with _$SignOff {
  const factory SignOff({
    required String typedName,
    required String signatureURL,
    @TimestampConverter() required DateTime createdAt,
  }) = _SignOff;

  factory SignOff.fromJson(Map<String, dynamic> json) =>
      _$SignOffFromJson(json);
}

@freezed
class Contact with _$Contact {
  const factory Contact({
    required String id,
    required String name,
    String? phone,
    String? email,
    @TimestampConverter() required DateTime createdAt,
  }) = _Contact;

  factory Contact.fromJson(Map<String, dynamic> json) =>
      _$ContactFromJson(json);
}

@freezed
class MapAsset with _$MapAsset {
  const factory MapAsset({
    required String id,
    required String name,
    required String storagePath,
    required String type, // 'image' or 'pdf'
    @TimestampConverter() required DateTime createdAt,
  }) = _MapAsset;

  factory MapAsset.fromJson(Map<String, dynamic> json) =>
      _$MapAssetFromJson(json);
}

@freezed
class Note with _$Note {
  const factory Note({
    required String id,
    required String content,
    String? author,
    @TimestampConverter() required DateTime createdAt,
  }) = _Note;

  factory Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);
}

@freezed
class SignedSchoolSummary with _$SignedSchoolSummary {
  const factory SignedSchoolSummary({
    required String id,
    required String schoolId,
    required String schoolName,
    String? schoolAddress,

    // Sign-off details
    required String signedBy,
    String? signatureUrl,
    @TimestampConverter() required DateTime signedDate,

    // Pack totals
    required int totalPacks,
    required Map<String, int> packTotalsByYearLevel,
    required Map<String, Map<String, int>> packTotalsByClassroom,

    // Consumables totals
    required Map<String, ConsumableSummary> consumablesTotals,
    required Map<String, Map<String, ConsumableSummary>> consumablesByYearLevel,
    required Map<String, Map<String, Map<String, ConsumableSummary>>> consumablesByClassroom,

    // Classroom delivery details (status, actual vs expected)
    @Default([]) List<ClassroomDeliveryDetail> classroomDeliveryDetails,

    // Photos and notes
    required List<String> photoUrls,
    String? notes,
    required Map<String, Map<String, List<String>>> notesByClassroom,

    @TimestampConverter() required DateTime createdAt,
  }) = _SignedSchoolSummary;

  factory SignedSchoolSummary.fromJson(Map<String, dynamic> json) =>
      _$SignedSchoolSummaryFromJson(json);
}

@freezed
class ConsumableSummary with _$ConsumableSummary {
  const factory ConsumableSummary({
    required String itemName,
    required int quantity,
    required String unit,
  }) = _ConsumableSummary;

  factory ConsumableSummary.fromJson(Map<String, dynamic> json) =>
      _$ConsumableSummaryFromJson(json);
}

@freezed
class ClassroomDeliveryDetail with _$ClassroomDeliveryDetail {
  const factory ClassroomDeliveryDetail({
    required String yearLevel,
    required String classroomName,
    required ClassroomCompletionStatus status,
    required int expectedPacks,
    int? actualPacksDelivered,
    required Map<String, ConsumableDeliveryDetail> consumables,
  }) = _ClassroomDeliveryDetail;

  factory ClassroomDeliveryDetail.fromJson(Map<String, dynamic> json) =>
      _$ClassroomDeliveryDetailFromJson(json);
}

@freezed
class ConsumableDeliveryDetail with _$ConsumableDeliveryDetail {
  const factory ConsumableDeliveryDetail({
    required String itemName,
    required int expectedQuantity,
    int? actualQuantityDelivered,
    required String unit,
  }) = _ConsumableDeliveryDetail;

  factory ConsumableDeliveryDetail.fromJson(Map<String, dynamic> json) =>
      _$ConsumableDeliveryDetailFromJson(json);
}
