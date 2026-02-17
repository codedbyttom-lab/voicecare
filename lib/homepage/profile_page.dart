import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:voicecare/homepage/login_page.dart';
import 'package:voicecare/homepage/home_page.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter/services.dart';
import 'package:voicecare/mic_widget/service_speech.dart';
import 'package:voicecare/mic_widget/speech_guard.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  static const MethodChannel _audioChannel =
      MethodChannel('voicecare/audio'); // native beep

  String? get _uid => _auth.currentUser?.uid;

  bool _voiceFlowStarted = false;
  bool _disposed = false;
  // UI guard to prevent double sign-out and show progress
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_voiceFlowStarted && mounted && !_disposed) {
        _voiceFlowStarted = true;
        _announceAndPrompt();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    // cut off any speaking/listening immediately
    try {
      _tts.stop();
    } catch (_) {}
    try {
      _stt.cancel();
    } catch (_) {}
    try {
      _stt.stop();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _playBeep() async {
    if (!mounted || _disposed) return;
    try {
      await _audioChannel.invokeMethod('playBeep');
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 160));
  }

  Future<void> _speak(String text) async {
    if (!mounted || _disposed) return;
    try {
      await _tts.speak(text);
      try {
        await _tts.awaitSpeakCompletion(true);
      } catch (_) {}
    } catch (_) {}
  }

  // Speak each digit in the phone number separately so it's clear to the user.
  Future<void> _speakNumber(String digits) async {
    // protect against accidental non-digits
    final onlyDigits = digits.replaceAll(RegExp(r'[^0-9+]'), '');
    // Short pause before speaking digits
    await Future.delayed(const Duration(milliseconds: 150));
    for (var ch in onlyDigits.split('')) {
      // speak each character (pauses enforced by await)
      await _speak(ch);
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  Future<String?> _listen({int timeoutSeconds = 6}) async {
    if (!mounted || _disposed) return null;
    // play beep, initialize and listen
    try {
      await _playBeep();
    } catch (_) {}

    // initialize if needed
    bool available = false;
    try {
      available = await _stt.initialize();
    } catch (_) {
      available = false;
    }
    if (!available || !mounted || _disposed) return null;

    String heard = '';
    try {
      await _stt.listen(
        listenFor: Duration(seconds: timeoutSeconds),
        onResult: (result) {
          heard = result.recognizedWords;
        },
      );
      // break early if page is disposed while waiting
      final totalMs = timeoutSeconds * 1000;
      int waited = 0;
      const step = 100;
      while (waited < totalMs && mounted && !_disposed) {
        await Future.delayed(const Duration(milliseconds: step));
        waited += step;
      }
    } catch (_) {
      // ignore
    } finally {
      try {
        await _stt.stop();
      } catch (_) {}
    }
    return (!mounted || _disposed || heard.trim().isEmpty)
        ? null
        : heard.trim();
  }

  Future<void> _announceAndPrompt() async {
    if (!mounted || _disposed) return;
    await _speak("Profile page.");
    if (!mounted || _disposed) return;
    await _speak(
        "Would you like to change your phone number? Say yes to change, or no to go back to home.");
    if (!mounted || _disposed) return;

    final reply = await _listen(timeoutSeconds: 6);
    if (!mounted || _disposed) return;

    if (reply == null) {
      await _speak("No response detected. Returning to the homepage.");
      if (!mounted || _disposed) return;
      try {
        Get.offAll(() => const HomePage());
      } catch (_) {}
      return;
    }

    final low = reply.toLowerCase();
    if (low.contains('yes') ||
        low.contains('yeah') ||
        low.contains('yep') ||
        low.contains('sure')) {
      await _speak("Please say your new phone number now.");
      if (!mounted || _disposed) return;
      // first attempt (beep is played by _listen)
      final spokenNumber = await _listen(timeoutSeconds: 8);
      if (!mounted || _disposed) return;
      if (spokenNumber == null) {
        await _speak("No phone number detected. Returning to the homepage.");
        if (!mounted || _disposed) return;
        try {
          Get.offAll(() => const HomePage());
        } catch (_) {}
        return;
      }

      // keep digits only for validation and saving
      String cleanedDigits = spokenNumber.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanedDigits.length != 10) {
        // notify user exact requirement, give one retry
        await _speak("A phone number is 10 digits, please try again.");
        if (!mounted || _disposed) return;
        // play beep and listen once more
        final retry = await _listen(timeoutSeconds: 8);
        if (!mounted || _disposed) return;
        if (retry == null) {
          await _speak("No phone number detected. Returning to the homepage.");
          if (!mounted || _disposed) return;
          try {
            Get.offAll(() => const HomePage());
          } catch (_) {}
          return;
        }
        cleanedDigits = retry.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleanedDigits.length != 10) {
          await _speak(
              "That doesn't look like a valid phone number. Returning to the homepage.");
          if (!mounted || _disposed) return;
          try {
            Get.offAll(() => const HomePage());
          } catch (_) {}
          return;
        }
      }

      // save to Firestore (use cleanedDigits)
      try {
        if (_uid != null) {
          await _firestore.collection('users').doc(_uid).set({
            'contactNumber': cleanedDigits,
            'phone': cleanedDigits,
          }, SetOptions(merge: true));
        }
        await _speak(
            "Your phone number has been updated. Your new phone number is.");
        await _speakNumber(cleanedDigits);
        await _speak("Returning to the homepage.");
      } catch (e) {
        await _speak(
            "Failed to update your phone number. Returning to the homepage.");
      }

      if (!mounted || _disposed) return;
      try {
        Get.offAll(() => const HomePage());
      } catch (_) {}
      return;
    }

    // any explicit "no" or unrecognized -> go home
    await _speak("Okay, returning to the homepage.");
    if (!mounted || _disposed) return;
    try {
      Get.offAll(() => const HomePage());
    } catch (_) {}
  }

  /// Stop all speech/listening and set/clear SpeechGuard flags to a safe state.
  /// This performs local native stops (TTS/STT) and then applies the global guard.
  Future<void> stopAllSpeechAndClearGuards() async {
    // Try to stop local TTS/STT even if widget is unmounted.
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _stt.cancel();
    } catch (_) {}
    try {
      await _stt.stop();
    } catch (_) {}

    // Ensure global guards are set so other pages won't auto-start listening while we transition.
    await SpeechGuard.applySuppressiveGuards();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF283862),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Get.offAll(() => const HomePage()),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _uid == null
            ? const Center(child: Text('Not signed in'))
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _firestore.collection('users').doc(_uid).snapshots(),
                builder: (context, snap) {
                  final doc = snap.data;
                  final data = doc?.data();
                  final storedName = (data?['name'] as String?)?.trim() ?? '';
                  final storedSurname =
                      (data?['surname'] as String?)?.trim() ?? '';
                  final displayName = ([
                    if (storedName.isNotEmpty) storedName,
                    if (storedSurname.isNotEmpty) storedSurname
                  ].join(' '))
                          .isNotEmpty
                      ? [storedName, storedSurname]
                          .where((s) => s.isNotEmpty)
                          .join(' ')
                      : (user?.displayName ?? '');
                  final email = (data?['email'] as String?)?.trim() ??
                      (user?.email ?? '');
                  final phone = (data?['contactNumber'] as String?)?.trim() ??
                      (user?.phoneNumber ?? '');
                  final photoUrl =
                      data?['photoURL'] as String? ?? user?.photoURL;
                  final createdAt = data?['createdAt'];

                  String createdAtFormatted = '';
                  if (createdAt is Timestamp) {
                    createdAtFormatted =
                        DateFormat.yMMMMd().add_jm().format(createdAt.toDate());
                  } else if (createdAt is String && createdAt.isNotEmpty) {
                    createdAtFormatted = createdAt;
                  } else {
                    createdAtFormatted = 'Unknown';
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 54,
                          backgroundColor: const Color(0xFFEFF3FF),
                          backgroundImage:
                              photoUrl != null && photoUrl.isNotEmpty
                                  ? NetworkImage(photoUrl) as ImageProvider
                                  : null,
                          child: (photoUrl == null || photoUrl.isEmpty)
                              ? Text(
                                  (displayName.isNotEmpty
                                          ? displayName
                                              .trim()
                                              .split(' ')
                                              .map((s) =>
                                                  s.isNotEmpty ? s[0] : '')
                                              .take(2)
                                              .join()
                                          : (email.isNotEmpty ? email[0] : '?'))
                                      .toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF283862)),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Text(
                          displayName.isNotEmpty
                              ? displayName
                              : 'No display name',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          email.isNotEmpty ? email : 'No email provided',
                          style: const TextStyle(
                              fontSize: 14, color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Column(
                            children: [
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.phone_outlined),
                                title: const Text('Phone'),
                                subtitle: Text(
                                    phone.isNotEmpty ? phone : 'Not provided'),
                              ),
                              const Divider(),
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading:
                                    const Icon(Icons.calendar_today_outlined),
                                title: const Text('Account created'),
                                subtitle: Text(createdAtFormatted),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _signingOut
                            ? null
                            : () async {
                                setState(() => _signingOut = true);
                                try {
                                  // centralized stop + clear guards (await to ensure it completes)
                                  try {
                                    await stopAllSpeechAndClearGuards();
                                  } catch (_) {}

                                  // sign out and navigate once done
                                  await _auth.signOut();
                                  if (!mounted) return;
                                  await Get.offAll(() => LoginPage());

                                  // small breathing room, then clear suppression so Login can enable listening safely
                                  await Future.delayed(
                                      const Duration(milliseconds: 220));
                                  try {
                                    await SpeechGuard.clearSuppression();
                                    debugPrint(
                                        '\x1B[33m[SpeechGuard] suppressAutoStart cleared by caller\x1B[0m');
                                  } catch (_) {}
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('Sign out failed: $e')),
                                    );
                                  }
                                } finally {
                                  if (mounted)
                                    setState(() => _signingOut = false);
                                }
                              },
                        icon: _signingOut
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.logout, color: Colors.white),
                        label: _signingOut
                            ? const Text('Signing out...',
                                style: TextStyle(color: Colors.white))
                            : const Text('Sign out',
                                style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color.fromARGB(255, 40, 56, 98),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          Get.offAll(() => const HomePage());
                        },
                        icon: const Icon(Icons.home_outlined,
                            color: Colors.white),
                        label: const Text('Back to Home',
                            style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color.fromARGB(255, 40, 56, 98),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
