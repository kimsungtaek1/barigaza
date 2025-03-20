import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import '../widgets/ad_banner_widget.dart';
import 'home_screen.dart';

class MyCarScreen5 extends StatefulWidget {
  final String manufacturer;
  final String? carNumber;
  final String carName;

  const MyCarScreen5({
    Key? key,
    required this.manufacturer,
    this.carNumber,
    required this.carName,
  }) : super(key: key);

  @override
  State<MyCarScreen5> createState() => _MyCarScreen5State();
}

class _MyCarScreen5State extends State<MyCarScreen5> {
  final TextEditingController _mileageController = TextEditingController();
  
  // 제조사 이름 매핑 - 한글명과 영문명
  Map<String, Map<String, String>> _manufacturerNameMap = {
    'honda': {'kor': '혼다', 'eng': 'Honda'},
    'yamaha': {'kor': '야마하', 'eng': 'Yamaha'},
    'suzuki': {'kor': '스즈키', 'eng': 'Suzuki'},
    'kawasaki': {'kor': '가와사키', 'eng': 'Kawasaki'},
    'bmw': {'kor': 'BMW Motorrad', 'eng': ''},
    'ducati': {'kor': '두카티', 'eng': 'Ducati'},
    'triumph': {'kor': '트라이엄프', 'eng': 'Triumph'},
    'ktm': {'kor': 'KTM', 'eng': ''},
    'royal_enfield': {'kor': '로얄 엔필드', 'eng': 'Royal Enfield'},
    'vespa': {'kor': '베스파', 'eng': 'Vespa'},
  };

  @override
  void dispose() {
    _mileageController.dispose();
    super.dispose();
  }
  
  // Helper method to get display name
  String _getManufacturerDisplayName(String manufacturerId) {
    final manufacturerInfo = _manufacturerNameMap[manufacturerId.toLowerCase()];
    if (manufacturerInfo == null) return manufacturerId;
    
    final korName = manufacturerInfo['kor'] ?? '';
    final engName = manufacturerInfo['eng'] ?? '';
    
    if (engName.isEmpty) return korName;
    return '$korName($engName)';
  }

  Future<void> _saveBikeInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('로그인이 필요합니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 주행거리 값 파싱
      int currentMileage = 0;
      if (_mileageController.text.isNotEmpty) {
        currentMileage = int.tryParse(_mileageController.text) ?? 0;
      }

      // Firestore에 바이크 정보 저장
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'bikeManufacturer': widget.manufacturer,
        'bikeName': widget.carName,
        'hasBikeInfo': true,
        'currentMileage': currentMileage,  // 입력받은 주행거리 값 사용
        'lastUpdated': FieldValue.serverTimestamp(),
        // 초기 교체 주기 설정
        'lastMaintenance': {
          'engineOil': {
            'date': DateTime.now().toIso8601String(),
            'mileage': currentMileage,
          },
          'oilFilter': {
            'date': DateTime.now().toIso8601String(),
            'mileage': currentMileage,
          },
          'chain': {
            'date': DateTime.now().toIso8601String(),
            'mileage': currentMileage,
          },
          'battery': {
            'date': DateTime.now().toIso8601String(),
            'mileage': currentMileage,
          },
          'sparkPlug': {
            'date': DateTime.now().toIso8601String(),
            'mileage': currentMileage,
          },
        },
      });

      if (mounted) {
        // 성공 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('차량 정보가 등록되었습니다.'),
            backgroundColor: Colors.green,
          ),
        );
        // 내 차 화면으로 이동
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const HomeScreen(initialIndex: 2),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('차량 정보 등록에 실패했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '내 차량 등록',
          style: TextStyle(color: Colors.black, fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '차량 정보를 확인해 주세요.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                '제조사',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getManufacturerDisplayName(widget.manufacturer),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '모델',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.carName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 주행거리 입력 영역
              const Text(
                '현재 주행거리 (km)',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _mileageController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '현재 주행거리 입력 (km)',
                    suffixText: 'km',
                  ),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveBikeInfo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF746B5D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '완료',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const AdBannerWidget(),
            ],
          ),
        ),
      ),
    );
  }
}