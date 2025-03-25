import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fuel_record.dart';
import '../services/maintenance_tracking_service.dart';
import '../widgets/ad_banner_widget.dart';

class FuelRecordScreen extends StatefulWidget {
  final String? recordId;
  
  const FuelRecordScreen({
    Key? key,
    this.recordId,
  }) : super(key: key);

  @override
  State<FuelRecordScreen> createState() => _FuelRecordScreenState();
}

class _FuelRecordScreenState extends State<FuelRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _distanceController = TextEditingController(text: '0');
  final _amountController = TextEditingController(text: '0');
  final _priceController = TextEditingController(text: '0');
  final _memoController = TextEditingController();
  String? selectedFuelType = '휘발유';
  bool _isLoading = false;
  String? _recordId;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _recordId = widget.recordId;
    _isEditing = _recordId != null;
    
    if (_isEditing) {
      _loadExistingRecord();
    } else {
      _loadLastMileage();
    }
  }

  @override
  void dispose() {
    _distanceController.dispose();
    _amountController.dispose();
    _priceController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  double _previousMileage = 0.0;
  double _originalDistance = 0.0;
  
  Future<void> _loadExistingRecord() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      // 사용자 정보 로드
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
          
      if (userDoc.exists && userDoc.data()?['currentMileage'] != null) {
        _previousMileage = double.parse(userDoc.data()!['currentMileage'].toString());
      }
      
      // 기존 주유 기록 로드
      final recordDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('fuel_records')
          .doc(_recordId)
          .get();
      
      if (recordDoc.exists) {
        final data = recordDoc.data()!;
        setState(() {
          _distanceController.text = data['distance'].toString();
          _originalDistance = double.parse(data['distance'].toString());
          _amountController.text = data['amount'].toString();
          _priceController.text = data['cost'].toString();
          selectedFuelType = data['type'];
          _memoController.text = data['memo'] ?? '';
        });
      }
    } catch (e) {
      print('Error loading existing record: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('기존 기록을 불러오는데 실패했습니다')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _loadLastMileage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists && userDoc.data()?['currentMileage'] != null) {
        setState(() {
          _previousMileage = double.parse(userDoc.data()!['currentMileage'].toString());
        });
      }
    } catch (e) {
      print('Error loading last mileage: $e');
    }
  }

  String? _validateDistance(String? value) {
    if (value == null || value.isEmpty) {
      return '주행거리를 입력해주세요';
    }
    if (double.tryParse(value) == null) {
      return '올바른 숫자를 입력해주세요';
    }
    return null;
  }

  String? _validateAmount(String? value) {
    if (value == null || value.isEmpty) {
      return '주유량을 입력해주세요';
    }
    if (double.tryParse(value) == null) {
      return '올바른 숫자를 입력해주세요';
    }
    return null;
  }

  String? _validatePrice(String? value) {
    if (value == null || value.isEmpty) {
      return '금액을 입력해주세요';
    }
    if (double.tryParse(value) == null) {
      return '올바른 숫자를 입력해주세요';
    }
    return null;
  }

  String? _validateFuelType(String? value) {
    if (value == null || value.isEmpty) {
      return '연료 종류를 선택해주세요';
    }
    return null;
  }

  Future<void> _saveFuelRecord() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('로그인이 필요합니다');

      // users 컬렉션 내의 fuel_records 서브컬렉션에 저장할 데이터
      final record = {
        'distance': double.parse(_distanceController.text),
        'amount': double.parse(_amountController.text),
        'type': selectedFuelType!,
        'cost': double.parse(_priceController.text),
        'memo': _memoController.text,
      };
      
      final usersRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      
      if (_isEditing) {
        // 기존 기록 수정
        record['date'] = FieldValue.serverTimestamp(); // 수정 시간으로 업데이트
        
        await usersRef.collection('fuel_records').doc(_recordId).update(record);
        
        // 주행거리 차이만큼 현재 주행거리에서 조정
        final distanceDifference = double.parse(_distanceController.text) - _originalDistance;
        final updatedMileage = _previousMileage + distanceDifference;
        
        await usersRef.update({
          'currentMileage': updatedMileage,
          'lastFuelRecord': {
            'date': Timestamp.fromDate(DateTime.now()),
            'fuelType': selectedFuelType,
            'amount': double.parse(_amountController.text),
            'price': double.parse(_priceController.text),
          },
        });
        
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('주유 기록이 수정되었습니다')),
          );
        }
      } else {
        // 새 기록 추가
        record['date'] = DateTime.now();
        
        await usersRef.collection('fuel_records').add(record);

        // 현재 주행거리 업데이트 (이전 주행거리 + 추가 주행거리)
        final updatedMileage = _previousMileage + double.parse(_distanceController.text);
        
        await usersRef.update({
          'currentMileage': updatedMileage,
          'lastFuelRecord': {
            'date': Timestamp.fromDate(DateTime.now()),
            'fuelType': selectedFuelType,
            'amount': double.parse(_amountController.text),
            'price': double.parse(_priceController.text),
          },
        });

        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('주유 기록이 저장되었습니다')),
          );
        }
      }
    } catch (e) {
      print('Error saving fuel record: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('주유 기록 저장에 실패했습니다: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditing ? '주유 기록 수정' : '주유 기록하기',
          style: TextStyle(fontSize: 16),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      resizeToAvoidBottomInset: true, // 키보드가 올라오면 화면이 스크롤되도록 변경
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '주유 기록',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 16),

                          // 주행거리 입력
                          Text('주행거리'),
                          SizedBox(height: 8),
                          TextFormField(
                            controller: _distanceController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d+\.?\d{0,2}$'),
                              ),
                            ],
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                              ),
                              suffixText: 'km',
                              errorStyle: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                            validator: _validateDistance,
                          ),
                          SizedBox(height: 24),

                          // 주유금액 입력
                          Text('주유금액'),
                          SizedBox(height: 8),
                          TextFormField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                              ),
                              suffixText: '원',
                              errorStyle: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                            validator: _validatePrice,
                          ),
                          SizedBox(height: 24),

                          // 연료 종류와 주유량
                          Text('종류/주유량'),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              // 연료 종류 선택
                              Expanded(
                                flex: 1,
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Color(0xFFF5F5F5)),
                                  ),
                                  child: DropdownButtonFormField<String>(
                                    value: selectedFuelType,
                                    hint: Text('선택'),
                                    dropdownColor: Colors.white,
                                    menuMaxHeight: 200,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: InputBorder.none,
                                      errorStyle: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                      ),
                                    ),
                                    items: <String>['휘발유', '고급유']
                                        .map<DropdownMenuItem<String>>((String value) {
                                      return DropdownMenuItem<String>(
                                        value: value,
                                        child: Container(
                                          color: Colors.white,
                                          child: Text(value),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      setState(() {
                                        selectedFuelType = newValue;
                                      });
                                    },
                                    validator: _validateFuelType,
                                  )
                                ),
                              ),
                              SizedBox(width: 12),

                              // 주유량 입력
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  controller: _amountController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d+\.?\d{0,2}$'),
                                    ),
                                  ],
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                    ),
                                    suffixText: 'L',
                                    errorStyle: TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                    ),
                                  ),
                                  validator: _validateAmount,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 24),
                          
                          // 메모 입력 필드 추가
                          Text('메모'),
                          SizedBox(height: 8),
                          TextFormField(
                            controller: _memoController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                              ),
                              hintText: '메모를 입력 하세요',
                              hintStyle: TextStyle(
                                color: Colors.grey,
                              ),
                              errorStyle: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 하단 버튼
              Container(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveFuelRecord,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF2F6DF3),
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                            : Text(_isEditing ? '수정하기' : '저장하기'),
                      ),
                    ),
                    SizedBox(height: 8),
                    AdBannerWidget(),
                  ],
                ),
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.1),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}