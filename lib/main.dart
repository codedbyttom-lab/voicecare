import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:voicecare/Firebase/auth_controller.dart';
import 'package:voicecare/Firebase/auth_wrapper.dart';
import 'package:voicecare/appointment/app_widget/appointment_service_speech.dart';
import 'package:voicecare/controllers/sign_up_controller.dart';
import 'package:voicecare/mic_widget/service_speech.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Await Firebase initialization
  await Firebase.initializeApp();
  try {
    await FirebaseFirestore.instance.collection('users').limit(1).get();
    print("Firestore connection OK");
  } catch (e) {
    print("Firestore connection FAILED: $e");
  }
FirebaseFirestore.instance.settings = const Settings(
  persistenceEnabled: false,
);

  // Register your controllers and services
  Get.put(AuthController());
  Get.put(SpeechService(), permanent: true);
  Get.put(AppointmentSpeechService());
  Get.put(SignUpController());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthWrapper(), // This handles login vs. home
    );
  }
}
