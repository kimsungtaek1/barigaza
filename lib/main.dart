import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

// 스크린 import
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/privacy_agreement_screen.dart';
import 'screens/find_id_screen.dart';
import 'screens/find_password_screen.dart';
import 'screens/admin/admin_login_screen.dart';
import 'screens/admin/admin_upgrade_request_screen.dart';
import 'screens/admin/admin_main_screen.dart';
import 'screens/admin/admin_banner_modify.dart';
import 'screens/fuel_record_screen.dart';

// 서비스 import
import 'services/auth_service.dart';
import 'services/event_service.dart';
import 'services/content_filter_service.dart';
import 'widgets/customColor.dart';
import 'services/meeting_service.dart';

// 상수 정의
const String NAVER_CLIENT_ID = '5k1r2vy3lz';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 기본 Firebase 초기화만 여기서 수행
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      debugPrint('Firebase already initialized');
    } else {
      rethrow;
    }
  }

  // 필요한 초기화를 여기서 수행
  await initializeApp();

  runApp(const MyApp());
}

// 앱 초기화 함수 - 스플래시 화면 없이 초기화 작업 수행
Future<void> initializeApp() async {
  try {
    // SharedPreferences 초기화 및 클리어
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // Firebase 캐시 강제 삭제
    try {
      await FirebaseFirestore.instance.clearPersistence();
    } catch (e) {
      debugPrint('Firestore persistence clear error: $e');
    }

    // 이벤트 체크 실행
    await EventService().checkExpiredEvents();

    // Firebase AppCheck 초기화
    await initializeAppCheck();
    
    // 콘텐츠 필터 서비스 초기화
    await ContentFilterService().initialize();

    // 네이버 지도 SDK 초기화
    await NaverMapSdk.instance.initialize(
      clientId: NAVER_CLIENT_ID,
      onAuthFailed: (error) => debugPrint('네이버 지도 초기화 실패: $error'),
    );

    // 만료된 이벤트 체크
    await EventService().checkExpiredEvents();

    // 만료된 번개모임 체크
    await MeetingService().checkExpiredMeetings();

    // AdMob 초기화
    await MobileAds.instance.initialize();
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
          testDeviceIds: ['57195416F96C769F4DC8787DA0B95470']
      ),
    );
  } catch (e) {
    debugPrint('초기화 오류: $e');
  }
}

Future<void> initializeAppCheck() async {
  try {
    if (kDebugMode) {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.debug,
        appleProvider: AppleProvider.debug,
      );

      // Debug token 출력 시도
      try {
        final token = await FirebaseAppCheck.instance.getToken();
        debugPrint('Firebase App Check Debug Token: $token');
      } catch (e) {
        if (e.toString().contains('Too many attempts')) {
          debugPrint('토큰 요청이 너무 많습니다. 잠시 후 다시 시도해주세요.');
        } else {
          debugPrint('Token 얻기 실패: $e');
        }
      }
    } else {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.playIntegrity,
        appleProvider: AppleProvider.deviceCheck,
      );
    }
  } catch (e) {
    debugPrint('App Check 활성화 실패: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider<EventService>(create: (_) => EventService()),
      ],
      child: MaterialApp(
        theme: _buildAppTheme(),
        // 스플래시 화면 대신 로그인 상태에 따라 직접 홈 또는 로그인 화면으로 이동
        home: _getInitialScreen(),
        routes: _buildAppRoutes(),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ko', 'KR'),
          Locale('en', 'US'),
        ],
        locale: const Locale('ko', 'KR'),
      ),
    );
  }

  // 로그인 상태에 따라 시작 화면 결정
  Widget _getInitialScreen() {
    // Firebase의 현재 로그인 상태 확인
    final User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // 사용자가 로그인 상태이면 홈 화면으로 이동
      return const HomeScreen();
    } else {
      // 로그인 되어 있지 않으면 로그인 화면으로 이동
      return LoginScreen();
    }
  }

  ThemeData _buildAppTheme() {
    return ThemeData(
      scaffoldBackgroundColor: Colors.white,
      canvasColor: Colors.white,
      primarySwatch: Colors.blue,
      colorScheme: ColorScheme.fromSwatch(primarySwatch: customColor),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Map<String, WidgetBuilder> _buildAppRoutes() {
    return {
      '/login': (context) => LoginScreen(),
      '/privacy-agreement': (context) => PrivacyAgreementScreen(),
      '/signup': (context) => SignUpScreen(),
      '/find-id': (context) => FindIdScreen(),
      '/find-password': (context) => FindPasswordScreen(),
      '/admin-login': (context) => AdminLoginScreen(),
      '/admin-upgrade-request': (context) => AdminUpgradeRequestScreen(),
      '/admin-main': (context) => AdminMainScreen(),
      '/admin-banner-modify': (context) => const AdminBannerModifyScreen(),
      '/fuel-record': (context) => FuelRecordScreen(),
      '/home': (context) => HomeScreen(),
    };
  }
}