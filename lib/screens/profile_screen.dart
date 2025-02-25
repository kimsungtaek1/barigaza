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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await AuthUtils.checkLoginAndShowAlert(context)) {
        await _loadUserData();
        if (mounted) {
          setState(() {});
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
                          color: Colors.blue,
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
                icon: const Icon(Icons.edit, color: Colors.grey),
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
        ],
      ),
    );
  }

  Widget _buildMeetingsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('meetings')
          .where('participants', arrayContains: _auth.currentUser?.uid)
          .orderBy('meetingTime', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('데이터를 불러오는데 실패했습니다');
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final meetings = snapshot.data?.docs ?? [];

        if (meetings.isEmpty) {
          return Center(
            child: Text('참여 중인 번개 모임이 없습니다', style: TextStyle(color: Colors.grey)),
          );
        }

        return Column(
          children: meetings.map((meeting) {
            final data = meeting.data() as Map<String, dynamic>;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey[200],
                child: Icon(Icons.group, color: Colors.grey),
              ),
              title: Text(data['title'] ?? '제목 없음'),
              subtitle: Text(data['address'] ?? '주소 없음'),
              trailing: Icon(Icons.chevron_right),
              onTap: () {
                if (data['chatRoomId'] != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatRoomScreen(
                        chatId: data['chatRoomId'],
                        otherUserNickname: data['title'] ?? '번개 모임',
                      ),
                    ),
                  );
                }
              },
            );
          }).toList(),
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
          return Center(child: CircularProgressIndicator());
        }

        final posts = snapshot.data?.docs ?? [];

        if (posts.isEmpty) {
          return Center(
            child: Text('작성한 게시글이 없습니다', style: TextStyle(color: Colors.grey)),
          );
        }

        return Column(
          children: posts.map((post) {
            final data = post.data() as Map<String, dynamic>;

            return StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('posts')
                    .doc(post.id)
                    .collection('comments')
                    .snapshots(),
                builder: (context, commentSnapshot) {
                  final commentCount = commentSnapshot.data?.docs.length ?? 0;

                  return ListTile(
                    leading: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        data['category'] ?? '카테고리 없음',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    title: Text(data['title'] ?? '제목 없음'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          commentCount.toString(),
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
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
                  );
                }
            );
          }).toList(),
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
      appBar: AppBar(
        title: const Text('마이페이지', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _handleLogout,
            child: const Text('로그아웃', style: TextStyle(color: Colors.red)),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '내 정보'),
            Tab(text: '내 차량'),
          ],
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Color(0xFF756C54),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 마이페이지 탭
          RefreshIndicator(
            onRefresh: _loadUserData,
            child: SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProfileInfo(),
                  Divider(),
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '참여중인 채팅방',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        _buildMeetingsList(),
                        SizedBox(height: 16),
                        Text(
                          '작성글',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        _buildPostsList(),
                      ],
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
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: '홈',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.group_outlined),
                activeIcon: Icon(Icons.group),
                label: '커뮤니티',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.directions_car_outlined),
                activeIcon: Icon(Icons.directions_car),
                label: '내 차',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.flash_on_outlined),
                activeIcon: Icon(Icons.flash_on),
                label: '번개',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.chat_bubble_outline),
                activeIcon: Icon(Icons.chat_bubble),
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
