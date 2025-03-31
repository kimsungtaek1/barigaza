import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/chat_room_screen.dart';
import '../services/chat_service.dart';

class UserProfileDialog extends StatefulWidget {
  final String userId;
  final String nickname;
  final String? profileImage;

  const UserProfileDialog({
    Key? key,
    required this.userId,
    required this.nickname,
    this.profileImage,
  }) : super(key: key);

  @override
  State<UserProfileDialog> createState() => _UserProfileDialogState();
}

class _UserProfileDialogState extends State<UserProfileDialog> {
  final ChatService _chatService = ChatService();
  bool _isLoading = false;

  Future<void> _handleStartChat() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('로그인이 필요합니다');
      }

      // 1. 기존 채팅방 찾기
      final chatQuery = await FirebaseFirestore.instance
          .collection('chatRooms')
          .where('users', arrayContains: currentUser.uid)
          .get();

      // 2. 두 사용자가 포함된 채팅방 찾기
      String? existingChatId;
      for (var doc in chatQuery.docs) {
        final users = List<String>.from(doc['users']);
        if (users.contains(widget.userId)) {
          existingChatId = doc.id;
          break;
        }
      }

      // 3. 채팅방이 없으면 새로 생성
      String chatId;
      if (existingChatId != null) {
        chatId = existingChatId;
      } else {
        // 현재 사용자 정보 가져오기
        final currentUserDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        final currentUserData = currentUserDoc.data() ?? {};
        final currentUserNickname = currentUserData['nickname'] ?? '알 수 없음';

        // 채팅방 생성
        final chatRef = await FirebaseFirestore.instance.collection('chatRooms').add({
          'users': [currentUser.uid, widget.userId],
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'userDetails': {
            currentUser.uid: {'nickname': currentUserNickname},
            widget.userId: {'nickname': widget.nickname, 'profileImage': widget.profileImage}
          }
        });
        chatId = chatRef.id;
      }

      if (mounted) {
        // 다이얼로그 닫기
        Navigator.of(context).pop();
        
        // 채팅방으로 이동
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatRoomScreen(
              chatId: chatId,
              otherUserNickname: widget.nickname,
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
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 24),
            CircleAvatar(
              radius: 50,
              backgroundColor: Color(0xFF7EA6FD), // 친구 탭의 원 배경색과 동일하게 설정
              backgroundImage: widget.profileImage != null
                  ? NetworkImage(widget.profileImage!)
                  : null,
              child: widget.profileImage == null
                  ? Icon(
                  Icons.person,
                  size: 40,
                  color: Colors.white,
                )
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              widget.nickname,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleStartChat,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F6DF3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  disabledBackgroundColor: Colors.grey,
                ),
                child: _isLoading
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : const Text(
                  '대화하기',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
