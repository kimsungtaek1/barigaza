class FuelRecord {
  final String id;
  final String userId;
  final String recordDate;
  final double distance;    // 주행거리 (km)
  final double amount;      // 주유량 (L)

  FuelRecord({
    required this.id,
    required this.userId,
    required this.recordDate,
    required this.distance,
    required this.amount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'recordDate': recordDate,
      'distance': distance,
      'amount': amount,
    };
  }

  factory FuelRecord.fromMap(Map<String, dynamic> map) {
    return FuelRecord(
      id: map['id'] as String,
      userId: map['userId'] as String,
      recordDate: map['recordDate'] as String,
      distance: (map['distance'] as num).toDouble(),
      amount: (map['amount'] as num).toDouble(),
    );
  }
}