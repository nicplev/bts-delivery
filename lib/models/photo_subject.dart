/// What a classroom photo shows, chosen when it is taken and never changed.
///
/// Stored as three flat optional fields on photo records and queued uploads:
/// `subjectType` (`'packs'` or `'consumable'`), `subjectId` (the consumable's
/// document id) and `subjectLabel` (the consumable's name when the photo was
/// taken). A photo without them is a general classroom photo.
class PhotoSubject {
  const PhotoSubject._(this.type, this.id, this.label);

  static const packsType = 'packs';
  static const consumableType = 'consumable';

  /// Longest saved item name (the photo rules allow 100 characters).
  static const maxLabelLength = 100;

  /// Consumable ids: Firestore auto ids and the short ids used by imports.
  static final idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  static const packs = PhotoSubject._(packsType, null, null);

  factory PhotoSubject.consumable({
    required String id,
    required String label,
  }) =>
      PhotoSubject._(consumableType, id, boundedLabel(label));

  /// `'packs'` or `'consumable'`.
  final String type;

  /// The consumable's document id (consumables only).
  final String? id;

  /// The consumable's name when the photo was taken (consumables only).
  final String? label;

  bool get isPacks => type == packsType;

  /// Reads the stored fields; null for a general photo and for any
  /// combination the app would not have written.
  static PhotoSubject? fromFields(String? type, String? id, String? label) {
    if (type == packsType && id == null && label == null) return packs;
    if (type == consumableType && id != null && id.isNotEmpty) {
      return PhotoSubject._(consumableType, id, label ?? '');
    }
    return null;
  }

  /// Trims [value] and keeps at most [maxLabelLength] UTF-16 units without
  /// splitting a character.
  static String boundedLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= maxLabelLength) return trimmed;
    final buffer = StringBuffer();
    for (final rune in trimmed.runes) {
      final next = String.fromCharCode(rune);
      if (buffer.length + next.length > maxLabelLength) break;
      buffer.write(next);
    }
    return buffer.toString().trimRight();
  }

  @override
  bool operator ==(Object other) =>
      other is PhotoSubject &&
      other.type == type &&
      other.id == id &&
      other.label == label;

  @override
  int get hashCode => Object.hash(type, id, label);

  @override
  String toString() => 'PhotoSubject($type, $id, $label)';
}
