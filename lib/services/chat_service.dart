import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

// 일반 채팅방 생성 (1:1)
  Future<String> createChatRoom(String otherUserId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) throw Exception('로그인이 필요합니다');

    final users = [currentUser.uid, otherUserId];
    final chatRoomId = users.join('_');

    try {
      final existingChat = await _firestore.collection('chatRooms').doc(chatRoomId).get();

      if (!existingChat.exists) {
        final currentUserDoc = await _firestore.collection('users').doc(currentUser.uid).get();
        final otherUserDoc = await _firestore.collection('users').doc(otherUserId).get();

        if (!currentUserDoc.exists || !otherUserDoc.exists) {
          throw Exception('유효하지 않은 사용자입니다');
        }

        // Firestore에 저장할 데이터 구조 확인
        final chatRoomData = {
          'users': users,  // 반드시 List<String> 형태여야 함
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'isGroupChat': false,
          'userDetails': {
            currentUser.uid: {
              'nickname': currentUserDoc.data()?['nickname'] ?? '알 수 없음',
              'profileImage': currentUserDoc.data()?['profileImage'],
            },
            otherUserId: {
              'nickname': otherUserDoc.data()?['nickname'] ?? '알 수 없음',
              'profileImage': otherUserDoc.data()?['profileImage'],
            },
          },
        };

        await _firestore.collection('chatRooms').doc(chatRoomId).set(chatRoomData);
      }

      return chatRoomId;
    } catch (e) {
      print('채팅방 생성 오류: $e');
      throw Exception('채팅방 생성에 실패했습니다');
    }
  }

  // 그룹 채팅방 생성
  Future<String> createGroupChatRoom(
      List<String> participantIds,
      String groupName, {
        String? meetingId,
      }) async {
    final currentUser = _auth.currentUser!;

    if (!participantIds.contains(currentUser.uid)) {
      participantIds.add(currentUser.uid);
    }

    final chatRoomId = meetingId != null ? 'meeting_$meetingId' : DateTime.now().millisecondsSinceEpoch.toString();

    // 그룹명에 '번개 모임:' 접두어 추가
    final formattedGroupName = meetingId != null ? '번개 모임: $groupName' : groupName;

    Map<String, dynamic> userDetails = {};
    for (String userId in participantIds) {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      userDetails[userId] = {
        'nickname': userDoc.data()?['nickname'] ?? '알 수 없음',
        'profileImage': userDoc.data()?['profileImage'],
      };
    }

    await _firestore.collection('chatRooms').doc(chatRoomId).set({
      'users': participantIds,
      'groupName': formattedGroupName,  // 수정된 그룹명 사용
      'createdAt': Timestamp.now(),
      'lastMessage': '',
      'lastMessageTime': Timestamp.now(),
      'userDetails': userDetails,
      'isGroupChat': true,
      'meetingId': meetingId,
    });

    return chatRoomId;
  }

  // 채팅방 삭제
  Future<void> deleteChatRoom(String chatRoomId) async {
    // 채팅방의 모든 메시지 삭제
    final messages = await _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .get();

    final batch = _firestore.batch();
    for (var message in messages.docs) {
      batch.delete(message.reference);
    }

    // 채팅방 문서 삭제
    batch.delete(_firestore.collection('chatRooms').doc(chatRoomId));

    await batch.commit();
  }

  // 채팅방 나가기
  Future<void> leaveChatRoom(String chatRoomId) async {
    final currentUser = _auth.currentUser!;

    await _firestore.collection('chatRooms').doc(chatRoomId).update({
      'users': FieldValue.arrayRemove([currentUser.uid]),
    });
  }

