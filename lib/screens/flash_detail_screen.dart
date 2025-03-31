import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/meeting_point.dart';
import '../widgets/ad_banner_widget.dart';
import '../services/notification_service.dart';
import '../services/chat_service.dart';
import '../services/friend_service.dart';
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
  final FriendService _friendService = FriendService();
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

  // 친구 추가 요청 메서드
  Future<void> _sendFriendRequest() async {
    try {
      final success = await _friendService.sendFriendRequest(widget.meeting.hostId);
      
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.meeting.hostName}님을 친구로 추가했습니다')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('이미 친구입니다')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('친구 추가에 실패했습니다: $e')),
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

  // 모임 수정 다이얼로그
  void _showEditMeetingDialog() {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController departureAddressController = TextEditingController(text: widget.meeting.departureAddress);
    final TextEditingController departureDetailAddressController = TextEditingController(text: widget.meeting.departureDetailAddress);
    final TextEditingController destinationAddressController = TextEditingController(text: widget.meeting.destinationAddress);
    final TextEditingController destinationDetailAddressController = TextEditingController(text: widget.meeting.destinationDetailAddress);
    final TextEditingController timeController = TextEditingController(
      text: DateFormat('yyyy년 MM월 dd일 HH시 mm분').format(widget.meeting.meetingTime)
    );
    DateTime? selectedTime = widget.meeting.meetingTime;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 20.0, bottom: 16.0, left: 20.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '모임 정보 수정',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 모임 시간
                      TextFormField(
                        controller: timeController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: '모임 시간',
                          hintStyle: TextStyle(color: Colors.grey),
                          prefixIcon: Icon(Icons.access_time, size: 16, color: Theme.of(context).primaryColor),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        onTap: () async {
                          final now = DateTime.now();
                          final DateTime? pickedDate = await showDatePicker(
                            context: context,
                            initialDate: selectedTime ?? now,
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 30)),
                            builder: (context, child) => Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: Colors.blue,
                                  onPrimary: Colors.white,
                                  onSurface: Colors.black,
                                ),
                                textButtonTheme: TextButtonThemeData(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.blue,
                                  ),
                                ),
                              ),
                              child: child!,
                            ),
                          );

                          if (pickedDate != null) {
                            final TimeOfDay? pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(selectedTime ?? now),
                              builder: (context, child) => Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.light(
                                    primary: Colors.blue,
                                    onPrimary: Colors.white,
                                    onSurface: Colors.black,
                                  ),
                                  textButtonTheme: TextButtonThemeData(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.blue,
                                    ),
                                  ),
                                ),
                                child: child!,
                              ),
                            );

                            if (pickedTime != null) {
                              selectedTime = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                pickedTime.hour,
                                pickedTime.minute,
                              );
                              timeController.text = DateFormat('yyyy년 MM월 dd일 HH시 mm분')
                                  .format(selectedTime!);
                            }
                          }
                        },
                      ),
                      SizedBox(height: 16),
                      
                      // 출발지
                      TextFormField(
                        controller: departureAddressController,
                        decoration: InputDecoration(
                          labelText: '출발지',
                          hintText: '출발지를 입력해주세요',
                          hintStyle: TextStyle(color: Colors.grey),
                          prefixIcon: Icon(Icons.location_on, size: 16, color: Theme.of(context).primaryColor),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      SizedBox(height: 8),
                    
                      // 출발지 상세주소
                      TextFormField(
                        controller: departureDetailAddressController,
                        decoration: InputDecoration(
                          labelText: '출발지 상세주소',
                          hintText: '출발지 상세주소를 입력해주세요 (선택)',
                          hintStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      SizedBox(height: 16),
                      
                      // 목적지
                      TextFormField(
                        controller: destinationAddressController,
                        decoration: InputDecoration(
                          labelText: '목적지',
                          hintText: '목적지를 입력해주세요',
                          hintStyle: TextStyle(color: Colors.grey),
                          prefixIcon: Icon(Icons.location_on, size: 16, color: Theme.of(context).primaryColor),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      SizedBox(height: 8),
                    
                      // 목적지 상세주소
                      TextFormField(
                        controller: destinationDetailAddressController,
                        decoration: InputDecoration(
                          labelText: '목적지 상세주소',
                          hintText: '목적지 상세주소를 입력해주세요 (선택)',
                          hintStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                          ),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                            ),
                          ),
                          child: Text(
                            '취소',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          if (departureAddressController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('출발지를 입력해주세요.')),
                            );
                            return;
                          }
                          if (destinationAddressController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('목적지를 입력해주세요.')),
                            );
                            return;
                          }
                          if (selectedTime == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('시간을 선택해주세요.')),
                            );
                            return;
                          }
                          if (selectedTime!.isBefore(DateTime.now())) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('현재 시간 이후로 선택해주세요.')),
                            );
                            return;
                          }
                          
                          try {
                            await FirebaseFirestore.instance
                                .collection('meetings')
                                .doc(widget.meeting.id)
                                .update({
                              'departureAddress': departureAddressController.text,
                              'departureDetailAddress': departureDetailAddressController.text,
                              'destinationAddress': destinationAddressController.text,
                              'destinationDetailAddress': destinationDetailAddressController.text,
                              'meetingTime': Timestamp.fromDate(selectedTime!),
                            });
                            
                            // 채팅방에 공지 메시지 전송
                            final chatRoomId = 'meeting_${widget.meeting.id}';
                            await _chatService.sendMessage(
                              chatRoomId, 
                              '[공지] 모임 정보가 수정되었습니다.\n'
                              '시간: ${DateFormat('MM/dd HH:mm').format(selectedTime!)}\n'
                              '출발지: ${departureAddressController.text} ${departureDetailAddressController.text}\n'
                              '목적지: ${destinationAddressController.text} ${destinationDetailAddressController.text}'
                            );

                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('모임 정보가 수정되었습니다.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            
                            // 화면 새로고침을 위해 Navigator.pop 후 다시 열기
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => FlashDetailScreen(
                                  meeting: MeetingPoint(
                                    id: widget.meeting.id,
                                    hostName: widget.meeting.hostName,
                                    hostId: widget.meeting.hostId,
                                    departureAddress: departureAddressController.text,
                                    departureDetailAddress: departureDetailAddressController.text,
                                    destinationAddress: destinationAddressController.text,
                                    destinationDetailAddress: destinationDetailAddressController.text,
                                    meetingTime: selectedTime!,
                                    location: widget.meeting.location,
                                    participants: widget.meeting.participants,
                                    createdAt: widget.meeting.createdAt,
                                  ),
                                ),
                              ),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('모임 수정 중 오류가 발생했습니다: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            borderRadius: BorderRadius.only(
                              bottomRight: Radius.circular(16),
                            ),
                          ),
                          child: Text(
                            '저장',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // 모임 삭제 확인 다이얼로그
  void _showDeleteConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('모임 삭제'),
        content: Text('정말 이 모임을 삭제하시겠습니까?\n삭제된 모임은 복구할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              try {
                // 채팅방에 모임 삭제 메시지 전송
                final chatRoomId = 'meeting_${widget.meeting.id}';
                await _chatService.sendMessage(
                  chatRoomId, 
                  '[공지] 모임이 주최자에 의해 삭제되었습니다.'
                );
                
                // 모임 삭제
                await FirebaseFirestore.instance
                    .collection('meetings')
                    .doc(widget.meeting.id)
                    .update({
                  'status': 'deleted',
                  'deletedAt': FieldValue.serverTimestamp(),
                });
                
                Navigator.pop(context); // 다이얼로그 닫기
                Navigator.pop(context); // 모임 상세 화면 닫기
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('모임이 삭제되었습니다.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('모임 삭제 중 오류가 발생했습니다: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('삭제'),
          ),
        ],
      ),
    );
  }
  
  // 공지사항 작성 다이얼로그
  void _showNoticeDialog() {
    final TextEditingController noticeController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('공지사항 작성'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('모든 참가자에게 공지사항을 전송합니다.'),
            SizedBox(height: 16),
            TextField(
              controller: noticeController,
              decoration: InputDecoration(
                hintText: '공지사항 내용을 입력하세요',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              final notice = noticeController.text.trim();
              if (notice.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('공지사항 내용을 입력해주세요')),
                );
                return;
              }
              
              try {
                // 채팅방에 공지 메시지 전송
                final chatRoomId = 'meeting_${widget.meeting.id}';
                await _chatService.sendMessage(
                  chatRoomId, 
                  '[공지] ${notice}'
                );
                
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('공지사항이 전송되었습니다.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('공지사항 전송 중 오류가 발생했습니다: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('전송'),
          ),
        ],
      ),
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
        actions: [
          if (_isHost)
            PopupMenuButton(
              icon: Icon(Icons.more_vert),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text('모임 수정'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('모임 삭제'),
                ),
                PopupMenuItem(
                  value: 'notice',
                  child: Text('공지사항 작성'),
                ),
              ],
              onSelected: (value) async {
                if (value == 'edit') {
                  _showEditMeetingDialog();
                } else if (value == 'delete') {
                  _showDeleteConfirmDialog();
                } else if (value == 'notice') {
                  _showNoticeDialog();
                }
              },
            ),
        ],
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
                                otherUserNickname: '${widget.meeting.hostName}님의 바리',
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
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(120, 45),
                            backgroundColor: Colors.grey,
                          ),
                          child: const Text('돌아가기'),
                        ),
                        if (!_isHost && !_isParticipant)
                          ElevatedButton(
                            onPressed: _isJoining ? null : _requestJoinMeeting,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(120, 45),
                              backgroundColor: Color(0xFF7EA6FD),
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
