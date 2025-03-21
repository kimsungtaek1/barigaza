// lib/screens/community_write_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../services/storage_service.dart';
import 'dart:io';

class CommunityWriteScreen extends StatefulWidget {
  @override
  _CommunityWriteScreenState createState() => _CommunityWriteScreenState();
}

class _CommunityWriteScreenState extends State<CommunityWriteScreen> {
  final _formKey = GlobalKey<FormState>();
  String _selectedCategory = '자유주제';
  String _title = '';
  String _content = '';
  String _link = '';
  File? _image;
  bool _isLoading = false;

  final List<String> _categories = ['자유주제', '장비튜닝', '라이더뉴스'];

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        _image = File(image.path);
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_image == null) return null;

    final maxRetries = 3;
    var attempts = 0;

    while (attempts < maxRetries) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('사용자 인증 정보가 없습니다');

        final bytes = await _image!.readAsBytes();
        final String fileExtension = _image!.path.split('.').last.toLowerCase();
        final String fileName = 'post_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
        final String storagePath = 'post_images/$fileName';

        final storageService = StorageService();
        final result = await storageService.uploadFile(
          path: storagePath,
          data: bytes,
          contentType: 'image/$fileExtension',
          customMetadata: {
            'uploadedBy': user.uid,
            'timestamp': DateTime.now().toIso8601String(),
            'type': 'post_image'
          },
          onProgress: (progress) {
            print('Upload progress: ${(progress * 100).toStringAsFixed(2)}%');
          },
        );

        if (result.isSuccess && result.data != null) {
          print('Upload success. URL: ${result.data}');
          return result.data;
        }

        throw Exception('업로드 실패: ${result.error}');
      } catch (e) {
        attempts++;
        print('이미지 업로드 시도 $attempts 실패: $e');

        if (attempts >= maxRetries) {
          print('최대 재시도 횟수 초과');
          return null;
        }

        await Future.delayed(Duration(seconds: 2));
      }
    }

    return null;
  }

  Future<void> _submitPost() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 현재 로그인한 사용자 정보 가져오기
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인이 필요합니다.')),
        );
        return;
      }

      print("유저:$user");

      // 사용자 정보 가져오기 (Firestore에서)
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};

      final userNickname = userData['nickname'] ?? '알 수 없음';

      String? imageUrl = await _uploadImage();

      await FirebaseFirestore.instance.collection('posts').add({
        'category': _selectedCategory,
        'title': _title,
        'content': _content,
        'imageUrl': imageUrl,
        'link': _link,
        'createdAt': Timestamp.now(),
        'userId': user.uid,
        'nickname': userNickname,
        'likeCount': 0,
        'viewCount': 0,
        'reportStatus': '', // 기본 상태 추가
        'isReported': false, // 신고 여부
        'reportCount': 0, // 신고 수 
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게시물이 등록되었습니다.')),
      );
      Navigator.pop(context);
    } catch (e) {
      print('게시물 등록 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게시물 등록에 실패했습니다.')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('글쓰기', style: TextStyle(color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('주제 카테고리',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCategory,
                      isExpanded: true,
                      items: _categories.map((String category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedCategory = newValue;
                          });
                        }
                      },
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text('제목',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                SizedBox(height: 8),
                TextFormField(
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    hintText: '제목을 입력하세요',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '제목을 입력해주세요';
                    }
                    return null;
                  },
                  onChanged: (value) => _title = value,
                ),
                SizedBox(height: 20),
                Text('내용',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                SizedBox(height: 8),
                TextFormField(
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    hintText: '내용을 입력하세요',
                  ),
                  maxLines: 10,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '내용을 입력해주세요';
                    }
                    return null;
                  },
                  onChanged: (value) => _content = value,
                ),
                SizedBox(height: 20),
                Text('이미지 첨부',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _image != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _image!,
                        fit: BoxFit.cover,
                      ),
                    )
                        : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate,
                          size: 50,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: 8),
                        Text(
                          '이미지 등록하기',
                          style: TextStyle(
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text('링크 등록하기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                SizedBox(height: 8),
                TextFormField(
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    hintText: 'URL을 입력하세요',
                  ),
                  onChanged: (value) => _link = value,
                ),
                SizedBox(height: 30),
                Container(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _submitPost,
                    child: Text(
                      '등록하기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF1066FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
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
}