import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/ad_banner_widget.dart';
import 'my_car_screen5.dart';

class MyCarScreen4 extends StatefulWidget {
  final String manufacturer;
  final String? carNumber;
  final String carName;
  final String carId;

  const MyCarScreen4({
    Key? key,
    required this.manufacturer,
    this.carNumber,
    required this.carName,
    required this.carId,
  }) : super(key: key);

  @override
  State<MyCarScreen4> createState() => _MyCarScreen4State();
}

class _MyCarScreen4State extends State<MyCarScreen4> {
  List<Map<String, dynamic>> modelList = [];
  String? selectedModel;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      final String response = await rootBundle.loadString('assets/jsons/car_models.json');
      final data = await json.decode(response);

      setState(() {
        modelList = List<Map<String, dynamic>>.from(data[widget.carId]);
      });
    } catch (e) {
      print('Error loading models: $e');
    }
  }

  void _navigateToNextScreen() {
    if (selectedModel != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MyCarScreen5(
            manufacturer: widget.manufacturer,
            carNumber: widget.carNumber,
            carName: widget.carName,
            modelName: selectedModel!,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '모델명을 선택해 주세요.',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.carName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: modelList.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final model = modelList[index];
                final isSelected = selectedModel == model['name'];

                return ListTile(
                  title: Text(
                    model['name'],
                    style: TextStyle(
                      fontSize: 16,
                      color: isSelected ? Colors.blue : Colors.black,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.blue)
                      : null,
                  onTap: () {
                    setState(() {
                      selectedModel = model['name'];
                    });
                  },
                );
              },
            ),
          ),
          if (selectedModel != null)
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
                child: const Text('선택 완료'),
              ),
            ),
          const SizedBox(height: 20),
          const AdBannerWidget(),
        ],
      ),
    );
  }
}