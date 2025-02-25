// admin_user_tab.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminUserTab extends StatefulWidget {
  final bool isSelectionMode;

  const AdminUserTab({
    Key? key,
    required this.isSelectionMode,
  }) : super(key: key);

  @override
  _AdminUserTabState createState() => _AdminUserTabState();
}

class _AdminUserTabState extends State<AdminUserTab> {
  Set<String> _selectedUsers = {};
  List<DocumentSnapshot> _users = [];
  bool _isLoading = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String _formatName(String? name) {
    if (name == null || name.isEmpty) return '이름 없음';
    return name.length > 3 ? '${name.substring(0, 3)}...' : name;
  }

  /// role 값을 읽기 좋은 한글 텍스트로 변환 (원하는대로 수정)
  String _formatRole(String? role) {
    switch (role) {
      case 'normal':
        return '사용자';
      case 'admin':
        return '관리자';
      case 'master':
        return '마스터';
      default:
        return '사용자';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void didUpdateWidget(AdminUserTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isSelectionMode) {
      setState(() {
        _selectedUsers.clear();
      });
    }
  }

  Future<void> _loadUsers() async {
    try {
      setState(() => _isLoading = true);
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('name')
          .get();
      setState(() {
        _users = snapshot.docs;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('사용자 목록을 불러오는데 실패했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteUsers() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('사용자 삭제'),
          content: Text('선택한 ${_selectedUsers.length}명의 사용자를 삭제하시겠습니까?'),
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

      for (String userId in _selectedUsers) {
        await FirebaseFirestore.instance.collection('users').doc(userId).delete();
      }

      await _loadUsers();
      setState(() => _selectedUsers.clear());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('선택한 사용자가 삭제되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('사용자 삭제에 실패했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 사용자 상세 정보를 보여주는 다이얼로그 (권한 수정 가능)
  void _showUserDetailDialog(String userId, Map<String, dynamic> userData) {
    // 초기값은 Firestore에 저장된 값으로 설정
    String currentRole = userData['role'] ?? 'normal';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('사용자 상세 정보'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDetailItem('이름', userData['name'] ?? ''),
                    _buildDetailItem('이메일', userData['email'] ?? ''),
                    _buildDetailItem('전화번호', userData['phone'] ?? ''),
                    _buildDetailItem('상태', userData['status'] ?? ''),
                    // 권한 수정 UI
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(
                            width: 80,
                            child: Text(
                              '권한',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Expanded(
                            child: DropdownButton<String>(
                              value: currentRole,
                              icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                              underline: Container(
                                height: 1,
                                color: Colors.grey[300],
                              ),
                              items: ['normal', 'admin', 'master'].map((String role) {
                                return DropdownMenuItem<String>(
                                  value: role,
                                  child: Text(
                                    _formatRole(role),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setStateDialog(() {
                                    currentRole = newValue;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    if ((userData['description']?.isNotEmpty ?? false))
                      _buildDetailItem('자기소개', userData['description']),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('닫기'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // 변경된 권한이 기존과 다를 경우 업데이트 시도
                    if (currentRole != (userData['role'] ?? 'normal')) {
                      try {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(userId)
                            .update({'role': currentRole});
                        // Firestore 업데이트 후 전체 사용자 목록을 다시 불러와 UI를 갱신합니다.
                        await _loadUsers();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('권한이 업데이트되었습니다')),
                          );
                        }
                        Navigator.pop(context);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('업데이트 실패: $e')),
                          );
                        }
                      }
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 검색어에 따라 사용자 리스트 필터링
    final filteredUsers = _users.where((user) {
      final userData = user.data() as Map<String, dynamic>;
      final name = (userData['name'] ?? '').toString().toLowerCase();
      final email = (userData['email'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || email.contains(query);
    }).toList();

    return Stack(
      children: [
        Column(
          children: [
            // 검색바
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '사용자 검색 (이름 또는 이메일)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: filteredUsers.length,
                padding: const EdgeInsets.only(bottom: kFloatingActionButtonMargin + 64),
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final user = filteredUsers[index];
                  final userData = user.data() as Map<String, dynamic>;
                  final userId = user.id;
                  final isSelected = _selectedUsers.contains(userId);

                  return SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: ListTile(
                      leading: widget.isSelectionMode
                          ? Checkbox(
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedUsers.add(userId);
                            } else {
                              _selectedUsers.remove(userId);
                            }
                          });
                        },
                      )
                          : CircleAvatar(
                        backgroundImage: (userData['profileImage'] ?? '').toString().isNotEmpty
                            ? NetworkImage(userData['profileImage'])
                            : null,
                        child: (userData['profileImage'] == null ||
                            (userData['profileImage'] as String).isEmpty)
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              _formatName(userData['name']),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Text(
                              userData['email'] ?? '',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              _formatRole(userData['role']),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      onTap: widget.isSelectionMode
                          ? () {
                        setState(() {
                          if (isSelected) {
                            _selectedUsers.remove(userId);
                          } else {
                            _selectedUsers.add(userId);
                          }
                        });
                      }
                          : () => _showUserDetailDialog(userId, userData),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        if (widget.isSelectionMode && _selectedUsers.isNotEmpty)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _deleteUsers,
              backgroundColor: Colors.red,
              child: const Icon(Icons.delete),
            ),
          ),
      ],
    );
  }
}
