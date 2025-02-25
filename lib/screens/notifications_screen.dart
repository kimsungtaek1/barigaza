import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/notification.dart'; // NotificationModel 클래스가 정의된 파일
import '../services/notification_service.dart'; // NotificationService 클래스가 정의된 파일
import 'community_content_screen.dart'; // 게시물 상세 페이지로 이동하기 위한 파일
import 'chat_room_screen.dart'; // 단톡방으로 이동하기 위한 파일

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _notificationService = NotificationService();
  final String _userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _isLoading = false;

  // 알림 타입에 따른 아이콘 생성
  Widget _buildNotificationIcon(String type) {
    IconData iconData;
    Color iconColor;
    switch (type) {
      case 'comment':
        iconData = Icons.comment;
        iconColor = Colors.blue;
        break;
      case 'meeting_request':
        iconData = Icons.group_add;
        iconColor = Colors.green;
        break;
      case 'meeting_accepted':
        iconData = Icons.check_circle;
        iconColor = Colors.green;
        break;
      case 'meeting_rejected':
        iconData = Icons.cancel;
        iconColor = Colors.red;
        break;
      default:
        iconData = Icons.notifications;
        iconColor = Colors.grey;
    }

    return CircleAvatar(
      backgroundColor: iconColor.withOpacity(0.1),
      child: Icon(iconData, color: iconColor),
    );
  }

  // 알림 터치 시 처리
  Future<void> _handleNotificationTap(NotificationModel notification) async {
    // 알림 읽음 처리
    if (!notification.isRead) {
      await _notificationService.markAsRead(notification.id);
    }

    if (!mounted) return;

    // 알림 타입에 따른 화면 이동
    switch (notification.type) {
      case 'comment':
        if (notification.targetId != null) {
          // 게시물 상세 페이지(CommunityContentScreen)로 이동
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CommunityContentScreen(
                postId: notification.targetId!,
              ),
            ),
          );
        }
        break;
      case 'meeting_request':
        _showMeetingRequestDialog(notification);
        break;
      case 'meeting_accepted':
        if (notification.targetId != null) {
          // meetingId를 이용해 채팅방 ID 조회
          final meetingDoc = await FirebaseFirestore.instance
              .collection('meetings')
              .doc(notification.targetId)
              .get();

          if (meetingDoc.exists) {
            final chatRoomId = meetingDoc.data()?['chatRoomId'];
            if (chatRoomId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatRoomScreen(
                    chatId: chatRoomId,  // 실제 채팅방 ID 사용
                    otherUserNickname: '번개 모임',
                  ),
                ),
              );
            }
          }
        }
        break;
      case 'meeting_rejected':
      // 거절 알림 처리
        break;
    }
  }

  Future<String?> _getRequestStatus(String meetingId, String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('meetings')
          .doc(meetingId)
          .collection('requests')
          .doc(userId)
          .get();

      if (doc.exists) {
        return doc.data()?['status'];
      }
      return null;
    } catch (e) {
      debugPrint('Error getting request status: $e');
      return null;
    }
  }

  // 번개 참가 요청 알림 터치 시 다이얼로그 표시
  void _showMeetingRequestDialog(NotificationModel notification) {
    showDialog(
      context: context,
      builder: (context) => StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('meetings')
            .doc(notification.targetId)
            .collection('requests')
            .doc(notification.userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const AlertDialog(
              content: Center(child: CircularProgressIndicator()),
            );
          }

          // 데이터 안전하게 가져오기
          final data = snapshot.data?.data() as Map<String, dynamic>?;
          final status = data?['status'] as String? ?? 'pending';
          final bool isPending = status == 'pending';

          return AlertDialog(
            title: Text(isPending ? '번개 참가 요청' : '처리된 참가 요청'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notification.message),
                const SizedBox(height: 16),
                if (!isPending)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: status == 'approved'
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status == 'approved' ? '승인 완료' : '거부 완료',
                      style: TextStyle(
                        color: status == 'approved' ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              if (isPending) ...[
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _handleMeetingResponse(notification, false);
                  },
                  child: const Text('거부', style: TextStyle(color: Colors.black)),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _handleMeetingResponse(notification, true);
                  },
                  child: const Text('승인', style: TextStyle(color: Colors.black)),
                ),
              ] else
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('확인', style: TextStyle(color: Colors.black)),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleMeetingResponse(NotificationModel notification, bool isAccepted) async {
    try {
      debugPrint('===== 번개 모임 응답 처리 시작 =====');

      final meetingRef = FirebaseFirestore.instance
          .collection('meetings')
          .doc(notification.targetId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        debugPrint('트랜잭션 시작');

        // 1. 모든 읽기 작업을 먼저 수행
        // 요청 문서 읽기
        final requestRef = meetingRef
            .collection('requests')
            .doc(notification.userId);
        final requestDoc = await transaction.get(requestRef);

        // 미팅 문서 읽기 (승인 시 필요한 정보)
        final meetingDoc = await transaction.get(meetingRef);

        // 채팅방 정보 미리 가져오기
        String? chatRoomId;
        if (isAccepted) {
          chatRoomId = meetingDoc.data()?['chatRoomId'];
        }

        debugPrint('요청 문서 조회 완료: exists=${requestDoc.exists}');

        if (!requestDoc.exists) {
          throw Exception('존재하지 않는 요청입니다.');
        }

        final requestData = requestDoc.data()!;
        if (requestData['status'] != 'pending') {
          throw Exception('이미 처리된 요청입니다.');
        }

        // 2. 모든 쓰기 작업 수행
        // 요청 상태 업데이트
        transaction.update(requestRef, {
          'status': isAccepted ? 'approved' : 'rejected',
          'respondedAt': FieldValue.serverTimestamp(),
        });

        if (isAccepted) {
          // 참가자 목록에 추가
          transaction.update(meetingRef, {
            'participants': FieldValue.arrayUnion([notification.userId])
          });

          // 채팅방 참가자 추가
          if (chatRoomId != null) {
            final chatRoomRef = FirebaseFirestore.instance
                .collection('chatRooms')
                .doc(chatRoomId);

            transaction.update(chatRoomRef, {
              'users': FieldValue.arrayUnion([notification.userId])
            });
          }
        }
      });

      // 트랜잭션 외부에서 알림 전송
      await _notificationService.createMeetingResponseNotification(
        requesterId: notification.userId!,
        meetingId: notification.targetId!,
        isAccepted: isAccepted,
      );

      debugPrint('===== 번개 모임 응답 처리 완료 =====');
    } catch (e, stackTrace) {
      debugPrint('===== 에러 발생 =====');
      debugPrint('에러 메시지: $e');
      debugPrint('스택 트레이스: $stackTrace');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          TextButton(
            onPressed: _isLoading
                ? null
                : () async {
              setState(() => _isLoading = true);
              try {
                await _notificationService.markAllAsRead();
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
            child: _isLoading
                ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text('모두 읽음', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_userId)
            .collection('notifications')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data?.docs ?? [];

          if (notifications.isEmpty) {
            return const Center(
              child: Text('알림이 없습니다'),
            );
          }

          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = NotificationModel.fromFirestore(
                notifications[index],
              );

              return Dismissible(
                key: Key(notification.id),
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20.0),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (direction) async {
                  await _notificationService.deleteNotification(notification.id);
                },
                child: StreamBuilder<DocumentSnapshot>(
                  stream: notification.type == 'meeting_request'
                      ? FirebaseFirestore.instance
                      .collection('meetings')
                      .doc(notification.targetId)
                      .collection('requests')
                      .doc(notification.userId)
                      .snapshots()
                      : null,
                  builder: (context, snapshot) {
                    String? status;
                    if (snapshot.hasData && notification.type == 'meeting_request') {
                      final Map<String, dynamic>? data =
                      snapshot.data!.data() as Map<String, dynamic>?;
                      if (data != null && data.containsKey('status')) {
                        status = data['status'] as String;
                      }
                    }

                    return Container(
                      color: notification.isRead
                          ? null
                          : Colors.blue.withOpacity(0.1),
                      child: ListTile(
                        leading: _buildNotificationIcon(notification.type),
                        title: Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight:
                            notification.isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(notification.message),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  _getTimeAgo(notification.timestamp),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                if (status != null && status != 'pending') ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2
                                    ),
                                    decoration: BoxDecoration(
                                      color: status == 'approved'
                                          ? Colors.green.withOpacity(0.1)
                                          : Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      status == 'approved' ? '승인 완료' : '거부 완료',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: status == 'approved'
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        onTap: () => _handleNotificationTap(notification),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  // 시간 차이를 계산하여 "방금 전", "5분 전" 등의 문자열로 반환
  String _getTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);

    if (difference.inMinutes < 1) {
      return '방금 전';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}시간 전';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}일 전';
    } else {
      return '${dateTime.year}.${dateTime.month}.${dateTime.day}';
    }
  }
}