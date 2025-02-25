import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminCommunityTab extends StatefulWidget {
  final bool isSelectionMode;

  const AdminCommunityTab({
    Key? key,
    required this.isSelectionMode,
  }) : super(key: key);

  @override
  _AdminCommunityTabState createState() => _AdminCommunityTabState();
}

class _AdminCommunityTabState extends State<AdminCommunityTab> {
  Set<String> _selectedPosts = {};
  List<DocumentSnapshot> _posts = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void didUpdateWidget(AdminCommunityTab oldWidget) {
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
            content: Text('게시물 로드 중 오류가 발생했습니다'),
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
          title: const Text('게시물 삭제'),
          content: Text('선택한 ${_selectedPosts.length}개의 게시물을 삭제하시겠습니까?'),
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
          const SnackBar(content: Text('선택한 게시물이 삭제되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('게시물 삭제 중 오류가 발생했습니다'),
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
        builder: (context) => _PostDetailScreen(
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
        ListView.separated(
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
                    // 카테고리 (2)
                    Expanded(
                      flex: 4,
                      child: Text(
                        postData['category'] ?? '자유주제',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
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
}

class _PostDetailScreen extends StatefulWidget {
  final DocumentSnapshot post;
  final VoidCallback onPostUpdated;

  const _PostDetailScreen({
    Key? key,
    required this.post,
    required this.onPostUpdated,
  }) : super(key: key);

  @override
  _PostDetailScreenState createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<_PostDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  String? _selectedCategory;
  bool _isLoading = false;
  List<DocumentSnapshot> _comments = [];
  bool _isLoadingComments = false;

  final List<String> _categories = ['자유주제', '장비튜닝', '라이더뉴스'];

  @override
  void initState() {
    super.initState();
    final data = widget.post.data() as Map<String, dynamic>;
    _titleController = TextEditingController(text: data['title'] ?? '');
    _contentController = TextEditingController(text: data['content'] ?? '');
    _selectedCategory = data['category'] ?? '자유주제';
    _loadComments();

    if (!_categories.contains(_selectedCategory)) {
      _selectedCategory = '자유주제';
    }
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
            '댓글',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
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
                          comment['userName'] ?? '익명',
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
    '게시물 상세',
    style: TextStyle(color: Colors.black),
    ),
    actions: [
    TextButton(
    onPressed: _isLoading ? null : _updatePost,
    child: const Text('수정'),
    ),
    ],
    ),
    body: SingleChildScrollView(
    child: Form(
    key: _formKey,
    child: Padding(padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            decoration: const InputDecoration(
              labelText: '카테고리',
              border: OutlineInputBorder(),
            ),
            items: _categories.map((String category) {
              return DropdownMenuItem<String>(
                value: category,
                child: Text(category),
              );
            }).toList(),
            onChanged: (value) {
              setState(() => _selectedCategory = value);
            },
          ),
          const SizedBox(height: 16),
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
        'category': _selectedCategory,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      widget.onPostUpdated();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('게시물이 수정되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('게시물 수정 중 오류가 발생했습니다'),
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