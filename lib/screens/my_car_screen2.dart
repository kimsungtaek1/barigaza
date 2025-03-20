// my_car_screen2.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/ad_banner_widget.dart';
import '../services/car_model_service.dart';
import '../models/car_model.dart';
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
  Map<String, String> _logoMap = {
    'honda': 'honda_logo.png',
    'yamaha': 'yamaha_logo.png',
    'suzuki': 'suzuki_logo.png',
    'kawasaki': 'kawasaki_logo.png',
    'bmw': 'bmw_logo.png',
    'ducati': 'ducati_logo.png',
    'triumph': 'triumph_logo.png',
    'ktm': 'ktm_logo.png',
    'royal_enfield': 'royal_enfield_logo.png',
    'vespa': 'vespa_logo.png',
  };

  @override
  void initState() {
    super.initState();
    _loadManufacturers();
  }

  Future<void> _loadManufacturers() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Firestore에서 데이터 불러오기
      final allManufacturers = await _carModelService.getManufacturers();
      
      // Firestore에 데이터가 없으면 JSON에서 마이그레이션
      if (allManufacturers.isEmpty) {
        await _migrateDataFromJson();
        final updatedManufacturers = await _carModelService.getManufacturers();
        
        // _logoMap에 있는 제조사만 필터링
        final filteredManufacturers = updatedManufacturers.where((manufacturer) => 
          _logoMap.containsKey(manufacturer.id.toLowerCase())).toList();
        
        setState(() {
          _manufacturers = filteredManufacturers;
          _isLoading = false;
        });
      } else {
        // _logoMap에 있는 제조사만 필터링
        final filteredManufacturers = allManufacturers.where((manufacturer) => 
          _logoMap.containsKey(manufacturer.id.toLowerCase())).toList();
        
        setState(() {
          _manufacturers = filteredManufacturers;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading manufacturers: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _migrateDataFromJson() async {
    try {
      // Firestore에서 제조사 목록 가져오기
      final firestore = FirebaseFirestore.instance;
      final manufacturersSnapshot = await firestore.collection('car_manufacturers').get();
      
      if (manufacturersSnapshot.docs.isEmpty) {
        print('No manufacturers found in Firestore');
        return;
      }
      
      // 제조사와 모델 매핑 구성
      final Map<String, List<Map<String, dynamic>>> data = {};
      
      // 각 제조사에 대한 데이터 구성
      for (final doc in manufacturersSnapshot.docs) {
        final manufacturer = doc.data();
        final manufacturerName = manufacturer['name'];
        
        // 초기에는 모든 제조사에 대해 빈 모델 리스트 설정
        data[manufacturerName] = [];
      }
      
      // 마이그레이션 수행
      if (data.isNotEmpty) {
        await _carModelService.migrateFromJson(data);
      }
    } catch (e) {
      print('Error migrating data: $e');
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
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('등록된 차량 제조사가 없습니다.'),
                                SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadManufacturers,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF746B5D),
                                  ),
                                  child: Text('새로고침'),
                                ),
                              ],
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
                                final logoFile = _logoMap[manufacturer.id.toLowerCase()] ?? 'brg_logo.png';
                                
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
            name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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