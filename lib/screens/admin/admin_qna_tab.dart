import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/storage_service.dart';
import 'dart:io';

class AdminQnaTab extends StatefulWidget {
  final bool isSelectionMode;

  const AdminQnaTab({
    Key? key,
    required this.isSelectionMode,
  }) : super(key: key);

  @override
  _AdminQnaTabState createState() => _AdminQnaTabState();
}

class _AdminQnaTabState extends State<AdminQnaTab> {
  Set<String> _selectedPosts = {};
  List<DocumentSnapshot> _posts = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void didUpdateWidget(AdminQnaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isSelectionMode) {
      setState(() {
        _selectedPosts.clear();
      });
    }
  }

  Future<void> _loadPosts() async {
    try {
      setState(() => _isLoading = true);
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('category', isEqualTo: '질문·답변')
          .orderBy('createdAt', descending: true)
          .get();
      setState(() {
        _posts = snapshot.docs;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('질문답변 로드 중 오류가 발생했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePosts() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('질문답변 삭제'),
          content: Text('선택한 ${_selectedPosts.length}개의 질문답변을 삭제하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('삭제'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() => _isLoading = true);

      for (String postId in _selectedPosts) {
        // 댓글 컬렉션 삭제
        final commentsSnapshot = await FirebaseFirestore.instance
            .collection('posts')
            .doc(postId)
            .collection('comments')
            .get();

        for (var doc in commentsSnapshot.docs) {
          await doc.reference.delete();
        }

        // 게시물 삭제
        await FirebaseFirestore.instance
            .collection('posts')
            .doc(postId)
            .delete();
      }

      await _loadPosts();
      setState(() => _selectedPosts.clear());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('선택한 질문답변이 삭제되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('질문답변 삭제 중 오류가 발생했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showPostDetail(DocumentSnapshot post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _QnaDetailScreen(
          post: post,
          onPostUpdated: _loadPosts,
        ),
      ),
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return '방금 전';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}시간 전';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}일 전';
    } else {
      return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Text(
                    '질문답변 관리',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      _navigateToWriteScreen(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: Size(120, 36),
                    ),
                    child: Text('질문답변 작성'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: _posts.length,
                padding: const EdgeInsets.only(bottom: kFloatingActionButtonMargin + 64),
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final post = _posts[index];
                  final postData = post.data() as Map<String, dynamic>;
                  final postId = post.id;
                  final isSelected = _selectedPosts.contains(postId);

                  return SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: ListTile(
                      leading: widget.isSelectionMode
                          ? Checkbox(
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedPosts.add(postId);
                            } else {
                              _selectedPosts.remove(postId);
                            }
                          });
                        },
                      )
                          : null,
                      title: Row(
                        children: [
                          // 제목 (3)
                          Expanded(
                            flex: 9,
                            child: Text(
                              postData['title'] ?? '제목 없음',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 작성일 (2)
                          Expanded(
                            flex: 2,
                            child: Text(
                              _formatDate(postData['createdAt'] as Timestamp?),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ),
                          // 조회수와 댓글수
                          Expanded(
                            flex: 2,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // 조회수
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.remove_red_eye_outlined,
                                      size: 10,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${postData['viewCount'] ?? 0}',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                                // 댓글수
                                FutureBuilder<AggregateQuerySnapshot>(
                                  future: FirebaseFirestore.instance
                                      .collection('posts')
                                      .doc(postId)
                                      .collection('comments')
                                      .count()
                                      .get(),
                                  builder: (context, snapshot) {
                                    int commentCount = 0;
                                    if (snapshot.hasData) {
                                      commentCount = snapshot.data!.count ?? 0;
                                    }
                                    return Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.chat_bubble_outline,
                                          size: 10,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$commentCount',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: widget.isSelectionMode
                          ? () {
                        setState(() {
                          if (isSelected) {
                            _selectedPosts.remove(postId);
                          } else {
                            _selectedPosts.add(postId);
                          }
                        });
                      }
                          : () => _showPostDetail(post),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        if (widget.isSelectionMode && _selectedPosts.isNotEmpty)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _deletePosts,
              backgroundColor: Colors.red,
              child: const Icon(Icons.delete),
            ),
          ),
      ],
    );
  }

  void _navigateToWriteScreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _QnaWriteScreen(
          onPostCreated: _loadPosts,
        ),
      ),
    );
  }
}

class _QnaDetailScreen extends StatefulWidget {
  final DocumentSnapshot post;
  final VoidCallback onPostUpdated;

  const _QnaDetailScreen({
    Key? key,
    required this.post,
    required this.onPostUpdated,
  }) : super(key: key);

  @override
  _QnaDetailScreenState createState() => _QnaDetailScreenState();
}

class _QnaDetailScreenState extends State<_QnaDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _commentController;
  bool _isLoading = false;
  List<DocumentSnapshot> _comments = [];
  bool _isLoadingComments = false;

  @override
  void initState() {
    super.initState();
    final data = widget.post.data() as Map<String, dynamic>;
    _titleController = TextEditingController(text: data['title'] ?? '');
    _contentController = TextEditingController(text: data['content'] ?? '');
    _commentController = TextEditingController();
    _loadComments();
  }

  Future<void> _loadComments() async {
    setState(() => _isLoadingComments = true);
    try {
      final commentsSnapshot = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post.id)
          .collection('comments')
          .orderBy('createdAt', descending: true)
          .get();

      setState(() {
        _comments = commentsSnapshot.docs;
        _isLoadingComments = false;
      });
    } catch (e) {
      print('댓글 로드 중 오류 발생: $e');
      setState(() => _isLoadingComments = false);
    }
  }

  Widget _buildCommentSection() {
    if (_isLoadingComments) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            '답변',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        TextField(
          controller: _commentController,
          decoration: InputDecoration(
            hintText: '답변을 입력하세요',
            border: OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(Icons.send),
              onPressed: _submitComment,
            ),
          ),
          maxLines: 3,
        ),
        SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _comments.length,
          itemBuilder: (context, index) {
            final comment = _comments[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          comment['nickname'] ?? '익명',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          _formatDate(comment['createdAt'] as Timestamp?),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, size: 16),
                          onPressed: () => _deleteComment(_comments[index].id),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(comment['content'] ?? ''),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인이 필요합니다')),
        );
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userDoc.data() ?? {};
      final userNickname = userData['nickname'] ?? '관리자';

      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post.id)
          .collection('comments')
          .add({
        'content': _commentController.text.trim(),
        'userId': user.uid,
        'nickname': userNickname,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _commentController.clear();
      await _loadComments();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('답변이 등록되었습니다')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('답변 등록 중 오류가 발생했습니다: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post.id)
          .collection('comments')
          .doc(commentId)
          .delete();

      await _loadComments();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('답변이 삭제되었습니다')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('답변 삭제 중 오류가 발생했습니다: $e')),
      );
    }
  }

  Widget _buildImageSection(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      height: 200,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[200],
              child: const Center(
                child: Icon(Icons.error_outline),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final postData = widget.post.data() as Map<String, dynamic>;
    final imageUrl = postData['imageUrl'] as String?;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          '질문답변 상세',
          style: TextStyle(color: Colors.black),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _updatePost,
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            child: const Text('수정'),
          ),
          TextButton(
            onPressed: _isLoading ? null : _deletePost,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return '제목을 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildImageSection(imageUrl),
                TextFormField(
                  controller: _contentController,
                  decoration: const InputDecoration(
                    labelText: '내용',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 15,
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return '내용을 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                _buildCommentSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return '방금 전';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}시간 전';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}일 전';
    } else {
      return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _updatePost() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await widget.post.reference.update({
        'title': _titleController.text,
        'content': _contentController.text,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      widget.onPostUpdated();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('질문답변이 수정되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('질문답변 수정 중 오류가 발생했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('질문답변 삭제'),
        content: const Text('이 질문답변을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      // 댓글 삭제
      final commentsSnapshot = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post.id)
          .collection('comments')
          .get();

      for (var doc in commentsSnapshot.docs) {
        await doc.reference.delete();
      }

      // 게시물 삭제
      await widget.post.reference.delete();

      widget.onPostUpdated();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('질문답변이 삭제되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('질문답변 삭제 중 오류가 발생했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _commentController.dispose();
    super.dispose();
  }
}

class _QnaWriteScreen extends StatefulWidget {
  final VoidCallback onPostCreated;

  const _QnaWriteScreen({
    Key? key,
    required this.onPostCreated,
  }) : super(key: key);

  @override
  _QnaWriteScreenState createState() => _QnaWriteScreenState();
}

class _QnaWriteScreenState extends State<_QnaWriteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isLoading = false;
  File? _imageFile;

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return null;

    final maxRetries = 3;
    var attempts = 0;

    while (attempts < maxRetries) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('사용자 인증 정보가 없습니다');

        final bytes = await _imageFile!.readAsBytes();
        final String fileExtension = _imageFile!.path.split('.').last.toLowerCase();
        final String fileName = 'qna_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
        final String storagePath = 'post_images/$fileName';

        final storageService = StorageService();
        final result = await storageService.uploadFile(
          path: storagePath,
          data: bytes,
          contentType: 'image/$fileExtension',
          customMetadata: {
            'uploadedBy': user.uid,
            'timestamp': DateTime.now().toIso8601String(),
            'type': 'qna_image'
          },
          onProgress: (progress) {
            print('Upload progress: ${(progress * 100).toStringAsFixed(2)}%');
          },
          isProfileImage: false,
          optimizeImage: true,
          convertToWebpFormat: true,
        );

        if (result.isSuccess && result.data != null) {
          print('Upload success. URL: ${result.data}');
          return result.data;
        }

        throw Exception('업로드 실패: ${result.error}');
      } catch (e) {
        attempts++;
        print('이미지 업로드 시도 $attempts 실패: $e');

        if (attempts >= maxRetries) {
          print('최대 재시도 횟수 초과');
          return null;
        }

        await Future.delayed(Duration(seconds: 2));
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          '질문답변 작성',
          style: TextStyle(color: Colors.black),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createPost,
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            child: const Text('등록'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return '제목을 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (_imageFile != null) ...[
                  Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _imageFile!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => setState(() => _imageFile = null),
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text('이미지 삭제', style: TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text('이미지 추가'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _contentController,
                  decoration: const InputDecoration(
                    labelText: '내용',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 15,
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return '내용을 입력해주세요';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createPost() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() => _isLoading = true);

  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다')),
      );
      return;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final userData = userDoc.data() ?? {};
    final userNickname = userData['nickname'] ?? '관리자';

    // 이미지 업로드
    String? imageUrl;
    if (_imageFile != null) {
      imageUrl = await _uploadImage();
    }

    await FirebaseFirestore.instance.collection('posts').add({
      'title': _titleController.text,
      'content': _contentController.text,
      'category': '질문·답변',
      'userId': user.uid,
      'nickname': userNickname,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'viewCount': 0,
      'likeCount': 0,
      'imageUrl': imageUrl ?? '',
      'link': '',
      'reportStatus': '',
      'isReported': false,
      'reportCount': 0,
    });

    widget.onPostCreated();

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('질문답변이 등록되었습니다')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('질문답변 등록 중 오류가 발생했습니다: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    setState(() => _isLoading = false);
  }
}

@override
void dispose() {
  _titleController.dispose();
  _contentController.dispose();
  super.dispose();
}
}