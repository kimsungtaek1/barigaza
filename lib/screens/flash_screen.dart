import 'package:barigaza/screens/profile_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math; // 랜덤 오프셋 생성을 위해 math 라이브러리 추가

import '../models/meeting_point.dart';
import '../services/chat_service.dart';
import 'flash_detail_screen.dart';
import 'login_screen.dart';
import 'naver_address_search_screen.dart';
import 'notifications_screen.dart';

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
    _meetingsSubscription = FirebaseFirestore.instance
        .collection('meetings')
        .orderBy('createdAt', descending: true)
        .snapshots()
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
    if (_mapController == null || !_isMapReady || _isDestroying) {
      return;
    }
    try {
      // 위치 기반 마커 맵 초기화
      _locationMeetingsMap.clear();

      // 현재 문서 ID 세트 생성
      final Set<String> currentIds = docs.map((doc) => doc.id).toSet();
      final List<String> markersToRemove = _markersMap.keys
          .where((key) => !currentIds.contains(key))
          .toList();

      // 필요 없는 마커 제거
      for (final key in markersToRemove) {
        final marker = _markersMap[key];
        if (marker != null && !_isDestroying) {
          await _mapController?.deleteOverlay(marker.info);
          _markersMap.remove(key);
        }
      }

      // 첫 번째 패스: 위치별 모임 ID 완전히 그룹화
      for (final doc in docs) {
        if (_disposed || !_isMapReady) return;

        final meeting = MeetingPoint.fromFirestore(doc);
        // 더 정밀한 위치키 사용 (소수점 5자리까지만 사용)
        final locationKey = '${meeting.location.latitude.toStringAsFixed(5)},${meeting.location.longitude.toStringAsFixed(5)}';

        if (!_locationMeetingsMap.containsKey(locationKey)) {
          _locationMeetingsMap[locationKey] = [];
        }
        _locationMeetingsMap[locationKey]!.add(meeting.id);
      }

      // 두 번째 패스: 각 문서에 대해 마커 생성
      for (final doc in docs) {
        if (_disposed || !_isMapReady) return;

        final meeting = MeetingPoint.fromFirestore(doc);

        // 이미 존재하는 마커 삭제
        if (_markersMap.containsKey(meeting.id)) {
          final existingMarker = _markersMap[meeting.id]!;
          try {
            await _mapController?.deleteOverlay(existingMarker.info);
          } catch (e) {
            debugPrint('Error deleting existing marker: $e');
          }
          _markersMap.remove(meeting.id);
        }

        if (!_isMapReady || _disposed) continue;

        try {
          // 정밀한 위치키로 jitter 계산
          final locationKey = '${meeting.location.latitude.toStringAsFixed(5)},${meeting.location.longitude.toStringAsFixed(5)}';

          // 해당 그룹 내 위치 인덱스 계산
          final index = _locationMeetingsMap[locationKey]!.indexOf(meeting.id);
          final jitteredPosition = _applyJitterImproved(meeting.location, locationKey, index);

          // 마커 생성 (커스텀 마커 이미지 사용)
          final markerImage = await _createCustomMarkerImage(meeting.title);

          // 네이버 맵에서 지원하는 기본 캡션 설정
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
            size: const NSize(36.0, 44.5),
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다. 먼저 로그인해주세요.')),
      );
      return;
    }

    final TextEditingController titleController = TextEditingController();
    final TextEditingController departureAddressController = TextEditingController();
    final TextEditingController departureDetailAddressController = TextEditingController();
    final TextEditingController destinationAddressController = TextEditingController();
    final TextEditingController destinationDetailAddressController = TextEditingController();
    final TextEditingController timeController = TextEditingController();
    DateTime? selectedTime;
    GeoPoint? selectedLocation;
    final ChatService _chatService = ChatService();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Theme(
        data: Theme.of(context).copyWith(
          datePickerTheme: const DatePickerThemeData(
            backgroundColor: Colors.white,
          ),
        ),
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0, bottom: 16.0, left: 20.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '번개 모임 만들기',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 모임 제목
                        TextFormField(
                          controller: titleController,
                          decoration: InputDecoration(
                            labelText: '모임 제목',
                            hintText: '모임 제목을 입력해주세요',
                            hintStyle: TextStyle(color: Colors.grey),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        SizedBox(height: 16),

                        // 모임 시간
                        TextFormField(
                          controller: timeController,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: '모임 시간',
                            hintStyle: TextStyle(color: Colors.grey),
                            prefixIcon: Icon(Icons.access_time, size: 16, color: Theme.of(context).primaryColor),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          onTap: () async {
                            final now = DateTime.now();
                            final DateTime? pickedDate = await showDatePicker(
                              context: context,
                              initialDate: now,
                              firstDate: now,
                              lastDate: now.add(const Duration(days: 30)),
                              builder: (context, child) => Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.light(
                                    primary: Colors.blue,
                                    onPrimary: Colors.white,
                                    onSurface: Colors.black,
                                  ),
                                  textButtonTheme: TextButtonThemeData(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.blue,
                                    ),
                                  ),
                                ),
                                child: child!,
                              ),
                            );

                            if (pickedDate != null) {
                              final TimeOfDay? pickedTime = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                                builder: (context, child) => Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: const ColorScheme.light(
                                      primary: Colors.blue,
                                      onPrimary: Colors.white,
                                      onSurface: Colors.black,
                                    ),
                                    textButtonTheme: TextButtonThemeData(
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.blue,
                                      ),
                                    ),
                                  ),
                                  child: child!,
                                ),
                              );

                              if (pickedTime != null) {
                                selectedTime = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  pickedTime.hour,
                                  pickedTime.minute,
                                );
                                timeController.text = DateFormat('yyyy년 MM월 dd일 HH시 mm분')
                                    .format(selectedTime!);
                              }
                            }
                          },
                        ),
                        SizedBox(height: 32),

                        // 출발지
                        TextFormField(
                          controller: departureAddressController,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: '출발지',
                            hintText: '출발지를 검색해주세요',
                            hintStyle: TextStyle(color: Colors.grey),
                            prefixIcon: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Image.asset(
                                'assets/images/marker.png',
                                width: 8,
                                height: 8,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const NaverAddressSearch(),
                              ),
                            );
                            if (result != null) {
                              departureAddressController.text = result;
                            }
                          },
                        ),
                        SizedBox(height: 8),

                        // 출발지 상세주소
                        TextFormField(
                          controller: departureDetailAddressController,
                          decoration: InputDecoration(
                            labelText: '출발지 상세주소',
                            hintText: '출발지 상세주소를 입력해주세요 (선택)',
                            hintStyle: TextStyle(color: Colors.grey),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        SizedBox(height: 32),

                        // 목적지
                        TextFormField(
                          controller: destinationAddressController,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: '목적지',
                            hintText: '목적지를 검색해주세요',
                            hintStyle: TextStyle(color: Colors.grey),
                            prefixIcon: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Image.asset(
                                'assets/images/marker.png',
                                width: 8,
                                height: 8,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const NaverAddressSearch(),
                              ),
                            );
                            if (result != null) {
                              destinationAddressController.text = result;
                            }
                          },
                        ),
                        SizedBox(height: 8),

                        // 목적지 상세주소
                        TextFormField(
                          controller: destinationDetailAddressController,
                          decoration: InputDecoration(
                            labelText: '목적지 상세주소',
                            hintText: '목적지 상세주소를 입력해주세요 (선택)',
                            hintStyle: TextStyle(color: Colors.grey),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.0),
                              borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Color(0xFFE5E7EB),
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                              ),
                            ),
                            child: Text(
                              '취소',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            if (titleController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('모임 제목을 입력해주세요.')),
                              );
                              return;
                            }
                            if (departureAddressController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('출발지를 선택해주세요.')),
                              );
                              return;
                            }
                            if (destinationAddressController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('목적지를 선택해주세요.')),
                              );
                              return;
                            }
                            if (selectedTime == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('시간을 선택해주세요.')),
                              );
                              return;
                            }
                            if (selectedTime!.isBefore(DateTime.now())) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('현재 시간 이후로 선택해주세요.')),
                              );
                              return;
                            }
                            try {
                              selectedLocation =
                              await getCoordinatesFromAddress(departureAddressController.text);
                              if (selectedLocation == null) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('출발지 주소를 좌표로 변환하는데 실패했습니다.')),
                                );
                                return;
                              }
                              // 사용자 닉네임 가져오기
                              final userDoc = await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user.uid)
                                  .get();

                              final userNickname = userDoc['nickname'] ?? '알 수 없음';

                              final newMeeting = {
                                'title': titleController.text,
                                'hostId': user.uid,
                                'hostName': userNickname, // Firestore에서 가져온 닉네임 사용
                                'departureAddress': departureAddressController.text,
                                'departureDetailAddress': departureDetailAddressController.text,
                                'destinationAddress': destinationAddressController.text,
                                'destinationDetailAddress': destinationDetailAddressController.text,
                                'meetingTime': Timestamp.fromDate(selectedTime!),
                                'location': selectedLocation,
                                'participants': [user.uid],
                                'status': 'active',
                                'createdAt': Timestamp.now(),
                              };

                              await FirebaseFirestore.instance.runTransaction((transaction) async {
                                final meetingRef = await FirebaseFirestore.instance
                                    .collection('meetings')
                                    .add(newMeeting);

                                final chatId = await _chatService.createGroupChatRoom(
                                  [user.uid],
                                  titleController.text,
                                  meetingId: meetingRef.id,
                                );

                                transaction.update(meetingRef, {
                                  'chatRoomId': chatId
                                });
                              });

                              if (!mounted) return;
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('모임이 성공적으로 생성되었습니다.'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('모임 생성 중 오류가 발생했습니다: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
                              borderRadius: BorderRadius.only(
                                bottomRight: Radius.circular(16),
                              ),
                            ),
                            child: Text(
                              '저장',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

  Future<GeoPoint?> getCoordinatesFromAddress(String address) async {
    try {
      final String apiUrl = 'https://naveropenapi.apigw.ntruss.com/map-geocode/v2/geocode';
      final Uri url = Uri.parse('$apiUrl?query=${Uri.encodeComponent(address)}');
      debugPrint("getCoordinatesFromAddress: Request URL: $url");

      final response = await http.get(
        url,
        headers: {
          'X-NCP-APIGW-API-KEY-ID': '5k1r2vy3lz', // 본인의 API Key ID로 교체
          'X-NCP-APIGW-API-KEY': 'W6McBwHf5CFEVZpfz1DSuc2DdzTNC8Ks0l1paU4P', // 본인의 API Key로 교체
        },
      );

      debugPrint("getCoordinatesFromAddress: Response status: ${response.statusCode}");
      debugPrint("getCoordinatesFromAddress: Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['addresses'] != null && data['addresses'].isNotEmpty) {
          final location = data['addresses'][0];
          final double? y = double.tryParse(location['y']);
          final double? x = double.tryParse(location['x']);
          if (y == null || x == null) {
            debugPrint("getCoordinatesFromAddress: Parsing error: y=$y, x=$x");
            return null;
          }
          debugPrint("getCoordinatesFromAddress: Parsed coordinates: GeoPoint($y, $x)");
          return GeoPoint(y, x);
        } else {
          debugPrint("getCoordinatesFromAddress: No addresses found in response.");
        }
      } else {
        debugPrint("getCoordinatesFromAddress: Non-200 status code: ${response.statusCode}");
      }
    } catch (e, stackTrace) {
      debugPrint("getCoordinatesFromAddress: Exception occurred: $e");
      debugPrint("Stack trace: $stackTrace");
    }
    return null;
  }
}