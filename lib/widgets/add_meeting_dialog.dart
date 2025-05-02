// add_meeting_dialog.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../screens/naver_address_search_screen.dart';
import '../services/chat_service.dart';

class AddMeetingDialog extends StatefulWidget {
  const AddMeetingDialog({Key? key}) : super(key: key);

  @override
  State<AddMeetingDialog> createState() => _AddMeetingDialogState();
}

class _AddMeetingDialogState extends State<AddMeetingDialog> {
  // 컨트롤러 선언
  final titleController = TextEditingController();
  final departureAddressController = TextEditingController();
  final departureDetailAddressController = TextEditingController();
  final destinationAddressController = TextEditingController();
  final destinationDetailAddressController = TextEditingController();
  final timeController = TextEditingController();

  // 포커스 노드 선언
  final titleFocus = FocusNode();
  final departureDetailFocus = FocusNode();
  final destinationDetailFocus = FocusNode();

  // 상태 변수
  DateTime? selectedTime;
  GeoPoint? selectedLocation;
  bool isDestinationDetailFocused = false;
  final ChatService _chatService = ChatService();
  final Map<String, GeoPoint?> _addressCache = {};

  @override
  void initState() {
    super.initState();
    destinationDetailFocus.addListener(_updateFocusState);
  }

  void _updateFocusState() {
    if (mounted) {
      setState(() {
        isDestinationDetailFocused = destinationDetailFocus.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    // 리소스 해제
    titleController.dispose();
    departureAddressController.dispose();
    departureDetailAddressController.dispose();
    destinationAddressController.dispose();
    destinationDetailAddressController.dispose();
    timeController.dispose();

    titleFocus.dispose();
    departureDetailFocus.dispose();
    destinationDetailFocus.removeListener(_updateFocusState);
    destinationDetailFocus.dispose();
    super.dispose();
  }

  // 키보드 숨김 함수
  void dismissKeyboard() {
    titleFocus.unfocus();
    departureDetailFocus.unfocus();
    destinationDetailFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // 주소를 좌표로 변환
  Future<GeoPoint?> _getCachedCoordinates(String address) async {
    // 캐시에 있으면 바로 반환
    if (_addressCache.containsKey(address)) {
      return _addressCache[address];
    }

    // 캐시에 없으면 API 호출하고 캐시에 저장
    final result = await getCoordinatesFromAddress(address);
    _addressCache[address] = result;
    return result;
  }

  // 네이버 지오코딩 API 호출
  Future<GeoPoint?> getCoordinatesFromAddress(String address) async {
    try {
      final String apiUrl = 'https://naveropenapi.apigw.ntruss.com/map-geocode/v2/geocode';
      final Uri url = Uri.parse('$apiUrl?query=${Uri.encodeComponent(address)}');

      final response = await http.get(
        url,
        headers: {
          'X-NCP-APIGW-API-KEY-ID': '5k1r2vy3lz',
          'X-NCP-APIGW-API-KEY': 'W6McBwHf5CFEVZpfz1DSuc2DdzTNC8Ks0l1paU4P',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['addresses'] != null && data['addresses'].isNotEmpty) {
          final location = data['addresses'][0];
          final double? y = double.tryParse(location['y']);
          final double? x = double.tryParse(location['x']);

          if (y != null && x != null) {
            return GeoPoint(y, x);
          }
        }
      } else if (response.statusCode == 429) {
        // 요청 제한 초과 시 짧은 대기 후 재시도
        await Future.delayed(const Duration(milliseconds: 500));
        return getCoordinatesFromAddress(address);
      }
    } catch (e) {
      debugPrint("주소 좌표 변환 오류: $e");
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    // 화면 크기 측정
    final screenSize = MediaQuery.of(context).size;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 0;

    // 다이얼로그 위치 및 크기 계산
    double dialogWidth = screenSize.width * 0.9;
    double dialogHeight = screenSize.height * 0.7;

    // 기본 위치를 상단에서 좀 더 내려오게 조정
    double dialogTop = 20;

    // 목적지 상세주소에 포커스가 있고 키보드가 열렸다면 다이얼로그 위치 조정
    if (isDestinationDetailFocused && isKeyboardOpen) {
      // 키보드 위로 다이얼로그를 올림
      dialogTop = -(screenSize.height - keyboardHeight) / 4;
    }

    return SafeArea(
      bottom: false,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // 다이얼로그 배경 탭 감지 (키보드 닫기용)
            GestureDetector(
              onTap: () {
                dismissKeyboard();
                setState(() {
                  isDestinationDetailFocused = false;
                });
              },
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.black54),
            ),

            // 다이얼로그 본체
            AnimatedPositioned(
              duration: Duration(milliseconds: 200),
              curve: Curves.easeOutQuad,
              top: dialogTop,
              left: (screenSize.width - dialogWidth) / 2,
              child: Container(
                width: dialogWidth,
                height: dialogHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // 대화상자 헤더
                    Padding(
                      padding: const EdgeInsets.only(top: 20.0, bottom: 16.0, left: 20.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '번개 모임 만들기',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                    // 대화상자 콘텐츠 - 스크롤 가능
                    Expanded(
                      child: GestureDetector(
                        // 빈 공간 터치 시 키보드 닫기
                        onTap: () {
                          dismissKeyboard();
                          setState(() {
                            isDestinationDetailFocused = false;
                          });
                        },
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 모임 제목
                              TextFormField(
                                controller: titleController,
                                focusNode: titleFocus,
                                textInputAction: TextInputAction.done,
                                onEditingComplete: () {
                                  dismissKeyboard();
                                  setState(() {
                                    isDestinationDetailFocused = false;
                                  });
                                },
                                decoration: InputDecoration(
                                  labelText: '모임 제목',
                                  hintText: '모임 제목을 입력해주세요',
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  floatingLabelBehavior: FloatingLabelBehavior.never,
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                onTap: () {
                                  setState(() {
                                    isDestinationDetailFocused = false;
                                  });
                                },
                              ),
                              SizedBox(height: 16),

                              // 모임 시간
                              TextFormField(
                                controller: timeController,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: '모임 시간',
                                  hintStyle: TextStyle(color: Colors.grey),
                                  prefixIcon: Icon(Icons.access_time, size: 16, color: Theme.of(context).primaryColor),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  floatingLabelBehavior: FloatingLabelBehavior.never,
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                onTap: () async {
                                  // 시간 선택 시 키보드가 열려있으면 닫기
                                  dismissKeyboard();
                                  setState(() {
                                    isDestinationDetailFocused = false;
                                  });

                                  final now = DateTime.now();
                                  final DateTime? pickedDate = await showDatePicker(
                                    context: context,
                                    initialDate: now,
                                    firstDate: now,
                                    lastDate: now.add(const Duration(days: 30)),
                                    builder: (context, child) => Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: const ColorScheme.light(
                                          primary: Colors.blue,
                                          onPrimary: Colors.white,
                                          onSurface: Colors.black,
                                        ),
                                        textButtonTheme: TextButtonThemeData(
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.blue,
                                          ),
                                        ),
                                      ),
                                      child: child!,
                                    ),
                                  );

                                  if (pickedDate != null) {
                                    final TimeOfDay? pickedTime = await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay.now(),
                                      builder: (context, child) => Theme(
                                        data: Theme.of(context).copyWith(
                                          colorScheme: const ColorScheme.light(
                                            primary: Colors.blue,
                                            onPrimary: Colors.white,
                                            onSurface: Colors.black,
                                          ),
                                          textButtonTheme: TextButtonThemeData(
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.blue,
                                            ),
                                          ),
                                        ),
                                        child: child!,
                                      ),
                                    );

                                    if (pickedTime != null) {
                                      selectedTime = DateTime(
                                        pickedDate.year,
                                        pickedDate.month,
                                        pickedDate.day,
                                        pickedTime.hour,
                                        pickedTime.minute,
                                      );
                                      timeController.text = DateFormat('yyyy년 MM월 dd일 HH시 mm분')
                                          .format(selectedTime!);
                                    }
                                  }
                                },
                              ),
                              SizedBox(height: 32),

                              // 출발지
                              TextFormField(
                                controller: departureAddressController,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: '출발지',
                                  hintText: '출발지를 검색해주세요',
                                  hintStyle: TextStyle(color: Colors.grey),
                                  prefixIcon: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Image.asset(
                                      'assets/images/marker.png',
                                      width: 8,
                                      height: 8,
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  floatingLabelBehavior: FloatingLabelBehavior.never,
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                onTap: () async {
                                  // 주소 검색 시 키보드가 열려있으면 닫기
                                  dismissKeyboard();
                                  setState(() {
                                    isDestinationDetailFocused = false;
                                  });

                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const NaverAddressSearch(),
                                    ),
                                  );
                                  if (result != null) {
                                    departureAddressController.text = result;
                                    // 주소가 선택되면 백그라운드에서 미리 좌표 변환 시작
                                    _getCachedCoordinates(result);
                                  }
                                },
                              ),
                              SizedBox(height: 8),

                              // 출발지 상세주소
                              TextFormField(
                                controller: departureDetailAddressController,
                                focusNode: departureDetailFocus,
                                textInputAction: TextInputAction.done,
                                onEditingComplete: () {
                                  dismissKeyboard();
                                  setState(() {
                                    isDestinationDetailFocused = false;
                                  });
                                },
                                decoration: InputDecoration(
                                  labelText: '출발지 상세주소',
                                  hintText: '출발지 상세주소를 입력해주세요 (선택)',
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  floatingLabelBehavior: FloatingLabelBehavior.never,
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                onTap: () {
                                  setState(() {
                                    isDestinationDetailFocused = false;
                                  });
                                },
                              ),
                              SizedBox(height: 32),

                              // 목적지
                              TextFormField(
                                controller: destinationAddressController,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: '목적지',
                                  hintText: '목적지를 검색해주세요',
                                  hintStyle: TextStyle(color: Colors.grey),
                                  prefixIcon: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Image.asset(
                                      'assets/images/marker.png',
                                      width: 8,
                                      height: 8,
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  floatingLabelBehavior: FloatingLabelBehavior.never,
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                onTap: () async {
                                  // 주소 검색 시 키보드가 열려있으면 닫기
                                  dismissKeyboard();
                                  setState(() {
                                    isDestinationDetailFocused = false;
                                  });

                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const NaverAddressSearch(),
                                    ),
                                  );
                                  if (result != null) {
                                    destinationAddressController.text = result;
                                  }
                                },
                              ),
                              SizedBox(height: 8),

                              // 목적지 상세주소
                              TextFormField(
                                controller: destinationDetailAddressController,
                                focusNode: destinationDetailFocus,
                                textInputAction: TextInputAction.done,
                                onEditingComplete: () {
                                  dismissKeyboard();
                                  setState(() {
                                    isDestinationDetailFocused = false;
                                  });
                                },
                                decoration: InputDecoration(
                                  labelText: '목적지 상세주소',
                                  hintText: '목적지 상세주소를 입력해주세요 (선택)',
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.0),
                                    borderSide: BorderSide(color: Color(0xFFF5F5F5)),
                                  ),
                                  floatingLabelBehavior: FloatingLabelBehavior.never,
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                onTap: () {
                                  setState(() {
                                    isDestinationDetailFocused = true;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 대화상자 하단 버튼 영역
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              dismissKeyboard();
                              Navigator.pop(context, false);
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Color(0xFFE5E7EB),
                                borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(16),
                                ),
                              ),
                              child: Text(
                                '취소',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              await _saveMeeting(context);
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                borderRadius: BorderRadius.only(
                                  bottomRight: Radius.circular(16),
                                ),
                              ),
                              child: Text(
                                '저장',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveMeeting(BuildContext context) async {
    // 키보드가 열려있으면 닫기
    dismissKeyboard();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다. 먼저 로그인해주세요.')),
      );
      return;
    }

    // 검증 단계
    if (titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모임 제목을 입력해주세요.')),
      );
      return;
    }
    if (departureAddressController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('출발지를 선택해주세요.')),
      );
      return;
    }
    if (destinationAddressController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('목적지를 선택해주세요.')),
      );
      return;
    }
    if (selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시간을 선택해주세요.')),
      );
      return;
    }
    if (selectedTime!.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 시간 이후로 선택해주세요.')),
      );
      return;
    }

    // 로딩 표시 (UI 응답성 향상)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: CircularProgressIndicator(),
        );
      },
    );

    try {
      // 병렬 처리로 성능 향상
      final results = await Future.wait([
        _getCachedCoordinates(departureAddressController.text),
        FirebaseFirestore.instance.collection('users').doc(user.uid).get()
      ]);

      // 결과 파싱
      selectedLocation = results[0] as GeoPoint?;
      final userDoc = results[1] as DocumentSnapshot;

      // 로딩 다이얼로그 닫기
      Navigator.of(context).pop();

      if (selectedLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('출발지 주소를 좌표로 변환하는데 실패했습니다.')),
        );
        return;
      }

      final userNickname = userDoc['nickname'] ?? '알 수 없음';

      // 모임 데이터 준비
      final newMeeting = {
        'title': titleController.text,
        'hostId': user.uid,
        'hostName': userNickname,
        'departureAddress': departureAddressController.text,
        'departureDetailAddress': departureDetailAddressController.text,
        'destinationAddress': destinationAddressController.text,
        'destinationDetailAddress': destinationDetailAddressController.text,
        'meetingTime': Timestamp.fromDate(selectedTime!),
        'location': selectedLocation,
        'participants': [user.uid],
        'status': 'active',
        'createdAt': Timestamp.now(),
      };

      // 모임 및 채팅룸 생성
      final meetingRef = await FirebaseFirestore.instance
          .collection('meetings')
          .add(newMeeting);

      // 채팅룸 생성
      final chatId = await _chatService.createGroupChatRoom(
        [user.uid],
        titleController.text,
        meetingId: meetingRef.id,
      );

      // chatRoomId 업데이트
      await meetingRef.update({'chatRoomId': chatId});

      // 성공 후 다이얼로그 닫기 및 성공 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('모임이 성공적으로 생성되었습니다.'),
          backgroundColor: Colors.green,
        ),
      );

      // true 반환하여 모임이 생성되었음을 부모에게 알림
      Navigator.pop(context, true);

    } catch (e) {
      // 에러 발생 시 로딩 다이얼로그 닫기
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('모임 생성 중 오류가 발생했습니다.'),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('모임 생성 오류: $e');
    }
  }
}