import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/meeting_point.dart';
import '../widgets/ad_banner_widget.dart';
import '../services/notification_service.dart';
import '../services/chat_service.dart';
import 'chat_room_screen.dart';

class FlashDetailScreen extends StatefulWidget {
  final MeetingPoint meeting;

  const FlashDetailScreen({
    Key? key,
    required this.meeting,
  }) : super(key: key);

  @override
  _FlashDetailScreenState createState() => _FlashDetailScreenState();
}

class _FlashDetailScreenState extends State<FlashDetailScreen> {
  final NotificationService _notificationService = NotificationService();
  final ChatService _chatService = ChatService();
  bool _isJoining = false;
  bool _isParticipant = false;
  bool _isHost = false;

  @override
  void initState() {
    super.initState();
    _checkUserStatus();
  }

  void _checkUserStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _isParticipant = widget.meeting.participants.contains(user.uid);
        _isHost = widget.meeting.hostId == user.uid;
      });
    }
  }

  Future<void> _createGroupChat() async {
    try {
      final chatId = await _chatService.createGroupChatRoom(
        [widget.meeting.hostId],
        '${widget.meeting.hostName}님의 바리',
        meetingId: widget.meeting.id,
      );

      await FirebaseFirestore.instance
          .collection('meetings')
          .doc(widget.meeting.id)
          .update({
        'chatRoomId': chatId,
      });
    } catch (e) {
      print('Error creating group chat: $e');
    }
  }

  Future<void> _requestJoinMeeting() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인이 필요합니다.')),
        );
      }
      return;
    }

    setState(() => _isJoining = true);

    try {
      // 먼저 기존 요청이 있는지 확인
      final existingRequest = await FirebaseFirestore.instance
          .collection('meetings')
          .doc(widget.meeting.id)
          .collection('requests')
          .doc(user.uid)
          .get();

      if (existingRequest.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('이미 참가 신청이 되어있습니다.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userDoc.data() ?? {};
      final userNickname = userData['nickname'] ?? '알 수 없음';

      await FirebaseFirestore.instance
          .collection('meetings')
          .doc(widget.meeting.id)
          .collection('requests')
          .doc(user.uid)
          .set({
        'userId': user.uid,
        'nickname': userNickname,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      await _notificationService.createMeetingRequestNotification(
        hostId: widget.meeting.hostId,
        meetingId: widget.meeting.id,
        requesterNickname: userNickname,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('참가 요청이 전송되었습니다.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error requesting join: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('참가 요청 중 오류가 발생했습니다. 다시 시도해주세요.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  Future<void> _handleMeetingRequest(String requesterId, bool isAccepted) async {
    try {
      final requestRef = FirebaseFirestore.instance
          .collection('meetings')
          .doc(widget.meeting.id)
          .collection('requests')
          .doc(requesterId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final requestDoc = await transaction.get(requestRef);
        if (!requestDoc.exists) {
          throw Exception('존재하지 않는 요청입니다.');
        }
        final requestData = requestDoc.data() as Map<String, dynamic>;
        if (requestData['status'] != 'pending') {
          throw Exception('이미 처리된 요청입니다.');
        }
        final meetingRef = FirebaseFirestore.instance
            .collection('meetings')
            .doc(widget.meeting.id);
        final meetingDoc = await transaction.get(meetingRef);
        if (!meetingDoc.exists) {
          throw Exception('존재하지 않는 모임입니다.');
        }
        transaction.update(requestRef, {
          'status': isAccepted ? 'approved' : 'rejected',
          'respondedAt': FieldValue.serverTimestamp(),
        });
        if (isAccepted) {
          transaction.update(meetingRef, {
            'participants': FieldValue.arrayUnion([requesterId])
          });
          final meetingData = meetingDoc.data()!;
          String? chatRoomId = meetingData['chatRoomId'];
          if (chatRoomId == null) {
            chatRoomId = 'meeting_${widget.meeting.id}';
            final userDoc = await transaction.get(
                FirebaseFirestore.instance.collection('users').doc(requesterId)
            );
            final userData = userDoc.data();
            final userNickname = userData?['nickname'] ?? '알 수 없음';
            final chatRoomRef = FirebaseFirestore.instance
                .collection('chatRooms')
                .doc(chatRoomId);
            transaction.set(chatRoomRef, {
              'users': [widget.meeting.hostId, requesterId],
              'userDetails': {
                widget.meeting.hostId: {'nickname': widget.meeting.hostName},
                requesterId: {'nickname': userNickname}
              },
              'lastMessage': '${userNickname}님이 참가했습니다.',
              'lastMessageTime': FieldValue.serverTimestamp(),
              'isGroupChat': true,
              'createdAt': FieldValue.serverTimestamp()
            });
            transaction.update(meetingRef, {'chatRoomId': chatRoomId});
          } else {
            final chatRoomRef = FirebaseFirestore.instance
                .collection('chatRooms')
                .doc(chatRoomId);
            final chatRoomDoc = await transaction.get(chatRoomRef);
            if (chatRoomDoc.exists) {
              final userDoc = await transaction.get(
                  FirebaseFirestore.instance.collection('users').doc(requesterId)
              );
              final userData = userDoc.data();
              final userNickname = userData?['nickname'] ?? '알 수 없음';
              transaction.update(chatRoomRef, {
                'users': FieldValue.arrayUnion([requesterId]),
                'userDetails.${requesterId}': {'nickname': userNickname},
                'lastMessage': '${userNickname}님이 참가했습니다.',
                'lastMessageTime': FieldValue.serverTimestamp()
              });
            }
          }
        }
      });

      await _notificationService.createMeetingResponseNotification(
        requesterId: requesterId,
        meetingId: widget.meeting.id,
        isAccepted: isAccepted,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAccepted ? '참가 요청을 승인했습니다.' : '참가 요청을 거절했습니다.',
            ),
            backgroundColor: isAccepted ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error handling meeting request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('요청 처리 중 오류가 발생했습니다: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildInfoRow({required IconData icon, required String label, required String value}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestsList() {
    if (!_isHost) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('meetings')
          .doc(widget.meeting.id)
          .collection('requests')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('요청 목록을 불러올 수 없습니다.'),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data?.docs ?? [];
        if (requests.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('대기 중인 참가 요청이 없습니다.'),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                '참가 요청 목록',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final request = requests[index].data() as Map<String, dynamic>;
                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person),
                  ),
                  title: Text(request['nickname'] ?? '알 수 없음'),
                  subtitle: const Text('참가 요청'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _handleMeetingRequest(request['userId'], true),
                        child: const Text('승인'),
                      ),
                      TextButton(
                        onPressed: () => _handleMeetingRequest(request['userId'], false),
                        child: const Text('거절'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('모임 상세'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          const AdBannerWidget(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow(
                          icon: Icons.person,
                          label: '주최자',
                          value: widget.meeting.hostName,
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          icon: Icons.access_time,
                          label: '시간',
                          value: DateFormat('MM/dd HH:mm').format(widget.meeting.meetingTime),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          icon: Icons.location_on,
                          label: '출발지',
                          value: widget.meeting.departureAddress + ' ' + widget.meeting.departureDetailAddress,
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          icon: Icons.location_on,
                          label: '목적지',
                          value: widget.meeting.destinationAddress + ' ' + widget.meeting.destinationDetailAddress,
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          icon: Icons.group,
                          label: '참가자',
                          value: '${widget.meeting.participants.length}명',
                        ),
                      ],
                    ),
                  ),
                  _buildRequestsList(),
                  if (_isHost || _isParticipant)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ElevatedButton(
                        onPressed: () async {
                          final chatRoomId = 'meeting_${widget.meeting.id}';
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatRoomScreen(
                                chatId: chatRoomId,
                                otherUserNickname: '번개 모임: ${widget.meeting.hostName}님의 바리',
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 45),
                        ),
                        child: const Text('채팅방 입장'),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(120, 45),
                            side: const BorderSide(color: Colors.grey),
                          ),
                          child: const Text('돌아가기'),
                        ),
                        if (!_isHost && !_isParticipant)
                          ElevatedButton(
                            onPressed: _isJoining ? null : _requestJoinMeeting,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(120, 45),
                              backgroundColor: Colors.blue,
                            ),
                            child: _isJoining
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                                : const Text('참가하기'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
