// ignore_for_file: unused_field

import 'dart:async';
import 'package:avatar_glow/avatar_glow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:get/get.dart';
import 'package:voicecare/Firebase/auth_controller.dart';
import 'package:voicecare/appointment/app_widget/appointment_service_speech.dart';
import 'package:voicecare/controllers/appointment_controller.dart';
import 'package:voicecare/homepage/home_page.dart';
import 'package:voicecare/appointment/appointment_page.dart';
import 'package:voicecare/homepage/login_page.dart';
import 'package:voicecare/homepage/profile_page.dart'; // ensure this exists
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:voicecare/appointment/user_appointments_page.dart';
import 'package:voicecare/mic_widget/service_speech.dart';
import 'package:voicecare/mic_widget/speech_guard.dart';

class HomePageMicButton extends StatefulWidget {
  final Future<void> Function()? onPressed;

  const HomePageMicButton({super.key, this.onPressed});

  @override
  _HomePageMicButtonState createState() => _HomePageMicButtonState();
}

class _HomePageMicButtonState extends State<HomePageMicButton> {
  static const MethodChannel _audioChannel = MethodChannel('voicecare/audio');

  final SpeechToText _speech = SpeechToText();
  final AuthController _auth = AuthController();
  final FlutterTts flutterTts = FlutterTts();
  final bool _isListening = false;
  bool _wasPressed = false;
  // guard to prevent concurrent sign-outs
  bool _signingOut = false;

  // Yellow-highlighted console output (ANSI) for debug messages
  void _logYellow(String msg) {
    const yellow = '\x1B[33m';
    const reset = '\x1B[0m';
    debugPrint('$yellow$msg$reset');
  }

  Future<String?> _listenOnce({int timeoutSeconds = 4}) async {
    // Log current guard state so we can see why suppression branch may not run
    _logYellow(
        'homepage_mic._listenOnce entry — suppress=${SpeechGuard.suppressAutoStart} allow=${SpeechGuard.allowListening} tts=${SpeechGuard.ttsSpeaking}');
    // honor suppression
    if (SpeechGuard.suppressAutoStart) {
      _logYellow(
          'homepage_mic._listenOnce: suppressed by SpeechGuard.suppressAutoStart');
      return null;
    }

    try {
      if (!_speech.isAvailable) {
        final initOk = await _speech.initialize(
          onStatus: (s) => _logYellow('STT status: $s'),
          onError: (e) => _logYellow('STT error: $e'),
        );
        if (!initOk) return null;
      }
    } catch (e) {
      _logYellow('STT initialize failed: $e');
      return null;
    }

    final completer = Completer<String?>();
    String latest = '';

    void resultHandler(dynamic r) {
      try {
        latest = r.recognizedWords ?? '';
        final isFinal = r.finalResult ?? false;
        _logYellow('HomePageMic onResult: "$latest" final=$isFinal');
        if (isFinal && !completer.isCompleted) {
          completer.complete(latest);
        }
      } catch (e, st) {
        _logYellow('HomePageMic resultHandler error: $e\n$st');
      }
    }

    try {
      await _speech.listen(
        listenFor: Duration(seconds: timeoutSeconds),
        onResult: resultHandler,
        partialResults: true,
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('STT listen start error: $e');
      if (!_speech.isListening && !completer.isCompleted) {
        completer.complete(null);
      }
    }

    // timeout fallback
    Future.delayed(Duration(seconds: timeoutSeconds), () async {
      if (!_speech.isListening && !completer.isCompleted) {
        completer.complete(latest.isEmpty ? null : latest);
      } else {
        try {
          if (_speech.isListening) await _speech.stop();
        } catch (_) {}
        if (!completer.isCompleted) {
          completer.complete(latest.isEmpty ? null : latest);
        }
      }
    });

    final res = await completer.future;
    try {
      if (_speech.isListening) await _speech.stop();
    } catch (_) {}
    return res;
  }

  Future<void> _playBeep() async {
    try {
      await _audioChannel.invokeMethod('playBeep');
    } catch (_) {
      // ignore failures
    }
    await Future.delayed(const Duration(milliseconds: 160));
  }

  Future<void> _startListening() async {
    // NEW: don't auto-start if suppression is active
    if (SpeechGuard.suppressAutoStart) {
      debugPrint(
          'homepage_mic._startListening: suppressed by SpeechGuard.suppressAutoStart');
      return;
    }
    // avoid starting STT during TTS playback (cold-start race)
    while (SpeechGuard.ttsSpeaking) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    // previous code that starts STT
    final ok = await _speech.initialize();
    if (!ok) return;
    _speech.listen(
      onResult: (r) {
        // ...existing code...
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appointmentSpeech = Get.isRegistered<AppointmentSpeechService>()
        ? Get.find<AppointmentSpeechService>()
        : Get.put(AppointmentSpeechService());

    // If this widget is not the current route (i.e. we've navigated away),
    // ensure any active listening / mic-pressed state is cleared so the avatar stops glowing.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) {
          if (appointmentSpeech.isListening.value) {
            await appointmentSpeech.stopListening();
          }
          appointmentSpeech.isListening.value = false;
          appointmentSpeech.wasMicPressed.value = false;
        }
      } catch (_) {
        // ignore
      }
    });

