import 'package:cloud_firestore/cloud_firestore.dart';

class MaintenancePeriod {
  final int kilometers;
  final int? months;

  MaintenancePeriod({
    required this.kilometers,
    this.months,
  });

  Map<String, dynamic> toMap() {
    return {
      'kilometers': kilometers,
      'months': months,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static MaintenancePeriod fromMap(Map<String, dynamic> map) {
    return MaintenancePeriod(
      kilometers: map['kilometers'] as int,
      months: map['months'] as int?,
    );
  }
}