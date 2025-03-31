import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 친구추가 (카카오톡 방식 - 단방향)
  Future<bool> sendFriendRequest(String targetUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('로그인이 필요합니다');
      }

      // 현재 사용자 정보 가져오기
      final currentUserDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final currentUserData = currentUserDoc.data() ?? {};
      final currentUserNickname = currentUserData['nickname'] ?? '알 수 없음';

      // 이미 친구인지 확인
      final friends = List<String>.from(currentUserData['friends'] ?? []);
      if (friends.contains(targetUserId)) {
        return false; // 이미 친구임
      }

      // 단방향으로 친구추가 (요청 없이 바로 추가)
      friends.add(targetUserId);
      await _firestore.collection('users').doc(currentUser.uid).update({
        'friends': friends,
      });

      // 알림 생성
      await _firestore.collection('notifications').add({
        'userId': targetUserId,
        'type': 'friendAdded',
        'senderId': currentUser.uid,
        'senderNickname': currentUserNickname,
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('친구추가 실패: $e');
      return false;
    }
  }

  // 친구 요청 수락
  Future<bool> acceptFriendRequest(String requestId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('로그인이 필요합니다');
      }

      // 요청 정보 가져오기
      final requestDoc = await _firestore.collection('friendRequests').doc(requestId).get();
      if (!requestDoc.exists) {
        return false;
      }

      final requestData = requestDoc.data() ?? {};
      final senderId = requestData['senderId'];
      final receiverId = requestData['receiverId'];

      // 현재 사용자가 수신자인지 확인
      if (receiverId != currentUser.uid) {
        return false;
      }

      // 트랜잭션으로 친구 관계 업데이트
      await _firestore.runTransaction((transaction) async {
        // 요청 상태 업데이트
        transaction.update(
          _firestore.collection('friendRequests').doc(requestId),
          {'status': 'accepted'},
        );

        // 발신자의 친구 목록에 수신자 추가
        final senderDoc = await transaction.get(_firestore.collection('users').doc(senderId));
        final senderData = senderDoc.data() ?? {};
        List<String> senderFriends = List<String>.from(senderData['friends'] ?? []);
        if (!senderFriends.contains(receiverId)) {
          senderFriends.add(receiverId);
          transaction.update(
            _firestore.collection('users').doc(senderId),
            {'friends': senderFriends},
          );
        }

        // 수신자의 친구 목록에 발신자 추가
        final receiverDoc = await transaction.get(_firestore.collection('users').doc(receiverId));
        final receiverData = receiverDoc.data() ?? {};
        List<String> receiverFriends = List<String>.from(receiverData['friends'] ?? []);
        if (!receiverFriends.contains(senderId)) {
          receiverFriends.add(senderId);
          transaction.update(
            _firestore.collection('users').doc(receiverId),
            {'friends': receiverFriends},
          );
        }
      });

      // 알림 생성
      final currentUserDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final currentUserData = currentUserDoc.data() ?? {};
      final currentUserNickname = currentUserData['nickname'] ?? '알 수 없음';

      await _firestore.collection('notifications').add({
        'userId': senderId,
        'type': 'friendAccepted',
        'senderId': currentUser.uid,
        'senderNickname': currentUserNickname,
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('친구 요청 수락 실패: $e');
      return false;
    }
  }

  // 친구 요청 거절
  Future<bool> rejectFriendRequest(String requestId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('로그인이 필요합니다');
      }

      // 요청 정보 가져오기
      final requestDoc = await _firestore.collection('friendRequests').doc(requestId).get();
      if (!requestDoc.exists) {
        return false;
      }

      final requestData = requestDoc.data() ?? {};
      final receiverId = requestData['receiverId'];

      // 현재 사용자가 수신자인지 확인
      if (receiverId != currentUser.uid) {
        return false;
      }

      // 요청 상태 업데이트
      await _firestore.collection('friendRequests').doc(requestId).update({
        'status': 'rejected',
      });

      return true;
    } catch (e) {
      print('친구 요청 거절 실패: $e');
      return false;
    }
  }

  // 친구 목록 가져오기
  Stream<List<DocumentSnapshot>> getFriendsList() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('users')
        .doc(currentUser.uid)
        .snapshots()
        .asyncMap((userDoc) async {
      if (!userDoc.exists) {
        return [];
      }

      final userData = userDoc.data() ?? {};
      final friendIds = List<String>.from(userData['friends'] ?? []);

      if (friendIds.isEmpty) {
        return [];
      }

      // 친구 목록 가져오기
      final friendDocs = await Future.wait(
        friendIds.map((id) => _firestore.collection('users').doc(id).get()),
      );

      return friendDocs.where((doc) => doc.exists).toList();
    });
  }

  // 받은 친구 요청 목록 가져오기
  Stream<QuerySnapshot> getReceivedFriendRequests() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.value(null as QuerySnapshot);
    }

    return _firestore
        .collection('friendRequests')
        .where('receiverId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  // 친구 삭제 (카카오톡 방식 - 단방향)
  Future<bool> removeFriend(String friendId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('로그인이 필요합니다');
      }

      // 현재 사용자의 친구 목록에서만 제거
      final currentUserDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final currentUserData = currentUserDoc.data() ?? {};
      List<String> currentUserFriends = List<String>.from(currentUserData['friends'] ?? []);
      
      currentUserFriends.remove(friendId);
      
      await _firestore.collection('users').doc(currentUser.uid).update({
        'friends': currentUserFriends,
      });

      return true;
    } catch (e) {
      print('친구 삭제 실패: $e');
      return false;
    }
  }

  // 사용자 차단 (카카오톡 방식 - 차단 후 양방향 삭제)
  Future<bool> blockUser(String userId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('로그인이 필요합니다');
      }

      // 현재 사용자 정보 가져오기
      final currentUserDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final currentUserData = currentUserDoc.data() ?? {};
      
      // 차단 목록 업데이트
      List<String> blockedUsers = List<String>.from(currentUserData['blockedUsers'] ?? []);
      if (!blockedUsers.contains(userId)) {
        blockedUsers.add(userId);
        await _firestore.collection('users').doc(currentUser.uid).update({
          'blockedUsers': blockedUsers,
        });
      }

      // 양방향으로 친구 관계 삭제 (카카오톡 방식)
      await _firestore.runTransaction((transaction) async {
        // 먼저 모든 읽기 작업 수행
        final currentUserDoc = await transaction.get(_firestore.collection('users').doc(currentUser.uid));
        final friendDoc = await transaction.get(_firestore.collection('users').doc(userId));
        
        // 데이터 처리
        final currentUserData = currentUserDoc.data() ?? {};
        final friendData = friendDoc.data() ?? {};
        
        List<String> currentUserFriends = List<String>.from(currentUserData['friends'] ?? []);
        List<String> friendFriends = List<String>.from(friendData['friends'] ?? []);
        
        currentUserFriends.remove(userId);
        friendFriends.remove(currentUser.uid);
        
        // 모든 읽기 작업 후 쓰기 작업 수행
        transaction.update(
          _firestore.collection('users').doc(currentUser.uid),
          {'friends': currentUserFriends},
        );
        
        transaction.update(
          _firestore.collection('users').doc(userId),
          {'friends': friendFriends},
        );
      });

      return true;
    } catch (e) {
      print('사용자 차단 실패: $e');
      return false;
    }
  }

  // 사용자 신고
  Future<bool> reportUser(String userId, String reason) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('로그인이 필요합니다');
      }

      // 신고 정보 저장
      await _firestore.collection('reports').add({
        'reporterId': currentUser.uid,
        'reportedUserId': userId,
        'reason': reason,
        'type': 'user',
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('사용자 신고 실패: $e');
      return false;
    }
  }
}
