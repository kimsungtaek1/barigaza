import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ContentFilterService {
  static final ContentFilterService _instance = ContentFilterService._internal();
  factory ContentFilterService() => _instance;
  ContentFilterService._internal();

  List<String> _bannedWords = [];
  
  // 현재 금칙어 목록 반환
  List<String> getBannedWords() {
    return List<String>.from(_bannedWords);
  }
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 금칙어 목록 초기화
  Future<void> initialize() async {
    try {
      // Firestore에서 금칙어 목록 로드
      final doc = await _firestore.collection('settings').doc('contentFilter').get();
      if (doc.exists && doc.data() != null && doc.data()!.containsKey('bannedWords')) {
        _bannedWords = List<String>.from(doc.data()!['bannedWords']);
        print('Firestore에서 금칙어 목록을 성공적으로 로드했습니다.');
      } else {
        // 문서가 없는 경우, 기본 금칙어 목록 생성 및 저장
        _bannedWords = _getDefaultBannedWords();
        try {
          await _firestore.collection('settings').doc('contentFilter').set({
            'bannedWords': _bannedWords,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          print('기본 금칙어 목록을 Firestore에 저장했습니다.');
        } catch (storageError) {
          print('Firestore에 금칙어 목록 저장 실패: $storageError');
        }
      }
    } catch (e) {
      print('금칙어 목록 초기화 실패: $e');
      // 기본 금칙어 설정
      _bannedWords = _getDefaultBannedWords();
    }
  }
  
  // 기본 금칙어 목록 반환
  List<String> _getDefaultBannedWords() {
    return ['비속어', '욕설', '혐오', '차별', '음란물'];
  }

  // 텍스트에 금칙어가 포함되어 있는지 확인
  bool containsBannedWords(String text) {
    if (_bannedWords.isEmpty) {
      return false;
    }
    
    final lowerText = text.toLowerCase();
    return _bannedWords.any((word) => lowerText.contains(word.toLowerCase()));
  }

  // 금칙어가 있다면 해당 단어들 반환
  List<String> findBannedWords(String text) {
    if (_bannedWords.isEmpty) {
      return [];
    }
    
    final lowerText = text.toLowerCase();
    return _bannedWords.where((word) => 
      lowerText.contains(word.toLowerCase())).toList();
  }

  // 추후 Google Cloud Vision API 연동을 위한 이미지 분석 메서드
  Future<bool> analyzeImage(String imageUrl) async {
    // 이 부분은 실제 Google Cloud Vision API 연동 코드로 대체되어야 함
    // 현재는 예시 코드로 모든 이미지를 안전하다고 판단
    try {
      // Google Cloud Vision API 호출 예시 코드
      /*
      final response = await http.post(
        Uri.parse('https://vision.googleapis.com/v1/images:annotate?key=YOUR_API_KEY'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requests': [
            {
              'image': {
                'source': {
                  'imageUri': imageUrl
                }
              },
              'features': [
                {
                  'type': 'SAFE_SEARCH_DETECTION',
                  'maxResults': 1
                }
              ]
            }
          ]
        })
      );
      
      final data = jsonDecode(response.body);
      final safeSearch = data['responses'][0]['safeSearchAnnotation'];
      
      // 'LIKELY' 또는 'VERY_LIKELY'인 경우 부적절한 콘텐츠로 판단
      return safeSearch['adult'] == 'LIKELY' || 
             safeSearch['adult'] == 'VERY_LIKELY' ||
             safeSearch['violence'] == 'LIKELY' || 
             safeSearch['violence'] == 'VERY_LIKELY' ||
             safeSearch['racy'] == 'LIKELY' || 
             safeSearch['racy'] == 'VERY_LIKELY';
      */
      
      return false; // 현재는 모든 이미지를 안전하다고 판단
    } catch (e) {
      print('이미지 분석 실패: $e');
      return false;
    }
  }
  
  // 금칙어 목록 업데이트
  Future<void> updateBannedWords(List<String> newWords) async {
    try {
      await _firestore.collection('settings').doc('contentFilter').update({
        'bannedWords': newWords,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      _bannedWords = newWords;
    } catch (e) {
      print('금칙어 목록 업데이트 실패: $e');
      throw e;
    }
  }
  
  // 채팅 메시지 신고
  Future<void> reportChatMessage({
    required String chatRoomId,
    required String messageId,
    required String senderId,
    required String senderName,
    required String reason,
    required String messageType,
    String? messageContent,
    String? imageUrl,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('로그인이 필요합니다');
      }
      
      // 신고 데이터 생성
      final reportData = {
        'chatRoomId': chatRoomId,
        'messageId': messageId,
        'reporterId': currentUser.uid,
        'reportedUserId': senderId,
        'reportedUserName': senderName,
        'reason': reason,
        'messageType': messageType,
        'content': messageContent,
        'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'contentType': 'chat',
        'viewed': false,
      };
      
      // Firestore에 신고 데이터 저장
      final docRef = await _firestore.collection('reportedContent').add(reportData);
      
      // 관리자에게 알림 보내기
      await _notifyAdmins('chat_report', {
        'reportId': docRef.id,
        'chatRoomId': chatRoomId,
        'messageType': messageType,
        'reason': reason,
        'reporterName': await _getUserNickname(currentUser.uid),
        'reportedName': senderName,
      });
      
    } catch (e) {
      print('채팅 메시지 신고 실패: $e');
      throw e;
    }
  }
  
  // 사용자 닉네임 가져오기
  Future<String> _getUserNickname(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return '알 수 없음';
      
      final userData = userDoc.data();
      return userData?['nickname'] ?? '알 수 없음';
    } catch (e) {
      print('사용자 정보 조회 오류: $e');
      return '알 수 없음';
    }
  }
  
  // 관리자에게 알림 보내기
  Future<void> _notifyAdmins(String notificationType, Map<String, dynamic> data) async {
    try {
      // 관리자 목록 가져오기
      final adminDocs = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();
      
      // 각 관리자에게 알림 전송
      for (final adminDoc in adminDocs.docs) {
        final adminId = adminDoc.id;
        
        await _firestore.collection('notifications').add({
          'userId': adminId,
          'type': notificationType,
          'data': data,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('관리자 알림 전송 오류: $e');
    }
  }
  
  // 채팅방 신고
  Future<void> reportChatRoom({
    required String chatRoomId,
    required String reportedBy,
    required String reason,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('로그인이 필요합니다');
      }
      
      // 채팅방 정보 가져오기
      final chatRoomDoc = await _firestore.collection('chatRooms').doc(chatRoomId).get();
      final isGroupChat = chatRoomDoc.data()?['isGroupChat'] ?? false;
      final chatRoomName = chatRoomDoc.data()?['groupName'] ?? chatRoomDoc.data()?['name'] ?? '알 수 없음';
      
      // 신고 데이터 생성
      final reportData = {
        'chatRoomId': chatRoomId,
        'chatRoomName': chatRoomName,
        'reporterId': currentUser.uid,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'contentType': 'chatRoom',
        'isGroupChat': isGroupChat,
        'viewed': false,
      };
      
      // Firestore에 신고 데이터 저장
      final docRef = await _firestore.collection('reportedContent').add(reportData);
      
      // 관리자에게 알림 보내기
      await _notifyAdmins('chatroom_report', {
        'reportId': docRef.id,
        'chatRoomId': chatRoomId,
        'chatRoomName': chatRoomName,
        'reason': reason,
        'reporterName': await _getUserNickname(currentUser.uid),
        'isGroupChat': isGroupChat,
      });
      
    } catch (e) {
      print('채팅방 신고 실패: $e');
      throw e;
    }
  }
}