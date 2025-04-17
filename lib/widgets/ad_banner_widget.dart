import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io';

class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({super.key});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 앱 심사 통과 후 주석 제거
    Future.delayed(const Duration(milliseconds: 100), () {
       if (mounted) {  // 위젯이 여전히 존재하는지 확인
         _loadAd();
       }
    });
  }

  Future<void> _loadAd() async {
    // 화면 너비를 가져옵니다
    final width = MediaQuery.of(context).size.width.truncate();

    // 스마트 배너 사이즈 사용
    final adSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);

    if (adSize == null) {
      debugPrint('Unable to get AdSize');
      return;
    }

    _bannerAd = BannerAd(
      size: adSize,
      adUnitId: Platform.isAndroid
          ? 'ca-app-pub-9517075079081829/9266232490'
          : Platform.isIOS
              ? 'ca-app-pub-9517075079081829/6442664585'
              : 'unexpected-platform-ad-unit-id',
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('광고 로드 실패: $error');
        },
      ),
      request: const AdRequest(),
    );

    try {
      await _bannerAd?.load();
    } catch (e) {
      debugPrint('광고 로드 중 에러 발생: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 앱 심사 통과 후 주석 제거
    if (!_isLoaded || _bannerAd == null) {
      return Container(
        width: MediaQuery.of(context).size.width,  // 전체 너비
        height: 50,  // 명시적 높이
        color: Colors.transparent,
      );
    }

    return Container(
      width: MediaQuery.of(context).size.width,  // 전체 너비
      height: 50,  // 명시적 높이
      color: Colors.white,
      child: AdWidget(ad: _bannerAd!),
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }
}