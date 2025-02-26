import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;

import '../../models/event.dart';
import '../../services/storage_service.dart';

class EventModifyScreen extends StatefulWidget {
  final Event? event;

  const EventModifyScreen({Key? key, this.event}) : super(key: key);

  @override
  _EventModifyScreenState createState() => _EventModifyScreenState();
}

class _EventModifyScreenState extends State<EventModifyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _contentController = TextEditingController();
  DateTime _startDate = DateTime.now(); // 기본값 설정
  DateTime _endDate = DateTime.now().add(Duration(days: 7)); // 기본값 설정
  File? _imageFile;
  String? _currentImageUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() {
    if (widget.event != null) {
      _titleController.text = widget.event!.title;
      _subtitleController.text = widget.event!.subtitle;
      _contentController.text = widget.event!.content;
      _startDate = widget.event!.startDate;
      _endDate = widget.event!.endDate;
      _currentImageUrl = widget.event!.imageUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event == null ? '새 이벤트 등록' : '이벤트 수정'),
        actions: [
          if (widget.event != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _handleDelete,
            ),
          TextButton(
            onPressed: _isLoading ? null : _handleSubmit,
            child: const Text(
              '저장',
              style: TextStyle(
                color: Colors.black, // 텍스트 색상을 흰색으로 설정
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildImageField(),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _titleController,
                label: '제목',
                validator: (value) => value?.isEmpty ?? true ? '제목을 입력하세요' : null,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _subtitleController,
                label: '소제목',
                validator: (value) => value?.isEmpty ?? true ? '소제목을 입력하세요' : null,
              ),
              const SizedBox(height: 16),
              _buildDateRangeField(),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _contentController,
                label: '내용',
                maxLines: 10,
                validator: (value) => value?.isEmpty ?? true ? '내용을 입력하세요' : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      maxLines: maxLines,
      validator: validator,
    );
  }

  Widget _buildDateRangeField() {
    return Row(
      children: [
        Expanded(
          child: _buildDateField(
            '시작일',
            _startDate!,
                (date) => setState(() => _startDate = date),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildDateField(
            '종료일',
            _endDate!,
                (date) => setState(() => _endDate = date),
          ),
        ),
      ],
    );
  }

  Widget _buildImageField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '이벤트 이미지',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_imageFile != null)
          Stack(
            children: [
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  image: DecorationImage(
                    image: FileImage(_imageFile!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton(
                  onPressed: () => setState(() {
                    _imageFile = null;
                    _currentImageUrl = null;
                  }),
                  icon: const Icon(Icons.close),
                  color: Colors.white,
                ),
              ),
            ],
          )
        else if (_currentImageUrl != null && _currentImageUrl!.isNotEmpty)
          Stack(
            children: [
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  image: DecorationImage(
                    image: NetworkImage(_currentImageUrl!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton(
                  onPressed: () => setState(() {
                    _imageFile = null;
                    _currentImageUrl = null;
                  }),
                  icon: const Icon(Icons.close),
                  color: Colors.white,
                ),
              ),
            ],
          )
        else
          InkWell(
            onTap: _pickImage,
            child: Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate, size: 48),
                  SizedBox(height: 8),
                  Text('이미지를 선택하세요'),
                ],
              ),
            ),
          ),
      ],
    );
  }
  Future<void> _pickImage() async {
    try {
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text('이미지 선택'),
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

      final XFile? pickedFile = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지를 선택하는 중 오류가 발생했습니다')),
      );
    }
  }

  Widget _buildDateField(
      String label,
      DateTime value,
      void Function(DateTime) onChanged,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (picked != null) {
              onChanged(picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('yyyy.MM.dd').format(value),
                  style: const TextStyle(fontSize: 16),
                ),
                const Icon(Icons.calendar_today),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이벤트 기간을 설정해주세요')),
      );
      return;
    }

    if (_endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('종료일은 시작일 이후여야 합니다')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? imageUrl;

      if (_imageFile != null) {
        final storageService = StorageService();
        final fileName = 'events/${DateTime.now().millisecondsSinceEpoch}${path.extension(_imageFile!.path)}';

        final bytes = await _imageFile!.readAsBytes();

        final result = await storageService.uploadFile(
          path: fileName,
          data: bytes,
          contentType: 'image/jpeg',
          customMetadata: {
            'uploadedBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
            'timestamp': DateTime.now().toIso8601String(),
            'type': 'event_image'
          },
        );

        if (result.isSuccess && result.data != null) {
          imageUrl = result.data;
        } else {
          throw Exception(result.error ?? '이미지 업로드에 실패했습니다');
        }
      }

      final eventData = {
        'title': _titleController.text,
        'subtitle': _subtitleController.text,
        'content': _contentController.text,
        'imageUrl': imageUrl ?? _currentImageUrl ?? '',
        'startDate': Timestamp.fromDate(_startDate!),
        'endDate': Timestamp.fromDate(_endDate!),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.event != null) {
        await FirebaseFirestore.instance
            .collection('events')
            .doc(widget.event!.id)
            .update(eventData);
      } else {
        eventData['createdAt'] = FieldValue.serverTimestamp();
        eventData['isActive'] = true;
        await FirebaseFirestore.instance
            .collection('events')
            .add(eventData);
      }

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.event == null ? '이벤트가 등록되었습니다' : '이벤트가 수정되었습니다',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('오류가 발생했습니다: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이벤트 삭제'),
        content: const Text('이 이벤트를 삭제하시겠습니까?'),
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

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      // 이미지 삭제
      if (_currentImageUrl != null) {
        final ref = FirebaseStorage.instance.refFromURL(_currentImageUrl!);
        await ref.delete();
      }

      // Firestore 문서 삭제
      await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event!.id)
          .delete();

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이벤트가 삭제되었습니다')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('삭제 중 오류가 발생했습니다: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
}// TODO Implement this library.