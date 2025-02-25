import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';

import '../services/notification_service.dart';
import 'community_edit_screen.dart'; // 편집 화면 임포트

class CommunityContentScreen extends StatefulWidget {
  final String postId;

  const CommunityContentScreen({
    Key? key,
    required this.postId,
  }) : super(key: key);

  @override
  _CommunityContentScreenState createState() => _CommunityContentScreenState();
}

class _CommunityContentScreenState extends State<CommunityContentScreen> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isLiked = false;
  int _likeCount = 0;
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  /// 댓글 편집 시 해당 댓글의 ID (null이면 새 댓글)
  String? editingCommentId;

  @override
  void initState() {
    super.initState();
    _checkIfLiked();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _checkIfLiked() async {
    if (currentUserId.isEmpty) return;
    final likeDoc = await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('likes')
        .doc(currentUserId)
        .get();
    setState(() {
      _isLiked = likeDoc.exists;
    });
  }

  Future<void> _toggleLike() async {
    if (currentUserId.isEmpty) return;

    final postRef =
    FirebaseFirestore.instance.collection('posts').doc(widget.postId);
    final likeRef = postRef.collection('likes').doc(currentUserId);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final postSnapshot = await transaction.get(postRef);

        if (!postSnapshot.exists) {
          throw Exception("Post does not exist!");
        }

        final likeSnapshot = await transaction.get(likeRef);
        final int currentLikes = postSnapshot.data()?['likeCount'] ?? 0;

        if (likeSnapshot.exists) {
          transaction.delete(likeRef);
          transaction.update(postRef, {
            'likeCount': currentLikes - 1,
          });
          setState(() {
            _isLiked = false;
            _likeCount = currentLikes - 1;
          });
        } else {
          transaction.set(likeRef, {
            'timestamp': FieldValue.serverTimestamp(),
          });
          transaction.update(postRef, {
            'likeCount': currentLikes + 1,
          });
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

  /// 게시글 삭제 메서드
  Future<void> _deletePost() async {
    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .delete();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게시글이 삭제되었습니다.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게시글 삭제에 실패했습니다.')),
      );
    }
  }

  /// 댓글 수정 메서드
  Future<void> _updateComment(String commentId, String newContent) async {
    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc(commentId)
          .update({
        'content': newContent,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('댓글이 수정되었습니다.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('댓글 수정에 실패했습니다.')),
      );
    }
  }

  /// 댓글 삭제 메서드
  Future<void> _deleteComment(String commentId) async {
    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc(commentId)
          .delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('댓글이 삭제되었습니다.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('댓글 삭제에 실패했습니다.')),
      );
    }
  }

  /// 댓글 전송 (추가 또는 수정)
  Future<void> _submitComment() async {
    final trimmed = _commentController.text.trim();
    if (trimmed.isEmpty) return;

    // 수정 모드인 경우
    if (editingCommentId != null) {
      await _updateComment(editingCommentId!, trimmed);
      setState(() {
        editingCommentId = null;
        _commentController.clear();
      });
      return;
    }

    // 새 댓글 추가 (댓글 데이터에는 프로필 이미지 URL을 저장하지 않고, 나중에 사용자 문서를 통해 불러옵니다)
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인이 필요합니다.')),
        );
        return;
      }

      final postDoc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .get();

      final postData = postDoc.data();
      final postOwnerId = postData?['userId'] as String?;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userDoc.data() ?? {};
      final userNickname = userData['nickname'] ?? '알 수 없음';

      final commentData = {
        'content': trimmed,
        'userId': user.uid,
        'nickname': userNickname,
        'createdAt': FieldValue.serverTimestamp(),
        'postId': widget.postId,
      };

      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .add(commentData);

      if (postOwnerId != null && postOwnerId != user.uid) {
        final notificationService = NotificationService();
        await notificationService.createCommentNotification(
          postOwnerId: postOwnerId,
          postId: widget.postId,
          commenterNickname: userNickname,
        );
      }

      setState(() {
        _commentController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글이 등록되었습니다.')),
      );
    } catch (e) {
      print('댓글 등록 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글 등록에 실패했습니다. 다시 시도해주세요.')),
      );
    }
  }

  void _sharePost(Map<String, dynamic> data) {
    final title = data['title'] ?? '';
    final content = data['content'] ?? '';
    final shareText = '$title\n\n$content';
    Share.share(shareText);
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  /// 게시글 헤더: 제목, 작성자(프로필 이미지, 닉네임, 시간)
  /// Firestore의 users 컬렉션에서 작성자 문서를 불러와 프로필 이미지를 표시합니다.
  Widget _buildPostHeader(Map<String, dynamic> postData, String timeAgo) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            postData['title'] ?? '제목 없음',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(postData['userId'])
                    .get(),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final userData =
                    snapshot.data!.data() as Map<String, dynamic>;
                    final profileImage =
                        (userData['profileImage'] as String?) ?? '';
                    return CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: profileImage.isNotEmpty
                          ? CachedNetworkImageProvider(profileImage)
                          : null,
                      child: profileImage.isEmpty
                          ? Icon(
                        Icons.person,
                        size: 20,
                        color: Colors.grey[600],
                      )
                          : null,
                    );
                  } else {
                    return CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.grey[300],
                      child: Icon(
                        Icons.person,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                    );
                  }
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      postData['nickname'] ?? '',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '• $timeAgo',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text('오류 발생', style: TextStyle(color: Colors.black87)),
              backgroundColor: Colors.white,
              elevation: 0,
            ),
            body: const Center(child: Text('에러가 발생했습니다')),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text('로딩 중...', style: TextStyle(color: Colors.black87)),
              backgroundColor: Colors.white,
              elevation: 0,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text('게시글 없음', style: TextStyle(color: Colors.black87)),
              backgroundColor: Colors.white,
              elevation: 0,
            ),
            body: const Center(child: Text('존재하지 않는 게시물입니다')),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        _likeCount = data['likeCount'] ?? 0;

        final DateTime? createdAt =
        (data['createdAt'] as Timestamp?)?.toDate();
        final String timeAgo =
        createdAt != null ? _getTimeAgo(createdAt) : '';

        return Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black87),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              data['category'] ?? '카테고리 없음',
              style: const TextStyle(color: Colors.black87),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            actions: [
              // 게시글 작성자만 ... 버튼 표시
              if (data['userId'] == currentUserId)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, color: Colors.black87),
                  onSelected: (value) async {
                    if (value == 'edit') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CommunityEditScreen(
                            postId: widget.postId,
                            initialTitle: data['title'] ?? '',
                            initialContent: data['content'] ?? '',
                            initialCategory: data['category'] ?? '',
                            imageUrl: data['imageUrl'],
                          ),
                        ),
                      );
                    } else if (value == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('게시글 삭제'),
                          content: const Text('정말 이 게시글을 삭제하시겠습니까?'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, false),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.black),
                              child: const Text('취소'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, true),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.black),
                              child: const Text('삭제'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await _deletePost();
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('수정'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('삭제'),
                    ),
                  ],
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 게시글 헤더: 제목, 작성자(프로필 이미지, 닉네임, 시간)
                      _buildPostHeader(data, timeAgo),
                      // 이미지 영역
                      displayImage(data['imageUrl']),
                      // 본문 내용 및 좋아요/공유 버튼
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['content'] ?? '',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: _toggleLike,
                                  child: Row(
                                    children: [
                                      Icon(
                                        _isLiked
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: Colors.red,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _likeCount.toString(),
                                        style: const TextStyle(
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                IconButton(
                                  icon: const Icon(Icons.share_outlined,
                                      color: Colors.grey),
                                  onPressed: () => _sharePost(data),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      _buildCommentList(),
                    ],
                  ),
                ),
              ),
              _buildCommentInput(),
              _buildNavigationButtons(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommentList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          print('댓글 로드 에러: ${snapshot.error}');
          return const Center(child: Text('댓글을 불러오는데 실패했습니다'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final comments = snapshot.data?.docs ?? [];

        if (comments.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('첫 번째 댓글을 작성해보세요!'),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: comments.length,
          itemBuilder: (context, index) {
            return _buildCommentItem(comments[index]);
          },
        );
      },
    );
  }

  Widget _buildCommentItem(DocumentSnapshot commentDoc) {
    final comment = commentDoc.data() as Map<String, dynamic>;
    final commentId = commentDoc.id;
    final DateTime? createdAt =
    (comment['createdAt'] as Timestamp?)?.toDate();
    final String timeAgo =
    createdAt != null ? _getTimeAgo(createdAt) : '방금 전';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 댓글 작성자의 프로필 이미지: Firestore의 users 컬렉션에서 해당 사용자의 문서를 읽어옵니다.
          FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(comment['userId'])
                .get(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.exists) {
                final userData =
                snapshot.data!.data() as Map<String, dynamic>;
                final profileImage =
                    (userData['profileImage'] as String?) ?? '';
                return CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: profileImage.isNotEmpty
                      ? CachedNetworkImageProvider(profileImage)
                      : null,
                  child: profileImage.isEmpty
                      ? Icon(
                    Icons.person,
                    size: 20,
                    color: Colors.grey[600],
                  )
                      : null,
                );
              } else {
                return CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.grey[300],
                  child: Icon(
                    Icons.person,
                    size: 20,
                    color: Colors.grey[600],
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 댓글 헤더: 작성자, 시간, 내 댓글이면 수정/삭제 메뉴 표시
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comment['nickname'] ?? '알 수 없음',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            timeAgo,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (comment['userId'] == currentUserId)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, size: 16),
                        onSelected: (value) async {
                          if (value == 'edit') {
                            // 수정 모드 전환 시 텍스트만 업데이트합니다.
                            setState(() {
                              editingCommentId = commentId;
                              _commentController.text =
                                  comment['content'] ?? '';
                            });
                          } else if (value == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('댓글 삭제'),
                                content:
                                const Text('정말 이 댓글을 삭제하시겠습니까?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    style: TextButton.styleFrom(
                                        foregroundColor: Colors.black),
                                    child: const Text('취소'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    style: TextButton.styleFrom(
                                        foregroundColor: Colors.black),
                                    child: const Text('삭제'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _deleteComment(commentId);
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('수정'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('삭제'),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(comment['content'] ?? ''),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('comment_input_field'),
              controller: _commentController,
              focusNode: _focusNode,
              keyboardType: TextInputType.multiline,
              maxLines: null,
              decoration: InputDecoration(
                hintText: '댓글을 입력해주세요',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () {
              if (_commentController.text.trim().isNotEmpty) {
                _submitComment();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Column(
      children: [
        FutureBuilder<DocumentSnapshot?>(
          future: _getPreviousPost(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildNavigationItem(
                  title: '로딩 중...', onTap: null);
            }

            final previousPost = snapshot.data;
            return _buildNavigationItem(
              title: previousPost != null
                  ? (previousPost.data() as Map<String, dynamic>)['title'] ?? ''
                  : '이전 글이 없습니다',
              onTap: previousPost != null
                  ? () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      CommunityContentScreen(postId: previousPost.id),
                ),
              )
                  : null,
              isDisabled: previousPost == null,
            );
          },
        ),
        FutureBuilder<DocumentSnapshot?>(
          future: _getNextPost(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildNavigationItem(
                  title: '로딩 중...', onTap: null, isNext: true);
            }

            final nextPost = snapshot.data;
            return _buildNavigationItem(
              title: nextPost != null
                  ? (nextPost.data() as Map<String, dynamic>)['title'] ?? ''
                  : '다음 글이 없습니다',
              isNext: true,
              onTap: nextPost != null
                  ? () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      CommunityContentScreen(postId: nextPost.id),
                ),
              )
                  : null,
              isDisabled: nextPost == null,
            );
          },
        ),
      ],
    );
  }

  Future<DocumentSnapshot?> _getPreviousPost() async {
    try {
      final currentDoc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .get();

      if (!currentDoc.exists) return null;

      final currentPostTime =
      currentDoc.data()?['createdAt'] as Timestamp;

      final querySnapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('createdAt', isLessThan: currentPostTime)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      return querySnapshot.docs.isNotEmpty ? querySnapshot.docs.first : null;
    } catch (e) {
      print('이전 글 가져오기 실패: $e');
      return null;
    }
  }

  Future<DocumentSnapshot?> _getNextPost() async {
    try {
      final currentDoc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .get();

      if (!currentDoc.exists) return null;

      final currentPostTime =
      currentDoc.data()?['createdAt'] as Timestamp;

      final querySnapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('createdAt', isGreaterThan: currentPostTime)
          .orderBy('createdAt')
          .limit(1)
          .get();

      return querySnapshot.docs.isNotEmpty ? querySnapshot.docs.first : null;
    } catch (e) {
      print('다음 글 가져오기 실패: $e');
      return null;
    }
  }

  Widget _buildNavigationItem({
    required String title,
    bool isNext = false,
    bool isDisabled = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: isDisabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDisabled ? Colors.grey[100] : Colors.grey[50],
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: Row(
          children: [
            Transform.rotate(
              angle: isNext ? 3.14159 : 0,
              child: SizedBox(
                width: 12,
                height: 8,
                child: SvgPicture.asset(
                  'assets/images/arrow.svg',
                  colorFilter: ColorFilter.mode(
                    isDisabled ? Colors.grey[400]! : Colors.grey[600]!,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: isDisabled ? Colors.grey[500] : Colors.black87,
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

  Widget displayImage(String? imageUrl) {
    return Container(
      width: double.infinity,
      height: 300,
      child: (imageUrl != null && imageUrl.isNotEmpty)
          ? CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) =>
        const Center(child: CircularProgressIndicator()),
        errorWidget: (context, url, error) => _buildDefaultImage(),
      )
          : _buildDefaultImage(),
    );
  }

  Widget _buildDefaultImage() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child:
        Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
      ),
    );
  }
}
