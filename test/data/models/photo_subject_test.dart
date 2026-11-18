import 'package:bts_delivery_app/models/photo_subject.dart';
import 'package:bts_delivery_app/models/school.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime.utc(2026, 11, 18, 9);
  final timestamp = Timestamp.fromDate(at);

  test('an older photo document parses unchanged as a general photo', () {
    final photo = Photo.fromJson({
      'id': 'p1',
      'storagePath': 'schools/s/yearLevels/y/classrooms/c/photos/p1.jpg',
      'uploadedBy': 'uid',
      'uploadedAt': timestamp,
    });
    expect(photo.subject, isNull);
    expect(photo.subjectType, isNull);
    expect(photo.toJson(), {
      'id': 'p1',
      'storagePath': 'schools/s/yearLevels/y/classrooms/c/photos/p1.jpg',
      'uploadedBy': 'uid',
      'uploadedAt': timestamp,
    });
  });

  test('a general photo writes exactly the original keys', () {
    final json = Photo(
      id: 'p1',
      storagePath: 'path.jpg',
      uploadedBy: 'uid',
      uploadedAt: at,
    ).toJson();
    expect(json.keys, ['id', 'storagePath', 'uploadedBy', 'uploadedAt']);
  });

  test('packs and consumable photos round-trip', () {
    final packs = Photo(
      id: 'p2',
      storagePath: 'path.jpg',
      uploadedBy: 'uid',
      uploadedAt: at,
      subjectType: PhotoSubject.packs.type,
    );
    expect(packs.toJson().keys,
        ['id', 'storagePath', 'uploadedBy', 'uploadedAt', 'subjectType']);
    expect(Photo.fromJson(packs.toJson()).subject, PhotoSubject.packs);

    final tissues = PhotoSubject.consumable(id: 'abc123', label: ' Tissues ');
    final consumable = Photo(
      id: 'p3',
      storagePath: 'path.jpg',
      uploadedBy: 'uid',
      uploadedAt: at,
      subjectType: tissues.type,
      subjectId: tissues.id,
      subjectLabel: tissues.label,
    );
    final json = consumable.toJson();
    expect(json['subjectType'], 'consumable');
    expect(json['subjectId'], 'abc123');
    expect(json['subjectLabel'], 'Tissues');
    final parsed = Photo.fromJson(json);
    expect(parsed.copyWith(uploadedAt: at), consumable);
    expect(parsed.subject, tissues);
  });

  test('labels are bounded for the rules without splitting characters', () {
    expect(PhotoSubject.boundedLabel('x' * 140), 'x' * 100);
    final emoji = '${'x' * 99}😀';
    expect(PhotoSubject.boundedLabel(emoji), 'x' * 99);
    expect(PhotoSubject.consumable(id: 'a', label: 'y' * 101).label!.length,
        100);
  });

  test('combinations the app never writes are treated as general', () {
    expect(PhotoSubject.fromFields(null, null, null), isNull);
    expect(PhotoSubject.fromFields('headphones', null, null), isNull);
    expect(PhotoSubject.fromFields('packs', 'id', null), isNull);
    expect(PhotoSubject.fromFields('consumable', null, 'Tissues'), isNull);
    expect(PhotoSubject.fromFields(null, 'id', 'Tissues'), isNull);
  });
}
