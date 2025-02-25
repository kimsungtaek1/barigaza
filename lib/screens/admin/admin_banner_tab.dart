import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_banner_modify.dart';

class AdminBannerTab extends StatefulWidget {
  const AdminBannerTab({Key? key}) : super(key: key);

  @override
  _AdminBannerTabState createState() => _AdminBannerTabState();
}

class _AdminBannerTabState extends State<AdminBannerTab> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('banners')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text('에러가 발생했습니다: ${snapshot.error}'),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('등록된 배너가 없습니다'));
            }

            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: snapshot.data!.docs.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                return _buildBannerListItem(context, doc);
              },
            );
          },
        ),
        if (_isLoading)
          Container(
            color: Colors.black.withOpacity(0.3),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildBannerListItem(BuildContext context, DocumentSnapshot banner) {
    final data = banner.data() as Map<String, dynamic>;
    // Firestore에 저장된 종료 일시
    final Timestamp endTimestamp = data['endDateTime'] as Timestamp;
    final DateTime endDateTime = endTimestamp.toDate();
    // 만약 현재 시간이 종료 일시보다 늦다면 만료로 처리
    bool expired = DateTime.now().isAfter(endDateTime);
    // 만료되었다면 항상 false로 표시하고, onChanged도 막음
    final bool storedIsActive = data['isActive'] ?? false;
    final bool displayActive = expired ? false : storedIsActive;
    final title = data['title'] ?? '제목 없음';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      subtitle: Text(
        '${_formatDateTime(data['startDateTime'])} ~ ${_formatDateTime(data['endDateTime'])}',
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 13,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: displayActive,
            onChanged: expired ? null : (value) => _toggleBannerStatus(banner.id, value),
            activeColor: Colors.black,
            inactiveThumbColor: Colors.black,
            inactiveTrackColor: Colors.grey,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 16),
            onPressed: () => _navigateToModify(context, banner: banner),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(Timestamp timestamp) {
    final DateTime date = timestamp.toDate();
    return '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleBannerStatus(String bannerId, bool newStatus) async {
    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance
          .collection('banners')
          .doc(bannerId)
          .update({'isActive': newStatus});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('배너가 ${newStatus ? '활성화' : '비활성화'} 되었습니다'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('상태 변경에 실패했습니다'),
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

  void _navigateToModify(BuildContext context, {DocumentSnapshot? banner}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminBannerModifyScreen(banner: banner),
      ),
    );
  }
}
