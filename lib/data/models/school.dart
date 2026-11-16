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
    @TimestampConverter() required DateTime createdAt,
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

@freezed
class Classroom with _$Classroom {
  const factory Classroom({
    required String id,
    required String name,
    @TimestampConverter() required DateTime createdAt,
  }) = _Classroom;

  factory Classroom.fromJson(Map<String, dynamic> json) =>
      _$ClassroomFromJson(json);
}

@freezed
class Photo with _$Photo {
  const factory Photo({
    required String id,
    required String storagePath,
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
