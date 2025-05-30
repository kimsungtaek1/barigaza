import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../widgets/ad_banner_widget.dart';
import 'chat_room_screen.dart';
import 'community_content_screen.dart';
import 'home_screen.dart';
import 'my_vehicle_tab.dart';
import 'profile_edit_screen.dart';
import 'home_tab_screen.dart';
import 'community_screen.dart';
import 'my_car_screen.dart';
import 'flash_screen.dart';
import 'chat_list_screen.dart';
import '../utils/auth_utils.dart';

class ProfileScreen extends StatefulWidget {
  final int initialTabIndex; // 추가
  final int selectedBottomTab;
  final bool showBottomNav;

  const ProfileScreen({
    Key? key,
    this.initialTabIndex = 0, // 기본값 0으로 설정
    this.selectedBottomTab = 2,
    this.showBottomNav = false,
  }) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic> _userData = {};
  String? _tempProfileImage;
  int _selectedIndex = 0;

  final List<Widget> _screens = <Widget>[
    HomeTabScreen(),
    CommunityScreen(),
    MyCarScreen(),
    FlashScreen(),
    ChatListScreen()
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _selectedIndex = widget.selectedBottomTab;

    // 탭 완전히 변경되었을 때만 UI 업데이트하도록 최적화
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.previousIndex != _tabController.index) {
        setState(() {
          // 탭 인덱스 변경에 따른 UI 업데이트
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await AuthUtils.checkLoginAndShowAlert(context)) {
        await _loadUserData();
      } else {
        // 로그인되지 않은 경우 로딩 상태 해제
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          setState(() {
            _userData = doc.data() as Map<String, dynamic>;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfileImage() async {
    if (!await AuthUtils.checkLoginAndShowAlert(context)) {
      return;
    }

    try {
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

      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _isLoading = true;
        _tempProfileImage = image.path;
      });

      final user = _auth.currentUser;
      if (user == null) throw Exception('사용자 인증 정보가 없습니다.');

      final bytes = await File(image.path).readAsBytes();

      // 파일 이름에 타임스탬프 추가
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final String fileExtension = image.path.split('.').last.toLowerCase();
      final String storagePath = 'profile_images/${user.uid}/profile_$timestamp.$fileExtension';

      // 먼저 이전 프로필 이미지가 있다면 삭제 시도
      if (_userData['profileImage'] != null) {
        try {
          final storageService = StorageService();
          // URL에서 경로 추출
          final previousPath = Uri.decodeFull(Uri.parse(_userData['profileImage']).path)
              .replaceFirst('/o/', '')
              .split('?')[0];
          await storageService.deleteFile(previousPath);
        } catch (e) {
          debugPrint('이전 프로필 이미지 삭제 실패: $e');
        }
      }

      final storageService = StorageService();
      final result = await storageService.uploadFile(
        path: storagePath,
        data: bytes,
        contentType: 'image/$fileExtension',
        customMetadata: {
          'uploadedBy': user.uid,
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'profile_image'
        },
      );

      if (result.isSuccess && result.data != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'profileImage': result.data,
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        setState(() {
          _userData['profileImage'] = result.data;
          _isLoading = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('프로필 이미지가 업데이트되었습니다')),
          );
        }
      } else {
        throw Exception(result.error ?? '이미지 업로드에 실패했습니다.');
      }
    } catch (e) {
      debugPrint('프로필 이미지 업데이트 실패: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 업로드에 실패했습니다. 잠시 후 다시 시도해주세요.')),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signOut();
      Navigator.of(context).pushReplacementNamed('/');
    } catch (e) {
      print('Error signing out: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그아웃에 실패했습니다')),
      );
    }
  }

  Future<void> _handleDeleteAccount() async {
    // 로그인 제공자 확인
    final user = _auth.currentUser;
    if (user == null) return;

    final isEmailUser = user.providerData.any((element) =>
    element.providerId == 'password');

    final isGoogleUser = user.providerData.any((element) =>
    element.providerId == 'google.com');

    // 회원 탈퇴 확인 다이얼로그
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('회원 탈퇴'),
        content: Text('정말로 탈퇴하시겠습니까? 이 작업은 취소할 수 없으며, 모든 데이터가 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('탈퇴하기', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      setState(() => _isLoading = true);
      final authService = Provider.of<AuthService>(context, listen: false);

      // 이메일 사용자인 경우 비밀번호 재인증 필요
      if (isEmailUser) {
        // 비밀번호 입력 다이얼로그
        final password = await _showPasswordDialog();
        if (password == null || password.isEmpty) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('비밀번호를 입력해야 탈퇴할 수 있습니다')),
          );
          return;
        }

        await authService.deleteAccount(password: password);
      }
      // 구글 사용자인 경우
      else if (isGoogleUser) {
        await authService.deleteAccount();
      }
      // 기타 제공자
      else {
        throw '지원하지 않는 로그인 방식입니다.';
      }

      // 계정 삭제 후 처리 - 직접 로그인 화면으로 이동
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('계정이 성공적으로 삭제되었습니다')),
        );
        // 로그아웃 상태에서 로그인 화면으로 강제 이동
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        print('Error deleting account: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

// 비밀번호 입력 다이얼로그 표시 메서드 추가
  Future<String?> _showPasswordDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('본인 확인'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('계정 삭제를 위해 비밀번호를 입력해주세요.'),
              SizedBox(height: 16),
              TextFormField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '비밀번호를 입력해주세요';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: Colors.black,
            ),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop(controller.text);
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.black,
            ),
            child: Text('확인'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _updateProfileImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: _tempProfileImage != null
                          ? FileImage(File(_tempProfileImage!))
                          : (_userData['profileImage'] != null
                          ? NetworkImage(_userData['profileImage'])
                          : null) as ImageProvider?,
                      child: (_tempProfileImage == null &&
                          _userData['profileImage'] == null)
                          ? Icon(Icons.person, size: 40, color: Colors.grey)
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.camera_alt,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userData['nickname'] ?? '이름 없음',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _userData['phone'] ?? '전화번호 없음',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: ImageIcon(AssetImage('assets/images/pencil_selected.png'), color: Theme.of(context).primaryColor),
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => ProfileEditScreen()),
                  );
                  if (result == true) {
                    _loadUserData();
                  }
                },
              ),
            ],
          ),
          // SizedBox(height: 20), // 회원 탈퇴 버튼 이동으로 인한 간격 조정 (필요시 제거 또는 수정)
        ],
      ),
    );
  }

  // 이 메서드는 더 이상 필요하지 않음 - chatRooms에서 직접 lastMessage를 가져오기 때문
  // Future<String> _getLastMessage(String? chatRoomId) async { ... }

  // 날짜 포맷 도우미 함수 - 항상 YYYY.MM.DD 형식으로 출력
  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '날짜 없음';

    try {
      DateTime dateTime;
      if (timestamp is Timestamp) {
        dateTime = timestamp.toDate();
      } else {
        try {
          // timestamp가 Map인 경우 Firestore의 Timestamp 형식으로 변환 시도
          dateTime = DateTime.fromMillisecondsSinceEpoch(
              ((timestamp as Map)['_seconds'] ?? 0) * 1000 +
                  ((timestamp as Map)['_nanoseconds'] ?? 0) ~/ 1000000);
        } catch (e) {
          // 다른 형식의 timestamp 처리 시도
          if (timestamp is int) {
            dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          } else {
            return '날짜 없음';
          }
        }
      }

      // 항상 YYYY.MM.DD 형식으로 반환
      return '${dateTime.year}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return '날짜 오류';
    }
  }

  // 카테고리 탭 위젯을 빌드하는 메서드 (코드 분리 및 재사용성 향상)
  Widget _buildCategoryTab(int index, String title) {
    final isSelected = _tabController.index == index;
    // 성능 최적화: 필요한 스타일만 계산
    final textStyle = TextStyle(
      color: isSelected ? const Color(0xFF2F6DF3) : Colors.grey,
      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
    );

    return InkWell( // GestureDetector 대신 InkWell 사용 (더 나은 터치 반응성)
      onTap: () {
        if (_tabController.index != index) {
          _tabController.animateTo(index);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            Text(title, style: textStyle),
            const SizedBox(height: 3),
            Container(
              width: 40.0,
              height: 2,
              color: isSelected ? const Color(0xFF2F6DF3) : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }

  // 성능 최적화: 미팅 리스트 캐싱 기능 추가
  Widget _buildMeetingsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('chatRooms')
          .where('users', arrayContains: _auth.currentUser?.uid)
          .orderBy('lastMessageTime', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('데이터를 불러오는데 실패했습니다');
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final chatRooms = snapshot.data?.docs ?? [];

        if (chatRooms.isEmpty) {
          return const Center(
            child: Text('참여 중인 채팅방이 없습니다', style: TextStyle(color: Colors.grey)),
          );
        }

        // ListView.builder 사용하여 렌더링 최적화
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: chatRooms.length,
          itemBuilder: (context, index) {
            final chatRoom = chatRooms[index];
            final data = chatRoom.data() as Map<String, dynamic>;

            // 채팅방 제목 결정 로직
            String chatTitle = '채팅방';
            // 그룹 채팅인 경우
            if (data['isGroupChat'] == true) {
              chatTitle = data['groupName'] ?? '그룹 채팅';
            }
            // 1:1 채팅인 경우
            else {
              if (data['userDetails'] != null) {
                final userDetails = data['userDetails'] as Map<String, dynamic>;
                // 자신을 제외한 다른 사용자의 닉네임 찾기
                userDetails.forEach((userId, details) {
                  if (userId != _auth.currentUser?.uid) {
                    chatTitle = details['nickname'] ?? '채팅상대';
                  }
                });
              }
            }

            // 참여자 수 계산
            final participantsCount = (data['users'] as List?)?.length ?? 0;

            return Card(
              margin: EdgeInsets.only(bottom: 16),
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatRoomScreen(
                        chatId: chatRoom.id,
                        otherUserNickname: chatTitle,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              chatTitle,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '참여자 $participantsCount명',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Text(
                        '최근 메시지: ${data['lastMessage'] ?? '메시지 없음'}',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600]
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPostsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('posts')
          .where('userId', isEqualTo: _auth.currentUser?.uid)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('데이터를 불러오는데 실패했습니다');
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final posts = snapshot.data?.docs ?? [];

        if (posts.isEmpty) {
          return const Center(
            child: Text('작성한 게시글이 없습니다', style: TextStyle(color: Colors.grey)),
          );
        }

        // ListView.builder 사용으로 성능 향상
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            final data = post.data() as Map<String, dynamic>;

            return Card(
              margin: EdgeInsets.only(bottom: 16),
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CommunityContentScreen(
                        postId: post.id,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              data['category'] ?? '카테고리 없음',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              data['title'] ?? '제목 없음',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            data['createdAt'] != null
                                ? _formatDate(data['createdAt'])
                                : '날짜 없음',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '조회 ${data['viewCount'] ?? 0}',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
        backgroundColor: _tabController.index == 1 ? Colors.white : const Color(0xFFF3F4F6),
        appBar: AppBar(
          title: Text(
            '마이페이지',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: false,
          backgroundColor: Colors.white,
          elevation: 0,
          actions: [
            TextButton(
              onPressed: _handleLogout,
              child: const Text('로그아웃', style: TextStyle(color: Colors.red)),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(1.0),
            child: Container(
              color: Colors.grey[200],
              height: 1.0,
            ),
          ),
        ),
        body: Column(
            children: [
            Builder(
            builder: (context) {
        // 내 차량 탭(탭 인덱스가 1)인 경우 프로필 정보 표시하지 않음
        if (_tabController.index == 1) {
      return Container(
        height: 60,
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
            Padding(
              padding: EdgeInsets.only(left: 16),
              child: Row(
                children: [
                  _buildCategoryTab(0, '내 정보'),
                  _buildCategoryTab(1, '내 차량'),
                ],
              ),
            ),
            Spacer(),
          ],
        ),
      );
    } else {
    // 내 정보 탭인 경우 프로필 정보 표시
    return Column(
    children: [
    _buildProfileInfo(),
    // 카테고리 메뉴
    Container(
    height: 60,
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
    Padding(
    padding: EdgeInsets.only(left: 16),
    child: Row(
    children: [
    _buildCategoryTab(0, '내 정보'),
    _buildCategoryTab(1, '내 차량'),
    ],
    ),
    ),
    Spacer(),
    ],
    ),
    ),
    ],
    );
    }
    },
    ),
    Builder(
    builder: (context) {
    // 내 차량 탭(탭 인덱스가 1)에서는 SizedBox 없이 바로 표시
    if (_tabController.index == 1) {
    return SizedBox.shrink();
    } else {
    // 내 정보 탭에서는 SizedBox 유지
    return SizedBox(height: 16);
    }
    },
    ),
              // 탭 내용 - 스크롤 가능한 부분
              Expanded(
                child: Container(
                  color: Colors.transparent,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // 내 정보 탭
                      RefreshIndicator(
                        onRefresh: _loadUserData,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  physics: AlwaysScrollableScrollPhysics(),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '참여중인 채팅방',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Spacer(),
                                          GestureDetector(
                                            onTap: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (context) => ChatListScreen()),
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  const Text('더보기',
                                                    style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Transform.translate(
                                                    offset: Platform.isAndroid
                                                        ? const Offset(0, 1)
                                                        : const Offset(0, -1),
                                                    child: Icon(Icons.keyboard_arrow_right,
                                                        size: 14,
                                                        color: Color(0xFF6B7280)
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 4),
                                        child: _buildMeetingsList(),
                                      ),
                                      SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Text(
                                            '작성글',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            child: const Text('최근 5개', style: TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 4),
                                        child: _buildPostsList(),
                                      ),
                                      SizedBox(height: 32), // 게시글 목록과 탈퇴 버튼 사이 간격
                                      // 회원 탈퇴 버튼 (최하단으로 이동)
                                      InkWell(
                                        onTap: _handleDeleteAccount,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(vertical: 16), // 상하 패딩 추가
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.end, // 우측 정렬로 변경
                                            children: [
                                              Icon(Icons.delete_forever, color: Colors.red[300], size: 20),
                                              SizedBox(width: 8),
                                              Text(
                                                '회원 탈퇴',
                                                style: TextStyle(
                                                  color: Colors.red[300],
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: 16), // 하단 여백
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 내 차량 탭
                      MyVehicleTab(),
                    ],
                  ),
                ),
              ),
            ],
        ),
      bottomNavigationBar: widget.showBottomNav ? Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
              });
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => HomeScreen(initialIndex: index),
                ),
              );
            },
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Theme.of(context).primaryColor,
            unselectedItemColor: Colors.grey,
            items: const [
              BottomNavigationBarItem(
                icon: ImageIcon(AssetImage('assets/images/home.png')),
                activeIcon: ImageIcon(AssetImage('assets/images/home_selected.png')),
                label: '홈',
              ),
              BottomNavigationBarItem(
                icon: ImageIcon(AssetImage('assets/images/community.png')),
                activeIcon: ImageIcon(AssetImage('assets/images/community_selected.png')),
                label: '커뮤니티',
              ),
              BottomNavigationBarItem(
                icon: ImageIcon(AssetImage('assets/images/motorcycle.png')),
                activeIcon: ImageIcon(AssetImage('assets/images/motorcycle_selected.png')),
                label: '내 차',
              ),
              BottomNavigationBarItem(
                icon: ImageIcon(AssetImage('assets/images/thunder.png')),
                activeIcon: ImageIcon(AssetImage('assets/images/thunder_selected.png')),
                label: '번개',
              ),
              BottomNavigationBarItem(
                icon: ImageIcon(AssetImage('assets/images/chat.png')),
                activeIcon: ImageIcon(AssetImage('assets/images/chat_selected.png')),
                label: '채팅',
              ),
            ],
          ),
          const AdBannerWidget(),
        ],
      ) : null,
    );
  }
}