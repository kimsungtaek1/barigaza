import 'package:barigaza/screens/profile_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';

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
      final String jsonString = await DefaultAssetBundle.of(context)
          .loadString('assets/jsons/regions.json');
      if (!_disposed) {
        setState(() {
          _regionsData = json.decode(jsonString);
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

  Future<void> _updateMarkers(List<QueryDocumentSnapshot> docs) async {
    if (_mapController == null || !_isMapReady || _isDestroying) {
      return;
    }
    try {
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

      for (final doc in docs) {
        if (_disposed || !_isMapReady) return;

        final meeting = MeetingPoint.fromFirestore(doc);

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
          final marker = NMarker(
            id: meeting.id,
            position: NLatLng(
              meeting.location.latitude,
              meeting.location.longitude,
            ),
            size: const NSize(50.0, 50.0),
            icon: NOverlayImage.fromAssetImage('assets/images/marker.png'),
          );

          final String formattedText = _formatMeetingInfo(meeting);

          if (!_isMapReady || _disposed) continue;

          final infoWindow = NInfoWindow.onMarker(
            id: 'info_${meeting.id}',
            text: formattedText,
          );

          marker.setOnTapListener((NMarker marker) {
            _showMeetingDetail(meeting);
          });

          if (!_disposed && _isMapReady) {
            await _mapController!.addOverlay(marker);
            await Future.delayed(const Duration(milliseconds: 100));
            if (!_disposed && _isMapReady) {
              marker.openInfoWindow(infoWindow);
              _markersMap[meeting.id] = marker;
            }
          }
        } catch (e) {
          debugPrint('Error creating marker/infoWindow: $e');
        }
      }
    } catch (e) {
      debugPrint('Error updating markers: $e');
    }
  }

  String _wrapText(String text, int maxChars) {
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i += maxChars) {
      final int end = (i + maxChars < text.length) ? i + maxChars : text.length;
      buffer.write(text.substring(i, end));
      if (end < text.length) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  // _formatMeetingInfo 함수에서 각 줄이 20글자(띄어쓰기 포함)를 넘으면 줄바꿈하도록 변경
  String _formatMeetingInfo(MeetingPoint meeting) {
    final buffer = StringBuffer();
    final meetingTimeStr = DateFormat('yy년MM월dd일 HH시mm분').format(meeting.meetingTime);
    buffer.writeln('시간: $meetingTimeStr');

    // 접두사 포함 전체 문자열을 대상으로 wrapping
    final wrappedDeparture = _wrapText('출발지: ${meeting.departureAddress} ${meeting.departureDetailAddress}', 20);
    buffer.writeln(wrappedDeparture);

    final wrappedDestination = _wrapText('목적지: ${meeting.destinationAddress} ${meeting.destinationDetailAddress}', 20);
    buffer.writeln(wrappedDestination);

    return buffer.toString();
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
          title: Image.asset('assets/images/brg_logo.png', height: 24),
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
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    '내 지역',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
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
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: SizedBox(
                      width: 100,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _showAddMeetingDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('추가'),
                      ),
                    ),
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
        child: AlertDialog(
          title: const Text('번개 모임 만들기'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '모임 제목',
                    hintText: '모임 제목을 입력해주세요',
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: departureAddressController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: '출발지',
                    hintText: '출발지를 검색해주세요',
                    border: const OutlineInputBorder(),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () async {
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
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: departureDetailAddressController,
                  decoration: const InputDecoration(
                    labelText: '출발지 상세주소',
                    hintText: '출발지 상세주소를 입력해주세요 (선택)',
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: destinationAddressController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: '목적지',
                    hintText: '목적지를 검색해주세요',
                    border: const OutlineInputBorder(),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () async {
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
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: destinationDetailAddressController,
                  decoration: const InputDecoration(
                    labelText: '목적지 상세주소',
                    hintText: '목적지 상세주소를 입력해주세요 (선택)',
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: timeController,
                  decoration: const InputDecoration(
                    labelText: '모임 시간',
                    suffixIcon: Icon(Icons.access_time),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  readOnly: true,
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[600],
              ),
            ),
            ElevatedButton(
              onPressed: () async {
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
                  final newMeeting = {
                    'title': titleController.text,
                    'hostId': user.uid,
                    'hostName': user.displayName ?? '익명',
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('만들기'),
            ),
          ],
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
}