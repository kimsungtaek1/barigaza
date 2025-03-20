import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminReportedContentTab extends StatefulWidget {
  final bool isSelectionMode;

  const AdminReportedContentTab({
    Key? key,
    required this.isSelectionMode,
  }) : super(key: key);

  @override
  _AdminReportedContentTabState createState() => _AdminReportedContentTabState();
}

class _AdminReportedContentTabState extends State<AdminReportedContentTab> {
  Set<String> _selectedReports = {};
  List<DocumentSnapshot> _reportedContents = [];
  bool _isLoading = false;
  String _filterStatus = 'pending'; // 기본값은 처리 대기중인 신고만 표시

  @override
  void initState() {
    super.initState();
    _loadReportedContents();
  }

  @override
  void didUpdateWidget(AdminReportedContentTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isSelectionMode) {
      setState(() {
        _selectedReports.clear();
      });
    }
  }

  Future<void> _loadReportedContents() async {
    try {
      setState(() => _isLoading = true);
      
      // reportedContent 컬렉션에서 status 필터링하여 가져오기
      Query query = FirebaseFirestore.instance.collection('reportedContent');
      
      if (_filterStatus != 'all') {
        query = query.where('status', isEqualTo: _filterStatus);
      }
      
      final QuerySnapshot snapshot = await query
          .orderBy('createdAt', descending: true)
          .get();
          
      setState(() {
        _reportedContents = snapshot.docs;
        _isLoading = false;
      });
    } catch (e) {
      print('신고된 콘텐츠 로드 오류: $e');
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('신고된 게시물 로드 중 오류가 발생했습니다'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleReportedContent(String action) async {
    if (_selectedReports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택된 신고가 없습니다')),
      );
      return;
    }

    String title = '';
    String content = '';
    String confirmText = '';
    String newStatus = '';
    bool blockContent = false;

    if (action == 'approve') {
      title = '신고 승인';
      content = '선택한 ${_selectedReports.length}개의 신고를 승인하시겠습니까? 해당 콘텐츠는 차단됩니다.';
      confirmText = '승인';
      newStatus = 'blocked';
      blockContent = true;
    } else if (action == 'reject') {
      title = '신고 거부';
      content = '선택한 ${_selectedReports.length}개의 신고를 거부하시겠습니까?';
      confirmText = '거부';
      newStatus = 'rejected';
      blockContent = false;
    } else {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: action == 'approve' ? Colors.red : Colors.blue,
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      for (String reportId in _selectedReports) {
        // 신고 상태 업데이트
        final reportDoc = _reportedContents.firstWhere((doc) => doc.id == reportId);
        final reportData = reportDoc.data() as Map<String, dynamic>;
        
        // 1. reportedContent 컬렉션의 문서 상태 업데이트
        await reportDoc.reference.update({
          'status': newStatus,
          'processedAt': FieldValue.serverTimestamp(),
        });
        
        // 2. 신고된 게시물/댓글 차단 처리
        if (blockContent) {
          final contentType = reportData['contentType'] ?? 'post';
          
          if (contentType == 'chat') {
            // 추가 차단 로직이 필요할 수 있음 (예: 채팅 금지, 사용자 제한 등)
            // 채팅 메시지의 경우 이미 보고되었으므로 추가 액션이 필요 없음
            // 사용자 제한 등의 추가 기능을 구현할 수 있음
            
            // 여기에서는 상태만 업데이트
          } else {
            // 게시물이나 댓글 차단
            final postId = reportData['postId'];
            final commentId = reportData['commentId']; // 댓글인 경우
            
            if (commentId != null) {
              // 댓글 차단
              await FirebaseFirestore.instance
                  .collection('posts')
                  .doc(postId)
                  .collection('comments')
                  .doc(commentId)
                  .update({
                'reportStatus': 'blocked',
              });
            } else {
              // 게시물 차단
              await FirebaseFirestore.instance
                  .collection('posts')
                  .doc(postId)
                  .update({
                'reportStatus': 'blocked',
              });
            }
          }
        }
      }

      await _loadReportedContents();
      setState(() => _selectedReports.clear());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('선택한 신고가 ${action == 'approve' ? '승인' : '거부'}되었습니다')),
      );
    } catch (e) {
      print('신고 처리 오류: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('신고 처리 중 오류가 발생했습니다'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showReportDetail(DocumentSnapshot report) async {
    final reportData = report.data() as Map<String, dynamic>;
    final contentType = reportData['contentType'] ?? 'post';
    
    // 신고된 게시물, 댓글 또는 채팅 메시지 데이터 가져오기
    DocumentSnapshot? contentDoc;
    String displayContentType = 'post';
    String content = '';
    Map<String, dynamic>? contentData;
    String? imageUrl;
    
    try {
      if (contentType == 'chat') {
        // 채팅 메시지 신고인 경우
        displayContentType = reportData['messageType'] == 'image' ? '채팅 이미지' : '채팅 메시지';
        content = reportData['content'] ?? '내용 없음';
        imageUrl = reportData['imageUrl'];
        contentData = reportData;
      } else {
        // 게시물 또는 댓글 신고인 경우
        final postId = reportData['postId'];
        final commentId = reportData['commentId'];
        
        if (commentId != null) {
          contentDoc = await FirebaseFirestore.instance
              .collection('posts')
              .doc(postId)
              .collection('comments')
              .doc(commentId)
              .get();
          displayContentType = 'comment';
        } else {
          contentDoc = await FirebaseFirestore.instance
              .collection('posts')
              .doc(postId)
              .get();
        }
        
        if (contentDoc.exists) {
          contentData = contentDoc.data() as Map<String, dynamic>;
          content = displayContentType == 'post' 
              ? contentData!['content'] ?? '내용 없음'
              : contentData!['content'] ?? '댓글 내용 없음';
          
          // 이미지 URL 가져오기
          if (contentData!.containsKey('imageUrl') && contentData!['imageUrl'] != null) {
            imageUrl = contentData!['imageUrl'];
          }
        }
      }
    } catch (e) {
      print('콘텐츠 로드 오류: $e');
    }
    
    // 신고자 정보 가져오기
    String reporterName = '알 수 없음';
    try {
      final reporterId = reportData['reporterId'];
      if (reporterId != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(reporterId)
            .get();
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          reporterName = userData['nickname'] ?? '알 수 없음';
        }
      }
    } catch (e) {
      print('신고자 정보 로드 오류: $e');
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('신고 상세 정보'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('신고 유형: $displayContentType',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('신고 사유: ${reportData['reason'] ?? '이유 없음'}'),
              SizedBox(height: 8),
              Text('신고자: $reporterName'),
              SizedBox(height: 8),
              Text('신고 일시: ${_formatDate(reportData['createdAt'] as Timestamp?)}'),
              SizedBox(height: 16),
              Text('신고된 내용:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(content),
              ),
              if (imageUrl != null && imageUrl.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 8),
                    Text('이미지:'),
                    SizedBox(height: 4),
                    Image.network(
                      imageUrl,
                      height: 100,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => 
                          Container(
                            height: 100, 
                            color: Colors.grey[300],
                            child: Center(child: Text('이미지 로드 실패')),
                          ),
                    )
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('닫기'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handleSingleReport(report.id, 'reject');
            },
            child: Text('거부'),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handleSingleReport(report.id, 'approve');
            },
            child: Text('승인 (차단)'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSingleReport(String reportId, String action) async {
    setState(() => _selectedReports = {reportId});
    await _handleReportedContent(action);
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Wrap(
        spacing: 8.0,
        children: [
          ChoiceChip(
            label: Text('처리 대기'),
            selected: _filterStatus == 'pending',
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _filterStatus = 'pending';
                  _loadReportedContents();
                });
              }
            },
          ),
          ChoiceChip(
            label: Text('차단됨'),
            selected: _filterStatus == 'blocked',
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _filterStatus = 'blocked';
                  _loadReportedContents();
                });
              }
            },
          ),
          ChoiceChip(
            label: Text('거부됨'),
            selected: _filterStatus == 'rejected',
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _filterStatus = 'rejected';
                  _loadReportedContents();
                });
              }
            },
          ),
          ChoiceChip(
            label: Text('전체'),
            selected: _filterStatus == 'all',
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _filterStatus = 'all';
                  _loadReportedContents();
                });
              }
            },
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

    return Stack(
      children: [
        Column(
          children: [
            _buildFilterChips(),
            Expanded(
              child: _reportedContents.isEmpty
                  ? Center(child: Text('신고된 콘텐츠가 없습니다'))
                  : ListView.separated(
                      itemCount: _reportedContents.length,
                      padding: const EdgeInsets.only(bottom: kFloatingActionButtonMargin + 64),
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final report = _reportedContents[index];
                        final reportData = report.data() as Map<String, dynamic>;
                        final reportId = report.id;
                        final isSelected = _selectedReports.contains(reportId);
                        String contentType;
                        if (reportData['contentType'] == 'chat') {
                          contentType = reportData['messageType'] == 'image' ? '채팅이미지' : '채팅메시지';
                        } else {
                          contentType = reportData['commentId'] != null ? '댓글' : '게시물';
                        }
                        
                        Color statusColor;
                        switch (reportData['status']) {
                          case 'blocked': 
                            statusColor = Colors.red; 
                            break;
                          case 'rejected': 
                            statusColor = Colors.blue; 
                            break;
                          default: 
                            statusColor = Colors.orange;
                        }

                        return SizedBox(
                          width: MediaQuery.of(context).size.width,
                          child: ListTile(
                            leading: widget.isSelectionMode
                                ? Checkbox(
                                    value: isSelected,
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedReports.add(reportId);
                                        } else {
                                          _selectedReports.remove(reportId);
                                        }
                                      });
                                    },
                                  )
                                : null,
                            title: Row(
                              children: [
                                // 신고 유형 (1)
                                Expanded(
                                  flex: 2,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: statusColor),
                                    ),
                                    child: Text(
                                      contentType,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: statusColor,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                // 신고 사유 (6)
                                Expanded(
                                  flex: 6,
                                  child: Text(
                                    reportData['reason'] ?? '이유 없음',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // 신고일 (3)
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    _formatDate(reportData['createdAt'] as Timestamp?),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                // 상태 (2)
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    reportData['status'] == 'pending'
                                        ? '대기중'
                                        : reportData['status'] == 'blocked'
                                            ? '차단됨'
                                            : '거부됨',
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                            onTap: widget.isSelectionMode
                                ? () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedReports.remove(reportId);
                                      } else {
                                        _selectedReports.add(reportId);
                                      }
                                    });
                                  }
                                : () => _showReportDetail(report),
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
        if (widget.isSelectionMode && _selectedReports.isNotEmpty)
          Positioned(
            bottom: 16,
            right: 16,
            left: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: 'approve_report',
                  onPressed: () => _handleReportedContent('reject'),
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.thumb_down),
                  tooltip: '신고 거부',
                ),
                SizedBox(width: 16),
                FloatingActionButton(
                  heroTag: 'reject_report',
                  onPressed: () => _handleReportedContent('approve'),
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.block),
                  tooltip: '승인 및 차단',
                ),
              ],
            ),
          ),
      ],
    );
  }
}