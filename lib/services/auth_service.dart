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
    debugPrint('로그아웃 시작');
    try {
      // 구글 로그인 세션 종료
      await _googleSignIn.signOut();
      debugPrint('구글 로그아웃 완료');

      // Firebase 로그아웃
      await _auth.signOut();
      debugPrint('Firebase 로그아웃 완료');

      // 추가 정리 (캐시 삭제 등)
      await FirebaseAuth.instance.signOut(); // 명시적으로 다시 호출

      notifyListeners();
      debugPrint('로그아웃 완료');
    } catch (e) {
      debugPrint('로그아웃 오류: $e');
      // 오류가 발생해도 알림
      notifyListeners();
      throw e;
    }
  }

  // 재인증 메서드
  Future<UserCredential> reauthenticateUser(String password) async {
    User? user = _auth.currentUser;
    if (user == null) throw '로그인 상태가 아닙니다.';

    // 이메일 제공자인 경우
    if (user.providerData.any((element) => element.providerId == 'password')) {
      // 사용자의 이메일로 EmailAuthCredential 생성
      AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      return await user.reauthenticateWithCredential(credential);
    }
    // Google 로그인인 경우
    else if (user.providerData.any((element) => element.providerId == 'google.com')) {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw '구글 로그인에 실패했습니다.';

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await user.reauthenticateWithCredential(credential);
    } else {
      throw '지원하지 않는 로그인 방식입니다.';
    }
  }

  // 회원 탈퇴 (이메일 계정용)
  Future<void> deleteEmailAccount(String password) async {
    try {
      User? user = _auth.currentUser;
      if (user == null) throw '로그인 상태가 아닙니다.';

      // 1. 사용자 재인증
      await reauthenticateUser(password);

      // 2. Firestore에서 사용자 데이터 삭제
      await _firestore.collection('users').doc(user.uid).delete();

      // 3. Firebase Auth에서 사용자 계정 삭제
      await user.delete();

      // 4. 로그아웃 처리
      await signOut();

      notifyListeners();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        // 이 에러는 이제 발생하지 않아야 함 (재인증을 먼저 수행했기 때문)
        throw '보안을 위해 다시 로그인한 후 시도해주세요.';
      } else if (e.code == 'wrong-password') {
        throw '비밀번호가 올바르지 않습니다.';
      }
      throw '계정 삭제 중 오류가 발생했습니다: ${e.message}';
    } catch (e) {
      throw '계정 삭제 중 오류가 발생했습니다: $e';
    }
  }

  // 회원 탈퇴 (Google 계정용)
  Future<void> deleteGoogleAccount() async {
    try {
      User? user = _auth.currentUser;
      if (user == null) throw '로그인 상태가 아닙니다.';

      // Google 로그인 사용자인지 확인
      bool isGoogleUser = user.providerData.any((element) =>
      element.providerId == 'google.com');

      if (!isGoogleUser) {
        throw '구글 계정으로 로그인한 사용자가 아닙니다.';
      }

      // 1. Google 재인증 시도
      await reauthenticateUser('');  // 비밀번호는 사용하지 않음

      // 2. Firestore에서 사용자 데이터 삭제
      await _firestore.collection('users').doc(user.uid).delete();

      // 3. Firebase Auth에서 사용자 계정 삭제
      await user.delete();

      // 4. 로그아웃 처리
      await signOut();

      notifyListeners();
    } catch (e) {
      throw '계정 삭제 중 오류가 발생했습니다: $e';
    }
  }

  Future<void> deleteAccount({String? password}) async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        // 재인증이 필요한 경우를 대비하여 password가 제공되었다면 재인증 수행
        if (password != null && user.email != null) {
          // 이메일/비밀번호 자격 증명 생성
          AuthCredential credential = EmailAuthProvider.credential(
            email: user.email!,
            password: password,
          );

          try {
            // 사용자 재인증
            await user.reauthenticateWithCredential(credential);
            debugPrint('사용자 재인증 성공');
          } catch (e) {
            debugPrint('재인증 실패: $e');
            throw '비밀번호가 일치하지 않습니다. 정확한 비밀번호를 입력해주세요.';
          }
        }

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

  // 회원가입 (상세 정보 포함)
  Future<UserCredential?> signUp({
    required String email,
    required String password,
    required String nickname,
    required String name,
    required String phone,
    String? gender,
    required String role,
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