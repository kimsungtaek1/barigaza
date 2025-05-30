import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/maintenance_period.dart';
import '../models/maintenance_record.dart';
import '../screens/fuel_record_screen.dart';
import '../screens/home_screen.dart';
import '../services/maintenance_service.dart';
import '../services/maintenance_tracking_service.dart';
import '../services/storage_service.dart';
import '../utils/manufacturer_names.dart';

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

  // Remove the local map definition

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

      if (mounted) { // Add mounted check
        setState(() {
          _isLoading = true;
          _tempBikeImage = image.path;
        });
      } else {
        return; // Exit if not mounted
      }

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
      if (mounted) { // Add mounted check
        setState(() => _isLoading = false);
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists && mounted) { // Add mounted check here
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
          .limit(10) // 최근 10개 기록만 사용
          .get();

      double totalEfficiency = 0.0;
      int validRecords = 0;

      for (var doc in records.docs) {
        final data = doc.data();
        // 각 기록에서 주행거리(distance)와 주유량(amount) 확인
        if (data.containsKey('distance') && data.containsKey('amount')) {
          final distance = data['distance'] is int
              ? (data['distance'] as int).toDouble()
              : data['distance'] as double;

          final amount = data['amount'] is int
              ? (data['amount'] as int).toDouble()
              : data['amount'] as double;

          // 유효한 데이터만 계산에 포함
          if (distance > 0 && amount > 0) {
            final efficiency = distance / amount;
            totalEfficiency += efficiency;
            validRecords++;
          }
        }
      }

      // 유효한 기록이 없으면 0 반환
      return validRecords > 0 ? totalEfficiency / validRecords : 0.0;
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
                  Builder( // Builder 위젯을 사용하여 context 접근 및 로직 처리
                    builder: (context) {
                      final manufacturerId = _userData['bikeManufacturer']?.toString().toLowerCase();
                      String manufacturerDisplayName = '제조사 미등록'; // 기본값

                      if (manufacturerId != null) {
                        // Use the imported map
                        final manufacturerInfo = manufacturerNameMap[manufacturerId];
                        if (manufacturerInfo != null) {
                          final engName = manufacturerInfo['eng'];
                          final korName = manufacturerInfo['kor'];
                          // 영어 이름 우선 사용, 없으면 한글 이름, 그것도 없으면 ID 사용
                          manufacturerDisplayName = (engName != null && engName.isNotEmpty)
                              ? engName
                              : (korName ?? manufacturerId);
                        } else {
                          // 맵에 없는 경우 ID 그대로 사용 (혹은 다른 기본값 설정 가능)
                          manufacturerDisplayName = manufacturerId;
                        }
                      }

                      return Text(
                        '$manufacturerDisplayName ${_userData['bikeName'] ?? '차량 미등록'}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '누적 주행거리: ',
                        style: TextStyle(
                            fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${(_userData['currentMileage'] ?? 0).toString()} km',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
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
                        fontSize: 16,
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
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                SizedBox(height: 12),
                // 주유 기록 카드 부분 수정
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

                          return GestureDetector(
                            onTap: () async {
                              try {
                                // 해당 레코드의 ID 가져오기
                                final user = FirebaseAuth.instance.currentUser;
                                if (user == null) return;

                                final querySnapshot = await _firestore
                                    .collection('users')
                                    .doc(user.uid)
                                    .collection('fuel_records')
                                    .orderBy('date', descending: true)
                                    .limit(5)
                                    .get();

                                if (index < querySnapshot.docs.length) {
                                  final recordId = querySnapshot.docs[index].id;

                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => FuelRecordScreen(recordId: recordId),
                                    ),
                                  );

                                  if (result == true) {
                                    if (mounted) {
                                      // 데이터를 완전히 새로고침
                                      setState(() => _isLoading = true);
                                      await _loadData();
                                      if (mounted) {
                                        setState(() => _isLoading = false);
                                      }
                                    }
                                  }
                                }
                              } catch (e) {
                                print('Error opening fuel record: $e');
                              }
                            },
                            child: Card(
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
                                      // 연비 표시 - 저장된 값이 있으면 사용하고 없으면 계산
                                      record.containsKey('fuelEfficiency')
                                          ? '${record['fuelEfficiency'].toStringAsFixed(1)} km/L'
                                          : '${(record['distance'] / record['amount']).toStringAsFixed(1)} km/L',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
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
                          if (mounted) {
                            // 데이터를 완전히 새로고침
                            setState(() => _isLoading = true);
                            await _loadData();
                            if (mounted) {
                              setState(() => _isLoading = false);
                            }
                          }
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
        SizedBox(height: 32), // 부품 목록과 삭제 버튼 사이 간격
        // 차량 삭제 버튼 추가
        InkWell(
          onTap: _handleDeleteVehicle,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 16), // 상하 패딩 추가
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end, // 우측 정렬
              children: [
                Icon(Icons.delete_outline, color: Colors.red[400], size: 20), // 아이콘 변경 및 색상 조정
                SizedBox(width: 8),
                Text(
                  '차량 삭제',
                  style: TextStyle(
                    color: Colors.red[400], // 색상 조정
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 16), // 하단 여백
      ],
    );
  }

  // 차량 삭제 처리 함수 추가
  Future<void> _handleDeleteVehicle() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('차량 삭제 확인'),
        content: Text('정말로 차량 정보를 삭제하시겠습니까? 이 작업은 복구할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('로그인이 필요합니다.');

      final userId = user.uid;
      final userDocRef = _firestore.collection('users').doc(userId);
      final batch = _firestore.batch();

      // 1. users 문서에서 차량 관련 필드 삭제
      batch.update(userDocRef, {
        'bikeManufacturer': FieldValue.delete(),
        'bikeName': FieldValue.delete(),
        'bikeImage': FieldValue.delete(),
        'currentMileage': FieldValue.delete(),
        'lastMaintenance': FieldValue.delete(),
        'hasBikeInfo': false, // hasBikeInfo 필드를 false로 업데이트 추가
        // 필요에 따라 다른 차량 관련 필드도 추가
      });

      // 2. maintenance_periods 하위 컬렉션 삭제
      final maintenancePeriodsSnapshot = await userDocRef.collection('maintenance_periods').get();
      for (var doc in maintenancePeriodsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // 3. fuel_records 하위 컬렉션 삭제
      final fuelRecordsSnapshot = await userDocRef.collection('fuel_records').get();
      for (var doc in fuelRecordsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // 4. Batch 작업 실행
      await batch.commit();

      // 5. 로컬 데이터 초기화 및 UI 갱신
      // await _loadUserData(); // 삭제 후에는 데이터를 다시 로드할 필요 없음

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('차량 정보가 삭제되었습니다.')),
        );
        // HomeScreen의 '내 차' 탭(인덱스 2)으로 이동하고 이전 경로 모두 제거
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen(initialIndex: 2)), // HomeScreen으로 이동하고 initialIndex 2 설정
          (Route<dynamic> route) => false, // 모든 이전 라우트 제거
        );
      }

    } catch (e) {
      print('차량 삭제 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('차량 정보 삭제에 실패했습니다: ${e.toString()}')),
        );
      }
    }
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => _showMaintenanceHistoryDialog(title, partType),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.3),
                      spreadRadius: 1,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  IntrinsicHeight(
                    child: Row(
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
                              vertical: 0,
                            ),
                            minimumSize: Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: const Text('교체'),
                        ),
                        Spacer(),
                      ],
                    ),
                  ),
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.grey[300],
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    progress > 0.9 ? Colors.red : Color(0xFF1066FF),
                                  ),
                                  minHeight: 6,
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
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _showPeriodUpdateDialog(partType),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F3ED),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '주기설정',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IntrinsicHeight(
                    child: Row(
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
                if (mounted) { // Add mounted check
                  setState(() {}); // 상태 갱신을 위해 추가
                }
                await _loadMaintenancePeriods(); // This already checks mounted internally

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
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 20.0, bottom: 16.0),
                child: Center(
                  child: Text(
                    '교체 주기 설정',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '주행거리 주기(km)',
                          style: TextStyle(fontSize: 14),
                        ),
                        Container(
                          width: 100,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: TextField(
                            controller: kmController,
                            textAlign: TextAlign.right,
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              border: InputBorder.none,
                              hintText: '숫자 입력',
                              hintStyle: TextStyle(fontSize: 13),
                            ),
                            style: TextStyle(fontSize: 14),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          ),
                        ),
                      ],
                    ),
                    if (partType == 'oilFilter' || partType == 'battery')
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '시간 주기(개월)',
                              style: TextStyle(fontSize: 14),
                            ),
                            Container(
                              width: 100,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade400),
                              ),
                              child: TextField(
                                controller: monthController,
                                textAlign: TextAlign.right,
                                decoration: InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  border: InputBorder.none,
                                  hintText: '숫자 입력',
                                  hintStyle: TextStyle(fontSize: 13),
                                ),
                                style: TextStyle(fontSize: 14),
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              ),
                            ),
                          ],
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
                            bottomLeft: Radius.circular(12),
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
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          borderRadius: BorderRadius.only(
                            bottomRight: Radius.circular(12),
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
