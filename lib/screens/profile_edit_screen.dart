import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../services/storage_service.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({Key? key}) : super(key: key);

  @override
  _ProfileEditScreenState createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _verificationCodeController = TextEditingController();


  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = true;
  bool _isPhoneVerified = false;
  bool _isVerificationCodeSent = false;
  String? _verificationId;
  String? _selectedGender;
  File? _tempProfileImage;
  Map<String, dynamic> _userData = {};
  String? _profileImage;
  String? _bikeImageUrl;
  File? _profileFile;
  File? _bikeImageFile;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final userData = doc.data() as Map<String, dynamic>;
          setState(() {
            _nameController.text = userData['name'] ?? '';
            _nicknameController.text = userData['nickname'] ?? '';
            _emailController.text = userData['email'] ?? '';
            _descriptionController.text = userData['description'] ?? '';
            _phoneController.text = userData['phone'] ?? '';
            _selectedGender = userData['gender'];
            _profileImage = userData['profileImage'];
            _bikeImageUrl = userData['bikeImage'];
            _selectedGender = userData['gender'] ?? '';
            _isLoading = false;
            _userData = userData;
          });
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfileImage() async {
    try {
      // 현재 사용자 확인
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }

      // 이미지 소스 선택 다이얼로그
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text('프로필 이미지 선택'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('갤러리에서 선택'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('카메라로 촬영'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      // 이미지 선택
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _isLoading = true;
        _tempProfileImage = File(image.path);
        _profileFile = File(image.path);
      });

      // 파일 읽기 및 경로 설정
      final bytes = await File(image.path).readAsBytes();
      final String fileExtension = image.path.split('.').last.toLowerCase();
      final String filename = 'profile_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final String storagePath = 'profile_images/${user.uid}/$filename';

      // 메타데이터 설정
      final metadata = {
        'uploadedBy': user.uid,
        'timestamp': DateTime.now().toIso8601String(),
        'type': 'profile_image',
        'originalFilename': image.name,
        'contentType': 'image/$fileExtension'
      };

      // Storage 서비스를 통한 업로드
      final storageService = StorageService();
      final result = await storageService.uploadFile(
        path: storagePath,
        data: bytes,
        contentType: 'image/$fileExtension',
        customMetadata: metadata,
        isProfileImage: true, // 프로필 이미지 최적화 (200KB 제한)
        optimizeImage: true,
        convertToWebpFormat: true, // WebP 포맷으로 변환
      );

      if (!result.isSuccess || result.data == null) {
        throw Exception(result.error ?? '이미지 업로드에 실패했습니다.');
      }

      // 이전 프로필 이미지 삭제 (옵션)
      if (_userData['profileImage'] != null) {
        try {
          final previousImageRef = FirebaseStorage.instance.refFromURL(_userData['profileImage']);
          await previousImageRef.delete();
        } catch (e) {
          print('이전 프로필 이미지 삭제 실패: $e');
        }
      }

      // Firestore 사용자 정보 업데이트
      await _firestore.collection('users').doc(user.uid).update({
        'profileImage': result.data,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // 상태 업데이트
      setState(() {
        _userData['profileImage'] = result.data;
        _isLoading = false;
      });

      // 성공 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('프로필 이미지가 업데이트되었습니다'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

    } catch (e) {
      print('프로필 이미지 업데이트 실패: $e');
      setState(() => _isLoading = false);

      if (mounted) {
        String errorMessage = '이미지 업로드에 실패했습니다.';

        if (e.toString().contains('permission-denied')) {
          errorMessage = '권한이 없습니다. 다시 로그인해주세요.';
        } else if (e.toString().contains('canceled')) {
          errorMessage = '업로드가 취소되었습니다.';
        } else if (e.toString().contains('not-found')) {
          errorMessage = '파일을 찾을 수 없습니다.';
        } else if (e.toString().contains('unauthorized')) {
          errorMessage = '인증되지 않은 사용자입니다.';
        } else if (e.toString().contains('quota-exceeded')) {
          errorMessage = '저장소 용량이 초과되었습니다.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
            action: SnackBarAction(
              label: '확인',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } finally {
      // 로딩 상태 해제
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildProfileImage() {
    return Column(
      children: [
        Center(
          child: Text(
            '프로필 사진',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ),
        SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: _updateProfileImage,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: _profileFile != null
                      ? FileImage(_profileFile!)
                      : (_profileImage != null
                      ? NetworkImage(_profileImage!) as ImageProvider
                      : null),
                  child: (_profileFile == null && _profileImage == null)
                      ? Icon(Icons.person, size: 50, color: Colors.grey)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    bool readOnly = false,
    int? maxLines,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          maxLines: maxLines ?? 1,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: maxLines != null ? 16 : 14,
            ),
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildGenderSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text( '성별', style: TextStyle(fontSize: 16, color: Colors.grey),),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                title: Text('남성'),
                value: 'male',
                groupValue: _selectedGender,
                onChanged: (value) => setState(() => _selectedGender = value),
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                title: Text('여성'),
                value: 'female',
                groupValue: _selectedGender,
                onChanged: (value) => setState(() => _selectedGender = value),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildBikeSelection() {
    return Column(
      children: [
        Center(
          child: Text(
            '내 차량 이미지',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
        SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: _updateBikeImage,
            child: Stack(
              children: [
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _bikeImageFile != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _bikeImageFile!,
                      fit: BoxFit.cover,
                    ),
                  )
                      : (_bikeImageUrl != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      _bikeImageUrl!,
                      fit: BoxFit.cover,
                    ),
                  )
                      : Center(
                    child: Icon(
                      Icons.directions_bike,
                      size: 64,
                      color: Colors.grey,
                    ),
                  )),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Future<void> _updateBikeImage() async {
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('차량 이미지 선택'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library),
              title: Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt),
              title: Text('카메라로 촬영'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _bikeImageFile = File(image.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지 선택에 실패했습니다')),
      );
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('사용자 인증 정보가 없습니다');

      String? profileImage = _profileImage;
      String? bikeImageUrl = _bikeImageUrl;

      // 프로필 이미지 업로드
      if (_profileFile != null) {
        final bytes = await _profileFile!.readAsBytes();
        final String fileExtension = _profileFile!.path.split('.').last.toLowerCase();
        final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        final String storagePath = 'profile_images/${user.uid}/profile_$timestamp.$fileExtension';

        final storageService = StorageService();
        final profileResult = await storageService.uploadFile(
          path: storagePath,
          data: bytes,
          contentType: 'image/$fileExtension',
          customMetadata: {
            'uploadedBy': user.uid,
            'timestamp': DateTime.now().toIso8601String(),
            'type': 'profile_image'
          },
          isProfileImage: true, // 프로필 이미지 최적화 (200KB 제한)
          optimizeImage: true,
          convertToWebpFormat: true, // WebP 포맷으로 변환
        );

        if (profileResult.isSuccess && profileResult.data != null) {
          profileImage = profileResult.data;
        } else {
          throw Exception(profileResult.error ?? '프로필 이미지 업로드에 실패했습니다.');
        }
      }

      // 차량 이미지 업로드
      if (_bikeImageFile != null) {
        final bytes = await _bikeImageFile!.readAsBytes();
        final String fileExtension = _bikeImageFile!.path.split('.').last.toLowerCase();
        final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        final String storagePath = 'bike_images/${user.uid}/bike_$timestamp.$fileExtension';

        final storageService = StorageService();
        final bikeResult = await storageService.uploadFile(
          path: storagePath,
          data: bytes,
          contentType: 'image/$fileExtension',
          customMetadata: {
            'uploadedBy': user.uid,
            'timestamp': DateTime.now().toIso8601String(),
            'type': 'bike_image'
          },
          isProfileImage: false, // 일반 이미지 최적화 (1MB 제한)
          optimizeImage: true,
          convertToWebpFormat: true, // WebP 포맷으로 변환
        );

        if (bikeResult.isSuccess && bikeResult.data != null) {
          bikeImageUrl = bikeResult.data;
        } else {
          throw Exception(bikeResult.error ?? '차량 이미지 업로드에 실패했습니다.');
        }
      }

      // Firestore에 사용자 정보 업데이트
      final Map<String, dynamic> updateData = {
        'name': _nameController.text.trim(),
        'nickname': _nicknameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'description': _descriptionController.text.trim(),
        'gender': _selectedGender,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      // 이미지 URL이 있는 경우에만 업데이트 데이터에 추가
      if (profileImage != null) {
        updateData['profileImage'] = profileImage;
      }
      if (bikeImageUrl != null) {
        updateData['bikeImage'] = bikeImageUrl;
      }

      // Firestore 업데이트 수행
      await _firestore.collection('users').doc(user.uid).update(updateData);

      // 성공 메시지 표시 및 화면 종료
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('프로필이 성공적으로 업데이트되었습니다'),
            backgroundColor: Colors.green,
          ),
        );

        // 데이터 새로고침
        await _loadUserData();
      }
    } catch (e) {
      print('프로필 저장 중 오류 발생: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('프로필 업데이트에 실패했습니다. 다시 시도해주세요.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '내 정보 수정',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProfileImage(),
                SizedBox(height: 24),
                _buildTextField(
                  label: '이름',
                  controller: _nameController,
                  hintText: '홍길동',
                ),
                _buildPhoneVerification(),
                _buildTextField(
                  label: '닉네임',
                  controller: _nicknameController,
                  hintText: '닉네임을 입력하세요',
                ),
                _buildTextField(
                  label: '이메일',
                  controller: _emailController,
                  readOnly: true,
                ),
                _buildGenderSelection(),
                _buildTextField(
                  label: '소개',
                  controller: _descriptionController,
                  hintText: '자기소개를 입력하세요',
                  maxLines: 3,
                ),
                _buildBikeSelection(),
                SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF1066FF),
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : Text(
                      '등록하기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneVerification() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '휴대폰 번호',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                enabled: !_isPhoneVerified,
                decoration: InputDecoration(
                  hintText: "'-' 없이 입력 (예: 01012345678)",
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),
            SizedBox(
              width: 100,
              height: 54, // TextFormField의 기본 높이와 동일하게 설정
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF1066FF),
                  padding: EdgeInsets.symmetric(vertical: 14), // TextFormField의 contentPadding과 동일
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8), // TextFormField와 동일한 borderRadius
                  ),
                ),
                onPressed: !_isVerificationCodeSent && !_isPhoneVerified
                    ? _sendVerificationCode
                    : null,
                child: Text(_isPhoneVerified ? '인증완료' : '인증번호 발송'),
              ),
            ),
          ],
        ),
        if (_isVerificationCodeSent && !_isPhoneVerified) ...[
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _verificationCodeController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: "인증번호 6자리 입력",
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              SizedBox(
                width: 100,
                height: 54, // TextFormField의 기본 높이와 동일하게 설정
                child: ElevatedButton(
                  onPressed: !_isPhoneVerified ? _verifyPhone : null,
                  child: Text('확인'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF1066FF),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _sendVerificationCode() async {
    if (_phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('휴대폰 번호를 입력해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String phoneNumber = '+82' + _phoneController.text.substring(1);

      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          setState(() {
            _isPhoneVerified = true;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('전화번호 인증이 완료되었습니다')),
          );
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('인증번호 발송에 실패했습니다')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _isVerificationCodeSent = true;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('인증번호가 발송되었습니다')),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          setState(() {
            _verificationId = verificationId;
            _isLoading = false;
          });
        },
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('인증번호 발송 중 오류가 발생했습니다')),
      );
    }
  }

  Future<void> _verifyPhone() async {
    if (_verificationCodeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('인증번호를 입력해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _verificationCodeController.text,
      );

      await _auth.currentUser?.updatePhoneNumber(credential);

      setState(() {
        _isPhoneVerified = true;
        _isLoading = false;
      });

      // Firestore에 전화번호 업데이트
      await _firestore.collection('users').doc(_auth.currentUser?.uid).update({
        'phone': _phoneController.text,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전화번호가 성공적으로 변경되었습니다')),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('인증번호가 올바르지 않습니다')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _emailController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}