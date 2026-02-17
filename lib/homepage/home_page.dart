// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:voicecare/appointment/appointment_page.dart';
import 'package:voicecare/appointment/user_appointments_page.dart';
import 'package:voicecare/homepage/coming_soon.dart';
import 'package:voicecare/homepage/profile_page.dart';
import 'package:voicecare/mic_widget/homepage_mic.dart';
import 'package:voicecare/registration/user_registration.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:voicecare/mic_widget/speech_guard.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    // Announce a short homepage hint after the first frame.
    // Delay slightly to let navigation settle and ensure previous TTS is stopped,
    // this prevents the "wel-" cut-off when returning to home.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _flutterTts.stop();
      } catch (_) {}
      try {
        await _flutterTts.setVolume(1.0);
        await _flutterTts.setSpeechRate(0.45);
      } catch (_) {}
      // small settle delay so the platform audio focus transfers cleanly
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        if (SpeechGuard.coldStart) {
          // first time after cold start: give the full hint
          await _flutterTts.speak(
              'Welcome to the Homepage, press the mic button located on the middle bottom and say help to hear available commands');
          await _flutterTts.awaitSpeakCompletion(true);
          // mark coldStart cleared so this full hint won't repeat until app restarts
          SpeechGuard.coldStart = false;
        } else {
          // subsequent visits: brief announcement
          await _flutterTts.speak('Home page');
          await _flutterTts.awaitSpeakCompletion(true);
        }
      } catch (e) {
        debugPrint('HomePage TTS error: $e');
      }
    });
  }

  @override
  void dispose() {
    try {
      _flutterTts.stop();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Home Page", style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 40, 56, 98),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                children: [
                  // Greeting / banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF283862),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Color(0xFFEFF3FF),
                          child: Icon(Icons.calendar_today,
                              color: Color(0xFF283862)),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Welcome to VoiceCare',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600)),
                              SizedBox(height: 6),
                              Text('Book and manage your appointments quickly.',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Grid of action cards
                  GridView.count(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.95,
                    children: [
                      // Book appointment
                      InkWell(
                        onTap: () => Get.to(() => const AppointmentPage()),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4CAF50), Color(0xFF78C257)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.18),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Center(
                                  child: Image.asset(
                                    'lib/assets/home_assets/calendar_icon.png',
                                    width: 56,
                                    height: 56,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text('Book Appointment',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              const Text('Find and book a time slot',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),

                      // My appointments
                      InkWell(
                        onTap: () => Get.to(() => const UserAppointmentsPage()),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF283862), Color(0xFF476089)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blueGrey.withOpacity(0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Center(
                                  child: Image.asset(
                                    'lib/assets/home_assets/emergency_icon.png',
                                    width: 56,
                                    height: 56,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text('My Appointments',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              const Text('View or cancel your bookings',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),

                      // Quick help (placeholder)
                      InkWell(
                        onTap: () => Get.to(() => const ComingSoonPage()),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F8FB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.grey.withOpacity(0.08)),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Center(
                                  child: Icon(Icons.help_outline,
                                      size: 44, color: Color(0xFF283862)),
                                ),
                              ),
                              SizedBox(height: 6),
                              Text('Help & Support',
                                  style: TextStyle(
                                      color: Color(0xFF283862),
                                      fontWeight: FontWeight.w700)),
                              SizedBox(height: 4),
                              Text('Get guidance and FAQs',
                                  style: TextStyle(
                                      color: Colors.black54, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),

                      // Profile / settings (placeholder)
                      InkWell(
                        onTap: () => Get.to(() => const ProfilePage()),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDF6EC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.orange.withOpacity(0.08)),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Center(
                                  child: Icon(Icons.person_outline,
                                      size: 44, color: Color(0xFFCC8A00)),
                                ),
                              ),
                              SizedBox(height: 6),
                              Text('Profile',
                                  style: TextStyle(
                                      color: Color(0xFFCC8A00),
                                      fontWeight: FontWeight.w700)),
                              SizedBox(height: 4),
                              Text('Manage your account',
                                  style: TextStyle(
                                      color: Colors.black54, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
          // place mic button below the scroll area so it doesn't overlap content
          Padding(
            padding:
                EdgeInsets.only(bottom: mediaQuery.padding.bottom + 10, top: 8),
            child: const Center(child: HomePageMicButton()),
          ),
        ],
      ),
    );
  }
}