// chat_service.dart의 sendMessage 메서드 수정
  Future<void> sendMessage(String chatRoomId, String message) async {
    final currentUser = _auth.currentUser!;
    final timestamp = FieldValue.serverTimestamp();

    try {
      // 현재 사용자 정보를 users 컬렉션에서 직접 조회
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final senderNickname = userDoc.data()?['nickname'] ?? '알 수 없음';

      // 메시지 추가
      await _firestore
          .collection('chatRooms')
          .doc(chatRoomId)
          .collection('messages')
          .add({
        'senderId': currentUser.uid,
        'senderName': senderNickname,
        'message': message,
        'type': 'text',
        'timestamp': timestamp,
      });

      // 채팅방 정보 업데이트
      await _firestore.collection('chatRooms').doc(chatRoomId).update({
        'lastMessage': message,
        'lastMessageTime': timestamp,
      });
    } catch (e) {
      print('Error sending message: $e');
      throw e;
    }
  }

  Future<void> sendImageMessage(String chatRoomId, File imageFile) async {
    final currentUser = _auth.currentUser!;
    final timestamp = FieldValue.serverTimestamp();

    try {
      // 디버깅: 현재 사용자 ID 확인
      print('Current User ID: ${currentUser.uid}');

      // 현재 사용자 정보를 users 컬렉션에서 직접 조회
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();

      // 디버깅: userDoc 데이터 확인
      print('User Doc exists: ${userDoc.exists}');
      print('User Doc data: ${userDoc.data()}');

      final senderNickname = userDoc.data()?['nickname'] ?? '알 수 없음';

      // 디버깅: 발신자 닉네임 확인
      print('Sender Nickname: $senderNickname');

      // Storage에 이미지 업로드
      final storageRef = _storage
          .ref()
          .child('chat_images')
          .child(chatRoomId)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putFile(imageFile);
      final imageUrl = await storageRef.getDownloadURL();

      // 디버깅: 이미지 URL 확인
      print('Image URL: $imageUrl');

      // Firestore에 이미지 메시지 저장
      final messageRef = await _firestore
          .collection('chatRooms')
          .doc(chatRoomId)
          .collection('messages')
          .add({
        'senderId': currentUser.uid,
        'senderName': senderNickname,
        'type': 'image',
        'imageUrl': imageUrl,
        'timestamp': timestamp,
      });

      // 디버깅: 메시지 문서 ID 확인
      print('Message created with ID: ${messageRef.id}');

      // 채팅방 정보 업데이트
      await _firestore.collection('chatRooms').doc(chatRoomId).update({
        'lastMessage': '사진',
        'lastMessageTime': timestamp,
      });
    } catch (e) {
      print('Error sending image message: $e');
      print('Error stack trace: ${StackTrace.current}');
      throw e;
    }
  }

  // 메시지 삭제
  Future<void> deleteMessage(String chatRoomId, String messageId) async {
    await _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  // 채팅방 목록 스트림
  Future<DocumentSnapshot> getChatRoom(String chatRoomId) async {
    return await _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .get();
  }

  Stream<QuerySnapshot> getChatRooms() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return Stream.empty();

    try {
      return _firestore.collection('chatRooms')
          .where('users', arrayContains: currentUser.uid)
          .orderBy('lastMessageTime', descending: true)
          .snapshots()
          .handleError((error) {
        print('채팅방 목록 조회 오류: $error');
        // 적절한 에러 처리
      });
    } catch (e) {
      print('getChatRooms 예외 발생: $e');
      return Stream.empty();
    }
  }

  // 메시지 스트림
  Stream<QuerySnapshot> getMessages(String chatRoomId) {
    return _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // 참여자 목록 가져오기
  Stream<List<Map<String, dynamic>>> getParticipants(String chatRoomId) {
    return _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .snapshots()
        .asyncMap((snapshot) async {
      final data = snapshot.data() as Map<String, dynamic>;
      final userIds = List<String>.from(data['users']);

      final userDocs = await Future.wait(
          userIds.map((uid) => _firestore.collection('users').doc(uid).get())
      );

      return userDocs
          .where((doc) => doc.exists)
          .map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'nickname': data['nickname'] ?? '알 수 없음',
          'profileImage': data['profileImage'],
        };
      })
          .toList();
    });
  }

  // 채팅방 정보 가져오기
  Future<Map<String, dynamic>> getChatRoomInfo(String chatRoomId) async {
    final doc = await _firestore.collection('chatRooms').doc(chatRoomId).get();
    return doc.data() ?? {};
  }

  // 참여자 추가
  Future<void> addParticipants(String chatRoomId, List<String> newUserIds) async {
    // 새 참여자들의 정보 가져오기
    final newUserDocs = await Future.wait(
        newUserIds.map((uid) => _firestore.collection('users').doc(uid).get())
    );

    // 새 참여자 정보를 userDetails에 추가
    Map<String, dynamic> newUserDetails = {};
    for (var doc in newUserDocs) {
      if (doc.exists) {
        final data = doc.data()!;
        newUserDetails[doc.id] = {
          'nickname': data['nickname'] ?? '알 수 없음',
          'profileImage': data['profileImage'],
        };
      }
    }

    await _firestore.collection('chatRooms').doc(chatRoomId).update({
      'users': FieldValue.arrayUnion(newUserIds),
      'userDetails': FieldValue.arrayUnion([newUserDetails]),
    });
  }

  // 읽지 않은 메시지 수 가져오기
  Stream<int> getUnreadMessageCount(String chatRoomId) {
    final currentUser = _auth.currentUser!;

    return _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .where('senderId', isNotEqualTo: currentUser.uid)
        .where('readBy', arrayContains: currentUser.uid)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
  
  // 사용자 차단하기
  Future<void> blockUser(String blockedUserId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('로그인이 필요합니다');
    
    try {
      // 사용자의 차단 목록에 추가
      await _firestore.collection('users').doc(currentUser.uid).update({
        'blockedUsers': FieldValue.arrayUnion([blockedUserId])
      });
      
      // 차단 기록 저장
      await _firestore.collection('userBlocks').add({
        'blockedBy': currentUser.uid,
        'blockedUser': blockedUserId,
        'blockedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('사용자 차단 중 오류 발생: $e');
      throw Exception('사용자 차단에 실패했습니다');
    }
  }
  
  // 차단 해제하기
  Future<void> unblockUser(String blockedUserId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('로그인이 필요합니다');
    
    try {
      // 사용자의 차단 목록에서 제거
      await _firestore.collection('users').doc(currentUser.uid).update({
        'blockedUsers': FieldValue.arrayRemove([blockedUserId])
      });
      
      // 차단 기록 업데이트
      final blockDocs = await _firestore
          .collection('userBlocks')
          .where('blockedBy', isEqualTo: currentUser.uid)
          .where('blockedUser', isEqualTo: blockedUserId)
          .get();
          
      for (var doc in blockDocs.docs) {
        await doc.reference.update({
          'unblockedAt': FieldValue.serverTimestamp(),
          'isActive': false,
        });
      }
    } catch (e) {
      print('차단 해제 중 오류 발생: $e');
      throw Exception('차단 해제에 실패했습니다');
    }
  }
  
  // 사용자가 차단한 유저 목록 가져오기
  Future<List<String>> getBlockedUsers() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return [];
    
    try {
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      if (!userDoc.exists) return [];
      
      final data = userDoc.data();
      if (data == null || !data.containsKey('blockedUsers')) return [];
      
      return List<String>.from(data['blockedUsers'] ?? []);
    } catch (e) {
      print('차단 목록 조회 중 오류 발생: $e');
      return [];
    }
  }
  
  // 차단된 사용자인지 확인
  Future<bool> isUserBlocked(String userId) async {
    final blockedUsers = await getBlockedUsers();
    return blockedUsers.contains(userId);
  }
}