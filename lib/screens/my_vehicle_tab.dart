import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/maintenance_period.dart';
import '../models/maintenance_record.dart';
import '../services/maintenance_service.dart';
import '../services/maintenance_tracking_service.dart';
import '../services/storage_service.dart';

class MyVehicleTab extends StatefulWidget {
  @override
  _MyVehicleTabState createState() => _MyVehicleTabState();
}

class _MyVehicleTabState extends State<MyVehicleTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;
  Map<String, dynamic> _userData = {};
  Map<String, MaintenancePeriod> _maintenancePeriods = {};
  String? _tempBikeImage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _updateBikeImage() async {
    try {
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text('차량 이미지 선택'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('갤러리에서 선택'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('카메라로 촬영'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _isLoading = true;
        _tempBikeImage = image.path;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('사용자 인증 정보가 없습니다.');

      final bytes = await File(image.path).readAsBytes();
      final String fileExtension = image.path.split('.').last.toLowerCase();
      final String storagePath = 'bike_images/${user.uid}/bike.$fileExtension';

      final storageService = StorageService();
      final result = await storageService.uploadFile(
        path: storagePath,
        data: bytes,
        contentType: 'image/$fileExtension',
        customMetadata: {
          'uploadedBy': user.uid,
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'bike_image'
        },
      );

      if (result.isSuccess && result.data != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'bikeImage': result.data,
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        setState(() {
          _userData['bikeImage'] = result.data;
          _isLoading = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('차량 이미지가 업데이트되었습니다')),
          );
        }
      } else {
        throw Exception(result.error ?? '이미지 업로드에 실패했습니다.');
      }
    } catch (e) {
      print('차량 이미지 업데이트 실패: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('이미지 업로드에 실패했습니다. 잠시 후 다시 시도해주세요.')),
        );
      }
    }
  }

  Future<void> _loadData() async {
    try {
      await Future.wait([
        _loadUserData(),
        _loadMaintenancePeriods(),
      ]);
      setState(() => _isLoading = false);
    } catch (e) {
      print('Error loading data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          setState(() {
            _userData = doc.data() as Map<String, dynamic>;
          });
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Future<void> _loadMaintenancePeriods() async {
    try {
      final maintenanceService = MaintenanceService(
        userId: FirebaseAuth.instance.currentUser!.uid,
      );

      Map<String, MaintenancePeriod> periods = {};
      for (String partType in [
        'engineOil',
        'oilFilter',
        'chain',
        'battery',
        'sparkPlug'
      ]) {
        final period = await maintenanceService.getMaintenancePeriod(partType);
        if (period != null) {
          periods[partType] = period;
        }
      }

      if (mounted) {
        setState(() {
          _maintenancePeriods = periods;
        });
      }
    } catch (e) {
      print('Error loading maintenance periods: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('교체 주기 정보를 불러오는데 실패했습니다')),
        );
      }
    }
  }

  Future<double> _calculateProgress(String partType) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 0.0;

      final currentUser =
      await _firestore.collection('users').doc(user.uid).get();
      final currentMileage =
      double.parse((currentUser.data()?['currentMileage'] ?? '0').toString());

      // 마지막 교체 시점의 주행거리 가져오기
      final lastMaintenance = currentUser.data()?['lastMaintenance']?[partType];
      final lastMaintenanceMileage = lastMaintenance != null
          ? double.parse(lastMaintenance['mileage'].toString())
          : 0.0;

      final periodDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('maintenance_periods')
          .doc(partType)
          .get();

      final period = periodDoc.exists
          ? (periodDoc.data()?['kilometers'] as num).toInt()
          : getDefaultPeriod(partType);

      if (period <= 0) return 0.0;

      // 마지막 교체 이후 주행한 거리의 비율 계산
      final distanceSinceLastMaintenance = currentMileage - lastMaintenanceMileage;
      final progress = distanceSinceLastMaintenance / period;

      return progress.clamp(0.0, 1.0);
    } catch (e) {
      print('Error calculating progress for $partType: $e');
      return 0.0;
    }
  }

  int getDefaultPeriod(String partType) {
    switch (partType) {
      case 'engineOil':
        return 8000;
      case 'oilFilter':
        return 10000;
      case 'chain':
        return 8000;
      case 'battery':
        return 10000;
      case 'sparkPlug':
        return 8000;
      default:
        return 0;
    }
  }

  Future<double> _calculateAverageFuelEfficiency() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('로그인이 필요합니다');

      final records = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('fuel_records')
          .orderBy('date', descending: true)
          .get();

      double totalDistance = 0.0;
      double totalFuel = 0.0;

      for (var doc in records.docs) {
        final data = doc.data();
        final distance = data['distance'] is int
            ? (data['distance'] as int).toDouble()
            : data['distance'] as double;
        final amount = data['amount'] is int
            ? (data['amount'] as int).toDouble()
            : data['amount'] as double;

        totalDistance += distance;
        totalFuel += amount;
      }

      return totalFuel > 0 ? totalDistance / totalFuel : 0.0;
    } catch (e) {
      print('평균 연비 계산 중 오류 발생: $e');
      return 0.0;
    }
  }

  Future<List<Map<String, dynamic>>> _loadFuelRecords() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('로그인이 필요합니다');

      final records = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('fuel_records')
          .orderBy('date', descending: true)
          .limit(5)
          .get();

      List<Map<String, dynamic>> fuelRecords = [];
      for (var doc in records.docs) {
        final data = doc.data();
        final timestamp = data['date'] as Timestamp;
        
        // 추가 주행거리와 주유량을 사용하여 연비(km/L) 계산
        final distance = data['distance'] is int
          ? (data['distance'] as int).toDouble()
          : data['distance'] as double;
        
        final amount = data['amount'] is int
          ? (data['amount'] as int).toDouble()
          : data['amount'] as double;
        
        final fuelEfficiency = distance > 0 && amount > 0 
          ? distance / amount 
          : 0.0;
          
        fuelRecords.add({
          'date': timestamp.toDate().toIso8601String(),
          'amount': data['amount'],
          'cost': data['cost'],
          'distance': data['distance'],
          'pricePerLiter': data['cost'] / data['amount'],
          'fuelEfficiency': fuelEfficiency,
        });
      }
      return fuelRecords;
    } catch (e) {
      print('Error loading fuel records: $e');
      return [];
    }
  }

  Widget _buildBikeInfo() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '[${_userData['bikeManufacturer'] ?? '제조사 미등록'}] ${_userData['bikeName'] ?? '차량 미등록'}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '누적 주행거리: ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${(_userData['currentMileage'] ?? 0).toString()} km',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 20),
        GestureDetector(
          onTap: _updateBikeImage,
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              image: (_tempBikeImage != null)
                  ? DecorationImage(
                image: FileImage(File(_tempBikeImage!)),
                fit: BoxFit.cover,
              )
                  : (_userData['bikeImage'] != null
                  ? DecorationImage(
                image: NetworkImage(_userData['bikeImage']!),
                fit: BoxFit.cover,
              )
                  : null),
            ),
            child: (_tempBikeImage == null && _userData['bikeImage'] == null)
                ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.directions_bike, size: 64, color: Colors.grey),
                Text('차량 사진 추가', style: TextStyle(color: Colors.grey)),
              ],
            )
                : null,
          ),
        ),
        SizedBox(height: 16),
        Card(
          color: Colors.grey[100],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '최근 주유 기록',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    FutureBuilder<double>(
                      future: _calculateAverageFuelEfficiency(),
                      builder: (context, snapshot) {
                        return Text(
                          '평균연비: ${(snapshot.data ?? 0.0).toStringAsFixed(1)} km/L',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _loadFuelRecords(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    }
                    
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Card(
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(
                            child: Text('주유 기록이 없습니다'),
                          ),
                        ),
                      );
                    }
                    
                    return Container(
                      height: snapshot.data!.length > 2 ? 200 : null,
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: snapshot.data!.length > 2 
                          ? AlwaysScrollableScrollPhysics() 
                          : NeverScrollableScrollPhysics(),
                        itemCount: snapshot.data!.length,
                        itemBuilder: (context, index) {
                          final record = snapshot.data![index];
                          final date = DateTime.parse(record['date']);
                          final formattedDate = '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
                          
                          return Card(
                            margin: EdgeInsets.only(bottom: 8),
                            color: Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          formattedDate,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).primaryColor,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          '₩${record['cost'].toInt()} / ${record['amount'].toStringAsFixed(1)}L',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${record['fuelEfficiency'].toStringAsFixed(1)} km/L',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 150,
                    child: ElevatedButton(
                      onPressed: () async {
                        final result = await Navigator.pushNamed(context, '/fuel-record');
                        if (result == true) {
                          await _loadData();
                          setState(() {});
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        minimumSize: Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: Text(
                        '주유 기록하기',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 24),
        Text(
          '부품 교체 주기',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 12),
        _buildMaintenanceItems(),
      ],
    );
  }

  Widget _buildMaintenanceItems() {
    return Column(
      children: [
        FutureBuilder<double>(
          future: _calculateProgress('engineOil'),
          builder: (context, snapshot) {
            return _buildMaintenanceItem(
              image: 'assets/images/engine_oil.png',
              title: '엔진오일',
              subtitle: '${_maintenancePeriods['engineOil']?.kilometers ?? 10000}km마다 교체',
              progress: snapshot.data ?? 0.0,
              partType: 'engineOil',
            );
          },
        ),
        FutureBuilder<double>(
          future: _calculateProgress('oilFilter'),
          builder: (context, snapshot) {
            return _buildMaintenanceItem(
              image: 'assets/images/oil_filter.png',
              title: '엔진오일필터',
              subtitle: '${_maintenancePeriods['oilFilter']?.kilometers ?? 20000}km | ${_maintenancePeriods['oilFilter']?.months ?? 36}개월 마다 교체',
              progress: snapshot.data ?? 0.0,
              partType: 'oilFilter',
            );
          },
        ),
        FutureBuilder<double>(
          future: _calculateProgress('chain'),
          builder: (context, snapshot) {
            return _buildMaintenanceItem(
              image: 'assets/images/chain.png',
              title: '체인',
              subtitle: '${_maintenancePeriods['chain']?.kilometers ?? 8000}km마다 교체',
              progress: snapshot.data ?? 0.0,
              partType: 'chain',
            );
          },
        ),
        FutureBuilder<double>(
          future: _calculateProgress('battery'),
          builder: (context, snapshot) {
            return _buildMaintenanceItem(
              image: 'assets/images/battery.png',
              title: '배터리',
              subtitle: '${_maintenancePeriods['battery']?.kilometers ?? 10000}km | ${_maintenancePeriods['battery']?.months ?? 24}개월 마다 교체',
              progress: snapshot.data ?? 0.0,
              partType: 'battery',
            );
          },
        ),
        FutureBuilder<double>(
          future: _calculateProgress('sparkPlug'),
          builder: (context, snapshot) {
            return _buildMaintenanceItem(
              image: 'assets/images/spark_plug.png',
              title: '점화플러그',
              subtitle: '${_maintenancePeriods['sparkPlug']?.kilometers ?? 8000}km마다 교체',
              progress: snapshot.data ?? 0.0,
              partType: 'sparkPlug',
            );
          },
        ),
      ],
    );
  }

  Widget _buildMaintenanceItem({
    required String image,
    required String title,
    required String subtitle,
    required double progress,
    required String partType,
  }) {
    final period = _maintenancePeriods[partType];

    String periodText = '';
    if (period != null) {
      if (period.months != null) {
        periodText = '${period.kilometers}km | ${period.months}개월 마다 교체';
      } else {
        periodText = '${period.kilometers}km마다 교체';
      }
    } else {
      periodText = subtitle;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      color: Colors.grey[100],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _showMaintenanceHistoryDialog(title, partType),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Image.asset(
                    image,
                    width: 30,
                    height: 30,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 3),
                      ElevatedButton(
                        onPressed: () => _showMaintenanceResetDialog(title, partType),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF5F3ED),
                          foregroundColor: const Color(0xFF1066FF),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          minimumSize: Size(0, 0),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: const Text('교체'),
                      ),
                      Spacer(),
                      ElevatedButton(
                        onPressed: () => _showPeriodUpdateDialog(partType),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF5F3ED),
                          foregroundColor: const Color(0xFF1066FF),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          minimumSize: Size(0, 0),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: const Text('주기설정'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress > 0.9 ? Colors.red : Color(0xFF1066FF),
                          ),
                          minHeight: 4,
                        ),
                      ),
                      if (progress > 0.9)
                        Positioned(
                          right: 0,
                          top: -2,
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: Colors.red,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        periodText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (progress > 0.9)
                        Text(
                          '교체 필요',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMaintenanceResetDialog(String title, String partType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('부품 교체'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$title을(를) 교체하시겠습니까?'),
            SizedBox(height: 8),
            Text(
              '교체 시 교체 주기가 초기화됩니다.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.black,
            ),
            child: Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) throw Exception('로그인이 필요합니다');

                final maintenanceTrackingService = MaintenanceTrackingService(
                  userId: user.uid,
                );

                final currentMileage = double.parse(
                    (_userData['currentMileage'] ?? '0').toString());

                await maintenanceTrackingService.addMaintenanceRecord(
                  MaintenanceRecord(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    userId: user.uid,
                    partType: partType,
                    maintenanceDate: DateTime.now(),
                    currentMileage: currentMileage,
                  ),
                );

                await _firestore.collection('users').doc(user.uid).update({
                  'lastMaintenance.$partType': {
                    'date': DateTime.now().toIso8601String(),
                    'mileage': currentMileage,
                  }
                });

                Navigator.pop(context);
                setState(() {}); // 상태 갱신을 위해 추가
                await _loadMaintenancePeriods();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$title 교체가 완료되었습니다'),
                      backgroundColor: Color(0xFF1066FF),
                    ),
                  );
                }
              } catch (e) {
                print('Error resetting maintenance: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('부품 교체 기록에 실패했습니다'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF1066FF),
              foregroundColor: Colors.white,
            ),
            child: Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showMaintenanceHistoryDialog(String title, String partType) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final records = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('maintenance_records')
          .where('partType', isEqualTo: partType)
          .orderBy('maintenanceDate', descending: true)
          .limit(5)
          .get();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('$title 교체 이력'),
          content: Container(
            width: double.maxFinite,
            child: records.docs.isEmpty
                ? Center(
              child: Text(
                '교체 이력이 없습니다',
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
                : ListView.builder(
              shrinkWrap: true,
              itemCount: records.docs.length,
              itemBuilder: (context, index) {
                final record = records.docs[index].data();
                final date = DateTime.parse(record['maintenanceDate']);
                return ListTile(
                  leading: Icon(
                    Icons.build,
                    color: Color(0xFF1066FF),
                  ),
                  title: Text(
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    '주행거리: ${record['currentMileage'].toStringAsFixed(1)}km',
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.black,
              ),
              child: Text('닫기'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('Error loading maintenance history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('교체 이력을 불러오는데 실패했습니다')),
        );
      }
    }
  }

  void _showPeriodUpdateDialog(String partType) {
    final TextEditingController kmController = TextEditingController();
    final TextEditingController monthController = TextEditingController();

    final currentPeriod = _maintenancePeriods[partType];
    if (currentPeriod != null) {
      kmController.text = currentPeriod.kilometers.toString();
      if (currentPeriod.months != null) {
        monthController.text = currentPeriod.months.toString();
      }
    } else {
      switch (partType) {
        case 'engineOil':
          kmController.text = '10000';
          break;
        case 'oilFilter':
          kmController.text = '20000';
          monthController.text = '36';
          break;
        case 'chain':
          kmController.text = '8000';
          break;
        case 'battery':
          kmController.text = '10000';
          monthController.text = '24';
          break;
        case 'sparkPlug':
          kmController.text = '8000';
          break;
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('교체 주기 설정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '주행거리 주기 (km)',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            TextField(
              controller: kmController,
              decoration: InputDecoration(
                hintText: '숫자만 입력해주세요',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            if (partType == 'oilFilter' || partType == 'battery')
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '시간 주기 (개월)',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    TextField(
                      controller: monthController,
                      decoration: InputDecoration(
                        hintText: '숫자만 입력해주세요',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.black,
            ),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('로그인이 필요합니다')),
                  );
                  return;
                }

                final maintenanceService = MaintenanceService(userId: user.uid);

                await maintenanceService.updateMaintenancePeriod(
                  partType,
                  MaintenancePeriod(
                    kilometers: int.parse(kmController.text),
                    months: monthController.text.isNotEmpty
                        ? int.parse(monthController.text)
                        : null,
                  ),
                );

                Navigator.pop(context);
                await _loadMaintenancePeriods();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('교체 주기가 업데이트되었습니다')),
                  );
                }
              } catch (e) {
                print('Error updating period: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('교체 주기 업데이트에 실패했습니다')),
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.black,
            ),
            child: Text('저장'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }
    return Container(
      color: Colors.white,
      child: _buildBikeInfo(),
    );
  }
}
