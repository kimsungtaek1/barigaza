// lib/models/post.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String userId;
  final String nickname;
  final String title;
  final String content;
  final String category;
  final String imageUrl;
  final String link;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int viewCount;
  final int likeCount;
  final String? profileImage; // 프로필 이미지 URL 추가

  Post({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.title,
    required this.content,
    required this.category,
    required this.imageUrl,
    required this.link,
    required this.createdAt,
    required this.updatedAt,
    required this.viewCount,
    required this.likeCount,
    this.profileImage, // optional parameter
  });

  factory Post.fromMap(Map<String, dynamic> map, String id) {
    DateTime getDateTime(dynamic timestamp) {
      if (timestamp == null) return DateTime.now();
      if (timestamp is Timestamp) return timestamp.toDate();
      return DateTime.now();
    }

    return Post(
      id: id,
      userId: map['userId'] ?? '',
      nickname: map['nickname'] ?? '',
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      category: map['category'] ?? '',
      imageUrl: map['imageUrl'] ?? '',
      link: map['link'] ?? '',
      createdAt: getDateTime(map['createdAt']),
      updatedAt: getDateTime(map['updatedAt']),
      viewCount: map['viewCount'] ?? 0,
      likeCount: map['likeCount'] ?? 0,
      profileImage: map['profileImage'],
    );
  }
}