import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';

class PostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<List<Post>> getPostsStream({
    required String category,
    required String sortBy,
    String searchQuery = '',
  }) {
    try {
      Query query = _firestore.collection('posts');

      if (category != '전체' && category != '탐색') {
        if (category == '팔로잉') {
          // '팔로잉'인 경우: createdAt 기준 정렬 및 제한
          query = query.orderBy('createdAt', descending: true).limit(50);
        } else {
          query = query.where('category', isEqualTo: category);
        }
      }

      // 검색어가 있을 때 (단, '팔로잉'에서는 검색어 기능 사용 X)
      if (searchQuery.isNotEmpty && category != '팔로잉') {
        String searchEnd = searchQuery + '\uf8ff';
        query = query.orderBy('title')
            .where('title', isGreaterThanOrEqualTo: searchQuery)
            .where('title', isLessThan: searchEnd);
      } else if (searchQuery.isEmpty) {
        // 검색어가 없을 때: 정렬 옵션 적용 (이미 '팔로잉'일 경우엔 중복 orderBy 호출을 피함)
        if (category != '팔로잉') {
          switch (sortBy) {
            case '신규':
            default:
              query = query.orderBy('createdAt', descending: true);
              break;
          }
        }
      }

      return query.snapshots().map((snapshot) {
        if (category == '팔로잉') {
          final posts = snapshot.docs.map((doc) {
            return Post.fromMap(doc.data() as Map<String, dynamic>, doc.id);
          }).toList();
          return posts.take(20).toList();
        }
        return snapshot.docs.map((doc) {
          return Post.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        }).toList();
      });
    } catch (e) {
      print('스트림 생성 에러: $e');
      return Stream.error(e);
    }
  }

  // 단일 게시글 가져오기
  Future<Post?> getPost(String postId) async {
    try {
      final doc = await _firestore.collection('posts').doc(postId).get();
      if (doc.exists) {
        return Post.fromMap(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      print('게시글 가져오기 실패: $e');
      return null;
    }
  }

  // 게시글 작성
  Future<String?> createPost({
    required String title,
    required String content,
    required String category,
    String? imageUrl,
    String? link,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;

      // 사용자 정보 가져오기
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final userData = userDoc.data();
      final nickname = userData?['nickname'] ?? '';

      final now = FieldValue.serverTimestamp();

      final docRef = await _firestore.collection('posts').add({
        'userId': currentUser.uid,
        'nickname': nickname,
        'title': title,
        'content': content,
        'category': category,
        'imageUrl': imageUrl ?? '',
        'link': link ?? '',
        'createdAt': now,
        'updatedAt': now,
        'viewCount': 0,
        'likeCount': 0,
      });

      return docRef.id;
    } catch (e) {
      print('게시글 작성 실패: $e');
      return null;
    }
  }

  // 게시글 수정
  Future<bool> updatePost({
    required String postId,
    required String title,
    required String content,
    required String category,
    String? imageUrl,
    String? link,
  }) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'title': title,
        'content': content,
        'category': category,
        'imageUrl': imageUrl ?? '',
        'link': link ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('게시글 수정 실패: $e');
      return false;
    }
  }

  // 게시글 삭제
  Future<bool> deletePost(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).delete();
      return true;
    } catch (e) {
      print('게시글 삭제 실패: $e');
      return false;
    }
  }

  // 조회수 증가
  Future<void> incrementViews(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'viewCount': FieldValue.increment(1),
      });
    } catch (e) {
      print('조회수 증가 실패: $e');
    }
  }

  // 좋아요 토글
  Future<bool> toggleLike(String postId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final postRef = _firestore.collection('posts').doc(postId);
      final postDoc = await postRef.get();

      if (!postDoc.exists) return false;

      await postRef.update({
        'likeCount': FieldValue.increment(1),
      });

      return true;
    } catch (e) {
      print('좋아요 토글 실패: $e');
      return false;
    }
  }

  // 사용자의 게시글 가져오기
  Stream<List<Post>> getUserPosts(String userId) {
    return _firestore
        .collection('posts')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Post.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }
}