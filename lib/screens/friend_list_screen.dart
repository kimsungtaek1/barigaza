// lib/screens/friend_list_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_room_screen.dart';

class FriendListScreen extends StatefulWidget {
  const FriendListScreen({Key? key}) : super(key: key);

  @override
  _FriendListScreenState createState() => _FriendListScreenState();
}

class _FriendListScreenState extends State<FriendListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '친구 목록',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // 검색 바
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
                decoration: const InputDecoration(
                  hintText: '검색',
                  prefixIcon: Icon(Icons.search),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),
          // 친구 목록
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('nickname')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('오류가 발생했습니다.'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users = snapshot.data!.docs.where((doc) {
                  if (currentUser?.uid == doc.id) return false;

                  final userData = doc.data() as Map<String, dynamic>;
                  final nickname = userData['nickname']?.toString().toLowerCase() ?? '';
                  return nickname.contains(_searchQuery);
                }).toList();

                if (users.isEmpty) {
                  return const Center(child: Text('검색 결과가 없습니다.'));
                }

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final userData = users[index].data() as Map<String, dynamic>;
                    final userId = users[index].id;

                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey[200]!,
                            width: 1,
                          ),
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: Colors.grey[300],
                          child: Icon(Icons.person, color: Colors.grey[600]),
                        ),
                        title: Text(
                          userData['nickname'] ?? '알 수 없음',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1066FF),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          onPressed: () => _showAddFriendDialog(
                            context,
                            userId,
                            userData['nickname'] ?? '알 수 없음',
                          ),
                          child: const Text(
                            '대화하기',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddFriendDialog(BuildContext context, String friendId, String friendNickname) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: const Text(
          '채팅 시작',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '$friendNickname님과 대화를 시작하시겠습니까?',
          style: const TextStyle(
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            child: const Text(
              '취소',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              '확인',
              style: TextStyle(
                color: Color(0xFF1066FF),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            onPressed: () async {
              final currentUser = FirebaseAuth.instance.currentUser;
              if (currentUser != null) {
                try {
                  // 현재 사용자의 정보 가져오기
                  final currentUserDoc = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUser.uid)
                      .get();

                  final currentUserNickname = currentUserDoc.data()?['nickname'] ?? '사용자';

                  // 기존 채팅방 찾기
                  final existingChatQuery = await FirebaseFirestore.instance
                      .collection('chatRooms')
                      .where('participants', arrayContains: currentUser.uid)
                      .get();

                  // String? 대신 String으로 선언하고 기본값 부여
                  String chatId = '';

                  // 기존 채팅방 찾기
                  for (var doc in existingChatQuery.docs) {
                    final participants = List<String>.from(doc.data()['participants']);
                    if (participants.contains(friendId)) {
                      chatId = doc.id;
                      break;
                    }
                  }

                  // 채팅방이 없으면 새로 생성
                  if (chatId.isEmpty) {
                    final chatRef = await FirebaseFirestore.instance.collection('chatRooms').add({
                      'participants': [currentUser.uid, friendId],
                      'lastMessage': '',
                      'lastMessageTime': FieldValue.serverTimestamp(),
                      'createdAt': FieldValue.serverTimestamp(),
                      'userDetails': {
                        currentUser.uid: {'nickname': currentUserNickname},
                        friendId: {'nickname': friendNickname}
                      }
                    });
                    chatId = chatRef.id;
                  }

                  if (!mounted) return;

                  Navigator.of(context).pop(); // 다이얼로그 닫기

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ChatRoomScreen(
                        chatId: chatId,
                        otherUserNickname: friendNickname,
                      ),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('채팅방 생성에 실패했습니다')),
                  );
                  Navigator.of(context).pop();
                  print('Error creating chat: $e');
                }
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}