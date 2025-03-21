import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../widgets/ad_banner_widget.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';

class RiderCafeScreen extends StatefulWidget {
  final GeoPoint? initialLocation;

  const RiderCafeScreen({
    Key? key,
    this.initialLocation,
  }) : super(key: key);

  @override
  _RiderCafeScreenState createState() => _RiderCafeScreenState();
}

class _RiderCafeScreenState extends State<RiderCafeScreen>
    with WidgetsBindingObserver {
  String _selectedRegionType = '광역시';
  String? _selectedRegion;
  String? _selectedDistrict;
  Map<String, dynamic> _regionsData = {};
  NaverMapController? _mapController;
  bool _isRegionDropdownOpen = false;
  bool _isDistrictDropdownOpen = false;
  final Map<String, NMarker> _markersMap = {};
  StreamSubscription? _cafesSubscription;
  DocumentSnapshot? _selectedCafe;
  bool _disposed = false;
  bool _isMapReady = false;
  bool _isDestroying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRegionsFromAssets();
  }

  @override
  void dispose() {
    _disposed = true;
    _isDestroying = true;
    _cleanupResourcesSafely();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _cafesSubscription?.cancel();
      _cafesSubscription = null;
    } else if (state == AppLifecycleState.resumed) {
      _setupCafesStream();
    }
  }

  void _navigateToAuthScreen(Widget screen) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _cleanupResourcesSafely().then((_) {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => LoginScreen()),
          );
        }
      });
    } else {
      _cleanupResourcesSafely().then((_) {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => screen),
          );
        }
      });
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
      
      if (!_disposed && mounted) {
        setState(() {
          // UTF-8 디코딩을 명시적으로 처리
          _regionsData = json.decode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      debugPrint('Error loading regions: $e');
    }
  }

  void _setupCafesStream() {
    _cafesSubscription?.cancel();
    _cafesSubscription =
        FirebaseFirestore.instance.collection('cafes').snapshots().listen(
              (snapshot) {
            if (!_disposed && _isMapReady) {
              _updateMarkers(snapshot.docs);
            }
          },
          onError: (error) {
            debugPrint('Error in cafes stream: $error');
          },
        );
  }

  Future<void> _updateMarkers(List<QueryDocumentSnapshot> docs) async {
    if (_mapController == null || !_isMapReady || _isDestroying) return;

    try {
      final Set<String> currentIds = docs.map((doc) => doc.id).toSet();
      final List<String> markersToRemove =
      _markersMap.keys.where((key) => !currentIds.contains(key)).toList();

      for (final key in markersToRemove) {
        final marker = _markersMap[key];
        if (marker != null && !_isDestroying) {
          await _mapController?.deleteOverlay(marker.info);
          _markersMap.remove(key);
        }
      }

      for (final doc in docs) {
        if (_disposed || !_isMapReady) return;

        final data = doc.data() as Map<String, dynamic>;
        final GeoPoint? location = data['location'] as GeoPoint?;

        if (location != null) {
          if (_markersMap.containsKey(doc.id)) {
            final existingMarker = _markersMap[doc.id]!;
            try {
              await _mapController?.deleteOverlay(existingMarker.info);
            } catch (e) {
              debugPrint('기존 마커/인포윈도우 제거 중 에러: $e');
            }
            _markersMap.remove(doc.id);
          }

          if (!_isMapReady || _disposed) continue;

          try {
            final marker = NMarker(
              id: doc.id,
              position: NLatLng(location.latitude, location.longitude),
              size: const NSize(24.0, 29.5),
              icon: NOverlayImage.fromAssetImage('assets/images/marker.png')
            );

            if (!_isMapReady || _disposed) continue;

            marker.setOnTapListener((NMarker marker) {
              _showCafeDetails(doc);
            });

            if (!_disposed && _isMapReady) {
              await _mapController!.addOverlay(marker);
              await Future.delayed(const Duration(milliseconds: 100));
              if (!_disposed && _isMapReady) {
                _markersMap[doc.id] = marker;
              }
            }
          } catch (e) {
            debugPrint('마커/인포윈도우 생성 중 에러: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error updating markers: $e');
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('카페 정보를 불러오는 중 오류가 발생했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatAddress(String address, String detailAddress) {
    final fullAddress = '$address ${detailAddress.trim()}'.trim();
    final buffer = StringBuffer();

    for (var i = 0; i < fullAddress.length; i += 15) {
      final end = (i + 15 < fullAddress.length) ? i + 15 : fullAddress.length;
      buffer.write(fullAddress.substring(i, end));
      if (end < fullAddress.length) {
        buffer.write('\n');
      }
    }

    return buffer.toString();
  }

  Future<void> _cleanupResourcesSafely() async {
    debugPrint('RiderCafeScreen: 리소스 정리 시작');

    if (!_isDestroying) return;

    try {
      _cafesSubscription?.cancel();
      _cafesSubscription = null;

      if (_mapController != null && _isMapReady) {
        for (var marker in _markersMap.values) {
          try {
            await _mapController?.deleteOverlay(marker.info);
          } catch (e) {
            debugPrint('마커 제거 중 에러: $e');
          }
        }
        _markersMap.clear();
      }

      setState(() {
        _isMapReady = false;
      });
    } catch (e) {
      debugPrint('RiderCafeScreen: 리소스 정리 중 에러: $e');
    }
  }

  void _showCafeDetails(DocumentSnapshot cafe) {
    if (_disposed) return;

    setState(() {
      _selectedCafe = cafe;
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final data = cafe.data() as Map<String, dynamic>;
        return Container(
          height: 400,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                spreadRadius: 0,
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (data['imageUrl'] != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                data['imageUrl'],
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 120,
                                    height: 120,
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.error,
                                        color: Colors.grey),
                                  );
                                },
                              ),
                            ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['name'] ?? '이름 없음',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  data['address'] ?? '주소 없음',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                                if (data['addressDetail'] != null &&
                                    data['addressDetail'].toString().isNotEmpty)
                                  Text(
                                    data['addressDetail'],
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (data['description'] != null &&
                          data['description'].toString().isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          '카페 설명',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data['description'],
                          style: TextStyle(
                            color: Colors.grey[800],
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _moveToSelectedLocation() {
    if (_mapController == null ||
        _selectedRegion == null ||
        !_isMapReady ||
        _disposed) return;

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
        await _cleanupResourcesSafely();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => const HomeScreen(initialIndex: 0),
            ),
                (route) => false,
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'BRG',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_none, color: Colors.black87),
              onPressed: () => _navigateToAuthScreen(NotificationsScreen()),
            ),
            IconButton(
              icon: const Icon(Icons.person_outline, color: Colors.black87),
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
                  const SizedBox(width: 12),
                  _buildRegionTypeDropdown(),
                  const SizedBox(width: 8),
                  _buildDistrictDropdown(),
                ],
              ),
            ),
            Expanded(
              child: NaverMap(
                key: const ValueKey('naver_map'),
                options: const NaverMapViewOptions(
                  initialCameraPosition: NCameraPosition(
                    target: NLatLng(37.5665, 126.9780),
                    zoom: 11,
                  ),
                  mapType: NMapType.basic,
                  activeLayerGroups: [
                    NLayerGroup.building,
                    NLayerGroup.transit
                  ],
                ),
                onMapReady: (controller) {
                  if (!_disposed) {
                    setState(() {
                      _mapController = controller;
                      _isMapReady = true;
                    });
                    if (widget.initialLocation != null) {
                      controller.updateCamera(
                        NCameraUpdate.withParams(
                          target: NLatLng(
                            widget.initialLocation!.latitude,
                            widget.initialLocation!.longitude,
                          ),
                          zoom: 15,
                        ),
                      );
                    }
                    _setupCafesStream();
                  }
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BottomNavigationBar(
              currentIndex: 0,
              onTap: (index) {
                if (!_disposed) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HomeScreen(initialIndex: index),
                    ),
                  );
                }
              },
              type: BottomNavigationBarType.fixed,
              selectedItemColor: Theme.of(context).primaryColor,
              unselectedItemColor: Colors.grey,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: '홈',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.group),
                  label: '커뮤니티',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.directions_car),
                  label: '내 차',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.flash_on),
                  label: '번개',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.chat),
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
}
