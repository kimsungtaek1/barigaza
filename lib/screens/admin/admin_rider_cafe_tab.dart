import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/storage_service.dart';
import '../map_coordinate_picker.dart';
import '../naver_address_search_screen.dart';
import 'package:http/http.dart' as http;

class CafeRegistrationScreen extends StatefulWidget {
  final DocumentSnapshot? cafe;
  final VoidCallback onCafeUpdated;

  const CafeRegistrationScreen({
    Key? key,
    this.cafe,
    required this.onCafeUpdated,
  }) : super(key: key);

  @override
  State<CafeRegistrationScreen> createState() => _CafeRegistrationScreenState();
}

class _CafeRegistrationScreenState extends State<CafeRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _addressDetailController = TextEditingController();
  final _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final storageService = StorageService();
  XFile? _selectedImage;
  String? _existingImageUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.cafe != null) {
      final data = widget.cafe!.data() as Map<String, dynamic>;
      _nameController.text = data['name'] ?? '';
      _addressController.text = data['address'] ?? '';
      _addressDetailController.text = data['addressDetail'] ?? '';
      _descriptionController.text = data['description'] ?? '';
      _existingImageUrl = data['imageUrl'] as String?;
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      print('이미지 선택 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지 선택 중 오류가 발생했습니다')),
        );
      }
    }
  }

  Future<GeoPoint?> getCoordinatesFromAddress(String address) async {
    try {
      // 주소 정제
      String refinedAddress = address
          .replaceAll(RegExp(r'\s+'), ' ') // 중복 공백 제거
          .trim();

      // 건물명이나 상세주소가 포함된 경우 기본 주소만 추출
      if (refinedAddress.contains('(')) {
        refinedAddress = refinedAddress.split('(')[0].trim();
      }

      final String apiUrl = 'https://naveropenapi.apigw.ntruss.com/map-geocode/v2/geocode';
      final response = await http.get(
        Uri.parse('$apiUrl?query=${Uri.encodeComponent(refinedAddress)}'),
        headers: {
          'X-NCP-APIGW-API-KEY-ID': '5k1r2vy3lz',
          'X-NCP-APIGW-API-KEY': 'W6McBwHf5CFEVZpfz1DSuc2DdzTNC8Ks0l1paU4P',
        },
      );

      print('Geocoding API Response Status: ${response.statusCode}');
      print('Geocoding API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['addresses'] != null && data['addresses'].isNotEmpty) {
          final location = data['addresses'][0];
          return GeoPoint(
            double.parse(location['y']),
            double.parse(location['x']),
          );
        }
      }
      return null;
    } catch (e) {
      print('Geocoding error: $e');
      return null;
    }
  }

  Future<void> _saveCafe() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 주소가 비어있는지 확인
      if (_addressController.text.trim().isEmpty) {
        throw Exception('주소를 입력해주세요');
      }

      print('Getting coordinates for address: ${_addressController.text}');
      final coordinates = await getCoordinatesFromAddress(_addressController.text);

      GeoPoint? finalCoordinates = coordinates;

      if (coordinates == null) {
        // 좌표 변환 실패시 지도 화면으로 이동
        finalCoordinates = await Navigator.push<GeoPoint>(
          context,
          MaterialPageRoute(
            builder: (context) => MapCoordinatePicker(
              address: _addressController.text,
            ),
          ),
        );

        if (finalCoordinates == null) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치를 선택해주세요')),
          );
          return;
        }
      }

      if (widget.cafe == null) {
        // 새로운 카페 추가
        final docRef = await FirebaseFirestore.instance.collection('cafes').add({
          'name': _nameController.text,
          'address': _addressController.text,
          'addressDetail': _addressDetailController.text,
          'description': _descriptionController.text,
          'location': finalCoordinates,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'rating': 0.0,
          'reviewCount': 0,
          'createdBy': FirebaseAuth.instance.currentUser?.uid,
          'randomField': Random().nextDouble(),
        });

        if (_selectedImage != null) {
          final imageUrl = await _uploadImage(docRef.id);
          await docRef.update({'imageUrl': imageUrl});
        }
      } else {
        // 기존 카페 수정
        if (_selectedImage != null) {
          await _deleteExistingImage();
          final imageUrl = await _uploadImage(widget.cafe!.id);
          await widget.cafe!.reference.update({
            'name': _nameController.text,
            'address': _addressController.text,
            'addressDetail': _addressDetailController.text,
            'description': _descriptionController.text,
            'location': finalCoordinates,
            'imageUrl': imageUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await widget.cafe!.reference.update({
            'name': _nameController.text,
            'address': _addressController.text,
            'addressDetail': _addressDetailController.text,
            'description': _descriptionController.text,
            'location': finalCoordinates,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      widget.onCafeUpdated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.cafe == null ? '새로운 카페가 등록되었습니다' : '카페 정보가 수정되었습니다'),
          ),
        );
      }
    } catch (e) {
      print('카페 저장 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('카페 ${widget.cafe == null ? '등록' : '수정'} 중 오류가 발생했습니다: ${e.toString()}'),
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

  Future<String?> _uploadImage(String cafeId) async {
    if (_selectedImage == null) return null;

    try {
      final bytes = await File(_selectedImage!.path).readAsBytes();
      final String fileExtension = _selectedImage!.path.split('.').last.toLowerCase();
      final String filename = 'cafe_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final String storagePath = 'cafe_images/$cafeId/$filename';

      final result = await storageService.uploadFile(
        path: storagePath,
        data: bytes,
        contentType: 'image/$fileExtension',
        customMetadata: {
          'uploadedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'cafe_image'
        },
      );

      if (!result.isSuccess || result.data == null) {
        throw Exception(result.error ?? '이미지 업로드에 실패했습니다.');
      }

      return result.data;
    } catch (e) {
      print('이미지 업로드 오류: $e');
      rethrow;
    }
  }

  Future<void> _deleteExistingImage() async {
    if (_existingImageUrl == null) return;

    try {
      final ref = FirebaseStorage.instance.refFromURL(_existingImageUrl!);
      await ref.delete();
    } catch (e) {
      print('기존 이미지 삭제 오류: $e');
    }
  }

  Widget _buildSection(String title, Widget child) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cafe == null ? '라이더 카페 등록' : '라이더 카페 수정'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveCafe,
            child: const Text('저장'),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF8F8F8),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSection(
                '카페이름',
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: '바이크카페',
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return '카페 이름을 입력해주세요';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                '주소',
                Column(
                  children: [
                    TextFormField(
                      controller: _addressController,
                      readOnly: true,
                      decoration: InputDecoration(
                        hintText: '주소 검색',
                        border: InputBorder.none,
                        filled: true,
                        fillColor: Colors.white,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const NaverAddressSearch(),
                              ),
                            );
                            if (result != null) {
                              setState(() {
                                _addressController.text = result;
                              });
                            }
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value?.isEmpty ?? true) {
                          return '주소를 입력해주세요';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _addressDetailController,
                      decoration: InputDecoration(
                        hintText: '상세주소를 입력해주세요',
                        border: InputBorder.none,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                '카페 설명',
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: '내용을 입력해 주세요',
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return '카페 설명을 입력해주세요';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),
              _buildSection(
                '카페 이미지',
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _selectedImage != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_selectedImage!.path),
                        fit: BoxFit.cover,
                      ),
                    )
                        : _existingImageUrl != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _existingImageUrl!,
                        fit: BoxFit.cover,
                      ),
                    )
                        : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '사진 업로드하기',
                          style: TextStyle(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveCafe,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF756C54),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(widget.cafe == null ? '등록하기' : '수정하기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _addressDetailController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}

class AdminRiderCafeTab extends StatefulWidget {
  final bool isSelectionMode;

  const AdminRiderCafeTab({
    Key? key,
    required this.isSelectionMode,
  }) : super(key: key);

  @override
  _AdminRiderCafeTabState createState() => _AdminRiderCafeTabState();}

class _AdminRiderCafeTabState extends State<AdminRiderCafeTab> {
  Set<String> _selectedCafes = {};
  List<DocumentSnapshot> _cafes = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCafes();
  }

  @override
  void didUpdateWidget(AdminRiderCafeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isSelectionMode) {
      setState(() {
        _selectedCafes.clear();
      });
    }
  }

  Future<void> _loadCafes() async {
    try {
      setState(() => _isLoading = true);
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('cafes')
          .orderBy('createdAt', descending: true)
          .get();
      setState(() {
        _cafes = snapshot.docs;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('카페 정보 로드 중 오류가 발생했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteCafes() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('카페 삭제'),
          content: Text('선택한 ${_selectedCafes.length}개의 카페를 삭제하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('삭제'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() => _isLoading = true);

      for (String cafeId in _selectedCafes) {
        // 이미지 삭제
        final cafeDoc = await FirebaseFirestore.instance
            .collection('cafes')
            .doc(cafeId)
            .get();
        final cafeData = cafeDoc.data() as Map<String, dynamic>;

        if (cafeData['imageUrl'] != null) {
          try {
            final ref = FirebaseStorage.instance.refFromURL(cafeData['imageUrl']);
            await ref.delete();
          } catch (e) {
            print('이미지 삭제 중 오류 발생: $e');
          }
        }

        // 리뷰 삭제
        final reviewsSnapshot = await FirebaseFirestore.instance
            .collection('cafes')
            .doc(cafeId)
            .collection('reviews')
            .get();

        for (var doc in reviewsSnapshot.docs) {
          await doc.reference.delete();
        }

        // 카페 문서 삭제
        await FirebaseFirestore.instance
            .collection('cafes')
            .doc(cafeId)
            .delete();
      }

      await _loadCafes();
      setState(() => _selectedCafes.clear());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('선택한 카페가 삭제되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('카페 삭제 중 오류가 발생했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showCafeDetail(DocumentSnapshot cafe) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CafeRegistrationScreen(
          cafe: cafe,
          onCafeUpdated: _loadCafes,
        ),
      ),
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return '방금 전';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}시간 전';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}일 전';
    } else {
      return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        _cafes.isEmpty
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '등록된 라이더 카페가 없습니다',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        )
            : ListView.separated(
          itemCount: _cafes.length,
          padding: const EdgeInsets.only(
              bottom: kFloatingActionButtonMargin + 64),
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final cafe = _cafes[index];
            final cafeData = cafe.data() as Map<String, dynamic>;
            final cafeId = cafe.id;
            final isSelected = _selectedCafes.contains(cafeId);

            return ListTile(
              leading: widget.isSelectionMode
                  ? Checkbox(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedCafes.add(cafeId);
                    } else {
                      _selectedCafes.remove(cafeId);
                    }
                  });
                },
              )
                  : cafeData['imageUrl'] != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  cafeData['imageUrl'],
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                ),
              )
                  : Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.store,
                  color: Colors.grey[400],
                ),
              ),
              title: Text(
                cafeData['name'] ?? '이름 없음',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cafeData['address'] ?? '',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              onTap: widget.isSelectionMode
                  ? () {
                setState(() {
                  if (isSelected) {
                    _selectedCafes.remove(cafeId);
                  } else {
                    _selectedCafes.add(cafeId);
                  }
                });
              }
                  : () => _showCafeDetail(cafe),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
            );
          },
        ),
        if (widget.isSelectionMode && _selectedCafes.isNotEmpty)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _deleteCafes,
              backgroundColor: Colors.red,
              child: const Icon(Icons.delete),
            ),
          ),
        if (!widget.isSelectionMode)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CafeRegistrationScreen(
                      cafe: null,
                      onCafeUpdated: _loadCafes,
                    ),
                  ),
                );
              },
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }
}