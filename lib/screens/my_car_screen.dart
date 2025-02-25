// my_car_screen.dart
import 'package:flutter/material.dart';
import 'my_car_screen2.dart';

class MyCarScreen extends StatefulWidget {
  const MyCarScreen({Key? key}) : super(key: key);

  @override
  State<MyCarScreen> createState() => _MyCarScreenState();
}

class _MyCarScreenState extends State<MyCarScreen> {
  final TextEditingController _pinController = TextEditingController();
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _pinController.addListener(_validateInput);
  }

  void _validateInput() {
    setState(() {
      _isValid = _pinController.text.isNotEmpty;
    });
  }

  void _navigateToNextScreen() {
    if (_isValid) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MyCarScreen2(carNumber: _pinController.text),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('차량 번호를 입력해주세요'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _skipAndNavigate() {
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
              '차량 번호를 입력해 주세요.',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                hintText: '0000',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
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
            Center(
              child: TextButton(
                onPressed: _skipAndNavigate,
                child: const Text(
                  '건너뛰기',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}