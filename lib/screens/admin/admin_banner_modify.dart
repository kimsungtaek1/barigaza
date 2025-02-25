import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/storage_service.dart';
import 'dart:io';

class AdminBannerModifyScreen extends StatefulWidget {
  final DocumentSnapshot? banner;

  const AdminBannerModifyScreen({
    Key? key,
    this.banner,
  }) : super(key: key);

  @override
  State<AdminBannerModifyScreen> createState() =>
      _AdminBannerModifyScreenState();
}

class _AdminBannerModifyScreenState extends State<AdminBannerModifyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();

  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _endDate;
  TimeOfDay? _endTime;

  File? _imageFile;
  String? _currentImageUrl;

  // 노출 여부 (true: 노출, false: 비노출)
  bool _isActive = true;

  bool _isLoading = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadBannerData();
  }

  void _loadBannerData() {
    if (widget.banner != null) {
      final data = widget.banner!.data() as Map<String, dynamic>;
      _titleController.text = data['title'] ?? '';

      final startDateTime = (data['startDateTime'] as Timestamp).toDate();
      final endDateTime = (data['endDateTime'] as Timestamp).toDate();

      // 만약 현재 시간이 종료 일시 이후라면 노출 여부를 false로 설정
      bool activeFromFirestore = data['isActive'] ?? true;
      if (DateTime.now().isAfter(endDateTime)) {
        activeFromFirestore = false;
      }

      setState(() {
        _startDate = startDateTime;
        _startTime = TimeOfDay.fromDateTime(startDateTime);
        _endDate = endDateTime;
        _endTime = TimeOfDay.fromDateTime(endDateTime);
        _currentImageUrl = data['imageUrl'];
        _isActive = activeFromFirestore;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          widget.banner != null ? '배너 상세' : '새 배너 등록',
          style: const TextStyle(color: Colors.black),
        ),
        actions: _buildAppBarActions(),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitleField(),
                  const SizedBox(height: 24),
                  _buildDateTimeField('시작', _startDate, _startTime, true),
                  const SizedBox(height: 24),
                  _buildDateTimeField('종료', _endDate, _endTime, false),
                  const SizedBox(height: 24),
                  _buildVisibilityRadio(), // Flutter 기본 라디오 버튼 사용
                  const SizedBox(height: 24),
                  _buildImageField(),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    if (widget.banner != null) {
      return [
        TextButton(
          onPressed: _handleDelete,
          child: const Text(
            '삭제',
            style: TextStyle(color: Colors.red),
          ),
        ),
        TextButton(
          onPressed: _isLoading ? null : _handleSubmit,
          child: const Text(
            '수정',
            style: TextStyle(color: Colors.black),
          ),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: _isLoading ? null : _handleSubmit,
        child: const Text(
          '저장',
          style: TextStyle(color: Colors.black),
        ),
      ),
    ];
  }

  Widget _buildTitleField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '배너 제목',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _titleController,
          decoration: const InputDecoration(
            hintText: '배너 제목을 입력하세요',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '배너 제목을 입력해주세요';
            }
            return null;
          },
        ),
      ],
    );
  }

  /// 날짜와 시간 필드 (시작/종료 구분)
  Widget _buildDateTimeField(String label, DateTime? date, TimeOfDay? time, bool isStart) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label 일시',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                readOnly: true,
                onTap: () => _selectDate(
                  date,
                      (selectedDate) {
                    setState(() {
                      if (isStart) {
                        _startDate = selectedDate;
                      } else {
                        _endDate = selectedDate;
                      }
                    });
                  },
                  // 종료 날짜 선택 시, 시작 날짜 이후만 선택 가능하도록
                  firstDate: isStart ? DateTime.now() : (_startDate ?? DateTime.now()),
                ),
                decoration: InputDecoration(
                  hintText: '날짜 선택',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                controller: TextEditingController(
                  text: date != null ? '${date.year}년 ${date.month}월 ${date.day}일' : '',
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return '날짜를 선택해주세요';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                readOnly: true,
                onTap: () => _selectTime(
                  time,
                      (selectedTime) {
                    setState(() {
                      if (isStart) {
                        _startTime = selectedTime;
                      } else {
                        _endTime = selectedTime;
                      }
                    });
                  },
                  isEnd: !isStart,
                ),
                decoration: InputDecoration(
                  hintText: '시간 선택',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.access_time),
                ),
                controller: TextEditingController(
                  text: time != null
                      ? '${time.hour}:${time.minute.toString().padLeft(2, '0')}'
                      : '',
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return '시간을 선택해주세요';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Flutter 기본 라디오 버튼을 사용하여 노출 여부 선택
  Widget _buildVisibilityRadio() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '노출 여부',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: _isActive,
              onChanged: (bool? value) {
                setState(() {
                  _isActive = value!;
                });
              },
            ),
            const Text('노출'),
            Radio<bool>(
              value: false,
              groupValue: _isActive,
              onChanged: (bool? value) {
                setState(() {
                  _isActive = value!;
                });
              },
            ),
            const Text('비노출'),
          ],
        ),
      ],
    );
  }

  Widget _buildImageField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '배너 이미지',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: GestureDetector(
            onTap: _pickImage,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildImagePreview(),
            ),
          ),
        ),
        if (_isUploading) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _uploadProgress / 100),
          const SizedBox(height: 4),
          Text('업로드 중... ${_uploadProgress.toStringAsFixed(1)}%'),
        ],
      ],
    );
  }

  /// showDatePicker에 builder를 추가하여 확인 버튼(OK) 텍스트 색상을 검은색으로 변경하고,
  /// initialDate가 firstDate보다 이전이면 firstDate를 사용하도록 함.
  Future<void> _selectDate(
      DateTime? currentDate,
      Function(DateTime) onSelect, {
        required DateTime firstDate,
      }) async {
    final DateTime effectiveInitialDate = (currentDate == null || currentDate.isBefore(firstDate))
        ? firstDate
        : currentDate;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: effectiveInitialDate,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: Colors.black),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) onSelect(picked);
  }

  /// showTimePicker에 builder를 추가하여 확인 버튼 텍스트 색상을 검은색으로 변경하고,
  /// 종료 시간 선택 시 (같은 날짜인 경우) 시작 시간보다 늦은 시간만 허용하도록 함.
  Future<void> _selectTime(
      TimeOfDay? currentTime,
      Function(TimeOfDay) onSelect, {
        bool isEnd = false,
      }) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: currentTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: Colors.black),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: Colors.black),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      if (isEnd && _startDate != null) {
        // 만약 종료 날짜가 시작 날짜와 같은 경우, 시작 시간보다 늦은 시간이어야 함.
        if (_endDate == null ||
            (_endDate!.year == _startDate!.year &&
                _endDate!.month == _startDate!.month &&
                _endDate!.day == _startDate!.day)) {
          if (_startTime != null) {
            final int startMinutes = _startTime!.hour * 60 + _startTime!.minute;
            final int pickedMinutes = picked.hour * 60 + picked.minute;
            if (pickedMinutes <= startMinutes) {
              _showErrorSnackBar('종료 시간은 시작 시간보다 늦어야 합니다.');
              return;
            }
          }
        }
      }
      onSelect(picked);
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      _showErrorSnackBar('이미지 선택에 실패했습니다');
    }
  }

  Widget _buildImagePreview() {
    if (_imageFile != null) {
      return Image.file(_imageFile!, fit: BoxFit.cover);
    }
    if (_currentImageUrl != null) {
      return Image.network(_currentImageUrl!, fit: BoxFit.cover);
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey),
        SizedBox(height: 8),
        Text('이미지를 선택하세요'),
      ],
    );
  }

  Future<String?> _uploadImage(File imageFile) async {
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('로그인이 필요합니다.');

      // 사용자 권한 확인 추가
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) throw Exception('사용자 정보를 찾을 수 없습니다.');

      final userData = userDoc.data() as Map<String, dynamic>;
      final userRole = userData['role'] as String?;

      if (!['admin', 'master'].contains(userRole)) {
        throw Exception('권한이 없습니다.');
      }

      final bytes = await imageFile.readAsBytes();
      final String fileExtension = imageFile.path.split('.').last.toLowerCase();
      final String fileName =
          'banner_${DateTime.now().millisecondsSinceEpoch}_${UniqueKey()}.$fileExtension';
      final String storagePath = 'banners/$fileName';

      final storageService = StorageService();
      final result = await storageService.uploadFile(
        path: storagePath,
        data: bytes,
        contentType: 'image/$fileExtension',
        customMetadata: {
          'uploadedBy': user.uid,
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'banner_image'
        },
      );

      if (!result.isSuccess || result.data == null) {
        throw Exception(result.error ?? '이미지 업로드에 실패했습니다.');
      }

      setState(() {
        _isUploading = false;
      });
      return result.data;
    } catch (e) {
      print('Upload error: $e');
      setState(() {
        _isUploading = false;
      });
      throw Exception('이미지 업로드에 실패했습니다');
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_imageFile == null && _currentImageUrl == null) {
      _showErrorSnackBar('이미지를 선택해주세요');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String imageUrl = _currentImageUrl ?? '';

      if (_imageFile != null) {
        if (_currentImageUrl != null) {
          try {
            final storageRef =
            FirebaseStorage.instance.refFromURL(_currentImageUrl!);
            await storageRef.delete();
          } catch (e) {
            print('기존 이미지 삭제 실패: $e');
          }
        }
        imageUrl = await _uploadImage(_imageFile!) ?? '';
      }

      final startDateTime = DateTime(
        _startDate!.year,
        _startDate!.month,
        _startDate!.day,
        _startTime!.hour,
        _startTime!.minute,
      );

      final endDateTime = DateTime(
        _endDate!.year,
        _endDate!.month,
        _endDate!.day,
        _endTime!.hour,
        _endTime!.minute,
      );

      final bannerData = {
        'title': _titleController.text,
        'imageUrl': imageUrl,
        'startDateTime': Timestamp.fromDate(startDateTime),
        'endDateTime': Timestamp.fromDate(endDateTime),
        'isActive': _isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.banner != null) {
        await widget.banner!.reference.update(bannerData);
        _showSuccessSnackBar('배너가 수정되었습니다');
      } else {
        bannerData['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('banners').add(bannerData);
        _showSuccessSnackBar('배너가 등록되었습니다');
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('배너 삭제'),
        content: const Text('이 배너를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true && widget.banner != null) {
      setState(() {
        _isLoading = true;
      });

      try {
        if (_currentImageUrl != null) {
          try {
            final storageRef =
            FirebaseStorage.instance.refFromURL(_currentImageUrl!);
            await storageRef.delete();
          } catch (e) {
            print('이미지 삭제 실패: $e');
          }
        }

        await widget.banner!.reference.delete();

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('배너가 삭제되었습니다')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('배너 삭제에 실패했습니다'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
