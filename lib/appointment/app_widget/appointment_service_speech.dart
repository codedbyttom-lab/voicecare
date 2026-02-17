import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:voicecare/controllers/appointment_controller.dart';
import 'package:voicecare/mic_widget/service_speech.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

const MethodChannel _appointmentAudioChannel = MethodChannel('voicecare/audio');

class AppointmentSpeechService extends GetxService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts flutterTts = FlutterTts();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final RxBool isListening = false.obs;
  final RxString speechText = ''.obs;
  final RxBool wasMicPressed = false.obs;

  void setWasMicPressed(bool value) {
    wasMicPressed.value = value;
  }

  /// -------------------- COMMAND HANDLER --------------------
  Future<void> _handleCommand(String command) async {
    final normalized = command.toLowerCase().trim();

    // 🔹 Highlight debug
    debugPrint('\x1B[30;43m🗣️ STT recognized: "$command"\x1B[0m');

    if (normalized.contains("book appointment")) {
      await flutterTts.speak("Booking your appointment.");
    } else if (normalized.contains("cancel appointment")) {
      await flutterTts.speak("Cancelling your appointment.");
    } else if (normalized.contains("reschedule")) {
      await flutterTts.speak("Rescheduling your appointment.");
    } else if (normalized.contains("go back")) {
      await flutterTts.speak("Going back to previous page.");
    } else if (normalized.contains("restart process")) {
      await flutterTts.speak("Restarting the appointment process.");
      await flutterTts.awaitSpeakCompletion(true);

      final controller = Get.find<AppointmentController>();
      controller.restartProcess();
      await controller.startVoiceBookingFlow();
    }
    // ----------------- NEW COMMAND: repeat time -----------------
    else if (normalized.contains("repeat time")) {
      debugPrint('\x1B[30;43m🔹 Repeat time command detected\x1B[0m');

      final controller = Get.find<AppointmentController>();

      await flutterTts.speak(
          "Your current appointment time is ${controller.formatTimeForSpeech(controller.selectedTime.value!)}. Would you like to change it?");
      await flutterTts.awaitSpeakCompletion(true);

      bool change = await controller.listenYesNo();
      if (change) {
        await controller.editTimeFlow(); // your existing method
      }
    }
    // -------------------------------------------------
    else {
      await flutterTts.speak("Command not recognized. Please repeat.");
    }
  }

  /// -------------------- LISTEN FOR COMMANDS --------------------
  Future<void> listenForCommand() async {
    if (_speech.isListening) {
      await _speech.stop();
      isListening.value = false;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'notListening') isListening.value = false;
      },
      onError: (error) {
        isListening.value = false;
      },
    );

    if (!available) {
      await flutterTts.speak("Speech recognition not available.");
      return;
    }

    // Play native beep so user knows when to speak, then start listening.
    try {
      debugPrint(
          '[AppointmentSpeechService] playing native beep before listenForCommand');
      await _appointmentAudioChannel.invokeMethod('playBeep');
      await Future.delayed(const Duration(milliseconds: 160));
    } catch (e, st) {
      debugPrint('[AppointmentSpeechService] native beep failed: $e\n$st');
    }

    // clear/prepare UI state then start listening
    speechText.value = '';
    await _speech.listen(
      onResult: (result) async {
        final recognized = result.recognizedWords.trim();
        if (recognized.isEmpty) return;

        speechText.value = recognized;

        if (result.finalResult) {
          await _handleCommand(recognized);
          await stopListening();
        }
      },
      listenMode: ListenMode.confirmation,
    );
    // mark listening after starting so UI doesn't show listening during beep/TTS
    isListening.value = true;
  }

  Future<void> handleAppointmentCommand(String command, BuildContext context,
      Future<void> Function() restartFlow) async {
    final normalized = command.toLowerCase().trim();

    if (normalized.contains("restart process")) {
      await flutterTts.speak("Restarting your appointment booking.");
      await flutterTts.awaitSpeakCompletion(true);
      restartFlow();
    } else if (normalized.contains("cancel appointment")) {
      await flutterTts.speak("Cancelling your appointment.");
      await flutterTts.awaitSpeakCompletion(true);
      Navigator.of(context).pop();
    } else if (normalized.contains("reschedule")) {
      await flutterTts.speak("Rescheduling your appointment.");
      await flutterTts.awaitSpeakCompletion(true);
      restartFlow();
    } else if (normalized.contains("go back")) {
      await flutterTts.speak("Going back to previous page.");
      await flutterTts.awaitSpeakCompletion(true);
      Navigator.of(context).pop();
    } else {
      await flutterTts.speak("Command not recognized. Please try again.");
    }
  }

  Future<String?> listenForCommandWithTimeout({int timeoutSeconds = 6}) async {
    if (_speech.isListening) await _speech.stop();
    bool available = await _speech.initialize();
    if (!available) return null;

    String? recognizedText;
    final completer = Completer<String?>();
    Timer? timer;

    timer = Timer(Duration(seconds: timeoutSeconds), () {
      if (!completer.isCompleted) completer.complete(null); // Timeout
      if (_speech.isListening) _speech.stop();
    });

    // Play a short beep cue before timeout-listen starts
    try {
      debugPrint(
          '[AppointmentSpeechService] playing native beep before listenForCommandWithTimeout');
      await _appointmentAudioChannel.invokeMethod('playBeep');
      await Future.delayed(const Duration(milliseconds: 140));
    } catch (e, st) {
      debugPrint(
          '[AppointmentSpeechService] native beep (timeout) failed: $e\n$st');
    }

    await _speech.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          recognizedText = result.recognizedWords.toLowerCase().trim();
        }
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(recognizedText);
          timer?.cancel();
        }
      },
      listenMode: ListenMode.confirmation,
    );

    return completer.future;
  }

  /// -------------------- STOP LISTENING --------------------
  Future<void> stopListening() async {
    if (isListening.value) {
      await _speech.stop();
      isListening.value = false;
      speechText.value = '';
    }
  }

  /// -------------------- OPTIONAL: PLAY BEEP --------------------
  Future<void> playBeep() async {
    await flutterTts.setSpeechRate(1.0);
    await flutterTts.speak("Listening");
  }

  /// Play the shared native beep (used by appointment UI before starting STT).
  /// Tries shared SpeechService, falls back to calling the native channel directly.
  Future<void> playBeepOnly({int delayMs = 160}) async {
    debugPrint('[AppointmentSpeechService] playBeepOnly called');
    try {
      // Preferred: use shared service if available
      if (Get.isRegistered<SpeechService>()) {
        final SpeechService shared = Get.find<SpeechService>();
        debugPrint(
            '[AppointmentSpeechService] delegating to shared SpeechService');
        await shared.playBeepOnly(delayMs: delayMs);
        debugPrint('[AppointmentSpeechService] delegated beep done');
        return;
      }
    } catch (e, st) {
      debugPrint('[AppointmentSpeechService] delegating failed: $e\n$st');
      // continue to fallback
    }

    // Fallback: call native MethodChannel directly
    try {
      debugPrint('[AppointmentSpeechService] invoking native channel fallback');
      await _appointmentAudioChannel.invokeMethod('playBeep');
      await Future.delayed(Duration(milliseconds: delayMs));
      debugPrint('[AppointmentSpeechService] native channel beep done');
    } on PlatformException catch (e, st) {
      debugPrint(
          '[AppointmentSpeechService] native channel PlatformException: ${e.message}\n$st');
    } catch (e, st) {
      debugPrint('[AppointmentSpeechService] native channel error: $e\n$st');
    }
  }

  /// Listen briefly and return recognized text (used for navigation from homepage).
  Future<String?> listenForNavigation({int timeoutSeconds = 4}) async {
    try {
      // reuse existing timeout-listen helper if present
      final text =
          await listenForCommandWithTimeout(timeoutSeconds: timeoutSeconds);
      return text;
    } catch (e, st) {
      debugPrint(
          '[AppointmentSpeechService] listenForNavigation error: $e\n$st');
      return null;
    }
  }

  /// CLIENT-SIDE FUZZY VOICE PASSPHRASE (Firestore-backed)
  /// Enroll normalized passphrase to Firestore for current user.
  Future<bool> enrollPassphraseToFirestore(String passphrase,
      {int minWords = 3}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final normalized = _normalizePhrase(passphrase);
    if (normalized.split(' ').length < minWords) return false;
    try {
      await _firestore.collection('users').doc(uid).set({
        'voiceNormalized': normalized,
        'voiceEnrollAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint(
          '[AppointmentSpeechService] enrolled voice passphrase for $uid');
      return true;
    } catch (e, st) {
      debugPrint('[AppointmentSpeechService] enroll error: $e\n$st');
      return false;
    }
  }

  /// Verify recognized speech against stored canonical phrase in Firestore.
  /// Returns true on accepted match.
  Future<bool> verifyVoiceWithFirestore(
      {int timeoutSeconds = 6, int maxDistance = 2}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final doc = await _firestore.collection('users').doc(uid).get();
    final stored = (doc.data()?['voiceNormalized'] ?? '') as String;
    if (stored.isEmpty) {
      debugPrint('[AppointmentSpeechService] no stored voice phrase for $uid');
      return false;
    }

    final recognized =
        await listenForCommandWithTimeout(timeoutSeconds: timeoutSeconds);
    if (recognized == null || recognized.trim().isEmpty) {
      debugPrint('[AppointmentSpeechService] no recognition result');
      return false;
    }

    final a = _normalizePhrase(recognized);
    final b = stored;
    final distance = _levenshtein(a, b);
    final rel = distance / max(1, b.length);
    final accepted = distance <= maxDistance || rel <= 0.25;
    debugPrint(
        '[AppointmentSpeechService] verify: recognized="$a" stored="$b" d=$distance rel=${rel.toStringAsFixed(2)} accept=$accepted');
    return accepted;
  }

  // Helpers
  String _normalizePhrase(String s) {
    final cleaned = s.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  int _levenshtein(String a, String b) {
    final n = a.length;
    final m = b.length;
    if (n == 0) return m;
    if (m == 0) return n;
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 0; i <= n; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= m; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = [dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
    }
    return dp[n][m];
  }
}
