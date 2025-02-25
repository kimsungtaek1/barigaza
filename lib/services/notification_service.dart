import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 알림 생성
  Future<void> createNotification({
    required String userId,
    required String title,
    required String message,
    required String type,
    String? targetId,
    Map<String,dynamic>? metadata,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .add({
        'title': title,
        'message': message,
        'type': type,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'targetId': targetId,
        'userId': _auth.currentUser?.uid,
      });
    } catch (e) {
      print('알림 생성 실패: $e');
      rethrow;
    }
  }

  // 댓글 알림 생성
  Future<void> createCommentNotification({
    required String postOwnerId,
    required String postId,
    required String commenterNickname,
  }) async {
    await createNotification(
      userId: postOwnerId,
      title: '새로운 댓글',
      message: '$commenterNickname님이 회원님의 게시물에 댓글을 달았습니다.',
      type: 'comment',
      targetId: postId,
    );
  }

  // 번개 모임 참가 요청 알림
  Future<void> createMeetingRequestNotification({
    required String hostId,
    required String meetingId,
    required String requesterNickname,
  }) async {
    await createNotification(
      userId: hostId,
      title: '번개 참가 요청',
      message: '$requesterNickname님이 번개 모임 참가를 요청했습니다.',
      type: 'meeting_request',
      targetId: meetingId,
      metadata: {
        'requestStatus': 'pending',
        'requesterId': _auth.currentUser?.uid,
        'requesterNickname': requesterNickname,
      }
    );
  }

  // 번개 모임 승인/거절 알림
  Future<void> createMeetingResponseNotification({
    required String requesterId,
    required String meetingId,
    required bool isAccepted,
  }) async {
    // 미팅 정보 조회
    final meetingDoc = await FirebaseFirestore.instance
        .collection('meetings')
        .doc(meetingId)
        .get();

    if (!meetingDoc.exists) return;

    final chatRoomId = meetingDoc.data()?['chatRoomId'];

    await createNotification(
      userId: requesterId,
      title: isAccepted ? '참가 요청 승인' : '참가 요청 거절',
      message: isAccepted
          ? '번개 모임 참가 요청이 승인되었습니다.'
          : '번개 모임 참가 요청이 거절되었습니다.',
      type: isAccepted ? 'meeting_accepted' : 'meeting_rejected',
      targetId: meetingId,  // meetingId 전달
      metadata: isAccepted ? {'chatRoomId': chatRoomId} : null,  // 채팅방 ID도 함께 전달
    );
  }

  Future<void> updateMeetingRequestAndNotify({
    required String requesterId,
    required String meetingId,
    required bool isAccepted,
    required String notificationId,  // 원본 요청 알림 ID
  }) async {
    final batch = _firestore.batch();

    // 1. 요청 상태 업데이트
    final requestRef = _firestore
        .collection('meetings')
        .doc(meetingId)
        .collection('requests')
        .doc(requesterId);

    batch.update(requestRef, {
      'status': isAccepted ? 'approved' : 'rejected',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. 기존 알림 메타데이터 업데이트
    final originalNotificationRef = _firestore
        .collection('users')
        .doc(requesterId)
        .collection('notifications')
        .doc(notificationId);

    batch.update(originalNotificationRef, {
      'metadata.requestStatus': isAccepted ? 'approved' : 'rejected',
      'metadata.responseTime': FieldValue.serverTimestamp(),
    });

    // 3. 새 응답 알림 생성
    final newNotificationRef = _firestore
        .collection('users')
        .doc(requesterId)
        .collection('notifications')
        .doc();

    batch.set(newNotificationRef, {
      'title': isAccepted ? '참가 요청 승인' : '참가 요청 거절',
      'message': isAccepted
          ? '번개 모임 참가 요청이 승인되었습니다.'
          : '번개 모임 참가 요청이 거절되었습니다.',
      'type': isAccepted ? 'meeting_accepted' : 'meeting_rejected',
      'targetId': meetingId,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      'metadata': {
        'requestStatus': isAccepted ? 'approved' : 'rejected',
        'originalRequestId': notificationId,
      }
    });

    await batch.commit();
  }

  // 알림 읽음 처리
  Future<void> markAsRead(String notificationId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});
    } catch (e) {
      print('알림 읽음 처리 실패: $e');
      rethrow;
    }
  }

  // 모든 알림 읽음 처리
  Future<void> markAllAsRead() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      final batch = _firestore.batch();
      final notifications = await _firestore
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .where('isRead', isEqualTo: false)
          .get();

      for (var doc in notifications.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      await batch.commit();
    } catch (e) {
      print('전체 알림 읽음 처리 실패: $e');
      rethrow;
    }
  }

  // 알림 삭제
  Future<void> deleteNotification(String notificationId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notificationId)
          .delete();
    } catch (e) {
      print('알림 삭제 실패: $e');
      rethrow;
    }
  }
}