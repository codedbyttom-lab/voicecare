// controllers/auth_controller.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:voicecare/Firebase/Auth_service.dart';
import 'package:voicecare/mic_widget/service_speech.dart';
import 'package:voicecare/mic_widget/speech_guard.dart';

class AuthController extends GetxController {
  final AuthService _authService = AuthService();
  var firebaseUser = Rxn<User>();

  @override
  void onInit() {
    firebaseUser.bindStream(_authService.userChanges);
    super.onInit();
  }

  Future<void> login(String email, String password) async {
    await _authService.signIn(email, password);
  }

  Future<void> register(String email, String password) async {
    await _authService.register(email, password);
  }

  Future<void> logout() async {
    await _authService.signOut();
  }

  // Example: AuthController.signOut()
  Future<void> signOut() async {
    try {
      // prevent any auto-restarts immediately
      SpeechGuard.suppressAutoStart = true;
      debugPrint(
          '\x1B[33m[AuthController] suppressAutoStart = true (begin signOut)\x1B[0m');
    } catch (_) {}

    try {
      // ensure all speech/stt is stopped before changing auth state
      await stopAllSpeechAndClearGuards();
    } catch (e) {
      debugPrint(
          '\x1B[33m[AuthController] stopAllSpeechAndClearGuards error: $e\x1B[0m');
    }

    try {
      await FirebaseAuth.instance.signOut();
      debugPrint('\x1B[33m[AuthController] Firebase signOut complete\x1B[0m');
    } catch (e) {
      debugPrint('\x1B[33m[AuthController] signOut failed: $e\x1B[0m');
      rethrow;
    }

    // NOTE: do NOT clear suppressAutoStart here — caller should clear it AFTER navigation to LoginPage.
  }

  AuthController() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (SpeechGuard.suppressAutoStart) {
        debugPrint('Auth listener: auto-start suppressed');
        return;
      }
      if (user != null) {
        // call service maybeAutoStart() or similar
        Get.find<SpeechService>().maybeAutoStart();
      }
    });
  }
}
