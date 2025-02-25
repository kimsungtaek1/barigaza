import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:barigaza/screens/login_screen.dart';
import 'package:barigaza/screens/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // 애니메이션 컨트롤러 설정 (2초 지속)
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    // 커브 애니메이션 적용 (easeIn)
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    // 애니메이션 실행
    _controller.forward();

    // 초기화 작업 실행 (3초 후에 자동 로그인 여부를 체크)
    _initializeApp();
  }

  /// 앱 초기화 후 Firebase 로그인 상태를 확인하여
  /// 로그인 되어 있으면 홈 화면으로, 아니면 로그인 화면으로 이동합니다.
  Future<void> _initializeApp() async {
    // 스플래시 화면을 보여주기 위한 딜레이 (필요에 따라 조절)
    await Future.delayed(const Duration(seconds: 1));

    // Firebase의 현재 로그인 상태 확인
    final User? user = FirebaseAuth.instance.currentUser;

    if (mounted) {
      if (user != null) {
        // 사용자가 로그인 상태이면 홈 화면으로 이동
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        // 로그인 되어 있지 않으면 로그인 화면으로 이동
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LoginScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    // AnimationController 자원 해제
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 배경색은 main.dart의 테마 색상과 동일하게 설정
      backgroundColor: const Color(0xFF726C56),
      body: Center(
        child: FadeTransition(
          opacity: _animation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 스플래시 이미지 (assets 폴더에 splash.png 파일이 있어야 합니다)
              Image.asset(
                'assets/images/splash.png',
                width: 300,
                height: 300,
              ),
              const SizedBox(height: 20),
              // 로딩 인디케이터
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
