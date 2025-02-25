// lib/widgets/app_bar_widget.dart
import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showNotification;
  final bool showProfile;
  final bool showMore;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;
  final VoidCallback? onMoreTap;

  const CustomAppBar({
    Key? key,
    this.title = 'BRG',
    this.actions,
    this.showNotification = true,
    this.showProfile = true,
    this.showMore = true,
    this.onNotificationTap,
    this.onProfileTap,
    this.onMoreTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      title: Text(
        title,
        style: TextStyle(
          color: Color(0xFF585858),
          fontWeight: FontWeight.bold,
          fontSize: 24,
        ),
      ),
      actions: actions ??
          [
            if (showNotification)
              IconButton(
                icon: Icon(Icons.notifications_none, color: Colors.black87),
                onPressed: onNotificationTap ?? () {},
              ),
            if (showProfile)
              IconButton(
                icon: Icon(Icons.person_outline, color: Colors.black87),
                onPressed: onProfileTap ?? () {},
              ),
            if (showMore)
              IconButton(
                icon: Icon(Icons.more_vert, color: Colors.black87),
                onPressed: onMoreTap ?? () {},
              ),
          ],
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight);
}