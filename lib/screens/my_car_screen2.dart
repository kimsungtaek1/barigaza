// my_car_screen2.dart
import 'package:flutter/material.dart';
import '../widgets/ad_banner_widget.dart';
import 'my_car_screen3.dart';
import 'my_car_screen_direct.dart';

class MyCarScreen2 extends StatelessWidget {
  final String? carNumber;

  const MyCarScreen2({Key? key, this.carNumber}) : super(key: key);

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
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                childAspectRatio: 0.75,  // 그리드 아이템의 가로:세로 비율 조정
                shrinkWrap: true,        // 콘텐츠 크기에 맞게 조정
                physics: const AlwaysScrollableScrollPhysics(),  // 스크롤 가능하도록 설정
                children: [
                  _buildBrandButton(context, '혼다', 'Honda', 'honda_logo.png'),
                  _buildBrandButton(context, '야마하', 'Yamaha', 'yamaha_logo.png'),
                  _buildBrandButton(context, '스즈키', 'Suzuki', 'suzuki_logo.png'),
                  _buildBrandButton(context, '가와사키', 'Kawasaki', 'kawasaki_logo.png'),
                  _buildBrandButton(context, 'BMW Motorrad', 'BMW', 'bmw_logo.png'),
                  _buildBrandButton(context, '두카티', 'Ducati', 'ducati_logo.png'),
                  _buildBrandButton(context, '트라이엄프', 'Triumph', 'triumph_logo.png'),
                  _buildBrandButton(context, 'KTM', 'KTM', 'ktm_logo.png'),
                  _buildBrandButton(context, '로얄 엔필드', 'Royal Enfield', 'royal_enfield_logo.png'),
                  _buildBrandButton(context, '베스파', 'Vespa', 'vespa_logo.png'),
                  _buildBrandButton(context, '직접 등록', '', 'add_icon.png'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const AdBannerWidget(),
          ],
        ),
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
                carNumber: carNumber,
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