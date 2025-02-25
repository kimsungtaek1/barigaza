import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'community_edit_screen.dart';

class CommunityPostsScreen extends StatefulWidget {
  @override
  _CommunityPostsScreenState createState() => _CommunityPostsScreenState();
}

class _CommunityPostsScreenState extends State<CommunityPostsScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;

  Future<void> _deletePost(String postId) async {
    try {
      await FirebaseFirestore.instance.collection('posts').doc(postId).delete();
      Navigator.pop(context); // 삭제 후 이전 화면으로 돌아가기
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게시글이 삭제되었습니다.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게시글 삭제에 실패했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('내가 쓴 글', style: TextStyle(color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .where('userId', isEqualTo: currentUserId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('에러가 발생했습니다.'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('작성한 게시글이 없습니다.'));
          }

          // 카테고리별로 게시글 그룹화
          Map<String, List<DocumentSnapshot>> categoryPosts = {};
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final category = data['category'] as String? ?? '미분류';
            if (!categoryPosts.containsKey(category)) {
              categoryPosts[category] = [];
            }
            categoryPosts[category]!.add(doc);
          }

          return ListView.builder(
            itemCount: categoryPosts.length,
            itemBuilder: (context, index) {
              String category = categoryPosts.keys.elementAt(index);
              List<DocumentSnapshot> posts = categoryPosts[category]!;

              return ExpansionTile(
                title: Text(category),
                children: posts.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return ListTile(
                    title: Text(data['title'] ?? '제목 없음'),
                    subtitle: Text(data['content']?.toString().substring(0,
                        data['content'].toString().length > 30 ? 30 : data['content'].toString().length) ?? ''),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CommunityEditScreen(
                            postId: doc.id,
                            initialTitle: data['title'] ?? '',
                            initialContent: data['content'] ?? '',
                            initialCategory: data['category'] ?? '',
                            imageUrl: data['imageUrl'],
                          ),
                        ),
                      );
                    },
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('게시글 삭제'),
                            content: Text('정말 이 게시글을 삭제하시겠습니까?'),
                            actions: [
                              TextButton(
                                child: Text('취소'),
                                onPressed: () => Navigator.pop(context),
                              ),
                              TextButton(
                                child: Text('삭제'),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _deletePost(doc.id);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }
}