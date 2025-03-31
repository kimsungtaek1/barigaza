import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_account_tab.dart';
import 'admin_banner_tab.dart';
import 'admin_event_tab.dart';
import 'admin_user_tab.dart';
import 'admin_community_tab.dart';
import 'admin_qna_tab.dart';
import 'admin_notice_tab.dart';
import 'admin_rider_cafe_tab.dart';
import 'admin_reported_content_tab.dart';
import 'admin_content_filter_screen.dart';
import 'admin_car_model_tab.dart';

class AdminMainScreen extends StatefulWidget {
  const AdminMainScreen({Key? key}) : super(key: key);

  @override
  _AdminMainScreenState createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  String _selectedTab = '관리자계정';
  final List<String> _tabs = ['관리자계정', '배너 광고', '이벤트', '사용자', '커뮤니티', '질문답변', '공지', '라이더카페', '신고관리', '금칙어관리', '차량모델'];
  bool _isSelectionMode = false;
  final List<String> _selectedItems = [];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '바리가자 관리자',
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: _buildActions(),
      ),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  List<Widget> _buildActions() {
    // 배너 광고 탭일 때는 + 버튼 표시
    if (_selectedTab == '배너 광고') {
      return [
        IconButton(
          icon: const Icon(Icons.add, color: Colors.black),
          onPressed: () {
            Navigator.pushNamed(context, '/admin-banner-modify');
          },
        ),
      ];
    }

    // 사용자, 커뮤니티, 신고관리, 라이더카페 탭일 때는 선택 버튼 표시
    if (_selectedTab == '사용자' || _selectedTab == '커뮤니티' || _selectedTab == '라이더카페' || _selectedTab == '신고관리') {
      return [
        TextButton(
          onPressed: () {
            setState(() {
              _isSelectionMode = !_isSelectionMode;
              if (!_isSelectionMode) {
                _selectedItems.clear();
              }
            });
          },
          child: Text(
            _isSelectionMode ? '취소' : '선택',
            style: const TextStyle(color: Colors.black),
          ),
        ),
        if (_isSelectionMode && _selectedItems.isNotEmpty)
          TextButton(
            onPressed: _handleDelete,
            child: const Text(
              '삭제',
              style: TextStyle(color: Colors.red),
            ),
          ),
      ];
    }

    return [];
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey, width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _tabs.map((tab) => _buildTab(tab)).toList(),
        ),
      ),
    );
  }

  Widget _buildTab(String title) {
    final isSelected = _selectedTab == title;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = title;
          _isSelectionMode = false; // 탭 변경시 선택 모드 초기화
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.black : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.grey,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  void _handleSelectionChanged(List<String> selectedItems) {
    setState(() {
      _selectedItems.clear();
      _selectedItems.addAll(selectedItems);
    });
  }

  Future<void> _handleDelete() async {
    // 탭에 따라 다른 삭제 로직 처리
    if (_selectedTab == '차량모델') {
      // 차량 모델 삭제 처리
      // 향후 구현 예정
    }

    setState(() {
      _selectedItems.clear();
    });
  }
  
  Widget _buildContent() {
    switch (_selectedTab) {
      case '관리자계정':
        return const AdminAccountTab();
      case '배너 광고':
        return const AdminBannerTab();
      case '사용자':
        return AdminUserTab(isSelectionMode: _isSelectionMode);
      case '커뮤니티':
        return AdminCommunityTab(isSelectionMode: _isSelectionMode);
      case '질문답변':
        return AdminQnaTab(isSelectionMode: _isSelectionMode);
      case '공지':
        return AdminNoticeTab(isSelectionMode: _isSelectionMode);
      case '라이더카페':
        return AdminRiderCafeTab(isSelectionMode: _isSelectionMode);
      case '이벤트':
        return AdminEventTab();
      case '신고관리':
        return AdminReportedContentTab(isSelectionMode: _isSelectionMode);
      case '금칙어관리':
        return const AdminContentFilterScreen();
      case '차량모델':
        return AdminCarModelTab(
          selectionMode: _isSelectionMode,
          onSelectionModeChanged: (value) {
            setState(() {
              _isSelectionMode = value;
            });
          },
          onSelectionChanged: _handleSelectionChanged,
        );
      default:
        return SizedBox.shrink();
    }
  }
}
