// lib/widgets/post_card.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';

class PostCard extends StatefulWidget {
  final Post post;
  final VoidCallback onTap;

  const PostCard({
    Key? key,
    required this.post,
    required this.onTap,
  }) : super(key: key);

  @override
  _PostCardState createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  // 로그인한 사용자가 좋아요를 눌렀는지 여부와 현재 좋아요 수
  bool _isLiked = false;
  int _likeCount = 0;
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
    _checkIfLiked();
  }

  /// 현재 로그인한 사용자가 이 게시물에 좋아요를 눌렀는지 체크합니다.
  Future<void> _checkIfLiked() async {
    if (currentUserId.isEmpty) return;

    final likeDoc = await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.post.id)
        .collection('likes')
        .doc(currentUserId)
        .get();

    setState(() {
      _isLiked = likeDoc.exists;
    });
  }

  /// 좋아요를 토글합니다.
  Future<void> _toggleLike() async {
    if (currentUserId.isEmpty) return;

    final postRef =
    FirebaseFirestore.instance.collection('posts').doc(widget.post.id);
    final likeRef = postRef.collection('likes').doc(currentUserId);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final postSnapshot = await transaction.get(postRef);

        if (!postSnapshot.exists) {
          throw Exception("Post does not exist!");
        }

        final int currentLikes = postSnapshot.data()?['likeCount'] ?? 0;
        final likeSnapshot = await transaction.get(likeRef);

        if (likeSnapshot.exists) {
          // 이미 좋아요한 상태 → 좋아요 삭제
          transaction.delete(likeRef);
          transaction.update(postRef, {'likeCount': currentLikes - 1});
          setState(() {
            _isLiked = false;
            _likeCount = currentLikes - 1;
          });
        } else {
          // 아직 좋아요하지 않은 상태 → 좋아요 추가
          transaction.set(likeRef, {
            'timestamp': FieldValue.serverTimestamp(),
          });
          transaction.update(postRef, {'likeCount': currentLikes + 1});
          setState(() {
            _isLiked = true;
            _likeCount = currentLikes + 1;
          });
        }
      });
    } catch (e) {
      print('Like toggle failed: $e');
    }
  }

  /// 프로필 이미지를 반환합니다.
  /// 1. Post 모델에 profileImage이 있다면 바로 사용합니다.
  /// 2. 없으면, userId를 이용해 Firestore에서 사용자 데이터를 가져와서 프로필 이미지를 표시합니다.
  Widget _buildProfileImage() {
    // Post 모델에 profileImage이 있다면 바로 사용
    if (widget.post.profileImage != null &&
        widget.post.profileImage!.isNotEmpty) {
      return CircleAvatar(
        radius: 12,
        backgroundColor: Colors.grey[200],
        backgroundImage:
        CachedNetworkImageProvider(widget.post.profileImage!),
      );
    }

    // Post 모델에 프로필 이미지 URL이 없다면, Firestore에서 사용자 데이터를 가져옵니다.
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.post.userId)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // 에러가 발생한 경우 콘솔에 출력하고 에러 아이콘 표시
          print("Error loading user document for userId ${widget.post.userId}: ${snapshot.error}");
          return CircleAvatar(
            radius: 12,
            backgroundColor: Colors.grey[200],
            child: Icon(Icons.error, size: 14, color: Colors.red),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          // 로딩 중일 때 프로그레스 인디케이터 표시
          return CircleAvatar(
            radius: 12,
            backgroundColor: Colors.grey[200],
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
              ),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data!.exists) {
          // 사용자 문서가 존재할 경우 데이터를 확인
          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          if (userData == null) {
            print("User document for userId ${widget.post.userId} contains no data.");
            return CircleAvatar(
              radius: 12,
              backgroundColor: Colors.grey[200],
              child: Icon(Icons.person, size: 14, color: Colors.grey[600]),
            );
          }

          final profileImage = userData['profileImage'] as String?;
          if (profileImage == null || profileImage.isEmpty) {
            print("No profileImage found for userId ${widget.post.userId} in user document.");
            return CircleAvatar(
              radius: 12,
              backgroundColor: Colors.grey[200],
              child: Icon(Icons.person, size: 14, color: Colors.grey[600]),
            );
          }

          // 프로필 이미지 URL이 정상적으로 로드된 경우
          return CircleAvatar(
            radius: 12,
            backgroundColor: Colors.grey[200],
            backgroundImage: CachedNetworkImageProvider(profileImage),
          );
        } else {
          // 사용자 문서가 없을 경우
          print("User document does not exist for userId: ${widget.post.userId}");
          return CircleAvatar(
            radius: 12,
            backgroundColor: Colors.grey[200],
            child: Icon(Icons.person, size: 14, color: Colors.grey[600]),
          );
        }
      },
    );
  }


  Widget _buildImageContent() {
    if (widget.post.imageUrl.isEmpty) {
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Icon(
            Icons.image_not_supported,
            size: 40,
            color: Colors.grey[400],
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.post.imageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Colors.grey[200],
        child: Center(
          child: CircularProgressIndicator(
            valueColor:
            AlwaysStoppedAnimation<Color>(Colors.grey),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[200],
        child: Center(
          child: Icon(
            Icons.broken_image,
            size: 40,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 카드 전체 터치 시 onTap 콜백 실행
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 이미지 영역
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 1,
                child: _buildImageContent(),
              ),
            ),
            // 프로필 이미지, 닉네임, 좋아요 아이콘 영역
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Row(
                children: [
                  _buildProfileImage(),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.post.nickname,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 좋아요 아이콘 터치 시 좋아요 토글
                  GestureDetector(
                    onTap: _toggleLike,
                    child: Row(
                      children: [
                        Icon(
                          _isLiked
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 14,
                          color: Colors.red[400],
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '$_likeCount',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 제목 영역
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Text(
                widget.post.title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
