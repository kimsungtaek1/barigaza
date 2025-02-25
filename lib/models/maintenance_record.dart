class MaintenanceRecord {
  final String id;
  final String userId;
  final String partType;
  final DateTime maintenanceDate;
  final double currentMileage;

  MaintenanceRecord({
    required this.id,
    required this.userId,
    required this.partType,
    required this.maintenanceDate,
    required this.currentMileage,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'partType': partType,
      'maintenanceDate': maintenanceDate.toIso8601String(),
      'currentMileage': currentMileage,
    };
  }
}