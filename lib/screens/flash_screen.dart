import '/screens/profile_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import '../services/meeting_service.dart';
import '../models/meeting_point.dart';
import '../services/chat_service.dart';
import 'flash_detail_screen.dart';
import 'login_screen.dart';
import 'naver_address_search_screen.dart';
import 'notifications_screen.dart';
import '../widgets/add_meeting_dialog.dart';

class FlashScreen extends StatefulWidget {
  const FlashScreen({Key? key}) : super(key: key);

  @override
  State<FlashScreen> createState() => _FlashScreenState();
}

class _FlashScreenState extends State<FlashScreen> with WidgetsBindingObserver {
  String _selectedRegionType = '광역시';
  String? _selectedRegion;
  String? _selectedDistrict;
  Map<String, dynamic> _regionsData = {};
  NaverMapController? _mapController;
  final List<NMarker> _meetingMarkers = [];
  bool _isRegionDropdownOpen = false;
  bool _isDistrictDropdownOpen = false;
  final Map<String, NMarker> _markersMap = {};
  StreamSubscription? _meetingsSubscription;
  bool _disposed = false;
  bool _isMapReady = false;
  bool _isDestroying = false;
  final MeetingService _meetingService = MeetingService();
  double _markerScale = 0.8;
  double _lastZoom = 11.0;
  List<QueryDocumentSnapshot> _latestDocs = [];

