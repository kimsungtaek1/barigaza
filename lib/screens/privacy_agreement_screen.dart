import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // rootBundle 사용
import 'package:http/http.dart' as http;

class PrivacyAgreementScreen extends StatefulWidget {
  @override
  _PrivacyAgreementScreenState createState() => _PrivacyAgreementScreenState();
}

class _PrivacyAgreementScreenState extends State<PrivacyAgreementScreen> {
  bool isAllChecked = false;
  bool isAge14Above = false;
  bool isTermsAgreed = false;
  bool isPrivacyAgreed = false;

  void _updateAllCheck(bool? value) {
    setState(() {
      isAllChecked = value ?? false;
      isAge14Above = isAllChecked;
      isTermsAgreed = isAllChecked;
      isPrivacyAgreed = isAllChecked;
    });
  }

  void _updateIndividualCheck() {
    setState(() {
      isAllChecked = isAge14Above && isTermsAgreed && isPrivacyAgreed;
    });
  }

  void _showTermsModal(String title) async {
    // title 값에 따라 로드할 JSON 파일 URL 결정
    String fileUrl;
    if (title == '개인정보처리방침') {
      fileUrl = 'https://barigaza-796a1.web.app/privacy_agreement.json';
    } else if(title == '이용약관'){
      // 기본값
      fileUrl = 'https://barigaza-796a1.web.app/terms.json';
    } else{
      fileUrl = 'https://barigaza-796a1.web.app/privacy_agreement.json';
    }

    // HTTP 요청으로 JSON 파일 가져오기
    final response = await http.get(Uri.parse(fileUrl));
    if (response.statusCode != 200) {
      debugPrint('Error fetching JSON from server: ${response.statusCode}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('약관 정보를 불러오는데 실패했습니다')),
      );
      return;
    }
    
    // UTF-8 디코딩을 명시적으로 처리
    Map<String, dynamic> policyData = jsonDecode(utf8.decode(response.bodyBytes));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: PrivacyPolicyContent(policyData: policyData),
      ),
    );
  }

  Widget _buildCheckbox({
    required String title,
    required bool value,
    required Function(bool?) onChanged,
    String? viewButtonTitle,
    VoidCallback? onViewPressed,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: CheckboxListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (viewButtonTitle != null && onViewPressed != null)
              TextButton(
                onPressed: onViewPressed,
                child: Text(
                  viewButtonTitle,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ),
          ],
        ),
        value: value,
        onChanged: onChanged,
        activeColor: Color(0xFF1066FF),
        checkColor: Colors.white,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Colors.black87, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '개인정보동의',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCheckbox(
                title: '전체 동의하기',
                value: isAllChecked,
                onChanged: _updateAllCheck,
              ),
              SizedBox(height: 16),
              _buildCheckbox(
                title: '만 14세 이상입니다',
                value: isAge14Above,
                onChanged: (value) {
                  setState(() {
                    isAge14Above = value ?? false;
                    _updateIndividualCheck();
                  });
                },
              ),
              _buildCheckbox(
                title: '약관 안내에 동의합니다',
                value: isTermsAgreed,
                onChanged: (value) {
                  setState(() {
                    isTermsAgreed = value ?? false;
                    _updateIndividualCheck();
                  });
                },
                viewButtonTitle: '보기',
                onViewPressed: () => _showTermsModal('이용약관'),
              ),
              _buildCheckbox(
                title: '개인정보 처리방침에 동의합니다',
                value: isPrivacyAgreed,
                onChanged: (value) {
                  setState(() {
                    isPrivacyAgreed = value ?? false;
                    _updateIndividualCheck();
                  });
                },
                viewButtonTitle: '보기',
                onViewPressed: () => _showTermsModal('개인정보처리방침'),
              ),
              Spacer(),
              Container(
                margin: EdgeInsets.only(bottom: 16),
                child: ElevatedButton(
                  onPressed: isAllChecked
                      ? () => Navigator.pushNamed(context, '/signup')
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF1066FF),
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: Text(
                    '다음으로',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// JSON 데이터를 기반으로 개인정보처리방침 내용을 표시하는 위젯
class PrivacyPolicyContent extends StatelessWidget {
  final Map<String, dynamic> policyData;

  const PrivacyPolicyContent({Key? key, required this.policyData})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 제목
        Text(
          policyData["title"] ?? "",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 서문
                Text(
                  policyData["intro"] ?? "",
                  style: TextStyle(fontSize: 15),
                ),
                SizedBox(height: 20),
                // 각 섹션별 내용 표시
                ...List<Widget>.from((policyData["sections"] as List).map((section) {
                  List<Widget> sectionWidgets = [];
                  sectionWidgets.add(Text(
                    section["sectionTitle"] ?? "",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ));
                  if (section.containsKey("description")) {
                    sectionWidgets.add(SizedBox(height: 5));
                    sectionWidgets.add(Text(
                      section["description"],
                      style: TextStyle(fontSize: 14),
                    ));
                  }
                  if (section.containsKey("items")) {
                    var items = section["items"] as Map<String, dynamic>;
                    items.forEach((key, value) {
                      sectionWidgets.add(SizedBox(height: 5));
                      sectionWidgets.add(Text(
                        "$key: ${(value as List).join(", ")}",
                        style: TextStyle(fontSize: 14),
                      ));
                    });
                  }
                  if (section.containsKey("purposes")) {
                    sectionWidgets.add(SizedBox(height: 5));
                    for (var purpose in section["purposes"]) {
                      sectionWidgets.add(Text(
                        "- $purpose",
                        style: TextStyle(fontSize: 14),
                      ));
                    }
                  }
                  if (section.containsKey("notes")) {
                    sectionWidgets.add(SizedBox(height: 5));
                    for (var note in section["notes"]) {
                      sectionWidgets.add(Text(
                        note,
                        style: TextStyle(fontSize: 14),
                      ));
                    }
                  }
                  if (section.containsKey("retention")) {
                    sectionWidgets.add(SizedBox(height: 10));
                    sectionWidgets.add(Text(
                      "보관 항목 / 보관 기간 / 근거 법령",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ));
                    sectionWidgets.add(_buildTable(
                      headers: ["보관 항목", "보관 기간", "근거 법령"],
                      rows: List<Map<String, dynamic>>.from(section["retention"]),
                    ));
                  }
                  if (section.containsKey("disposal")) {
                    sectionWidgets.add(SizedBox(height: 5));
                    sectionWidgets.add(Text(
                      section["disposal"],
                      style: TextStyle(fontSize: 14),
                    ));
                  }
                  if (section.containsKey("conditions")) {
                    sectionWidgets.add(SizedBox(height: 5));
                    for (var condition in section["conditions"]) {
                      sectionWidgets.add(Text(
                        "- $condition",
                        style: TextStyle(fontSize: 14),
                      ));
                    }
                  }
                  if (section.containsKey("entrustments")) {
                    sectionWidgets.add(SizedBox(height: 10));
                    sectionWidgets.add(Text(
                      "위탁업체 / 위탁 업무 내용 / 보유 및 이용 기간",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ));
                    sectionWidgets.add(_buildTable(
                      headers: ["위탁업체", "위탁 업무 내용", "보유 및 이용 기간"],
                      rows: List<Map<String, dynamic>>.from(section["entrustments"]),
                    ));
                  }
                  if (section.containsKey("methods")) {
                    sectionWidgets.add(SizedBox(height: 5));
                    for (var method in section["methods"]) {
                      sectionWidgets.add(Text(
                        "- $method",
                        style: TextStyle(fontSize: 14),
                      ));
                    }
                  }
                  if (section.containsKey("measures")) {
                    sectionWidgets.add(SizedBox(height: 5));
                    for (var measure in section["measures"]) {
                      sectionWidgets.add(Text(
                        "- $measure",
                        style: TextStyle(fontSize: 14),
                      ));
                    }
                  }
                  if (section.containsKey("contact")) {
                    var contact = section["contact"];
                    sectionWidgets.add(SizedBox(height: 5));
                    sectionWidgets.add(Text(
                      "이메일: ${contact["이메일"]}",
                      style: TextStyle(fontSize: 14),
                    ));
                    sectionWidgets.add(Text(
                      "주소: ${contact["주소"]}",
                      style: TextStyle(fontSize: 14),
                    ));
                  }
                  sectionWidgets.add(SizedBox(height: 16));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: sectionWidgets,
                  );
                })),
                // 효력 발생일
                Text(
                  "효력 발생일: ${policyData["effectiveDate"]}",
                  style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
        // 확인 버튼
        Container(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '확인',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF1066FF),
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 테이블 형식 위젯 생성 (Table 위젯 사용)
  Widget _buildTable({required List<String> headers, required List<Map<String, dynamic>> rows}) {
    return Table(
      border: TableBorder.all(color: Colors.grey),
      columnWidths: {
        0: FlexColumnWidth(),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
      },
      children: [
        // 헤더 row
        TableRow(
          decoration: BoxDecoration(color: Colors.grey[300]),
          children: headers
              .map(
                (header) => Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                header,
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          )
              .toList(),
        ),
        // 데이터 row
        ...rows.map(
              (row) => TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  row[headers[0]] ?? "",
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  row[headers[1]] ?? "",
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  row[headers[2]] ?? "",
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        )
      ],
    );
  }
}
