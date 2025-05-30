import 'package:flutter/material.dart';
import '../services/car_model_service.dart';
import '../models/car_model.dart';
import '../widgets/ad_banner_widget.dart';
import '../utils/manufacturer_names.dart';
import 'my_car_screen5.dart';
import 'my_car_screen_direct.dart';

class MyCarScreen3 extends StatefulWidget {
  final String manufacturer;
  final String? carNumber;

  const MyCarScreen3({
    Key? key,
    required this.manufacturer,
    this.carNumber,
  }) : super(key: key);

  @override
  State<MyCarScreen3> createState() => _MyCarScreen3State();
}

class _MyCarScreen3State extends State<MyCarScreen3> {
  final CarModelService _carModelService = CarModelService();
  bool _isLoading = true;
  List<CarModel> _carModels = [];
  String? selectedCarId;
  String? selectedCarName;


  @override
  void initState() {
    super.initState();
    _loadCarModels();
  }

  // Helper method to get display name
  String _getManufacturerDisplayName(String manufacturerId) {
    final manufacturerInfo = manufacturerNameMap[manufacturerId.toLowerCase()];
    if (manufacturerInfo == null) return manufacturerId;

    final korName = manufacturerInfo['kor'] ?? '';
    final engName = manufacturerInfo['eng'] ?? '';

    if (engName.isEmpty) return korName;
    return '$korName($engName)';
  }

  Future<void> _loadCarModels() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final models = await _carModelService.getModels(widget.manufacturer);

      setState(() {
        _carModels = models;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading car models: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _navigateToNextScreen() {
    if (selectedCarId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MyCarScreen5(
            manufacturer: widget.manufacturer,
            carNumber: widget.carNumber,
            carName: selectedCarName ?? '',
          ),
        ),
      );
    }
  }
  
  void _navigateToDirectRegistration() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MyCarScreenDirect(
          manufacturer: widget.manufacturer,
          carNumber: widget.carNumber,
        ),
      ),
    );
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: const Text(
              '사용하시는 차량 이름을 선택해 주세요.',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Text(
              _getManufacturerDisplayName(widget.manufacturer),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
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
            child: Column(
              children: [
                Expanded(
                  child: _carModels.isEmpty
                      ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Text('등록된 차량 모델이 없습니다.'),
                    ),
                  )
                      : ListView.separated(
                    itemCount: _carModels.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final car = _carModels[index];
                      final isSelected = selectedCarId == car.id;

                      return ListTile(
                        title: Text(
                          car.model,
                          style: TextStyle(
                            color: isSelected ? Colors.blue : Colors.black,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Colors.blue)
                            : null,
                        onTap: () {
                          setState(() {
                            selectedCarId = car.id;
                            selectedCarName = car.model;
                          });
                        },
                      );
                    },
                  ),
                ),
                // 직접 등록 버튼 추가
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _navigateToDirectRegistration,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        '직접 등록',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (selectedCarId != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: ElevatedButton(
                onPressed: _navigateToNextScreen,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor, // Primary color로 변경
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('다음으로'),
              ),
            ),
          const SizedBox(height: 20),
          const AdBannerWidget(),
        ],
      ),
    );
  }
}
