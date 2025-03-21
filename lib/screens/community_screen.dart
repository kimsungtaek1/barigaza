// lib/screens/community_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../widgets/post_grid.dart';
import 'community_content_screen.dart';
import 'community_posts_screen.dart';
import 'community_write_screen.dart';

class CommunityScreen extends StatefulWidget {
  @override
  _CommunityScreenState createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final PostService _postService = PostService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  String _selectedCategory = '팔로잉';
  String _selectedSort = '신규';
  String _searchQuery = '';
  bool _isSearching = false;

  final List<String> _categories = [
    '팔로잉',
    '탐색',
    '전체',
    '자유주제',
    '장비튜닝',
    '라이더뉴스'
  ];
  // 기본값은 '팔로잉'에서는 신규만 사용하므로 별도의 _sortOptions 변수 대신 동적으로 구성합니다.

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildCategoryMenu(),
          if (_selectedCategory == '탐색') _buildSearchBar(),
          Expanded(
            child: StreamBuilder<List<Post>>(
              stream: _postService.getPostsStream(
                category: _selectedCategory,
                sortBy: _selectedSort,
                searchQuery: _searchQuery,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildErrorWidget(snapshot.error.toString());
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                final posts = snapshot.data ?? [];
                return _buildPostList(posts);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'community_add_button',
        onPressed: _navigateToWriteScreen,
        backgroundColor: Color(0xFF2F6DF3),
        shape: CircleBorder(),
        child: Icon(
          Icons.add,
          color: Colors.white,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        '커뮤니티',
        style: TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.bold,
        ),
      ),
      centerTitle: false,
      backgroundColor: Colors.white,
      elevation: 0,
      actions: [
        IconButton(
          icon: ImageIcon(AssetImage('assets/images/pencil.png'), color: Colors.black87),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => CommunityPostsScreen()),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(1.0),
        child: Container(
          color: Colors.grey[200],
          height: 1.0,
        ),
      ),
    );
  }

  Widget _buildCategoryMenu() {
    // _selectedCategory에 따라 정렬 옵션을 다르게 구성
    List<String> sortOptions;
    if (_selectedCategory == '탐색') {
      sortOptions = ['추천순', '조회순', '신규'];
    } else {
      sortOptions = ['신규'];
    }

    return Container(
      height: 60, // 전체 높이 증가
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[200]!,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 2,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.only(left: 16),
            child: Container(
              width: 78, // 1.3배 정도 더 넓게 설정 (대략 60*1.3)
              child: DropdownButton<String>(
                value: _selectedSort,
                isExpanded: true, // 컨테이너 너비에 맞추기
                icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[600]), // V 모양 아이콘
                underline: SizedBox(), // 밑줄 제거
                items: sortOptions.map((String option) {
                  return DropdownMenuItem<String>(
                    value: option,
                    child: Text(
                      option,
                      style: TextStyle(
                        color: Colors.grey, // 카테고리 텍스트와 동일한 스타일
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() => _selectedSort = newValue);
                  }
                },
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;

                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedCategory = category;
                    _searchQuery = '';
                    _searchController.clear();
                    // 카테고리 변경 시 정렬 옵션도 업데이트 (탐색은 3개, 나머지는 신규만)
                    if (_selectedCategory == '탐색') {
                      _selectedSort = '추천순'; // 탐색 카테고리 기본값
                    } else {
                      _selectedSort = '신규';
                    }
                  }),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(height: 8), // 상단 여백 늘림
                        Text(
                          category,
                          style: TextStyle(
                            color: isSelected ? Color(0xFF2F6DF3) : Colors.grey, // primary color로 변경
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        SizedBox(height: 3), // 텍스트와 밑줄 사이 간격
                        FittedBox(
                          fit: BoxFit.none,
                          child: Container(
                            width: category.length * 12.0, // 글자 수에 비례해 너비 설정
                            height: 2, // 3픽셀 유지
                            color: isSelected ? Color(0xFF2F6DF3) : Colors.transparent, // primary color
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '검색어를 입력하세요',
              hintStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, color: Colors.grey[600]),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _isSearching = false;
                  });
                },
              )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(color: Colors.brown[200]!),
              ),
              fillColor: Colors.grey[100],
              filled: true,
            ),
            onChanged: _onSearchChanged,
          ),
          if (_isSearching)
            Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text(
                '검색 중...',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSortOptions() {
    // _selectedCategory에 따라 정렬 옵션을 다르게 구성
    List<String> sortOptions;
    if (_selectedCategory == '탐색') {
      sortOptions = ['추천순', '조회순', '신규'];
    } else {
      sortOptions = ['신규'];
    }
    return Container(
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          DropdownButton<String>(
            value: _selectedSort,
            icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
            underline: Container(
              height: 2,
              color: Colors.brown[200],
            ),
            items: sortOptions.map((String option) {
              return DropdownMenuItem<String>(
                value: option,
                child: Text(
                  option,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                  ),
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() => _selectedSort = newValue);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPostList(List<Post> posts) {
    if (_searchQuery.isNotEmpty && posts.isEmpty) {
      return _buildEmptySearchResult();
    }

    return PostGrid(
      posts: posts,
      onPostTap: (String postId) {
        _postService.incrementViews(postId);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CommunityContentScreen(postId: postId),
          ),
        );
      },
    );
  }

  Widget _buildEmptySearchResult() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            '검색 결과가 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '다른 검색어로 시도해보세요',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red[300],
          ),
          SizedBox(height: 16),
          Text(
            '오류가 발생했습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[800],
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '잠시 후 다시 시도해주세요',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    setState(() => _isSearching = true);

    _debounceTimer = Timer(Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = query.trim();
        _isSearching = false;
      });
    });
  }

  void _navigateToWriteScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CommunityWriteScreen()),
    );
  }
}
