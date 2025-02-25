import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/user_profile_dialog.dart';
import 'chat_room_screen.dart';
import '../utils/auth_utils.dart';
import '../services/chat_service.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({Key? key}) : super(key: key);

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ChatService _chatService = ChatService();
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkLoginStatus();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showAddFriendCompletionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '친구 추가가 완료되었습니다!',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B785D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('확인'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // UserProfileDialog를 보여주는 부분
  void _showUserProfile(String userId, String nickname, String? profileImage) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) => UserProfileDialog(
        userId: userId,         // userId 전달
        nickname: nickname,
        profileImage: profileImage,
      ),
    ).then((_) {
      // Dialog가 닫힌 후의 추가 작업이 필요하다면 여기서 처리
      setState(() {
        // 필요한 상태 업데이트
      });
    }).catchError((error) {
      // 에러 처리
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생했습니다: $error')),
        );
      }
    });
  }

  Future<void> _checkLoginStatus() async {
    if (!await AuthUtils.checkLoginAndShowAlert(context)) {
      return;
    }
  }

  Future<void> _createOrOpenChat(String otherUserId, String otherUserNickname) async {
    if (!await AuthUtils.checkLoginAndShowAlert(context)) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser!;

      // 1. 기존 채팅방 찾기
      final chatQuery = await FirebaseFirestore.instance
          .collection('chatRooms')
          .where('participants', arrayContains: currentUser.uid)
          .get();

      // 2. 두 사용자가 포함된 채팅방 찾기
      String? existingChatId;
      for (var doc in chatQuery.docs) {
        final participants = List<String>.from(doc['participants']);
        if (participants.contains(otherUserId)) {
          existingChatId = doc.id;
          break;
        }
      }

      // 3. 채팅방이 없으면 새로 생성
      final chatId = existingChatId ?? await _chatService.createChatRoom(otherUserId);

      // 4. 채팅방 화면으로 이동
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatRoomScreen(
              chatId: chatId,
              otherUserNickname: otherUserNickname,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('채팅방 생성에 실패했습니다: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('채팅'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '채팅'),
            Tab(text: '사용자'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '검색',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [
                    _buildChatList(currentUser?.uid ?? ''),
                    _buildUserList(currentUser?.uid ?? ''),
                  ],
                ),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(String currentUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _chatService.getChatRooms(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('ChatListScreen Error: ${snapshot.error}');
          return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final chats = snapshot.data?.docs ?? [];
        if (chats.isEmpty) {
          return const Center(child: Text('채팅 내역이 없습니다'));
        }

        return ListView.builder(
          itemCount: chats.length,
          itemBuilder: (context, index) {
            final chatData = chats[index].data() as Map<String, dynamic>;
            final isGroupChat = chatData['isGroupChat'] ?? false;
            String chatTitle;
            String? chatImage;

            if (isGroupChat) {
              // 그룹 채팅방인 경우
              chatTitle = chatData['groupName'] ?? '단체 채팅방';
              // 미팅 ID가 있는 경우 번개 모임 채팅방
              final meetingId = chatData['meetingId'];
              if (meetingId != null) {
                chatTitle = '번개 모임: $chatTitle';
              }
            } else {
              // 1:1 채팅방인 경우
              final users = (chatData['users'] as List?)?.map((e) => e.toString()).toList() ?? [];
              if (users.isEmpty) return const SizedBox.shrink();

              final otherUserId = users.firstWhere(
                    (id) => id != currentUserId,
                orElse: () => '',
              );
              if (otherUserId.isEmpty) return const SizedBox.shrink();

              final userDetails = chatData['userDetails'] as Map<String, dynamic>?;
              if (userDetails == null) return const SizedBox.shrink();

              final otherUserDetail = userDetails[otherUserId] as Map<String, dynamic>?;
              if (otherUserDetail == null) return const SizedBox.shrink();

              chatTitle = otherUserDetail['nickname'] as String? ?? '알 수 없음';
              chatImage = otherUserDetail['profileImage'] as String?;
            }

            return Dismissible(
              key: Key(chats[index].id),
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (direction) async {
                return await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('채팅방 나가기'),
                    content: const Text('채팅방에서 나가시겠습니까?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('취소'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('나가기', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
              onDismissed: (direction) async {
                await _chatService.leaveChatRoom(chats[index].id);
              },
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isGroupChat ? Colors.blue : null,
                  backgroundImage: chatImage != null ? NetworkImage(chatImage) : null,
                  child: chatImage == null
                      ? Icon(isGroupChat ? Icons.group : Icons.person)
                      : null,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chatTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isGroupChat)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(Icons.group, size: 16, color: Colors.grey[600]),
                      ),
                  ],
                ),
                subtitle: Text(
                  chatData['lastMessage']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      chatData['lastMessageTime'] != null
                          ? _formatTimestamp(chatData['lastMessageTime'] as Timestamp)
                          : '',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    StreamBuilder<int>(
                      stream: _chatService.getUnreadMessageCount(chats[index].id),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data == 0) {
                          return const SizedBox.shrink();
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            snapshot.data.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatRoomScreen(
                        chatId: chats[index].id,
                        otherUserNickname: chatTitle,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUserList(String currentUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = snapshot.data?.docs
            .where((doc) => doc.id != currentUserId)
            .toList() ?? [];

        if (users.isEmpty) {
          return const Center(child: Text('사용자가 없습니다'));
        }

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final userData = users[index].data() as Map<String, dynamic>;
            final nickname = userData['nickname'] as String? ?? '알 수 없음';

            if (_searchQuery.isNotEmpty &&
                !nickname.toLowerCase().contains(_searchQuery)) {
              return const SizedBox.shrink();
            }

            return ListTile(
              leading: CircleAvatar(
                backgroundImage: userData['profileImage'] != null
                    ? NetworkImage(userData['profileImage'])
                    : null,
                child: userData['profileImage'] == null
                    ? Text(nickname[0])
                    : null,
              ),
              title: Text(nickname),
              subtitle: Text(userData['status'] ?? ''),
              onTap: () {
                _showUserProfile(
                  users[index].id,         // userId 전달
                  nickname,
                  userData['profileImage'],
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';

    final DateTime messageTime = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(messageTime);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}시간 전';
    } else {
      return '${difference.inDays}일 전';
    }
  }
}