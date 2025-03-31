import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:barigaza/screens/profile_screen.dart';
import 'package:barigaza/screens/rider_cafe_screen.dart';
import 'package:barigaza/screens/login_screen.dart';
import 'package:barigaza/widgets/weather_widget.dart';
import 'package:barigaza/screens/event_page_screen.dart';
import 'package:barigaza/screens/notifications_screen.dart';
import '../models/event.dart';

class HomeTabScreen extends StatefulWidget {
  const HomeTabScreen({super.key});

  @override
  _HomeTabScreenState createState() => _HomeTabScreenState();
}

class _HomeTabScreenState extends State<HomeTabScreen> {
  Position? _currentPosition;
  String _currentAddress = '';
  bool _mounted = true;
  final PageController _eventPageController = PageController(
    initialPage: 0,
    keepPage: true,
    viewportFraction: 1.0,
  );
  int _currentEventPage = 0;
  List<QueryDocumentSnapshot> _events = [];
  List<DocumentSnapshot> _cafes = [];
  bool _hasUnreadNotifications = false;
  StreamSubscription? _notificationsSubscription;

  @override
  void initState() {
    super.initState();
    // 프레임 완료 후 실행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getCurrentLocation();
      _loadEvents();
      _loadCafes();
      _checkUnreadNotifications();
    });
  }

  @override
  void dispose() {
    imageCache.clear();
    imageCache.clearLiveImages();
    _notificationsSubscription?.cancel();
    _eventPageController.dispose();
    super.dispose();
    _mounted = false;
  }

  // 1. 위치 정보 가져오기
  Future<void> _getCurrentLocation() async {
    if (!_mounted) return;

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!_mounted) return;
      setState(() => _currentPosition = position);

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (!_mounted) return;
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          final adminArea = place.administrativeArea ?? '';
          final locality = place.locality ?? '';
          
          // 중복 방지: adminArea와 locality가 같으면 하나만 표시
          if (adminArea.isNotEmpty && locality.isNotEmpty && adminArea == locality) {
            _currentAddress = adminArea;
          } else {
            _currentAddress = '${adminArea.isNotEmpty ? adminArea : ''} ${locality.isNotEmpty ? locality : ''}';
          }
        });
      }
    } catch (e) {
      // 위치 정보 오류 발생
    }
  }

  // 2. 이벤트 데이터 로드
  Future<void> _loadEvents() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('events')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();

      if (mounted) {
        setState(() => _events = snapshot.docs);
      }
    } catch (e) {
      debugPrint('이벤트 로드 오류: $e');
    }
  }

  // 3. 카페 데이터 로드
  Future<void> _loadCafes() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('cafes').get();
      if (!mounted) return;

      final shuffledDocs = snapshot.docs..shuffle(Random());
      setState(() => _cafes = shuffledDocs.take(10).toList());
    } catch (e) {
      debugPrint('카페 로드 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('카페 정보 불러오기 실패'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 4. 알림 상태 체크
  void _checkUnreadNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    _notificationsSubscription?.cancel();

    _notificationsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() => _hasUnreadNotifications = snapshot.docs.isNotEmpty);
      }
    });
  }

  // 5. 알림 모두 읽음 처리
  Future<void> _markAllNotificationsAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final query = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in query.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  // 6. 인증 화면 네비게이션
  void _navigateToAuthScreen(Widget screen) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => LoginScreen()));
    } else {
      // 전달받은 screen으로 이동
      Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
    }
  }

  // 7. 카페 카드 위젯
  Widget _buildLocationCard(DocumentSnapshot cafe) {
    final data = cafe.data() as Map<String, dynamic>;
    return Container(
      width: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 100,
            width: double.infinity, // Makes image width match parent
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: CachedNetworkImage(
                imageUrl: data['imageUrl'],
                fit: BoxFit.cover,
                width: double.infinity, // Makes image width match parent
                memCacheWidth: 800,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            )
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['name'] ?? '이름 없음',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  data['address'] ?? '주소 없음',
                  style: const TextStyle(color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'BRG',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Stack(
              alignment: Alignment.topRight,
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none, color: Colors.black),
                if (_hasUnreadNotifications)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () {
              _markAllNotificationsAsRead();
              _navigateToAuthScreen(const NotificationsScreen());
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline, color: Colors.black),
            onPressed: () => _navigateToAuthScreen(const ProfileScreen()),
          ),
          const SizedBox(width: 12),
        ],
      ),
        body: RefreshIndicator(
          onRefresh: _getCurrentLocation,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              spreadRadius: 1,
                              blurRadius: 3,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: WeatherWidget(
                            latitude: _currentPosition?.latitude ?? 37.5665,
                            longitude: _currentPosition?.longitude ?? 126.9780,
                            address: _currentAddress.isEmpty ? '위치를 불러오는 중...' : _currentAddress,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildEventSection(),
                _buildLocationSection(),
                const SizedBox(height: 50),
              ],
            ),
          ),
        )
    );
  }

  // 8. 이벤트 섹션
  Widget _buildEventSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '이벤트 · 광고',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => EventsListScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: const Row(
                    children: [
                      Text('더보기', style: TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                      SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_right, size: 14, color: Color(0xFF6B7280)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: _events.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Stack(
              children: [
                PageView.builder(
                  controller: _eventPageController,
                  onPageChanged: (index) => setState(() => _currentEventPage = index),
                  itemCount: _events.length,
                  itemBuilder: (context, index) {
                    final event = Event.fromFirestore(_events[index]);
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EventDetailScreen(event: event),
                        ),
                      ),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              spreadRadius: 2,
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: event.imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 240,
                            placeholder: (context, url) =>
                            const Center(child: CircularProgressIndicator()),
                            errorWidget: (context, url, error) =>
                                Image.asset('assets/images/event_banner.png'),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (_events.length > 1)
                  Positioned(
                    bottom: 26,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_currentEventPage + 1}/${_events.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 9. 카페 추천 섹션
  Widget _buildLocationSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '바이크 카페 추천',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => RiderCafeScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: const Row(
                    children: [
                      Text('더보기', style: TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                      SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_right, size: 14, color: Color(0xFF6B7280)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _cafes.isEmpty
                  ? [const Center(child: CircularProgressIndicator())]
                  : _cafes.map((cafe) {
                final data = cafe.data() as Map<String, dynamic>;
                return Padding(
                  padding: EdgeInsets.only(right: cafe != _cafes.last ? 8 : 0),
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RiderCafeScreen(
                          initialLocation: data['location'] as GeoPoint?,
                        ),
                      ),
                    ),
                    child: _buildLocationCard(cafe),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}