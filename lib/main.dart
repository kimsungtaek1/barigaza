import 'package:barigaza/screens/admin/admin_banner_modify.dart';
import 'package:barigaza/screens/admin/admin_banner_tab.dart';
import 'package:barigaza/screens/fuel_record_screen.dart';
import 'package:barigaza/widgets/customColor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

// 스크린 import
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/privacy_agreement_screen.dart';
import 'screens/find_id_screen.dart';
import 'screens/find_password_screen.dart';
import 'screens/admin/admin_login_screen.dart';
import 'screens/admin/admin_upgrade_request_screen.dart';
import 'screens/admin/admin_main_screen.dart';

// 서비스 import
import 'services/auth_service.dart';
import 'services/event_service.dart';

// 상수 정의
const String APP_NAME = 'BRG';
const String NAVER_CLIENT_ID = '5k1r2vy3lz';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // Firebase 캐시 강제 삭제
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseFirestore.instance.clearPersistence();

    // 이벤트 체크 실행
    await EventService().checkExpiredEvents();

  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      debugPrint('Firebase already initialized');
    } else {
      rethrow;
    }
  }

  // Firebase AppCheck 초기화
  if (kDebugMode) {
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.debug,
        appleProvider: AppleProvider.debug,
      );

      // 잠시 대기
      await Future.delayed(const Duration(seconds: 2));

      // Debug token 출력 시도
      try {
        final token = await FirebaseAppCheck.instance.getToken();
        print('Firebase App Check Debug Token: $token');
      } catch (e) {
        if (e.toString().contains('Too many attempts')) {
          print('토큰 요청이 너무 많습니다. 잠시 후 다시 시도해주세요.');
          // 앱을 다시 시작하거나 몇 분 정도 기다린 후 다시 시도
        } else {
          print('Token 얻기 실패: $e');
        }
      }
    } catch (e) {
      print('App Check 활성화 실패: $e');
    }
  } else {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.deviceCheck,
    );
  }

  // 네이버 지도 SDK 초기화
  await NaverMapSdk.instance.initialize(
    clientId: NAVER_CLIENT_ID,
    onAuthFailed: (error) => debugPrint('네이버 지도 초기화 실패: $error'),
  );

  // AdMob 초기화
  await MobileAds.instance.initialize();
  await MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(
        testDeviceIds: ['57195416F96C769F4DC8787DA0B95470']
    ),
  );

  runApp(const MyApp());
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
        title: APP_NAME,
        theme: _buildAppTheme(),
        home: const SplashScreen(),
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