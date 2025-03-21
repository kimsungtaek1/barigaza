import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SignUpScreen extends StatefulWidget {
  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _verificationCodeController = TextEditingController();
  final _nickController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = false;
  bool _isPhoneVerified = false;
  bool _isVerificationCodeSent = false;
  String? _verificationId;
  String? _selectedGender;

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return '비밀번호를 입력해주세요';
    }
    if (value.length < 6) {
      return '비밀번호는 6자 이상이어야 합니다';
    }
    return null;
  }

  String? _validatePasswordConfirm(String? value) {
    if (value == null || value.isEmpty) {
      return '비밀번호 확인을 입력해주세요';
    }
    if (value != _passwordController.text) {
      return '비밀번호가 일치하지 않습니다';
    }
    return null;
  }

  String? _validateName(String? value) {
    if (value == null || value.isEmpty) {
      return '이름을 입력해주세요';
    }
    if (value.length < 2) {
      return '이름은 2자 이상이어야 합니다';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return '휴대폰 번호를 입력해주세요';
    }
    // 예제: 010으로 시작하는 11자리 번호 (01012345678)
    if (!RegExp(r'^010\d{8}$').hasMatch(value)) {
      return '올바른 휴대폰 번호 형식이 아닙니다';
    }
    return null;
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool isPassword = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isPassword,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: validator,
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildGenderSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '성별 (선택사항)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                title: Text('남성'),
                value: 'male',
                groupValue: _selectedGender,
                onChanged: (String? value) {
                  setState(() {
                    _selectedGender = value;
                  });
                },
                activeColor: Color(0xFF1066FF),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                title: Text('여성'),
                value: 'female',
                groupValue: _selectedGender,
                onChanged: (String? value) {
                  setState(() {
                    _selectedGender = value;
                  });
                },
                activeColor: Color(0xFF1066FF),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPhoneVerification() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '휴대폰 번호',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                enabled: !_isPhoneVerified, // 인증 완료 시 비활성화
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey[100],
                  hintText: "'-' 없이 입력 (예: 01012345678)",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: _validatePhone,
              ),
            ),
            SizedBox(width: 8),
            Flexible(
              child: ElevatedButton(
                onPressed: !_isVerificationCodeSent && !_isPhoneVerified
                    ? _sendVerificationCode
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF1066FF),
                  padding: EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
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
                    filled: true,
                    fillColor: Colors.grey[100],
                    hintText: "인증번호 6자리 입력",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Flexible(
                child: ElevatedButton(
                  onPressed: !_isPhoneVerified ? _verifyPhone : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF1066FF),
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text('확인'),
                ),
              ),
            ],
          ),
        ],
        SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '회원가입',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTextField(
                    label: '이메일',
                    controller: _emailController,
                    hintText: '이메일을 입력하세요',
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '이메일을 입력해주세요';
                      }
                      if (!value.contains('@')) {
                        return '올바른 이메일 형식이 아닙니다';
                      }
                      return null;
                    },
                  ),
                  _buildTextField(
                    label: '비밀번호',
                    controller: _passwordController,
                    isPassword: true,
                    hintText: '비밀번호를 입력하세요',
                    validator: _validatePassword,
                  ),
                  _buildTextField(
                    label: '비밀번호 확인',
                    controller: _passwordConfirmController,
                    isPassword: true,
                    hintText: '비밀번호를 다시 입력하세요',
                    validator: _validatePasswordConfirm,
                  ),
                  _buildTextField(
                    label: '이름',
                    controller: _nameController,
                    hintText: '이름을 입력하세요',
                    validator: _validateName,
                  ),
                  _buildTextField(
                    label: '닉네임',
                    controller: _nickController,
                    hintText: '닉네임을 입력하세요',
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '닉네임을 입력해주세요';
                      }
                      return null;
                    },
                  ),
                  _buildGenderSelection(),
                  _buildPhoneVerification(),
                  SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: !_isLoading 
                          ? _handleSignUp
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF1066FF),
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
                        '가입하기',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 실제 Firebase Phone Auth를 통한 인증번호 발송
  Future<void> _sendVerificationCode() async {
    if (_phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('휴대폰 번호를 입력해주세요')),
      );
      return;
    }

    final String? validationResult = _validatePhone(_phoneController.text);
    if (validationResult != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationResult)),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 예제에서는 한국 번호 (01012345678)라고 가정하고, 국가코드 +82를 붙입니다.
      String phoneNumber = '+82' + _phoneController.text.substring(1);
      print("입력받은 번호: ${_phoneController.text}");
      print("포맷 후 번호: $phoneNumber");

      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // 안드로이드의 자동 SMS 검출 등으로 자동 인증이 완료될 경우
          await _auth.signInWithCredential(credential);
          setState(() {
            _isPhoneVerified = true;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('전화번호 인증이 자동으로 완료되었습니다.')),
          );
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          String errorMessage = '인증번호 발송에 실패했습니다.';
          if (e.code == 'invalid-phone-number') {
            errorMessage = '잘못된 전화번호 형식입니다.';
          } else if (e.code == 'too-many-requests') {
            errorMessage =
            '너무 많은 인증 시도가 있었습니다. 잠시 후 다시 시도해주세요.';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage)),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _isVerificationCodeSent = true;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('인증번호가 발송되었습니다.')),
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
        SnackBar(
            content:
            Text('인증번호 발송 중 오류가 발생했습니다: ${e.toString()}')),
      );
    }
  }

  /// 실제 SMS 코드와 Firebase에서 발급한 verificationId를 통해 인증 진행
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

      await _auth.signInWithCredential(credential);

      setState(() {
        _isPhoneVerified = true;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전화번호 인증이 완료되었습니다.')),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      String errorMessage = '인증번호가 올바르지 않습니다.';
      if (e.code == 'invalid-verification-code') {
        errorMessage = '인증번호가 올바르지 않습니다.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  /// 회원가입 처리 (전화번호 인증 후 이메일/비밀번호 계정 생성 및 Firestore 저장)
  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final User? phoneUser = _auth.currentUser;

      if (phoneUser == null) {
        // 전화번호 인증 후 아직 계정이 없다면 이메일/비밀번호 계정 생성
        final userCredential = await _auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        // Firestore에 사용자 정보 저장
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
          'uid': userCredential.user!.uid,
          'email': _emailController.text,
          'name': _nameController.text,
          'nickname': _nickController.text,
          'phone': _phoneController.text,
          'gender': _selectedGender, // 선택 사항이므로 null 가능
          'role': 'normal', // 기본 역할 지정
          'isPhoneVerified': _isPhoneVerified,
          'createdAt': FieldValue.serverTimestamp(),
          'lastActive': FieldValue.serverTimestamp(),
        });
      } else {
        // 이미 전화번호 인증된 사용자인 경우,
        // 이메일 제공자('password')가 연결되어 있는지 확인 후 링크 또는 업데이트 진행
        bool isEmailLinked = phoneUser.providerData
            .any((provider) => provider.providerId == 'password');

        if (!isEmailLinked) {
          final AuthCredential emailCredential = EmailAuthProvider.credential(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
          final UserCredential linkedUser =
          await phoneUser.linkWithCredential(emailCredential);

          await FirebaseFirestore.instance
              .collection('users')
              .doc(linkedUser.user!.uid)
              .set({
            'uid': linkedUser.user!.uid,
            'email': _emailController.text,
            'name': _nameController.text,
            'nickname': _nickController.text,
            'phone': _phoneController.text,
            'gender': _selectedGender, // 선택 사항이므로 null 가능
            'role': 'normal',
            'isPhoneVerified': _isPhoneVerified,
            'createdAt': FieldValue.serverTimestamp(),
            'lastActive': FieldValue.serverTimestamp(),
          });
        } else {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(phoneUser.uid)
              .set({
            'uid': phoneUser.uid,
            'email': _emailController.text,
            'name': _nameController.text,
            'nickname': _nickController.text,
            'phone': _phoneController.text,
            'gender': _selectedGender, // 선택 사항이므로 null 가능
            'role': 'normal',
            'isPhoneVerified': _isPhoneVerified,
            'createdAt': FieldValue.serverTimestamp(),
            'lastActive': FieldValue.serverTimestamp(),
          });
        }
      }

      // 회원가입 완료 후 홈 화면 등으로 이동
      Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      String errorMessage = '회원가입 실패';
      if (e.code == 'email-already-in-use') {
        errorMessage = '이미 가입된 이메일입니다';
      } else if (e.code == 'credential-already-in-use') {
        errorMessage = '이미 연동된 계정입니다';
      } else if (e.code == 'requires-recent-login') {
        errorMessage = '인증 세션이 만료되었습니다. 다시 시도해주세요';
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorMessage)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류 발생: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _verificationCodeController.dispose();
    _nickController.dispose();
    super.dispose();
  }
}
