// my_car_screen2.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/ad_banner_widget.dart';
import '../services/car_model_service.dart';
import '../models/car_model.dart';
import '../utils/manufacturer_names.dart';
import 'my_car_screen3.dart';
import 'my_car_screen_direct.dart';

class MyCarScreen2 extends StatefulWidget {
  final String? carNumber;

  const MyCarScreen2({Key? key, this.carNumber}) : super(key: key);

  @override
  State<MyCarScreen2> createState() => _MyCarScreen2State();
}

class _MyCarScreen2State extends State<MyCarScreen2> {
  final CarModelService _carModelService = CarModelService();
  bool _isLoading = true;
  List<CarManufacturer> _manufacturers = [];

  @override
  void initState() {
    super.initState();
    _loadManufacturers();
  }
  
  void _loadManufacturers() {
    setState(() {
      _isLoading = true;
    });
    
    // manufacturer_names.dart에서 제조사 목록 가져오기
    final List<CarManufacturer> manufacturers = [];
    
    // manufacturerNameMap의 각 키(제조사 ID)와 값(제조사 정보)을 순회
    manufacturerNameMap.forEach((id, info) {
      manufacturers.add(CarManufacturer(
        id: id,
        name: info['kor'] ?? id, // 한글 이름 사용, 없으면 ID 사용
      ));
    });
    
    setState(() {
      _manufacturers = manufacturers;
      _isLoading = false;
    });
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
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '차량 제조사를 선택해 주세요.',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _isLoading
                ? Expanded(
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                : Expanded(
                    child: _manufacturers.isEmpty
                        ? Center(
                            // 새로고침 버튼 레이아웃 및 스타일 수정
                            child: Padding( // 좌우 패딩 추가
                              padding: const EdgeInsets.symmetric(horizontal: 20.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('등록된 차량 제조사가 없습니다.'),
                                  SizedBox(height: 16),
                                  SizedBox( // 버튼 너비 전체로 확장
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: _loadManufacturers,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context).primaryColor, // Primary color로 변경
                                        foregroundColor: Colors.white, // 텍스트 색상 흰색으로
                                        padding: const EdgeInsets.symmetric(vertical: 15), // 다른 버튼과 패딩 맞춤
                                        shape: RoundedRectangleBorder( // 다른 버튼과 모양 맞춤
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: Text('새로고침'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : GridView.builder(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 20,
                              crossAxisSpacing: 20,
                              childAspectRatio: 0.75,
                            ),
                            itemCount: _manufacturers.length + 1, // +1 for direct registration button
                            itemBuilder: (context, index) {
                              if (index == _manufacturers.length) {
                                // 마지막 아이템은 직접등록 버튼
                                return _buildBrandButton(
                                  context, 
                                  '직접 등록', 
                                  '', 
                                  'add_icon.png'
                                );
                              } else {
                                final manufacturer = _manufacturers[index];
                                final logoFile = manufacturerNameMap[manufacturer.id.toLowerCase()]?['logo'] ?? 'brg_logo.png';
                                
                                return _buildManufacturerButton(
                                  context,
                                  manufacturer.name,
                                  manufacturer.id,
                                  logoFile,
                                );
                              }
                            },
                          ),
                  ),
            const SizedBox(height: 20),
            const AdBannerWidget(),
          ],
        ),
      ),
    );
  }

  Widget _buildManufacturerButton(BuildContext context, String name, String id, String logoPath) {
    // 매핑된 제조사 이름이 있으면 사용하고, 없으면 기존 이름 사용
    final manufacturerInfo = manufacturerNameMap[id.toLowerCase()];
    final korName = manufacturerInfo?['kor'] ?? name;
    final engName = manufacturerInfo?['eng'] ?? '';
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MyCarScreen3(
              manufacturer: id,
              carNumber: widget.carNumber,
            ),
          ),
        );
      },
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Image.asset(
                'assets/images/$logoPath',
                width: 60,
                height: 60,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            korName,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (engName.isNotEmpty)
            Text(
              '($engName)',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _buildBrandButton(BuildContext context, String korName, String engName, String logoPath) {
    return GestureDetector(
      onTap: () {
        if (engName.isEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MyCarScreenDirect()),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MyCarScreen3(
                manufacturer: engName,
                carNumber: widget.carNumber,
              ),
            ),
          );
        }
      },
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Image.asset(
                'assets/images/$logoPath',
                width: 60,
                height: 60,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            korName,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          if (engName.isNotEmpty)
            Text(
              '($engName)',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
