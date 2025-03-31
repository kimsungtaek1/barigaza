import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/chat_service.dart';
import '../services/storage_service.dart';
import '../services/content_filter_service.dart';
import '../services/friend_service.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatId;
  final String otherUserNickname;

  const ChatRoomScreen({
    Key? key,
    required this.chatId,
    required this.otherUserNickname,
  }) : super(key: key);

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final currentUser = FirebaseAuth.instance.currentUser;
  final ChatService _chatService = ChatService();
  final ContentFilterService _contentFilterService = ContentFilterService();
  final FriendService _friendService = FriendService();
  bool _isComposing = false;
  bool _isShowingParticipants = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _handleSubmitted() async {
    final messageText = _messageController.text.trim();

    if (messageText.isEmpty || currentUser == null) return;

    try {
      await _chatService.sendMessage(widget.chatId, messageText);
      _messageController.clear();
      setState(() => _isComposing = false);
      _scrollToBottom();
    } catch (e) {
      print('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메시지 전송 실패: $e')),
        );
      }
    }
  }

  // 채팅방 참여 확인 함수 추가
  Future<bool> _isUserParticipant() async {
    final chatDoc = await FirebaseFirestore.instance
        .collection('chatRooms')
        .doc(widget.chatId)
        .get();

    if (!chatDoc.exists) return false;

    final participants = List<String>.from(chatDoc.data()?['users'] ?? []);
    return participants.contains(FirebaseAuth.instance.currentUser?.uid);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // 1. 사용자 인증 확인
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다');
      }

      setState(() => _isLoading = true);

      // 2. 이미지 선택
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );

      if (image == null) return;

      // 3. 파일 크기 확인
      final file = File(image.path);
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        throw Exception('파일 크기는 5MB를 초과할 수 없습니다');
      }

      // 4. 이미지 전송
      await _chatService.sendImageMessage(widget.chatId, file);
      _scrollToBottom();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 전송 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library),
              title: Text('갤러리에서 선택'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(Icons.camera_alt),
              title: Text('사진 촬영'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            setState(() {
              _isShowingParticipants = !_isShowingParticipants;
            });
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.otherUserNickname,
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _chatService.getParticipants(widget.chatId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return SizedBox();
                  return Text(
                    '참여자 ${snapshot.data!.length}명',
                    style: TextStyle(fontSize: 12),
                  );
                },
              ),
            ],
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Container(
            color: Colors.grey[200],
            height: 1.0,
          ),
        ),
        actions: [
          PopupMenuButton(
            icon: Icon(Icons.more_vert),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'participants',
                child: Text('참여자 목록'),
              ),
              PopupMenuItem(
                value: 'leave',
                child: Text('채팅방 나가기'),
              ),
              PopupMenuItem(
                value: 'report',
                child: Text('신고하기'),
              ),
            ],
            onSelected: (value) async {
              if (value == 'participants') {
                setState(() {
                  _isShowingParticipants = !_isShowingParticipants;
                });
              } else if (value == 'leave') {
                final result = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('채팅방 나가기'),
                    content: Text('정말 채팅방을 나가시겠습니까?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('취소'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text('나가기'),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    ],
                  ),
                );

                if (result == true) {
                  await _chatService.leaveChatRoom(widget.chatId);
                  if (mounted) {
                    Navigator.pop(context);
                  }
                }
              } else if (value == 'report') {
                final reasonController = TextEditingController();
                
                final result = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('채팅방 신고'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('신고 사유를 선택하거나 직접 입력해주세요'),
                        SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildReasonChip('욕설/비속어', reasonController),
                            _buildReasonChip('음란물', reasonController),
                            _buildReasonChip('광고/스팸', reasonController),
                            _buildReasonChip('사기/기만', reasonController),
                            _buildReasonChip('불법정보', reasonController),
                            _buildReasonChip('개인정보침해', reasonController),
                          ],
                        ),
                        SizedBox(height: 16),
                        TextField(
                          controller: reasonController,
                          decoration: InputDecoration(
                            hintText: '직접 입력',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('취소'),
                      ),
                      TextButton(
                        onPressed: () {
                          final reason = reasonController.text.trim();
                          if (reason.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('신고 사유를 입력해주세요')),
                            );
                            return;
                          }
                          Navigator.pop(context, reason);
                        },
                        child: Text('신고하기'),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    ],
                  ),
                );
                
                if (result != null && result.isNotEmpty) {
                  await _contentFilterService.reportChatRoom(
                    chatRoomId: widget.chatId,
                    reportedBy: currentUser!.uid,
                    reason: result,
                  );
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('신고가 접수되었습니다. 관리자 검토 후 조치됩니다.')),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_isShowingParticipants) _buildParticipantsList(),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _chatService.getMessages(widget.chatId),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
                    }

                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final messages = snapshot.data?.docs ?? [];

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(8.0),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index].data() as Map<String, dynamic>;
                        final isMe = message['senderId'] == currentUser?.uid;

                        return message['type'] == 'image'
                            ? _buildImageMessage(message, isMe)
                            : _buildTextMessage(message, isMe);
                      },
                    );
                  },
                ),
              ),
              _buildInputArea(),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildParticipantsList() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _chatService.getParticipants(widget.chatId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          final participants = snapshot.data!;
          final currentUserId = FirebaseAuth.instance.currentUser?.uid;
          
          // 참여자 목록 정렬: 현재 사용자를 맨 앞으로, 나머지는 닉네임 순
          participants.sort((a, b) {
            final isACurrentUser = a['userId'] == currentUserId;
            final isBCurrentUser = b['userId'] == currentUserId;
            
            if (isACurrentUser && !isBCurrentUser) return -1;
            if (!isACurrentUser && isBCurrentUser) return 1;
            
            return (a['nickname'] as String).compareTo(b['nickname'] as String);
          });

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: participants.length,
            itemBuilder: (context, index) {
              final user = participants[index];
              final userId = user['userId'] as String;
              final isCurrentUser = userId == currentUserId;
              
              return Padding(
                padding: EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: !isCurrentUser ? () => _showUserProfileDialog(userId, user['nickname'], user['profileImage']) : null,
                      child: CircleAvatar(
                        radius: 24,
                        backgroundImage: user['profileImage'] != null
                            ? NetworkImage(user['profileImage'])
                            : null,
                        child: user['profileImage'] == null ? Icon(Icons.person, size: 25) : null,
                      ),
                    ),
                    SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user['nickname'],
                          style: TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isCurrentUser)
                          Text(
                            ' (나)',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
  
  // 사용자 프로필 다이얼로그 표시
  void _showUserProfileDialog(String userId, String nickname, String? profileImage) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: profileImage != null ? NetworkImage(profileImage) : null,
                    child: profileImage == null ? Icon(Icons.person, size: 40) : null,
                  ),
                  SizedBox(height: 16),
                  Text(
                    nickname,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _addFriend(userId, nickname);
              },
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey[300]!)),
                ),
                child: Center(
                  child: Text(
                    '친구추가',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _showBlockUserDialog(userId, nickname);
              },
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey[300]!)),
                ),
                child: Center(
                  child: Text(
                    '차단하기',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // 친구추가 메서드
  Future<void> _addFriend(String userId, String nickname) async {
    try {
      final success = await _friendService.sendFriendRequest(userId);
      
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$nickname님을 친구로 추가했습니다')),
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
          SnackBar(content: Text('친구추가에 실패했습니다: $e')),
        );
      }
    }
  }

  Widget _buildTextMessage(Map<String, dynamic> message, bool isMe) {
    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isMe ? 64 : 16,
        right: isMe ? 16 : 64,
      ),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                message['senderName'] ?? '알 수 없음',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      message['message'] ?? '',
                      style: TextStyle(color: Colors.black),
                    ),
                  ),
                ),
                if (!isMe) ...[
                  IconButton(
                    icon: Icon(Icons.flag, color: Colors.red, size: 16),
                    padding: EdgeInsets.all(4),
                    constraints: BoxConstraints(),
                    tooltip: '신고하기',
                    onPressed: () => _showReportDialog(message, 'text'),
                  ),
                  IconButton(
                    icon: Icon(Icons.block, color: Colors.red, size: 16),
                    padding: EdgeInsets.all(4),
                    constraints: BoxConstraints(),
                    tooltip: '차단하기',
                    onPressed: () => _showBlockUserDialog(
                      message['senderId'] ?? '',
                      message['senderName'] ?? '알 수 없음',
                    ),
                  ),
                ],
              ] else
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1066FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      message['message'] ?? '',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
            child: Text(
              _formatTimestamp(message['timestamp'] as Timestamp?),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // 메시지 옵션 보여주기 (신고 등)
  void _showMessageOptions(Map<String, dynamic> message, String messageType) {
    final senderId = message['senderId'] as String?;
    if (senderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메시지 정보를 찾을 수 없습니다')),
      );
      return;
    }
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.flag, color: Colors.red),
              title: Text('신고하기'),
              onTap: () {
                Navigator.pop(context);
                _showReportDialog(message, messageType);
              },
            ),
            ListTile(
              leading: Icon(Icons.block, color: Colors.red),
              title: Text('사용자 차단'),
              onTap: () {
                Navigator.pop(context);
                _showBlockUserDialog(senderId, message['senderName'] ?? '알 수 없음');
              },
            ),
            ListTile(
              leading: Icon(Icons.content_copy),
              title: Text('복사하기'),
              onTap: () {
                Navigator.pop(context);
                // 복사 기능 구현 (필요시)
              },
            ),
          ],
        ),
      ),
    );
  }
  
  // 사용자 차단 확인 다이얼로그
  void _showBlockUserDialog(String userId, String userName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('사용자 차단'),
        content: Text('$userName 님을 차단하시겠습니까?\n\n차단하면 이 사용자의 메시지를 더 이상 받지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _blockUser(userId, userName);
            },
            child: Text('차단하기'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }
  
  // 사용자 차단 처리
  Future<void> _blockUser(String userId, String userName) async {
    setState(() => _isLoading = true);
    
    try {
      await _chatService.blockUser(userId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$userName 님이 차단되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('차단 처리 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  // 신고 다이얼로그 표시
  void _showReportDialog(Map<String, dynamic> message, String messageType) {
    final reasonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('신고 사유'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('신고 사유를 선택하거나 직접 입력해주세요'),
            SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildReasonChip('욕설/비속어', reasonController),
                _buildReasonChip('음란물', reasonController),
                _buildReasonChip('광고/스팸', reasonController),
                _buildReasonChip('사기/기만', reasonController),
                _buildReasonChip('불법정보', reasonController),
                _buildReasonChip('개인정보침해', reasonController),
              ],
            ),
            SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: '직접 입력',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
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
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('신고 사유를 입력해주세요')),
                );
                return;
              }
              
              Navigator.pop(context);
              await _reportMessage(message, messageType, reason);
            },
            child: Text('신고하기'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }
  
  // 신고 사유 칩 위젯
  Widget _buildReasonChip(String label, TextEditingController controller) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        controller.text = label;
      },
    );
  }
  
  // 메시지 신고 처리
  Future<void> _reportMessage(Map<String, dynamic> message, String messageType, String reason) async {
    try {
      setState(() => _isLoading = true);
      
      final messageId = message['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
      final senderId = message['senderId'] ?? '';
      final senderName = message['senderName'] ?? '알 수 없음';
      
      if (messageType == 'text') {
        await _contentFilterService.reportChatMessage(
          chatRoomId: widget.chatId,
          messageId: messageId,
          senderId: senderId,
          senderName: senderName,
          reason: reason,
          messageType: 'text',
          messageContent: message['message'] ?? '',
          imageUrl: null,
        );
      } else if (messageType == 'image') {
        await _contentFilterService.reportChatMessage(
          chatRoomId: widget.chatId,
          messageId: messageId,
          senderId: senderId,
          senderName: senderName,
          reason: reason,
          messageType: 'image',
          messageContent: null,
          imageUrl: message['imageUrl'] ?? '',
        );
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('신고가 접수되었습니다. 관리자 검토 후 조치됩니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('신고 처리 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildImageMessage(Map<String, dynamic> message, bool isMe) {
    final timestamp = message['timestamp'] as Timestamp?;
    final timeString = timestamp != null ? _formatTimestamp(timestamp) : '방금 전';
    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isMe ? 64 : 16,
        right: isMe ? 16 : 64,
      ),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                message['senderName'] ?? '알 수 없음',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () => _showImageDialog(message['imageUrl']),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.6,
                    maxHeight: 200,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: message['imageUrl'],
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 50,
                        height: 50,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => Icon(Icons.error),
                    ),
                  ),
                ),
              ),
              if (!isMe) ...[
                IconButton(
                  icon: Icon(Icons.flag, color: Colors.red, size: 16),
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(),
                  tooltip: '신고하기',
                  onPressed: () => _showReportDialog(message, 'image'),
                ),
                IconButton(
                  icon: Icon(Icons.block, color: Colors.red, size: 16),
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(),
                  tooltip: '차단하기',
                  onPressed: () => _showBlockUserDialog(
                    message['senderId'] ?? '',
                    message['senderName'] ?? '알 수 없음',
                  ),
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
            child: Text(
              timeString,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveImage(String imageUrl) async {
    setState(() => _isLoading = true);
    try {
      // 저장소 권한 요청
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('저장소 접근 권한이 필요합니다');
      }

      // 이미지 다운로드
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        throw Exception('이미지 다운로드 실패');
      }

      // 저장 경로 설정
      final appDir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${appDir.path}/downloads');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      // 파일 이름 생성
      final fileName = 'chat_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '${downloadsDir.path}/$fileName';

      // 파일 저장
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      // Media Store에 파일 등록 (안드로이드)
      if (Platform.isAndroid) {
        final downloadsPath = '/storage/emulated/0/Download';
        final downloadFile = File('$downloadsPath/$fileName');
        await downloadFile.writeAsBytes(response.bodyBytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지가 저장되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => Center(
                      child: CircularProgressIndicator(),
                    ),
                    errorWidget: (context, url, error) => Icon(Icons.error),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: Icon(Icons.download),
                  label: Text('저장'),
                  onPressed: () {
                    Navigator.pop(context);
                    _saveImage(imageUrl);
                  },
                ),
                ElevatedButton.icon(
                  icon: Icon(Icons.share),
                  label: Text('공유'),
                  onPressed: () {
                    // 공유 기능 구현
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(
            top: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Image.asset('assets/images/gallery.png',width:16,height: 16),
              onPressed: _showImageOptions,
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: '메시지를 입력하세요',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[200],
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                maxLines: null,
                onChanged: (text) {
                  setState(() => _isComposing = text.trim().isNotEmpty);
                },
                textInputAction: TextInputAction.send,
                onSubmitted: (text) {
                  if (_isComposing) {
                    _handleSubmitted();
                  }
                },
              ),
            ),
            IconButton(
              icon: Image.asset('assets/images/send.png',width:16,height: 16),
              onPressed: _isComposing ? _handleSubmitted : null,
              color: _isComposing ? Color(0xFF7EA6FD) : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '방금 전';

    final DateTime dateTime = timestamp.toDate();
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
