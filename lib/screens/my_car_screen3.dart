import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/ad_banner_widget.dart';
import 'my_car_screen4.dart';

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
  List<Map<String, dynamic>> carList = [];
  String? selectedCarId;
  String? selectedCarName;

  @override
  void initState() {
    super.initState();
    _loadCarNames();
  }

  Future<void> _loadCarNames() async {
    try {
      final String response = await rootBundle.loadString('assets/jsons/car_names.json');
      final data = await json.decode(response);

      setState(() {
        carList = List<Map<String, dynamic>>.from(data[widget.manufacturer]);
      });
    } catch (e) {
      print('Error loading car names: $e');
    }
  }

  void _navigateToNextScreen() {
    if (selectedCarId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MyCarScreen4(
            manufacturer: widget.manufacturer,
            carNumber: widget.carNumber,
            carId: selectedCarId ?? '',
            carName: selectedCarName ?? '',
          ),
        ),
      );
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
              widget.manufacturer,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: carList.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final car = carList[index];
                final isSelected = selectedCarId == car['id'];

                return ListTile(
                  title: Text(
                    car['model'],
                    style: TextStyle(
                      color: isSelected ? Colors.blue : Colors.black,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.blue)
                      : null,
                  onTap: () {
                    setState(() {
                      selectedCarId = car['id'];
                      selectedCarName = car['model'];
                    });
                  },
                );
              },
            ),
          ),
          if (selectedCarId != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: ElevatedButton(
                onPressed: _navigateToNextScreen,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF746B5D),
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