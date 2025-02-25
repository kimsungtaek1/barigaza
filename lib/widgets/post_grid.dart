// lib/widgets/post_grid.dart
import 'package:flutter/material.dart';
import '../models/post.dart';
import 'post_card.dart';

class PostGrid extends StatelessWidget {
  final List<Post> posts;
  final Function(String) onPostTap;

  const PostGrid({
    Key? key,
    required this.posts,
    required this.onPostTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.70, // 비율 조정으로 오버플로우 해결
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        return PostCard(
          post: posts[index],
          onTap: () => onPostTap(posts[index].id),
        );
      },
    );
  }
}