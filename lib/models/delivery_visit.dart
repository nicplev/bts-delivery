/// Identifies the independent work records for one scheduled delivery.
class DeliveryVisit {
  const DeliveryVisit({required this.deliveryId, required this.schoolId});

  final String deliveryId;
  final String schoolId;

  String get workspacePath => 'deliveries/$deliveryId/workspace/$schoolId';

  @override
  bool operator ==(Object other) =>
      other is DeliveryVisit &&
      other.deliveryId == deliveryId &&
      other.schoolId == schoolId;

  @override
  int get hashCode => Object.hash(deliveryId, schoolId);
}

String schoolWorkPath(String schoolId,
    {DeliveryVisit? visit, String suffix = ''}) {
  final school = '/schools/${Uri.encodeComponent(schoolId)}';
  return visit == null
      ? '$school$suffix'
      : '/deliveries/${Uri.encodeComponent(visit.deliveryId)}$school$suffix';
}
