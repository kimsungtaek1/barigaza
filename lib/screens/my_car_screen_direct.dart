// my_car_screen_direct.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../widgets/ad_banner_widget.dart';
import '../utils/manufacturer_names.dart';
import 'home_screen.dart';

class MyCarScreenDirect extends StatefulWidget {
  final String? manufacturer; // 제조사 정보 추가
  final String? carNumber;

  const MyCarScreenDirect({
    Key? key, 
    this.manufacturer,
    this.carNumber,
  }) : super(key: key);

  @override
  _MyCarScreenDirectState createState() => _MyCarScreenDirectState();
}

class _MyCarScreenDirectState extends State<MyCarScreenDirect> {
  // 제조사가 이미 선택된 경우 모델 입력부터 시작
  late int _currentStep;
  late int _totalSteps;

  // 단계별 입력값 컨트롤러
  // step 1: 차량 이름 (bikeName)
  final TextEditingController _modelController1 = TextEditingController();
  // step 2: 제조사 (bikeManufacturer)
  final TextEditingController _manufacturerController = TextEditingController();
  // step 3: 현재 주행거리
  final TextEditingController _mileageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 제조사가 이미 선택된 경우 모델 입력부터 시작
    if (widget.manufacturer != null) {
      _currentStep = 1;
      _totalSteps = 2; // 제조사 입력 단계 제외
      
      // 제조사 ID를 사용하여 영어 이름 가져오기
      final manufacturerInfo = manufacturerNameMap[widget.manufacturer!.toLowerCase()];
      if (manufacturerInfo != null && manufacturerInfo['eng'] != null) {
        _manufacturerController.text = manufacturerInfo['eng']!;
      } else {
        _manufacturerController.text = widget.manufacturer!;
      }
    } else {
      _currentStep = 1;
      _totalSteps = 3; // 모든 단계 포함
    }
  }

  @override
  void dispose() {
    _modelController1.dispose();
    _manufacturerController.dispose();
    _mileageController.dispose();
    super.dispose();
  }

  // 회원 정보(차량 정보) 업데이트 함수
  Future<void> _saveBikeInfo() async {
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

      // 현재 주행거리 파싱
      int currentMileage = 0;
      if (_mileageController.text.isNotEmpty) {
        currentMileage = int.tryParse(_mileageController.text) ?? 0;
      }

      // Firestore에 차량 정보 업데이트
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'bikeManufacturer': _manufacturerController.text.trim(),
        'bikeName': _modelController1.text.trim(),
        'hasBikeInfo': true,
        'currentMileage': currentMileage, // 입력받은 주행거리 설정
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

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('차량 정보가 등록되었습니다.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const HomeScreen(initialIndex: 2),
          ),
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

  // 다음 단계 이동 로직 수정 (총 3단계)
  void _nextStep() {
    if (_currentStep < _totalSteps) {
      setState(() {
        _currentStep++;
      });
    }
    // 3단계에서 완료 버튼 누르면 _saveBikeInfo 호출됨 (아래 _buildMileageInputStep 참고)
  }

  void _previousStep() {
    if (_currentStep > 1) {
      setState(() {
        _currentStep--;
      });
    } else {
      Navigator.pop(context);
    }
  }

  Widget _buildStepContent() {
    // 제조사가 이미 선택된 경우
    if (widget.manufacturer != null) {
      switch (_currentStep) {
        case 1:
          return _buildInputStep(
            label: '모델을 입력해 주세요.',
            controller: _modelController1,
            hintText: '차량 이름 입력',
          );
        case 2:
          return _buildMileageInputStep(); // 2단계에서 완료 처리
        default:
          return Container();
      }
    } else {
      // 기존 로직 (제조사부터 입력)
      switch (_currentStep) {
        case 1:
          return _buildInputStep(
            label: '모델을 입력해 주세요.',
            controller: _modelController1,
            hintText: '차량 이름 입력',
          );
        case 2:
          return _buildInputStep(
            label: '제조사를 입력해 주세요.',
            controller: _manufacturerController,
            hintText: '제조사 입력',
          );
        case 3:
          return _buildMileageInputStep(); // 3단계에서 완료 처리
        default:
          return Container();
      }
    }
  }

  Widget _buildInputStep({
    required String label,
    required TextEditingController controller,
    required String hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 단계 제목
        Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 30),
        // 입력 필드 (MyCarScreen5와 유사한 스타일)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              isDense: true,
              fillColor: Colors.grey[100],
              filled: true,
            ),
          ),
        ),
        const SizedBox(height: 40),
        // 다음 버튼
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('입력을 해주세요.'),
                    backgroundColor: Colors.red,
                  ),
                );
              } else {
                _nextStep();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor, // Primary color로 변경
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              '다음',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 3단계 UI 수정: 제조사, 모델 표시 및 완료 버튼으로 변경
  Widget _buildMileageInputStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '차량 정보를 확인하고 주행거리를 입력해 주세요.', // 안내 문구 수정
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 30),
        // 제조사 정보 표시
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
            _manufacturerController.text.trim(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 20),
        // 모델 정보 표시
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
            _modelController1.text.trim(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 20),
        // 주행거리 입력
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
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: '현재 주행거리 입력 (km)',
              suffixText: 'km',
              contentPadding: EdgeInsets.zero,
              isDense: true,
              fillColor: Colors.grey[100],
              filled: true,
            ),
          ),
        ),
        const SizedBox(height: 40),
        // 완료 버튼
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saveBikeInfo, // 바로 저장 함수 호출
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              '완료', // 버튼 텍스트 변경
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 4단계 제거
  // Widget _buildCompletionStep() { ... }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: _previousStep,
        ),
        title: Text(
          widget.manufacturer != null 
              ? '모델 직접 등록' 
              : '내 차량 등록 (직접 등록)',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 16,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepContent(),
              const SizedBox(height: 20),
              // 광고 배너 영역
              const AdBannerWidget(),
            ],
          ),
        ),
      ),
    );
  }
}
