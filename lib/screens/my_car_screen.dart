// my_car_screen.dart
import 'package:flutter/material.dart';
import 'my_car_screen2.dart';

class MyCarScreen extends StatefulWidget {
  const MyCarScreen({Key? key}) : super(key: key);

  @override
  State<MyCarScreen> createState() => _MyCarScreenState();
}

class _MyCarScreenState extends State<MyCarScreen> {

  void _navigateToNextScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MyCarScreen2(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
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
              '안녕하세요!\n고객님의 바이크 정보를 등록해 주시면\n맞춤형 서비스를 제공해 드릴 수 있습니다.',
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            const Text(
              '바이크 정보를 등록하시겠습니까?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _navigateToNextScreen,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF746B5D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('확인하기'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}