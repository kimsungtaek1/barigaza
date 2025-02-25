import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminUpgradeRequestScreen extends StatefulWidget {
  const AdminUpgradeRequestScreen({Key? key}) : super(key: key);

  @override
  _AdminUpgradeRequestScreenState createState() => _AdminUpgradeRequestScreenState();
}

class _AdminUpgradeRequestScreenState extends State<AdminUpgradeRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _currentRole;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      setState(() {
        _currentRole = doc.data()?['role'] as String?;
        _userEmail = user.email;
        _nameController.text = doc.data()?['name'] ?? '';
        _phoneController.text = doc.data()?['phone'] ?? '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 등급 신청'),
        backgroundColor: const Color(0xFF2F6DF3),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoSection('현재 정보'),
              const SizedBox(height: 24),
              _buildUserInfoFields(),
              const SizedBox(height: 24),
              _buildRequestSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildInfoItem('현재등급', _currentRole ?? '일반회원'),
        _buildInfoItem('이메일', _userEmail ?? '로딩중...'),
      ],
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserInfoFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '신청자 정보',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: '이름',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '이름을 입력해주세요';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _phoneController,
          decoration: const InputDecoration(
            labelText: '연락처',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '연락처를 입력해주세요';
            }
            // 전화번호 형식 검증
            final phoneRegExp = RegExp(r'^01([0|1|6|7|8|9])-?([0-9]{3,4})-?([0-9]{4})$');
            if (!phoneRegExp.hasMatch(value)) {
              return '올바른 전화번호 형식이 아닙니다';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildRequestSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '신청 사유',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _reasonController,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: '관리자 권한이 필요한 사유를 상세히 작성해주세요',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '신청 사유를 입력해주세요';
            }
            if (value.length < 10) {
              return '최소 10자 이상 작성해주세요';
            }
            return null;
          },
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submitRequest,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
              '신청하기',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // 이전 신청 내역 확인
        final existingRequests = await FirebaseFirestore.instance
            .collection('admin_requests')
            .where('userId', isEqualTo: user.uid)
            .where('status', isEqualTo: 'pending')
            .get();

        if (existingRequests.docs.isNotEmpty) {
          _showErrorDialog('이미 처리중인 신청이 있습니다.');
          return;
        }

        // 사용자 정보 업데이트
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'name': _nameController.text,
          'phone': _phoneController.text,
        });

        // 관리자 권한 신청
        await FirebaseFirestore.instance
            .collection('admin_requests')
            .add({
          'userId': user.uid,
          'email': user.email,
          'name': _nameController.text,
          'phone': _phoneController.text,
          'reason': _reasonController.text,
          'status': 'pending',
          'currentRole': _currentRole,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // 성공 메시지 표시 및 화면 닫기
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('신청이 완료되었습니다. 검토 후 연락드리겠습니다.')),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      _showErrorDialog('오류가 발생했습니다. 다시 시도해주세요.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('오류'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}