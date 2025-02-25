import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/maintenance_period.dart';

class MaintenanceService {
  final String userId;
  final FirebaseFirestore _firestore;

  MaintenanceService({required this.userId}) :
        _firestore = FirebaseFirestore.instance;

  // 교체 주기 조회
  Future<MaintenancePeriod?> getMaintenancePeriod(String partType) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null || currentUser.uid != userId) {
        throw Exception('인증 오류: 사용자 권한이 없습니다.');
      }

      final docRef = _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('maintenance_periods')
          .doc(partType);

      final doc = await docRef.get();

      if (!doc.exists) {
        return null;
      }

      return MaintenancePeriod.fromMap(doc.data() ?? {});

    } catch (e) {
      print('교체 주기 조회 실패: $e');
      rethrow;
    }
  }

  // 교체 주기 업데이트
  Future<void> updateMaintenancePeriod(String partType, MaintenancePeriod period) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null || currentUser.uid != userId) {
        throw Exception('인증 오류: 사용자 권한이 없습니다.');
      }

      final docRef = _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('maintenance_periods')
          .doc(partType);

      // period.toMap() 사용하여 데이터 저장
      await docRef.set(period.toMap(), SetOptions(merge: true));

    } catch (e) {
      print('교체 주기 업데이트 실패: $e');
      rethrow;
    }
  }
}