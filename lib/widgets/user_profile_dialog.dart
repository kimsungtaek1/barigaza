import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/chat_screen.dart';
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

  Future<void> _handleAddFriend() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('로그인이 필요합니다');
      }

      // 현재 사용자의 친구 목록 가져오기
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      
      // 친구 목록이 없으면 새로 생성
      final userData = userDoc.data() ?? {};
      List<String> friends = List<String>.from(userData['friends'] ?? []);
      
      // 이미 친구 목록에 있는지 확인
      if (friends.contains(widget.userId)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('이미 친구로 추가되어 있습니다')),
          );
        }
        return;
      }
      
      // 친구 목록에 추가
      friends.add(widget.userId);
      
      // 사용자 문서 업데이트
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({'friends': friends});

      if (mounted) {
        // 다이얼로그 닫기
        Navigator.of(context).pop();
        
        // 성공 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.nickname}님이 친구로 추가되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('친구 추가에 실패했습니다: $e')),
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
                onPressed: _isLoading ? null : _handleAddFriend,
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
                  '친구추가',
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