// lib/widgets/weather_widget.dart

import 'package:flutter/material.dart';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'dart:convert';

class WeatherWidget extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String address;

  const WeatherWidget({
    Key? key,
    required this.latitude,
    required this.longitude,
    required this.address,
  }) : super(key: key);

  @override
  State<WeatherWidget> createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<WeatherWidget> {
  Map<String, dynamic>? _weatherInfo;
  // ※ 반드시 올바른 서비스 키를 사용하세요.
  final String serviceKey =
      's25A4yqFg1IPZZHpGSPHvi%2FT9%2Bb0I%2BRCVP4Osq8%2FEgPV2aTrMcsb6b%2FnWpwgfhwyK9JZjD8ats0iPIshXRQJpg%3D%3D';

  @override
  void initState() {
    super.initState();
    _getWeatherInfo();
  }

  // 위경도를 기상청 좌표(Grid)로 변환하는 함수
  Map<String, int> _convertToGridCoord(double lat, double lon) {
    double RE = 6371.00877; // 지구 반경 (km)
    double GRID = 5.0; // 격자 간격 (km)
    double SLAT1 = 30.0; // 투영 위도1 (degree)
    double SLAT2 = 60.0; // 투영 위도2 (degree)
    double OLON = 126.0; // 기준점 경도 (degree)
    double OLAT = 38.0; // 기준점 위도 (degree)
    double XO = 43; // 기준점 X좌표 (GRID)
    double YO = 136; // 기준점 Y좌표 (GRID)

    double DEGRAD = pi / 180.0;
    double re = RE / GRID;
    double slat1 = SLAT1 * DEGRAD;
    double slat2 = SLAT2 * DEGRAD;
    double olon = OLON * DEGRAD;
    double olat = OLAT * DEGRAD;

    double sn = tan(pi * 0.25 + slat2 * 0.5) / tan(pi * 0.25 + slat1 * 0.5);
    sn = log(cos(slat1) / cos(slat2)) / log(sn);
    double sf = tan(pi * 0.25 + slat1 * 0.5);
    sf = pow(sf, sn) * cos(slat1) / sn;
    double ro = tan(pi * 0.25 + olat * 0.5);
    ro = re * sf / pow(ro, sn);

    Map<String, int> rs = {};
    double ra = tan(pi * 0.25 + lat * DEGRAD * 0.5);
    ra = re * sf / pow(ra, sn);
    double theta = lon * DEGRAD - olon;
    if (theta > pi) theta -= 2.0 * pi;
    if (theta < -pi) theta += 2.0 * pi;
    theta *= sn;

    rs['nx'] = (ra * sin(theta) + XO + 0.5).floor();
    rs['ny'] = (ro - ra * cos(theta) + YO + 0.5).floor();

    print("Converted grid coordinates: $rs");

    return rs;
  }

  // 단기예보조회(getVilageFcst) API용 base_date, base_time을 동적으로 계산하는 함수
  // 유효한 base_time 값: 0200, 0500, 0800, 1100, 1400, 1700, 2000, 2300
  // 발표시각 10분 이후에 데이터가 제공되므로, 현재 시각이 (baseHour:10) 이상이면 그 발표시간을 사용하고,
  // 그렇지 않으면 이전 발표시간(예: 현재가 02:05이면 어제의 23시 발표)을 사용합니다.
  Map<String, String> _getForecastBaseDateTime() {
    List<int> baseHours = [2, 5, 8, 11, 14, 17, 20, 23];
    DateTime now = DateTime.now();
    int? selectedHour;
    // 현재 시각과 비교하여, 발표시각(분이 10 이상인) 조건을 만족하는 가장 최근 baseHour를 선택
    for (int hour in baseHours) {
      if (now.hour > hour || (now.hour == hour && now.minute >= 10)) {
        selectedHour = hour;
      } else {
        break;
      }
    }

    DateTime baseDateTime;
    if (selectedHour == null) {
      // 현재 시각이 02:10 이전이면 어제의 23시 발표를 사용
      selectedHour = baseHours.last; // 23
      baseDateTime = now.subtract(Duration(days: 1));
    } else {
      baseDateTime = now;
    }

    String baseDate =
        '${baseDateTime.year}${baseDateTime.month.toString().padLeft(2, '0')}${baseDateTime.day.toString().padLeft(2, '0')}';
    String baseTime = selectedHour.toString().padLeft(2, '0') + "00";
    return {'baseDate': baseDate, 'baseTime': baseTime};
  }

  // 기존 초단기실황(getUltraSrtNcst) API용 base_time 계산 함수 (예: 05시 기준)
  String _getCurrentBaseTime() {
    var now = DateTime.now();
    var hour = now.hour;
    var minute = now.minute;

    // 매시 40분 이전이면 이전 시간의 데이터를 사용
    if (minute < 40) {
      hour = hour - 1;
      if (hour < 0) hour = 23;
    }

    String baseTime = '${hour.toString().padLeft(2, '0')}00';
    return baseTime;
  }

  Future<void> _getWeatherInfo() async {
    try {
      Map<String, int> grid = _convertToGridCoord(widget.latitude, widget.longitude);

      // 단기예보 조회 API용 base_date, base_time 계산
      Map<String, String> forecastDateTime = _getForecastBaseDateTime();
      String forecastBaseDate = forecastDateTime['baseDate']!;
      String forecastBaseTime = forecastDateTime['baseTime']!;

      // 초단기실황 API용 현재 날짜 계산
      DateTime now = DateTime.now();
      String nowBaseDate =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

      // 1. 단기예보 조회 API 호출 (최저/최고 기온(TMN, TMX) 용)
      final fcstUrl = Uri.parse(
          'http://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getVilageFcst'
              '?serviceKey=$serviceKey'
              '&pageNo=1'
              '&numOfRows=1000'
              '&dataType=JSON'
              '&base_date=$forecastBaseDate'
              '&base_time=$forecastBaseTime'
              '&nx=${grid['nx']}'
              '&ny=${grid['ny']}'
      );

      // 2. 초단기실황 조회 API 호출 (현재 기온(T1H), SKY, PTY 용)
      final ncstUrl = Uri.parse(
          'http://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getUltraSrtNcst'
              '?serviceKey=$serviceKey'
              '&pageNo=1'
              '&numOfRows=10'
              '&dataType=JSON'
              '&base_date=$nowBaseDate'
              '&base_time=${_getCurrentBaseTime()}'
              '&nx=${grid['nx']}'
              '&ny=${grid['ny']}'
      );

      final fcstResponse = await http.get(fcstUrl);

      final ncstResponse = await http.get(ncstUrl);

      Map<String, dynamic> weatherInfo = {};

      // 단기예보 응답 파싱 (TMN, TMX)
      if (fcstResponse.statusCode == 200) {
        final data = json.decode(fcstResponse.body);
        print("===== 단기예보 전체 응답 데이터 =====");
        print(fcstResponse.body);
        print("===================================");
        
        // 응답 헤더의 resultCode가 "03"이면 NO_DATA
        if (data['response']['header']['resultCode'] == "03") {
          print("Forecast API returned NO_DATA. 예보 데이터가 없습니다.");
        } else {
          final items = data['response']?['body']?['items']?['item'];
          if (items != null) {
            for (var item in items) {
              String category = item['category'];
              String value = item['fcstValue'];
              if (category == 'TMN' || category == 'TMX') {
                print("날씨 데이터 발견: $category = $value");
                weatherInfo[category] = value;
              }
            }
          } else {
            print("Forecast items가 null입니다. 응답 데이터: $data");
          }
        }
      } else {
        print("Forecast API 호출 실패: ${fcstResponse.statusCode}");
      }

      // 초단기실황 응답 파싱 (T1H, SKY, PTY)
      if (ncstResponse.statusCode == 200) {
        final data = json.decode(ncstResponse.body);
        print("===== 초단기실황 전체 응답 데이터 =====");
        print(ncstResponse.body);
        print("===================================");
        
        final items = data['response']?['body']?['items']?['item'];
        if (items != null) {
          for (var item in items) {
            String category = item['category'];
            String value = item['obsrValue'];
            print("초단기실황 데이터: $category = $value");
            if (['T1H', 'SKY', 'PTY'].contains(category)) {
              if (category == 'T1H') {
                weatherInfo['TMP'] = value; // T1H를 TMP로 변환하여 현재 기온으로 저장
              } else {
                weatherInfo[category] = value;
              }
            }
          }
        } else {
          print("Nowcast items가 null입니다. 응답 데이터: $data");
        }
      } else {
        print("Nowcast API 호출 실패: ${ncstResponse.statusCode}");
      }

      if (weatherInfo.isNotEmpty) {
        setState(() {
          _weatherInfo = weatherInfo;
        });
      }
    } catch (e) {
      print('Weather API 호출 중 오류 발생: $e');
      setState(() {
        _weatherInfo = {
          'TMP': '0',
          'SKY': '1',
          'PTY': '0',
          'TMN': '',
          'TMX': ''
        };
      });
    }
  }

  String _getSkyStatus(String sky, String pty) {
    if (pty != '0') {
      switch (pty) {
        case '1':
          return '비';
        case '2':
          return '비/눈';
        case '3':
          return '눈';
        case '4':
          return '소나기';
        default:
          return '강수';
      }
    }
    switch (sky) {
      case '1':
        return '맑음';
      case '3':
        return '구름많음';
      case '4':
        return '흐림';
      default:
        return '알 수 없음';
    }
  }

  Color _getWeatherBackgroundColor(String sky, String pty) {
    if (pty != '0') {
      return const Color(0xFF31335C); // 비/눈일 때 배경색
    }
    switch (sky) {
      case '1':
        return const Color(0xFF8BB9EE); // 맑음
      case '3': // 구름많음
      case '4':
        return const Color(0xFFA4AAAB); // 흐림
      default:
        return const Color(0xFF8BB9EE); // 기본값은 맑음
    }
  }

  @override
  Widget build(BuildContext context) {
    final sky = _weatherInfo?['SKY'] ?? '1';
    final pty = _weatherInfo?['PTY'] ?? '0';
    final backgroundColor = _getWeatherBackgroundColor(sky, pty);

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: backgroundColor,
      child: Stack(
        children: [
          // 지역명 (좌측 상단)
          Positioned(
            left: 20,
            top: 20,
            child: Text(
              widget.address.isEmpty ? '위치를 불러오는 중...' : widget.address,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 현재 온도 (우측 상단)
          Positioned(
            right: 20,
            top: 20,
            child: _weatherInfo == null
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
                : Text(
              '${_weatherInfo!['TMP'] ?? '-'}°C',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 날씨 상태 (좌측 하단)
          Positioned(
            left: 20,
            bottom: 20,
            child: Text(
              _weatherInfo == null
                  ? '날씨 정보를 불러오는 중...'
                  : _getSkyStatus(sky, pty),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
              ),
            ),
          ),
          // 최고/최저 온도 (우측 하단)
          Positioned(
            right: 20,
            bottom: 20,
            child: Text(
              '최고:${_weatherInfo?['TMX']?.isNotEmpty == true ? '${_weatherInfo!['TMX']}°C' : '-'}  '
                  '최저:${_weatherInfo?['TMN']?.isNotEmpty == true ? '${_weatherInfo!['TMN']}°C' : '-'}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
