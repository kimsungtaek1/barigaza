// lib/utils/auth_utils.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthUtils {
  static Future<bool> showLoginAlert(BuildContext context) async {
    bool shouldNavigate = false;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('로그인 필요'),
          content: Text('이 기능을 사용하기 위해서는 로그인이 필요합니다.\n로그인 페이지로 이동하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () {
                shouldNavigate = false;
                Navigator.of(context).pop();
              },
              child: Text('취소'),
            ),
            TextButton(
              onPressed: () {
                shouldNavigate = true;
                Navigator.of(context).pop();
              },
              child: Text('로그인하기'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
              ),
            ),
          ],
        );
      },
    );

    return shouldNavigate;
  }

  static Future<bool> checkLoginAndShowAlert(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      final shouldNavigateToLogin = await showLoginAlert(context);
      if (shouldNavigateToLogin) {
        if (context.mounted) {
          Navigator.pushNamed(context, '/login');
        }
      }
      return false;
    }

    return true;
  }
}