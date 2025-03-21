import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class MapCoordinatePicker extends StatefulWidget {
  final String address;

  const MapCoordinatePicker({
    Key? key,
    required this.address,
  }) : super(key: key);

  @override
  State<MapCoordinatePicker> createState() => _MapCoordinatePickerState();
}

class _MapCoordinatePickerState extends State<MapCoordinatePicker> {
  late NaverMapController _mapController;
  NLatLng? _selectedLocation;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('위치 선택'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          TextButton(
            onPressed: _selectedLocation != null
                ? () {
              Navigator.pop(
                context,
                GeoPoint(
                  _selectedLocation!.latitude,
                  _selectedLocation!.longitude,
                ),
              );
            }
                : null,
            style: TextButton.styleFrom(
              foregroundColor: Colors.black,
            ),
            child: Text('선택'),
          ),
        ],
      ),
      body: Stack(
        children: [
          NaverMap(
            options: NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: NLatLng(37.5665, 126.9780), // 서울 시청 기본 위치
                zoom: 15,
              ),
              mapType: NMapType.basic,
            ),
            onMapReady: (controller) {
              _mapController = controller;
              _searchAddress();
            },
            onCameraIdle: () async {
              final cameraPosition = await _mapController.getCameraPosition();
              setState(() {
                _selectedLocation = cameraPosition.target;
              });
            },
          ),
          // 중앙 마커
          Center(
            child: Icon(
              Icons.location_on,
              color: const Color(0xFF1066FF), // primary color로 변경
              size: 36,
            ),
          ),
          // 현재 좌표 표시
          if (_selectedLocation != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  '위도: ${_selectedLocation!.latitude.toStringAsFixed(6)}\n경도: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _searchAddress() async {
    setState(() => _isLoading = true);
    try {
      // 주소 정제
      String refinedAddress = widget.address
          .replaceAll(RegExp(r'\s+'), ' ') // 중복 공백 제거
          .trim();

      // 괄호와 그 안의 내용 제거 (예: "서울특별시 강남구 테헤란로 152 (강남파이낸스센터)" -> "서울특별시 강남구 테헤란로 152")
      if (refinedAddress.contains('(')) {
        refinedAddress = refinedAddress.split('(')[0].trim();
      }

      final String apiUrl = 'https://naveropenapi.apigw.ntruss.com/map-geocode/v2/geocode';
      final response = await http.get(
        Uri.parse('$apiUrl?query=${Uri.encodeComponent(refinedAddress)}&coordinate=latlng'),
        headers: {
          'X-NCP-APIGW-API-KEY-ID': '5k1r2vy3lz',
          'X-NCP-APIGW-API-KEY': 'W6McBwHf5CFEVZpfz1DSuc2DdzTNC8Ks0l1paU4P',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['addresses'] != null && data['addresses'].isNotEmpty) {
          final location = data['addresses'][0];

          // 도로명 주소와 지번 주소 중 더 정확한 것 선택
          String roadAddress = location['roadAddress'] ?? '';
          String jibunAddress = location['jibunAddress'] ?? '';
          double distance = double.infinity;
          NLatLng targetLatLng;

          // 입력된 주소와 가장 유사한 결과 선택
          if (roadAddress.contains(refinedAddress) ||
              refinedAddress.contains(roadAddress)) {
            targetLatLng = NLatLng(
              double.parse(location['y']),
              double.parse(location['x']),
            );
          } else if (jibunAddress.contains(refinedAddress) ||
              refinedAddress.contains(jibunAddress)) {
            targetLatLng = NLatLng(
              double.parse(location['y']),
              double.parse(location['x']),
            );
          } else {
            // 주소 문자열 유사도로 가장 가까운 결과 선택
            targetLatLng = NLatLng(
              double.parse(location['y']),
              double.parse(location['x']),
            );
          }

          await _mapController.updateCamera(
            NCameraUpdate.withParams(
              target: targetLatLng,
              zoom: 17, // 줌 레벨을 높여서 더 자세히 보이도록 함
            ),
          );

          // 선택된 위치 업데이트
          setState(() {
            _selectedLocation = targetLatLng;
          });

          print('Found location: ${location['roadAddress']}');
          print('Selected coordinates: ${targetLatLng.latitude}, ${targetLatLng.longitude}');
        } else {
          print('No matching address found');

          // 정확한 주소를 찾지 못한 경우, 주소를 분할하여 재시도
          List<String> addressParts = refinedAddress.split(' ');
          if (addressParts.length > 2) {
            String simplifiedAddress = addressParts.take(3).join(' ');
            final retryResponse = await http.get(
              Uri.parse('$apiUrl?query=${Uri.encodeComponent(simplifiedAddress)}'),
              headers: {
                'X-NCP-APIGW-API-KEY-ID': '5k1r2vy3lz',
                'X-NCP-APIGW-API-KEY': 'W6McBwHf5CFEVZpfz1DSuc2DdzTNC8Ks0l1paU4P',
              },
            );

            final retryData = json.decode(retryResponse.body);
            if (retryData['addresses'] != null && retryData['addresses'].isNotEmpty) {
              final retryLocation = retryData['addresses'][0];
              final retryLatLng = NLatLng(
                double.parse(retryLocation['y']),
                double.parse(retryLocation['x']),
              );

              await _mapController.updateCamera(
                NCameraUpdate.withParams(
                  target: retryLatLng,
                  zoom: 16,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      print('주소 검색 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
}