import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 이메일/비밀번호 회원가입
  Future<UserCredential?> signUpWithEmail(
      String email, String password, String username) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Firestore에 사용자 정보 저장
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'username': username,
        'email': email,
        'createdAt': Timestamp.now(),
        'lastActive': Timestamp.now(),
      });

      return userCredential;
    } catch (e) {
      print(e.toString());
      return null;
    }
  }

  // 이메일/비밀번호 로그인
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      print(e.toString());
      return null;
    }
  }

  // Google 로그인
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential =
      await _auth.signInWithCredential(credential);

      // Firestore에 사용자 정보 저장 또는 업데이트
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'username': googleUser.displayName,
        'email': googleUser.email,
        'lastActive': Timestamp.now(),
      }, SetOptions(merge: true));

      return userCredential;
    } catch (e) {
      print(e.toString());
      return null;
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    notifyListeners();
  }

  // 회원 탈퇴
  Future<void> deleteAccount() async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        // Firestore에서 사용자 데이터 삭제
        await _firestore.collection('users').doc(user.uid).delete();
        
        // Firebase Auth에서 사용자 계정 삭제
        await user.delete();
        
        // 로그아웃 처리
        await signOut();
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        // 민감한 작업을 수행하기 위해 재인증이 필요한 경우
        throw '보안을 위해 다시 로그인한 후 시도해주세요.';
      }
      throw '계정 삭제 중 오류가 발생했습니다: ${e.message}';
    } catch (e) {
      throw '계정 삭제 중 오류가 발생했습니다: $e';
    }
  }

  Future<UserCredential?> signUp({
    required String email,
    required String password,
    required String nickname,
    required String name,
    required String phone,
    String? gender, required String role,
  }) async {
    try {
      // 1. Firebase Auth로 사용자 계정 생성
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 2. 생성된 유저의 프로필 업데이트 (닉네임 설정)
      await userCredential.user?.updateDisplayName(nickname);

      debugPrint('테스터:${userCredential.user!.uid}');

      // 3. Firestore에 추가 사용자 정보 저장
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        // SignUpScreen에서 받은 기본 정보
        'email': email,
        'nickname': nickname,
        'name': name,
        'phone': phone,
        'gender': gender,
        'role': role,

        // AuthService에서 추가하는 시스템 정보
        'uid': userCredential.user!.uid,        // Firebase Auth에서 생성된 UID
        'isPhoneVerified': true,                // 전화번호 인증 상태
        'createdAt': Timestamp.now(),           // 계정 생성 시간
        'lastActive': Timestamp.now(),          // 마지막 활동 시간
      });

      notifyListeners(); // ChangeNotifier 상태 업데이트
      return userCredential;
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth 에러: ${e.code}');
      if (e.code == 'weak-password') {
        throw '비밀번호가 너무 약합니다.';
      } else if (e.code == 'email-already-in-use') {
        throw '이미 사용 중인 이메일입니다.';
      }
      throw '회원가입 중 오류가 발생했습니다.';
    } catch (e) {
      print('기타 에러: $e');
      throw '회원가입 중 오류가 발생했습니다.';
    }
  }
}