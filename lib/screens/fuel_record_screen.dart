import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fuel_record.dart';
import '../services/maintenance_tracking_service.dart';
import '../widgets/ad_banner_widget.dart';

class FuelRecordScreen extends StatefulWidget {
  const FuelRecordScreen({Key? key}) : super(key: key);

  @override
  State<FuelRecordScreen> createState() => _FuelRecordScreenState();
}

class _FuelRecordScreenState extends State<FuelRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _distanceController = TextEditingController();
  final _amountController = TextEditingController();
  final _priceController = TextEditingController();
  String? selectedFuelType;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLastMileage();
  }

  @override
  void dispose() {
    _distanceController.dispose();
    _amountController.dispose();
    _priceController.dispose();
    super.dispose();
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
          _distanceController.text =
              userDoc.data()!['currentMileage'].toString();
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

      // users 컬렉션 내의 fuel_records 서브컬렉션에 저장
      final record = {
        'distance': double.parse(_distanceController.text),
        'amount': double.parse(_amountController.text),
        'type': selectedFuelType!,
        'cost': double.parse(_priceController.text),
        'date': DateTime.now(),
      };

      // users/{userId}/fuel_records에 저장
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('fuel_records')
          .add(record);

      // 현재 주행거리 업데이트
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'currentMileage': double.parse(_distanceController.text),
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
          '주유 기록하기',
          style: TextStyle(fontSize: 16),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
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
                              fillColor: Color(0xFFF7F7F7),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
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
                              fillColor: Color(0xFFF7F7F7),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
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
                                    color: Color(0xFFF7F7F7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: DropdownButtonFormField<String>(
                                    value: selectedFuelType,
                                    hint: Text('선택'),
                                    dropdownColor: Color(0xFFF7F7F7),
                                    menuMaxHeight: 200,  // 추가
                                    decoration: InputDecoration(
                                      filled: true,  // 추가
                                      fillColor: Color(0xFFF7F7F7), // 추가
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
                                        child: Container(  // 감싸기
                                          color: Color(0xFFF7F7F7),  // 각 아이템의 배경색 설정
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
                                    fillColor: Color(0xFFF7F7F7),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
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
                          backgroundColor: Color(0xFF8B785D),
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
                            : Text('저장하기'),
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