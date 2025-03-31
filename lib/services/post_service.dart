import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';
import 'dart:async';
import 'content_filter_service.dart';
import 'notification_service.dart';

class PostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ContentFilterService _contentFilter = ContentFilterService();
  final NotificationService _notificationService = NotificationService();
  
  // 차단한 사용자 목록을 가져오는 메서드
  Future<List<String>> getBlockedUsers() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return [];
      
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      if (!userDoc.exists) return [];
      
      final blockedList = userDoc.data()?['blockedUsers'] as List<dynamic>? ?? [];
      return blockedList.map((item) => item.toString()).toList();
    } catch (e) {
      print('차단 사용자 목록 가져오기 실패: $e');
      return [];
    }
  }
  
  // 사용자 차단 메서드
  Future<bool> blockUser(String userId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;
      
      // 자기 자신은 차단할 수 없음
      if (currentUser.uid == userId) return false;
      
      await _firestore.collection('users').doc(currentUser.uid).update({
        'blockedUsers': FieldValue.arrayUnion([userId])
      });
      
      return true;
    } catch (e) {
      print('사용자 차단 실패: $e');
      return false;
    }
  }
  
  // 사용자 차단 해제 메서드
  Future<bool> unblockUser(String userId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;
      
      await _firestore.collection('users').doc(currentUser.uid).update({
        'blockedUsers': FieldValue.arrayRemove([userId])
      });
      
      return true;
    } catch (e) {
      print('사용자 차단 해제 실패: $e');
      return false;
    }
  }

  // 게시글 신고 메서드
  Future<bool> reportPost(String postId, String reason) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;
      
      // 이미 신고했는지 확인
      final alreadyReported = await _firestore
          .collection('posts')
          .doc(postId)
          .collection('reports')
          .doc(currentUser.uid)
          .get();
          
      if (alreadyReported.exists) {
        return false; // 이미 신고한 경우
      }
      
      // 사용자 정보 가져오기
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final userData = userDoc.data();
      final nickname = userData?['nickname'] ?? '사용자';
      
      // 신고 정보 저장
      await _firestore
          .collection('posts')
          .doc(postId)
          .collection('reports')
          .doc(currentUser.uid)
          .set({
        'userId': currentUser.uid,
        'nickname': nickname,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // 게시글 신고 카운트 증가 및 신고 상태 업데이트
      await _firestore.collection('posts').doc(postId).update({
        'reportCount': FieldValue.increment(1),
        'isReported': true,
        'reportStatus': 'pending',
        'reportDetails': '$nickname님이 신고: $reason',
      });
      
      // 신고 관리 컬렉션에도 저장 (관리자가 확인하기 위함)
      final reportDocRef = await _firestore.collection('reportedContent').add({
        'postId': postId,
        'reporterId': currentUser.uid,
        'reporterNickname': nickname,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'contentType': 'post',
        'isAutoDetected': false,
      });
      
      // 관리자에게 알림 전송
      await _notificationService.notifyAdminsAboutReportedContent(
        contentId: postId,
        contentType: 'post',
        reason: reason,
        reporterId: currentUser.uid
      );
      
      return true;
    } catch (e) {
      print('게시글 신고 실패: $e');
      return false;
    }
  }
  
  // 댓글 신고 메서드
  Future<bool> reportComment(String postId, String commentId, String reason) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;
      
      // 이미 신고했는지 확인
      final alreadyReported = await _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(commentId)
          .collection('reports')
          .doc(currentUser.uid)
          .get();
          
      if (alreadyReported.exists) {
        return false; // 이미 신고한 경우
      }
      
      // 사용자 정보 가져오기
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final userData = userDoc.data();
      final nickname = userData?['nickname'] ?? '사용자';
      
      // 신고 정보 저장
      await _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(commentId)
          .collection('reports')
          .doc(currentUser.uid)
          .set({
        'userId': currentUser.uid,
        'nickname': nickname,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // 댓글 신고 카운트 증가 및 신고 상태 업데이트
      await _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(commentId)
          .update({
        'reportCount': FieldValue.increment(1),
        'isReported': true,
        'reportStatus': 'pending',
        'reportDetails': '$nickname님이 신고: $reason',
      });
      
      // 신고 관리 컬렉션에도 저장 (관리자가 확인하기 위함)
      await _firestore.collection('reportedContent').add({
        'postId': postId,
        'commentId': commentId,
        'reporterId': currentUser.uid,
        'reporterNickname': nickname,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'contentType': 'comment',
        'isAutoDetected': false,
      });
      
      // 관리자에게 알림 전송
      await _notificationService.notifyAdminsAboutReportedContent(
        contentId: commentId,
        contentType: 'comment',
        reason: reason,
        reporterId: currentUser.uid
      );
      
      return true;
    } catch (e) {
      print('댓글 신고 실패: $e');
      return false;
    }
  }

  Stream<List<Post>> getPostsStream({
    required String category,
    required String sortBy,
    String searchQuery = '',
    bool includeReported = false, // 신고된 컨텐츠 포함 여부
  }) {
    try {
      Query query = _firestore.collection('posts');

      // 신고된 게시물 필터링 (관리자 모드가 아닐 경우)
      if (!includeReported) {
        // reportStatus가 'blocked'인 게시물은 제외
        query = query.where('reportStatus', isNotEqualTo: 'blocked');
      }

      if (category == '팔로잉') {
        // '팔로잉'인 경우: 정렬은 아래 쿼리에서 적용 (친구 목록 필터링)
        // 여기서는 기본 쿼리만 사용
      } else if (category == '질문·답변') {
        // 질문답변 카테고리: 로그인한 사용자의 게시물만 표시
        final currentUser = _auth.currentUser;
        if (currentUser != null) {
          query = query.where('category', isEqualTo: category)
                       .where('userId', isEqualTo: currentUser.uid);
        } else {
          // 로그인하지 않은 경우 빈 결과 반환
          query = query.where('category', isEqualTo: 'non_existent_category');
        }
      } else if (category != '탐색') {
        // '탐색'이 아닌 모든 카테고리: 카테고리 필터링 적용
        print('카테고리 필터링: $category');
        query = query.where('category', isEqualTo: category);
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
            case '추천순':
              query = query.orderBy('likeCount', descending: true)
                           .orderBy('createdAt', descending: true);
              break;
            case '최신순':
            default:
              query = query.orderBy('createdAt', descending: true);
              break;
          }
        }
      }

      return query.snapshots().asyncMap((snapshot) async {
        final currentUser = _auth.currentUser;
        
        // 차단된 사용자 목록 가져오기 (로그인한 경우만)
        List<String> blockedUsers = [];
        // 팔로잉 목록(친구 목록) 가져오기
        List<String> friends = [];
        
        if (currentUser != null) {
          blockedUsers = await getBlockedUsers();
          
          // 친구 목록 가져오기
          if (category == '팔로잉') {
            final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
            final userData = userDoc.data() ?? {};
            friends = List<String>.from(userData['friends'] ?? []);
          }
        }
        
        // 게시글 변환 및 필터링
        final posts = snapshot.docs.map((doc) {
          return Post.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        }).where((post) {
          // 차단된 사용자의 게시글 제외
          if (blockedUsers.contains(post.userId)) {
            return false;
          }
          
          // 팔로잉 탭에서는 친구가 작성한 게시글만 표시
          if (category == '팔로잉') {
            return friends.contains(post.userId);
          }
          
          return true;
        }).toList();
        
        // 정렬 적용
        if (category == '팔로잉') {
          // 최신순으로 정렬
          posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return posts.take(20).toList();
        }
        
        return posts;
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
      
      // 공지사항 카테고리는 관리자만 작성 가능
      if (category == '공지사항') {
        // 사용자 역할 확인
        final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
        final userData = userDoc.data();
        final userRole = userData?['role'] ?? '';
        
        if (userRole != 'admin' && userRole != 'master') {
          return null; // 관리자가 아닌 경우 게시글 작성 거부
        }
      }

      // 콘텐츠 필터링 체크
      bool containsBannedWords = _contentFilter.containsBannedWords(title) || 
                                _contentFilter.containsBannedWords(content);
      
      List<String> bannedWordsFound = [];
      if (containsBannedWords) {
        bannedWordsFound = [
          ..._contentFilter.findBannedWords(title),
          ..._contentFilter.findBannedWords(content)
        ];
        // 중복 제거
        bannedWordsFound = bannedWordsFound.toSet().toList();
      }
      
      // 이미지 URL이 있는 경우 이미지 분석
      bool inappropriateImage = false;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        inappropriateImage = await _contentFilter.analyzeImage(imageUrl);
      }

      // 사용자 정보 가져오기
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final userData = userDoc.data();
      final nickname = userData?['nickname'] ?? '';

      final now = FieldValue.serverTimestamp();

      // 금칙어나 부적절한 이미지가 포함된 경우 자동 신고 플래그 설정
      bool isAutoReported = containsBannedWords || inappropriateImage;
      
      final postData = {
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
        'isReported': isAutoReported,
        'reportCount': isAutoReported ? 1 : 0,
        'reportStatus': isAutoReported ? 'pending' : '',
      };
      
      // 금칙어가 발견된 경우 신고 상세 정보 추가
      if (containsBannedWords) {
        postData['reportDetails'] = '금칙어 발견: ${bannedWordsFound.join(", ")}';
      } else if (inappropriateImage) {
        postData['reportDetails'] = '부적절한 이미지 발견';
      }

      final docRef = await _firestore.collection('posts').add(postData);
      
      // 금칙어나 부적절한 이미지가 발견된 경우 자동 신고 처리
      if (isAutoReported) {
        final reportReason = containsBannedWords 
            ? '시스템 자동 감지: 금칙어 발견 (${bannedWordsFound.join(", ")})'
            : '시스템 자동 감지: 부적절한 이미지';
            
        // 신고 정보 저장
        await _firestore.collection('reportedContent').add({
          'postId': docRef.id,
          'reporterId': 'system',
          'reason': reportReason,
          'createdAt': now,
          'status': 'pending',
          'contentType': 'post',
          'isAutoDetected': true
        });
        
        // 관리자에게 알림 전송
        await _notificationService.notifyAdminsAboutReportedContent(
          contentId: docRef.id,
          contentType: 'post',
          reason: reportReason,
          isAutoDetected: true
        );
      }

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
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;
      
      // 공지사항 카테고리는 관리자만 작성 가능
      if (category == '공지사항') {
        // 사용자 역할 확인
        final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
        final userData = userDoc.data();
        final userRole = userData?['role'] ?? '';
        
        if (userRole != 'admin' && userRole != 'master') {
          return false; // 관리자가 아닌 경우 게시글 수정 거부
        }
      }
      // 콘텐츠 필터링 체크
      bool containsBannedWords = _contentFilter.containsBannedWords(title) || 
                                _contentFilter.containsBannedWords(content);
      
      List<String> bannedWordsFound = [];
      if (containsBannedWords) {
        bannedWordsFound = [
          ..._contentFilter.findBannedWords(title),
          ..._contentFilter.findBannedWords(content)
        ];
        // 중복 제거
        bannedWordsFound = bannedWordsFound.toSet().toList();
      }
      
      // 이미지 URL이 있는 경우 이미지 분석
      bool inappropriateImage = false;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        inappropriateImage = await _contentFilter.analyzeImage(imageUrl);
      }
      
      // 금칙어나 부적절한 이미지가 포함된 경우 자동 신고 플래그 설정
      bool isAutoReported = containsBannedWords || inappropriateImage;
      
      final updateData = {
        'title': title,
        'content': content,
        'category': category,
        'imageUrl': imageUrl ?? '',
        'link': link ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      // 부적절한 콘텐츠가 발견된 경우 자동 신고 처리
      if (isAutoReported) {
        updateData['isReported'] = true;
        updateData['reportCount'] = FieldValue.increment(1);
        updateData['reportStatus'] = 'pending';
        
        if (containsBannedWords) {
          updateData['reportDetails'] = '금칙어 발견: ${bannedWordsFound.join(", ")}';
        } else if (inappropriateImage) {
          updateData['reportDetails'] = '부적절한 이미지 발견';
        }
        
        // 신고 관리 컬렉션에도 저장 (관리자가 확인하기 위함)
        final reportReason = containsBannedWords 
            ? '시스템 자동 감지: 금칙어 발견 (${bannedWordsFound.join(", ")})'
            : '시스템 자동 감지: 부적절한 이미지';
            
        await _firestore.collection('reportedContent').add({
          'postId': postId,
          'reporterId': 'system',
          'reason': reportReason,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'pending',
          'contentType': 'post',
          'isAutoDetected': true
        });
        
        // 관리자에게 알림 전송
        await _notificationService.notifyAdminsAboutReportedContent(
          contentId: postId,
          contentType: 'post',
          reason: reportReason,
          isAutoDetected: true
        );
      }
      
      await _firestore.collection('posts').doc(postId).update(updateData);
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
