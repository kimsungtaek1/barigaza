import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminAccountTab extends StatefulWidget {
  const AdminAccountTab({Key? key}) : super(key: key);

  @override
  _AdminAccountTabState createState() => _AdminAccountTabState();
}

class _AdminAccountTabState extends State<AdminAccountTab> {
  Map<String, dynamic>? _adminInfo;
  bool _isLoading = true;

  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _nameController = TextEditingController();
  final _nameConfirmController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _nicknameConfirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAdminInfo();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _nameController.dispose();
    _nameConfirmController.dispose();
    _nicknameController.dispose();
    _nicknameConfirmController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        setState(() {
          _adminInfo = doc.data();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      // Show error
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_adminInfo == null) {
      return const Center(child: Text('관리자 정보를 불러올 수 없습니다.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '관리자 상세 정보',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildInfoCard([
            _buildInfoItem('아이디', _adminInfo!['email'] ?? ''),
            _buildInfoItem('비밀번호', '********', showEdit: true),
            _buildInfoItem('이름', _adminInfo!['name'] ?? '', showEdit: true),
            _buildInfoItem('닉네임', _adminInfo!['nickname'] ?? '', showEdit: true),
            _buildInfoItem('연락처', _adminInfo!['phone'] ?? ''),
            _buildInfoItem('관리자 등급', _adminInfo!['role'] ?? ''),
          ]),
        ],
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, {bool showEdit = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[200]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          if (showEdit)
            GestureDetector(
              onTap: () => _showEditDialog(label.toLowerCase()),
              child: Icon(
                Icons.edit,
                size: 20,
                color: Colors.grey[400],
              ),
            ),
        ],
      ),
    );
  }

  void _showEditDialog(String field) {
    // 컨트롤러 초기화
    if (field == '비밀번호') {
      _passwordController.clear();
      _passwordConfirmController.clear();
    } else if (field == '이름') {
      _nameController.text = _adminInfo!['name'] ?? '';
    } else if (field == '닉네임') {
      _nicknameController.text = _adminInfo!['nickname'] ?? '';
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Text(
                  '$field 변경',
                  style: const TextStyle(color: Colors.black),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (field == '비밀번호') ...[
                      _buildEditField(
                        '새로운 비밀번호',
                        _passwordController,
                        isPassword: true,
                      ),
                      const SizedBox(height: 16),
                      _buildEditField(
                        '비밀번호 확인',
                        _passwordConfirmController,
                        isPassword: true,
                      ),
                    ] else if (field == '이름') ...[
                      _buildEditField(
                        '새로운 이름',
                        _nameController,
                      ),
                    ] else if (field == '닉네임') ...[
                      _buildEditField(
                        '새로운 닉네임',
                        _nicknameController,
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2F6DF3),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () => _handleSave(field),
                        child: const Text('저장하기'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave(String field) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      String? newValue;
      bool isValid = false;

      // 입력값 검증
      if (field == '비밀번호') {
        isValid = _passwordController.text.isNotEmpty &&
            _passwordController.text == _passwordConfirmController.text;
        newValue = _passwordController.text;
      } else if (field == '이름') {
        isValid = _nameController.text.isNotEmpty;
        newValue = _nameController.text;
      } else if (field == '닉네임') {
        isValid = _nicknameController.text.isNotEmpty;
        newValue = _nicknameController.text;
      }

      if (!isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('입력값을 확인해주세요'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 데이터 업데이트
      if (field == '비밀번호') {
        await user.updatePassword(newValue!);
      } else {
        String fieldName = field == '이름' ? 'name' : 'nickname';
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({fieldName: newValue});

        setState(() {
          if (_adminInfo != null) {
            _adminInfo![fieldName] = newValue;
          }
        });
      }

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$field가 변경되었습니다')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('오류가 발생했습니다: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildEditField(String label, TextEditingController controller, {bool isPassword = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          TextField(
            controller: controller,
            obscureText: isPassword,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}