    // controller may be used by callers; ensure it exists
    if (!Get.isRegistered<AppointmentController>()) {
      Get.put(AppointmentController());
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(() {
              final isMicPressed = appointmentSpeech.wasMicPressed.value;
              final isListening = appointmentSpeech.isListening.value;

              return AvatarGlow(
                  glowColor: const Color.fromARGB(255, 40, 56, 98),
                  // start the glow as soon as the mic is pressed OR while listening
                  // (more responsive than requiring both to be true)
                  animate: isMicPressed || isListening,
                  duration: const Duration(milliseconds: 2000),
                  repeat: true,
                  child: GestureDetector(
                    onTap: () async {
                      // NEW: abort if an app-wide suppression is active (set during sign-out)
                      if (SpeechGuard.suppressAutoStart) {
                        debugPrint(
                            'homepage_mic: tap suppressed by SpeechGuard.suppressAutoStart');
                        return;
                      }
                      // indicate mic pressed so AvatarGlow starts immediately
                      appointmentSpeech.wasMicPressed.value = true;
                      try {
                        // play beep, then start listening
                        await _playBeep();

                        // mark listening for UI glow
                        appointmentSpeech.isListening.value = true;
                        final recognized = await _listenOnce(timeoutSeconds: 4);
                        _logYellow(
                            'HomePageMic recognized: "${recognized ?? ""}"');

                        // only handle navigation commands here
                        final text = recognized?.toLowerCase().trim() ?? '';
                        if (text.isNotEmpty) {
                          // Help command: speak available homepage commands
                          if (text.contains('help')) {
                            try {
                              // make the help prompt slower and louder for clarity
                              await flutterTts.setVolume(1.0);
                              await flutterTts.setSpeechRate(0.45);
                              await flutterTts.setPitch(1.0);
                            } catch (_) {}
                            try {
                              await flutterTts.speak(
                                  "Available homepage commands are: 'GO TO' , followed by book appointment to open booking, or go to, followed by view appointments to hear your appointments, or Profile to go to profile page.");
                              await flutterTts.awaitSpeakCompletion(true);
                            } catch (_) {}
                            return;
                          }
                          // Navigate to Profile
                          if ((text.contains('go to') &&
                                  text.contains('profile')) ||
                              text == 'profile' ||
                              text.contains('my profile')) {
                            await Get.to(() => const ProfilePage());
                            return;
                          }

                          if ((text.contains('go to') &&
                                  text.contains('home')) ||
                              text == 'home' ||
                              text.contains('homepage')) {
                            await Get.offAll(() => const HomePage());
                          } else if ((text.contains('go to') &&
                                  text.contains('appointment')) ||
                              text.contains('book')) {
                            await Get.to(() => const AppointmentPage());
                          } else if (text.contains('view') ||
                              text.contains('view appointments') ||
                              text.contains('my appointments') ||
                              text.contains('view appointment')) {
                            // Navigate to the user's appointments page, then schedule the
                            // appointment controller to announce the latest appointment
                            // after a short delay so the destination is built.
                            await Get.to(() => const UserAppointmentsPage());
                            Future.delayed(const Duration(milliseconds: 400),
                                () async {
                              try {
                                final ctrl =
                                    Get.isRegistered<AppointmentController>()
                                        ? Get.find<AppointmentController>()
                                        : Get.put(AppointmentController());
                                await ctrl.promptCancelLatestAppointment();
                              } catch (_) {}
                            });
                          } else if (text.contains('log out') ||
                              text.contains('logout') ||
                              text.contains('sign out')) {
                            if (_signingOut) return;
                            setState(() => _signingOut = true);
                            try {
                              try {
                                await flutterTts.setVolume(1.0);
                                await flutterTts.setSpeechRate(0.45);
                                await flutterTts.setPitch(1.0);
                              } catch (_) {}
                              try {
                                await flutterTts
                                    .speak('You are being logged out now');
                                await flutterTts.awaitSpeakCompletion(true);
                              } catch (_) {}
                              // small pause so TTS finishes audibly
                              await Future.delayed(
                                  const Duration(milliseconds: 700));

                              // ensure global speech/stt is fully stopped and guards cleared
                              try {
                                await stopAllSpeechAndClearGuards();
                              } catch (e) {
                                _logYellow(
                                    'stopAllSpeechAndClearGuards failed: $e');
                              }

                              // sign out and navigate only after cleanup completes
                              try {
                                await _auth.signOut();
                                if (!mounted) return;
                                await Get.offAll(() => LoginPage());
                              } catch (e) {
                                _logYellow('signOut failed: $e');
                              }
                            } finally {
                              if (mounted) setState(() => _signingOut = false);
                            }
                          }
                        }
                      } finally {
                        // reset service flags (safe even if widget disposed)
                        try {
                          appointmentSpeech.isListening.value = false;
                          appointmentSpeech.wasMicPressed.value = false;
                        } catch (_) {}
                        // only call setState if still mounted
                        if (mounted) {
                          setState(() {
                            _wasPressed = false;
                          });
                        }
                      }
                    },
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.fromARGB(255, 40, 56, 98),
                      ),
                      child:
                          const Icon(Icons.mic, size: 50, color: Colors.white),
                    ),
                  ));
            }),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Ensure speech service is stopped when this widget is removed
    try {
      final appointmentSpeech = Get.isRegistered<AppointmentSpeechService>()
          ? Get.find<AppointmentSpeechService>()
          : null;
      appointmentSpeech?.stopListening();
      if (appointmentSpeech != null) {
        appointmentSpeech.isListening.value = false;
        appointmentSpeech.wasMicPressed.value = false;
      }
    } catch (_) {}
    super.dispose();
  }
}
