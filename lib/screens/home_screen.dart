import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/auth_utils.dart';
import '../widgets/ad_banner_widget.dart';
import 'home_tab_screen.dart';
import 'community_screen.dart';
import 'my_car_screen.dart';
import 'flash_screen.dart';
import 'chat_list_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final int initialIndex;

  const HomeScreen({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late int _selectedIndex;
  bool _isDisposed = false;

  List<Widget> get _screens => [
    const HomeTabScreen(),
    CommunityScreen(),
    _buildCarTab(),
    const FlashScreen(),
    const ChatListScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      debugPrint('HomeScreen: 앱이 백그라운드로 전환됨');
    }
  }

  Widget _buildCarTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('로그인이 필요합니다.'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(child: Text('오류가 발생했습니다.'));
        }

        final data = snapshot.data?.data();
        final hasBikeInfo = data != null && data['hasBikeInfo'] == true;

        if (hasBikeInfo) {
          return const ProfileScreen(
            initialTabIndex: 1,  // 내 차량 탭 선택
            selectedBottomTab: 2, // 하단 내비게이션 바에서 내 차 탭 선택
            showBottomNav: false, // 하단 내비게이션 바 숨김 (이미 HomeScreen에 있으므로)
          );
        } else {
          return const MyCarScreen();
        }
      },
    );
  }

  Future<void> _checkAndNavigate(int index) async {
    debugPrint('HomeScreen: 탭 전환 시도 $_selectedIndex -> $index');

    if (index == 2) { // 내 차 탭
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('로그인이 필요합니다.'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    if (!_isDisposed && context.mounted) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  Widget _buildCurrentScreen() {
    return IndexedStack(
      index: _selectedIndex,
      children: _screens,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvoked: (didPop) async {
        debugPrint('HomeScreen: 뒤로가기 버튼 감지');
        if (!didPop && _selectedIndex != 0) {
          debugPrint('HomeScreen: 메인 탭으로 이동');
          await _checkAndNavigate(0);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: _buildCurrentScreen(),
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: _checkAndNavigate,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: Theme.of(context).primaryColor,
              unselectedItemColor: Colors.grey,
              showUnselectedLabels: true,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: '홈',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.group_outlined),
                  activeIcon: Icon(Icons.group),
                  label: '커뮤니티',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.directions_car_outlined),
                  activeIcon: Icon(Icons.directions_car),
                  label: '내 차',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.flash_on_outlined),
                  activeIcon: Icon(Icons.flash_on),
                  label: '번개',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.chat_bubble_outline),
                  activeIcon: Icon(Icons.chat_bubble),
                  label: '채팅',
                ),
              ],
            ),
            const AdBannerWidget(),
          ],
        ),
      ),
    );
  }
}