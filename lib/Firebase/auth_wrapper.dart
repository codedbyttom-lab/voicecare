import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:voicecare/admin/admin_homepage.dart';

import 'package:voicecare/homepage/home_page.dart';
import 'package:voicecare/homepage/login_page.dart';
import 'auth_controller.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthController authController = Get.find<AuthController>();

    return Obx(() {
      final user = authController.firebaseUser.value;
      if (user != null) {
        final email = (user.email ?? '').toLowerCase();
        if (email.contains('@admin')) {
          return const AdminHomePage();
        }
        return const HomePage(); // regular user
      } else {
        return LoginPage(); // User is not logged in
      }
    });
  }
}
