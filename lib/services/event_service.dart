import 'package:cloud_firestore/cloud_firestore.dart';

class EventService {
  static final EventService _instance = EventService._internal();

  factory EventService() {
    return _instance;
  }

  EventService._internal();

  Future<void> checkExpiredEvents() async {
    try {
      // 활성화된 이벤트만 조회
      final querySnapshot = await FirebaseFirestore.instance
          .collection('events')
          .where('isActive', isEqualTo: true)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      bool hasExpiredEvents = false;
      final now = Timestamp.now();

      for (var doc in querySnapshot.docs) {
        if (doc.data().containsKey('endDate')) {
          final endDate = doc.data()['endDate'] as Timestamp;
          if (endDate.compareTo(now) <= 0) {
            batch.update(doc.reference, {
              'isActive': false,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            hasExpiredEvents = true;
          }
        }
      }

      if (hasExpiredEvents) {
        await batch.commit();
        print('만료된 이벤트가 비활성화되었습니다.');
      }
    } catch (e) {
      print('이벤트 체크 중 오류 발생: $e');
    }
  }
}