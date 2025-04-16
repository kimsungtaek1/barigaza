import 'package:cloud_firestore/cloud_firestore.dart';

class MeetingService {
  static final MeetingService _instance = MeetingService._internal();

  factory MeetingService() {
    return _instance;
  }

  MeetingService._internal();

  /// 만료된 번개모임을 체크하고 상태를 updated합니다.
  /// 모임 시간 이후 3시간이 지난 모임을 'completed' 상태로 변경합니다.
  Future<void> checkExpiredMeetings() async {
    try {
      // 현재 활성화된 모임만 조회
      final querySnapshot = await FirebaseFirestore.instance
          .collection('meetings')
          .where('status', isEqualTo: 'active')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      bool hasExpiredMeetings = false;
      final now = Timestamp.now();

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        if (data.containsKey('meetingTime')) {
          final meetingTime = data['meetingTime'] as Timestamp;

          // 모임 시간 + 3시간을 계산
          final expiryTime = DateTime.fromMillisecondsSinceEpoch(
              meetingTime.millisecondsSinceEpoch + (3 * 60 * 60 * 1000) // 3시간 추가
          );

          // 만료 시간이 현재보다 이전이면 상태 업데이트
          if (Timestamp.fromDate(expiryTime).compareTo(now) <= 0) {
            batch.update(doc.reference, {
              'status': 'completed',
              'completedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });

            // 채팅방에 모임 종료 공지 메시지 보내기
            final chatRoomId = data['chatRoomId'] ?? 'meeting_${doc.id}';
            final chatRef = FirebaseFirestore.instance
                .collection('chatRooms')
                .doc(chatRoomId)
                .collection('messages')
                .doc();

            batch.set(chatRef, {
              'senderId': 'system',
              'senderName': '시스템',
              'message': '[공지] 이 번개모임은 종료되었습니다.',
              'type': 'text',
              'timestamp': FieldValue.serverTimestamp(),
            });

            // 채팅방 마지막 메시지 업데이트
            batch.update(
                FirebaseFirestore.instance.collection('chatRooms').doc(chatRoomId),
                {
                  'lastMessage': '[공지] 이 번개모임은 종료되었습니다.',
                  'lastMessageTime': FieldValue.serverTimestamp(),
                }
            );

            hasExpiredMeetings = true;
          }
        }
      }

      if (hasExpiredMeetings) {
        await batch.commit();
        print('만료된 번개모임이 completed 상태로 변경되었습니다.');
      }
    } catch (e) {
      print('번개모임 만료 체크 중 오류 발생: $e');
    }
  }

  /// 앱 시작 시 호출되는 메서드
  /// main.dart에서 호출하여 앱 시작 시 만료된 모임을 체크합니다.
  Future<void> initializeMeetingCheck() async {
    await checkExpiredMeetings();
  }

  /// 주기적인 체크를 위한 메서드
  /// 앱이 백그라운드에서 실행 중일 때 주기적으로 호출합니다.
  Future<void> setupPeriodicMeetingCheck() async {
    // 여기서는 앱 내 주기적 실행 코드만 추가
    // 실제 구현은 main.dart 또는 적절한 위치에서 처리
  }
}