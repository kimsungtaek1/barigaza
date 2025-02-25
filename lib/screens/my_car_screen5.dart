import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/ad_banner_widget.dart';

class MyCarScreen5 extends StatelessWidget {
  final String manufacturer;
  final String? carNumber;
  final String carName;
  final String modelName;

  const MyCarScreen5({
    Key? key,
    required this.manufacturer,
    this.carNumber,
    required this.carName,
    required this.modelName,
  }) : super(key: key);

  Future<void> _saveBikeInfo(BuildContext context) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('로그인이 필요합니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Firestore에 바이크 정보 저장
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'bikeManufacturer': manufacturer,
        'bikeNumber': carNumber,
        'bikeName': carName,
        'bikeModel': modelName,
        'hasBikeInfo': true,
        'currentMileage': 0,  // 초기 주행거리 0으로 설정
        'lastUpdated': FieldValue.serverTimestamp(),
        // 초기 교체 주기 설정
        'lastMaintenance': {
          'engineOil': {
            'date': DateTime.now().toIso8601String(),
            'mileage': 0,
          },
          'oilFilter': {
            'date': DateTime.now().toIso8601String(),
            'mileage': 0,
          },
          'chain': {
            'date': DateTime.now().toIso8601String(),
            'mileage': 0,
          },
          'battery': {
            'date': DateTime.now().toIso8601String(),
            'mileage': 0,
          },
          'sparkPlug': {
            'date': DateTime.now().toIso8601String(),
            'mileage': 0,
          },
        },
      });

      if (context.mounted) {
        // 성공 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('차량 정보가 등록되었습니다.'),
            backgroundColor: Colors.green,
          ),
        );
        // 홈 화면으로 이동
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/home', // 홈 화면의 라우트 이름
              (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
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
              if (carNumber != null) ...[
                const Text(
                  '차량 번호',
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
                    carNumber!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
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
                  manufacturer,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '차량 이름',
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
                  carName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '모델명',
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
                  modelName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _saveBikeInfo(context),
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