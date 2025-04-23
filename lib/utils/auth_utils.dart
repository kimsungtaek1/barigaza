// lib/utils/auth_utils.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthUtils {
  static Future<bool> showLoginAlert(BuildContext context) async {
    bool shouldNavigate = false;
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