  // 위치 기반 마커 캐싱을 위한 맵 추가
  final Map<String, List<String>> _locationMeetingsMap = {};
  final math.Random _random = math.Random(); // 지터 효과를 위한 랜덤 객체

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_disposed) {
        _loadRegionsFromAssets();
      }
    });
    _checkExpiredMeetings();
  }

  // 만료된 모임 체크 메서드
  Future<void> _checkExpiredMeetings() async {
    try {
      await _meetingService.checkExpiredMeetings();
    } catch (e) {
      debugPrint('모임 만료 체크 중 오류: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _isDestroying = true;
    _cleanupResourcesSafely();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _meetingsSubscription?.cancel();
      _meetingsSubscription = null;
    } else if (state == AppLifecycleState.resumed) {
      // 앱이 포그라운드로 돌아올 때 만료된 모임 체크
      _checkExpiredMeetings();
      _setupMeetingsStream();
    }
  }

  Future<void> _loadRegionsFromAssets() async {
    if (_disposed) return;
    try {
      final response = await http.get(Uri.parse('https://barigaza-796a1.web.app/regions.json'));
      if (response.statusCode != 200) {
        debugPrint('Error fetching regions from server: ${response.statusCode}');
        return;
      }

      if (!_disposed) {
        setState(() {
          // UTF-8 디코딩을 명시적으로 처리
          _regionsData = json.decode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      debugPrint('Error loading regions: $e');
    }
  }

  void _setupMeetingsStream() {
    _meetingsSubscription?.cancel();
    // 상태가 'active'인 모임만 가져오도록 쿼리 수정
    _meetingsSubscription = FirebaseFirestore.instance
        .collection('meetings')
        .where('status', isEqualTo: 'active') // 상태가 active인 모임만 필터링
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (!_disposed && _isMapReady) {
        _updateMarkers(snapshot.docs);
      }
    }, onError: (error) {
      debugPrint('Error in meetings stream: $error');
    });
  }

  // 커스텀 마커 이미지를 생성하는 함수
  Future<NOverlayImage> _createCustomMarkerImage(String title) async {
    // UI 위젯을 이미지로 변환하는 대신, 간단히 에셋 이미지 사용
    return NOverlayImage.fromAssetImage('assets/images/marker.png');
  }

  Future<void> _updateMarkers(List<QueryDocumentSnapshot> docs) async {
    _latestDocs = docs;
    if (_mapController == null || !_isMapReady || _isDestroying) {
      return;
    }
    try {
      // 지도 중심 좌표 가져오기
      final cameraPosition = await _mapController!.getCameraPosition();
      final NLatLng center = cameraPosition.target;
      double calcDistance(GeoPoint? p) {
        if (p == null) return double.infinity;
        final dx = center.latitude - p.latitude;
        final dy = center.longitude - p.longitude;
        return dx * dx + dy * dy; // 빠른 거리 계산
      }
      final sortedDocs = [...docs];
      sortedDocs.sort((a, b) {
        final aLoc = (a.data() as Map<String, dynamic>)['location'] as GeoPoint?;
        final bLoc = (b.data() as Map<String, dynamic>)['location'] as GeoPoint?;
        return calcDistance(aLoc).compareTo(calcDistance(bLoc));
      });
      // 위치 기반 마커 맵 초기화
      _locationMeetingsMap.clear();
      final Set<String> currentIds = docs.map((doc) => doc.id).toSet();
      final List<String> markersToRemove = _markersMap.keys
          .where((key) => !currentIds.contains(key))
          .toList();
      for (final key in markersToRemove) {
        final marker = _markersMap[key];
        if (marker != null && !_isDestroying) {
          await _mapController?.deleteOverlay(marker.info);
          _markersMap.remove(key);
        }
      }
      // 첫 번째 패스: 위치별 모임 ID 완전히 그룹화
      for (final doc in sortedDocs) {
        if (_disposed || !_isMapReady) return;
        final meeting = MeetingPoint.fromFirestore(doc);
        final data = doc.data() as Map<String, dynamic>;
        if (data['status'] != 'active') continue;
        final locationKey = '${meeting.location.latitude.toStringAsFixed(5)},${meeting.location.longitude.toStringAsFixed(5)}';
        if (!_locationMeetingsMap.containsKey(locationKey)) {
          _locationMeetingsMap[locationKey] = [];
        }
        _locationMeetingsMap[locationKey]!.add(meeting.id);
      }
      // 가까운 N개만 먼저 추가, 나머지는 비동기 배치로 추가
      const int batchSize = 20;
      final initialDocs = sortedDocs.take(batchSize).toList();
      final restDocs = sortedDocs.skip(batchSize).toList();
      Future<void> addMarkerForDoc(QueryDocumentSnapshot doc) async {
        if (_disposed || !_isMapReady) return;
        final meeting = MeetingPoint.fromFirestore(doc);
        final data = doc.data() as Map<String, dynamic>;
        if (data['status'] != 'active') return;
        if (_markersMap.containsKey(meeting.id)) {
          final existingMarker = _markersMap[meeting.id]!;
          try {
            await _mapController?.deleteOverlay(existingMarker.info);
          } catch (e) {
            debugPrint('Error deleting existing marker: $e');
          }
          _markersMap.remove(meeting.id);
        }
        if (!_isMapReady || _disposed) return;
        try {
          final locationKey = '${meeting.location.latitude.toStringAsFixed(5)},${meeting.location.longitude.toStringAsFixed(5)}';
          final index = _locationMeetingsMap[locationKey]!.indexOf(meeting.id);
          final jitteredPosition = _applyJitterImproved(meeting.location, locationKey, index);
          final markerImage = await _createCustomMarkerImage(meeting.title);
          final caption = NOverlayCaption(
            text: meeting.title,
            textSize: 14,
            color: Colors.black,
            haloColor: Colors.white,
            minZoom: 10,
            maxZoom: 20,
          );
          final marker = NMarker(
            id: meeting.id,
            position: jitteredPosition,
            size: NSize(36.0 * _markerScale, 44.5 * _markerScale),
            icon: markerImage,
            caption: caption,
            captionOffset: -50,
          );
          marker.setOnTapListener((NMarker marker) {
            _showMeetingDetail(meeting);
          });
          if (!_disposed && _isMapReady) {
            await _mapController!.addOverlay(marker);
            _markersMap[meeting.id] = marker;
          }
        } catch (e) {
          debugPrint('Error creating marker: $e');
        }
      }
      // 가까운 N개 즉시 추가
      for (final doc in initialDocs) {
        await addMarkerForDoc(doc);
      }
      // 나머지는 배치로 추가
      for (int i = 0; i < restDocs.length; i += batchSize) {
        if (_disposed || !_isMapReady) break;
        final batch = restDocs.skip(i).take(batchSize);
        await Future.wait(batch.map(addMarkerForDoc));
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } catch (e) {
      debugPrint('Error updating markers: $e');
    }
  }

// 스파이럴 패턴으로 마커를 분포시키는 함수
  NLatLng _applyJitterImproved(GeoPoint location, String locationKey, int index) {
    // 기본 설정값
    const double jitterBase = 0.0001; // 기본 거리 스케일 (값이 작을수록 조밀한 나선)
    const double growthFactor = 0.2;   // 나선 성장 속도 계수 (값이 클수록 빠르게 확장)

    if (index == 0) {
      // 첫 번째 마커는 중앙에 배치
      return NLatLng(location.latitude, location.longitude);
    }

    // 스파이럴 패턴 계산
    // 각도를 지속적으로 증가시키면서 거리도 증가
    double angle = index * 0.5; // 회전 간격 (값이 작을수록 촘촘하게 회전)

    // 아르키메데스 나선 공식 r = a + bθ
    double distance = jitterBase * (1 + angle * growthFactor);

    // 계산된 극좌표를 직교좌표로 변환
    double latOffset = distance * math.cos(angle);
    double lngOffset = distance * math.sin(angle);

    return NLatLng(
      location.latitude + latOffset,
      location.longitude + lngOffset,
    );
  }

  void _moveToSelectedLocation() {
    if (_mapController == null || _selectedRegion == null || !_isMapReady) return;
    try {
      if (_selectedDistrict != null) {
        final districts = _regionsData[_selectedRegion]?['districts'] as List?;
        if (districts != null) {
          final district = districts.firstWhere(
                (d) => d['name'] == _selectedDistrict,
            orElse: () => null,
          );
          if (district != null) {
            final coordinates = district['coordinates'];
            final position = NLatLng(
              coordinates['lat'],
              coordinates['lng'],
            );
            _mapController!.updateCamera(
              NCameraUpdate.withParams(
                target: position,
                zoom: 13,
              ),
            );
            return;
          }
        }
      }
      final regionCoordinates = _regionsData[_selectedRegion]?['coordinates'];
      if (regionCoordinates != null) {
        final position = NLatLng(
          regionCoordinates['lat'],
          regionCoordinates['lng'],
        );
        _mapController!.updateCamera(
          NCameraUpdate.withParams(
            target: position,
            zoom: 11,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error moving to location: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        debugPrint('FlashScreen: back button pressed');
        if (didPop) {
          await _cleanupResourcesSafely();
        }
      },
      child: Scaffold(
        // 키보드가 나타날 때 레이아웃 조정 방지 - 이 부분이 핵심!
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            'BRG',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_none, color: Colors.black),
              onPressed: () => _navigateToAuthScreen(NotificationsScreen()),
            ),
            IconButton(
              icon: const Icon(Icons.person_outline, color: Colors.black),
              onPressed: () => _navigateToAuthScreen(ProfileScreen()),
            ),
            const SizedBox(width: 12),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'flash_add_button',
          onPressed: _showAddMeetingDialog,
          backgroundColor: Color(0xFF2F6DF3),
          shape: CircleBorder(),
          child: Icon(
            Icons.add,
            color: Colors.white,
          ),
        ),
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  _buildRegionTypeDropdown(),
                  const SizedBox(width: 8),
                  _buildDistrictDropdown(),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  NaverMap(
                    options: const NaverMapViewOptions(
                      initialCameraPosition: NCameraPosition(
                        target: NLatLng(37.5665, 126.9780),
                        zoom: 11,
                      ),
                      mapType: NMapType.basic,
                      activeLayerGroups: [NLayerGroup.building, NLayerGroup.transit],
                    ),
                    onMapReady: (controller) {
                      if (!_disposed) {
                        setState(() {
                          _mapController = controller;
                          _isMapReady = true;
                        });
                        _setupMeetingsStream();
                      }
                    },
                    onCameraIdle: () async {
                      if (_mapController != null && _latestDocs.isNotEmpty) {
                        final cameraPosition = await _mapController!.getCameraPosition();
                        final zoom = cameraPosition.zoom;
                        double newScale;
                        if (zoom >= 11) {
                          newScale = 0.8;
                        } else if (zoom > 8) {
                          newScale = 0.5;
                        } else{
                          newScale = 0.3;
                        }
                        if (newScale != _markerScale) {
                          setState(() {
                            _markerScale = newScale;
                          });
                          _updateMarkers(_latestDocs); // 마커 크기 반영
                        }
                        _lastZoom = zoom;
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cleanupResourcesSafely() async {
    debugPrint('FlashScreen: Cleaning up resources');
    if (!_isDestroying) return;
    try {
      _meetingsSubscription?.cancel();
      _meetingsSubscription = null;
      if (_mapController != null && _isMapReady) {
        for (var marker in _markersMap.values) {
          try {
            await _mapController?.deleteOverlay(marker.info);
          } catch (e) {
            debugPrint('Error deleting marker: $e');
          }
        }
        _markersMap.clear();
        _meetingMarkers.clear();
      }
      setState(() {
        _isMapReady = false;
      });
    } catch (e) {
      debugPrint('Error during cleanup: $e');
    }
  }

  Widget _buildRegionTypeDropdown() {
    return PopupMenuButton<String>(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _isRegionDropdownOpen ? Colors.black : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedRegion ?? _selectedRegionType,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                fontWeight: FontWeight.w400,
              ),
            ),
            const Icon(
              Icons.arrow_drop_down,
              color: Colors.black87,
            ),
          ],
        ),
      ),
      onOpened: () {
        if (!_disposed) {
          setState(() {
            _isRegionDropdownOpen = true;
          });
        }
      },
      onCanceled: () {
        if (!_disposed) {
          setState(() {
            _isRegionDropdownOpen = false;
          });
        }
      },
      onSelected: (String value) {
        if (!_disposed) {
          setState(() {
            _selectedRegion = value;
            _selectedDistrict = null;
            _isRegionDropdownOpen = false;
          });
          _moveToSelectedLocation();
        }
      },
      itemBuilder: (BuildContext context) {
        return _regionsData.keys.map((String region) {
          return PopupMenuItem<String>(
            value: region,
            child: Text(region),
          );
        }).toList();
      },
    );
  }

  Widget _buildDistrictDropdown() {
    final List<Map<String, dynamic>> districts = _selectedRegion != null
        ? List<Map<String, dynamic>>.from(
        _regionsData[_selectedRegion]?['districts'] ?? [])
        : [];
    return PopupMenuButton<String>(
      enabled: _selectedRegion != null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _isDistrictDropdownOpen ? Colors.black : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedDistrict ?? '시군구',
              style: TextStyle(
                fontSize: 14,
                color: _selectedRegion != null ? Colors.black87 : Colors.grey,
                fontWeight: FontWeight.w400,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: _selectedRegion != null ? Colors.black87 : Colors.grey,
            ),
          ],
        ),
      ),
      onOpened: () {
        if (!_disposed) {
          setState(() {
            _isDistrictDropdownOpen = true;
          });
        }
      },
      onCanceled: () {
        if (!_disposed) {
          setState(() {
            _isDistrictDropdownOpen = false;
          });
        }
      },
      onSelected: (String value) {
        if (!_disposed) {
          setState(() {
            _selectedDistrict = value;
            _isDistrictDropdownOpen = false;
          });
          _moveToSelectedLocation();
        }
      },
      itemBuilder: (BuildContext context) {
        return districts.map((district) {
          return PopupMenuItem<String>(
            value: district['name'],
            child: Text(district['name']),
          );
        }).toList();
      },
    );
  }

  void _showAddMeetingDialog() async {
    // 지도 화면과 분리된 새로운 라우트로 다이얼로그 표시
    final result = await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false, // 배경을 투명하게 설정
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: const AddMeetingDialog(),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );

    // 모임이 생성되었으면 마커 업데이트
    if (result == true) {
      // 마커 업데이트 트리거
      if (_latestDocs.isNotEmpty && _isMapReady) {
        _updateMarkers(_latestDocs);
      } else {
        // 스트림 재연결 필요 시
        _setupMeetingsStream();
      }
    }
  }

  void _showMeetingDetail(MeetingPoint meeting) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FlashDetailScreen(meeting: meeting),
      ),
    );
  }
  void _navigateToAuthScreen(Widget screen) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => screen),
      );
    }
  }

  // 네이버 지오코딩 API 호출 최적화
  Future<GeoPoint?> getCoordinatesFromAddress(String address) async {
    // 캐싱은 _getCachedCoordinates 메서드에서 처리하므로 여기서는 API 호출만 최적화

    try {
      final String apiUrl = 'https://naveropenapi.apigw.ntruss.com/map-geocode/v2/geocode';
      final Uri url = Uri.parse('$apiUrl?query=${Uri.encodeComponent(address)}');

      // 디버그 로그 최소화
      // debugPrint("getCoordinatesFromAddress: Request URL: $url");

      final response = await http.get(
        url,
        headers: {
          'X-NCP-APIGW-API-KEY-ID': '5k1r2vy3lz',
          'X-NCP-APIGW-API-KEY': 'W6McBwHf5CFEVZpfz1DSuc2DdzTNC8Ks0l1paU4P',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['addresses'] != null && data['addresses'].isNotEmpty) {
          final location = data['addresses'][0];
          final double? y = double.tryParse(location['y']);
          final double? x = double.tryParse(location['x']);

          if (y != null && x != null) {
            return GeoPoint(y, x);
          }
        }
      } else if (response.statusCode == 429) {
        // 요청 제한 초과 시 짧은 대기 후 재시도
        await Future.delayed(const Duration(milliseconds: 500));
        return getCoordinatesFromAddress(address);
      }
    } catch (e) {
      debugPrint("주소 좌표 변환 오류: $e");
    }

    return null;
  }
}