import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fuel_record.dart';
import '../models/maintenance_record.dart';

class MaintenanceTrackingService {
  final String userId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  MaintenanceTrackingService({required this.userId});

  Future<void> addMaintenanceRecord(MaintenanceRecord record) async {
    try {
      // 트랜잭션으로 안전하게 처리
      await _firestore.runTransaction((transaction) async {
        // 사용자의 maintenance_records 서브컬렉션에 기록 추가
        final recordRef = _firestore
            .collection('users')
            .doc(userId)
            .collection('maintenance_records')
            .doc();

        final recordData = {
          ...record.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        };

        transaction.set(recordRef, recordData);

        // 사용자 문서의 lastMaintenance 필드 업데이트
        final userRef = _firestore.collection('users').doc(userId);
        transaction.update(userRef, {
          'lastMaintenance.${record.partType}': {
            'date': record.maintenanceDate.toIso8601String(),
            'mileage': record.currentMileage,
          }
        });
      });
    } catch (e) {
      print('Error adding maintenance record: $e');
      rethrow;
    }
  }

  Future<List<MaintenanceRecord>> getMaintenanceRecords(String partType) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('maintenance_records')
          .where('partType', isEqualTo: partType)
          .orderBy('maintenanceDate', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return MaintenanceRecord(
          id: doc.id,
          userId: data['userId'],
          partType: data['partType'],
          maintenanceDate: DateTime.parse(data['maintenanceDate']),
          currentMileage: data['currentMileage'].toDouble(),
        );
      }).toList();
    } catch (e) {
      print('Error getting maintenance records: $e');
      throw e;
    }
  }

  Future<double> calculateAverageFuelEfficiency() async {
    try {
      // 사용자의 최근 5개 주유 기록 조회
      final records = await _firestore
          .collection('users')
          .doc(userId)
          .collection('fuel_records')
          .orderBy('recordDate', descending: true)
          .get();

      if (records.docs.isEmpty) return 0.0;

      double totalDistance = 0.0;
      double totalFuel = 0.0;

      // 각 기록에서 거리와 주유량 합산
      for (var doc in records.docs) {
        final data = doc.data();
        totalDistance += data['distance'] as double;
        totalFuel += data['amount'] as double;
      }

      // 평균 연비 계산 (총 주행거리 / 총 주유량)
      return totalFuel > 0 ? totalDistance / totalFuel : 0.0;
    } catch (e) {
      print('Error calculating average fuel efficiency: $e');
      return 0.0;
    }
  }
}