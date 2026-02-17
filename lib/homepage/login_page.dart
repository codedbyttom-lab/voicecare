import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:voicecare/Firebase/auth_controller.dart';
import 'package:voicecare/mic_widget/speech_guard.dart';
import 'package:voicecare/registration/user_registration.dart';
import 'package:voicecare/widgets/voice_form_field.dart';
import 'package:voicecare/homepage/home_page.dart';
import 'package:voicecare/admin/admin_homepage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

// process-start timestamp used for cold-start delay (7s)
final DateTime _appStartTime = DateTime.now();

class LoginPage extends StatefulWidget {
  LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final AuthController authController = Get.find<AuthController>();
  // local flag: only allow _listenOnce to start when this page explicitly enables it
  bool _allowListening = false;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final SpeechToText _speech = SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _speechAvailable = false;
  // local TTS state so listeners/waiters can observe when TTS is active
  bool _isTtsSpeaking = false;
  // lifecycle guard used by async flows to stop work after dispose
  bool _disposed = false;

  // Speak text and wait for completion; sets a local and global TTS guard.
  Future<void> _speakAndWait(String text,
      {double volume = 1.0, double rate = 0.45, int postDelayMs = 250}) async {
    try {
      _isTtsSpeaking = true;
      SpeechGuard.ttsSpeaking = true;
      await _flutterTts.setVolume(volume);
      await _flutterTts.setSpeechRate(rate);
      await _flutterTts.speak(text);
      await _flutterTts.awaitSpeakCompletion(true);
      // small safety delay so audio pipeline finishes before playing beep/listening
      await Future.delayed(Duration(milliseconds: postDelayMs));
    } catch (e) {
      _logDebug('TTS speak error: $e');
    } finally {
      _isTtsSpeaking = false;
      SpeechGuard.ttsSpeaking = false;
    }
  }

  // Wait until TTS and any playing audio are finished before starting STT.
  Future<void> _waitForAudioAndTtsIdle({int timeoutMs = 3000}) async {
    final start = DateTime.now();
    // wait for TTS flags to clear
    while ((_isTtsSpeaking || SpeechGuard.ttsSpeaking) &&
        DateTime.now().difference(start).inMilliseconds < timeoutMs) {
      await Future.delayed(const Duration(milliseconds: 25));
    }
    // wait for audio player completion (best-effort)
    try {
      await _audioPlayer.onPlayerComplete.first
          .timeout(Duration(milliseconds: timeoutMs));
    } catch (_) {
      // ignore - fallback below
    }
    // small safety delay to ensure the audio pipeline is quiet
    await Future.delayed(const Duration(milliseconds: 40));
  }

  Future<String?> _listenOnce({int timeoutSeconds = 6}) async {
    // Respect local and global guards. Caller must enable _allowListening before calling.
    if (!_allowListening || _disposed || !mounted) {
      _logDebug(
          '[STT] listen blocked — _allowListening=false or page not ready');
      return null;
    }
    // cold-start: ensure we wait up to 7s after app process start before initializing STT
    const coldDelaySeconds = 7;
    final elapsed = DateTime.now().difference(_appStartTime);
    if (elapsed.inSeconds < coldDelaySeconds) {
      final remaining = Duration(seconds: coldDelaySeconds) - elapsed;
      _logDebug(
          '[STT] coldStart — delaying listen for ${remaining.inSeconds}s');
      await Future.delayed(remaining);
    }
    // Also respect global guard if other code cleared it on sign-out
    if (!SpeechGuard.allowListening) {
      _logDebug(
          '[STT] global SpeechGuard.allowListening=false — aborting listen');
      return null;
    }

    try {
      // Defensive teardown: ensure any previous session is cancelled to avoid
      // native engine races after navigation/sign-out.
      _logDebug(
          '[STT] pre-listen cleanup: stopping/cancelling previous session');
      try {
        await _speech.stop();
      } catch (_) {}
      try {
        await _speech.cancel();
      } catch (_) {}
      // small pause so native layer can settle
      await Future.delayed(const Duration(milliseconds: 120));

      // Initialize with callbacks so we can see status/errors in logs.
      _logDebug('[STT] calling initialize() (prevAvailable=$_speechAvailable)');
      bool initialized = false;
      try {
        initialized = await _speech.initialize(
          onStatus: (status) => _logDebug('[STT] status: $status'),
          onError: (error) =>
              _logDebug('[STT] error: ${error?.errorMsg ?? error}'),
        );
      } catch (e) {
        _logDebug('[STT] initialize threw: $e');
        initialized = false;
      }
      _speechAvailable = initialized;
      _logDebug(
          '[STT] initialize result: $initialized hasPermission=${_speech.hasPermission}');
      if (!initialized) {
        _logDebug('[STT] initialization failed — aborting listen');
        return null;
      }

      final completer = Completer<String?>();
      // Start listening and log callbacks (also sound level to help debug)
      _speech.listen(
        onResult: (r) {
          try {
            final partial = r.recognizedWords;
            if (partial != null && partial.isNotEmpty) {
              _logHeard('Heard: $partial');
            }
          } catch (_) {}
          if (r.finalResult) {
            try {
              _logHeard('Final: ${r.recognizedWords ?? "<empty>"}');
            } catch (_) {}
            if (!completer.isCompleted) completer.complete(r.recognizedWords);
          }
        },
        listenMode: ListenMode.confirmation,
        partialResults: true,
        onSoundLevelChange: (level) => _logDebug('[STT] sound level: $level'),
      );
      // Play the beep AFTER listen() is active so the beep timing lines up with the STT window.
      // This moves the audible click to occur at the correct moment (was previously too early).
      try {
        await _playBeep();
        // increase small breathing room so STT won't capture TTS tail or beep artifact
        await Future.delayed(const Duration(milliseconds: 60));
      } catch (_) {}
      // timeout fallback
      Future.delayed(Duration(seconds: timeoutSeconds), () async {
        if (!completer.isCompleted) {
          try {
            await _speech.stop();
          } catch (_) {}
          completer.complete(null);
        }
      });
      final result = await completer.future;
      // show final captured text as well
      try {
        _logDebug('Captured: ${result ?? "<no result>"}');
      } catch (_) {}
      return result;
    } catch (_) {
      _logDebug('Listen initialization failed');
      return null;
    }
  }

  String _normalizeSpelledEmail(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    var s = raw.toLowerCase();
    // common spoken tokens -> symbols
    s = s.replaceAll(RegExp(r'\b(at)\b'), '@');
    s = s.replaceAll(RegExp(r'\b(dot|period)\b'), '.');
    s = s.replaceAll(RegExp(r'\b(underscore|under score)\b'), '_');
    s = s.replaceAll(RegExp(r'\b(hyphen|dash)\b'), '-');
    s = s.replaceAll(RegExp(r'\b(plus)\b'), '+');
    // remove filler words and spaces
    s = s.replaceAll(RegExp(r'\s+'), '');
    return s;
  }

  // Capitalize first character for voice-entered password
  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  // debug only to console
  void _logDebug(String msg) => debugPrint(msg);

  // Yellow-highlighted console output for recognized speech (visible in terminals that support ANSI)
  void _logHeard(String msg) {
    const yellow = '\x1B[33m';
    const reset = '\x1B[0m';
    debugPrint('$yellow$msg$reset');
  }

  // Interpret spoken "capital X" / "uppercase X" tokens and apply casing.
  // Example: "capital t" => "T", "capital t e s t" => "Test"
  String _applyCaseTokens(String raw) {
    if (raw.trim().isEmpty) return '';
    final parts = raw.trim().split(RegExp(r'\s+'));
    final buffer = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      final p = parts[i];
      final lower = p.toLowerCase();
      if ((lower == 'capital' || lower == 'cap' || lower == 'uppercase') &&
          i + 1 < parts.length) {
        final next = parts[++i];
        // If next is a single letter word like "t" or "tee", take first character
        final ch = next.isNotEmpty ? next[0] : '';
        buffer.write(ch.toUpperCase());
      } else if ((lower == 'lowercase' || lower == 'small') &&
          i + 1 < parts.length) {
        final next = parts[++i];
        final ch = next.isNotEmpty ? next[0] : '';
        buffer.write(ch.toLowerCase());
      } else {
        // Normal token: append as-is (preserve spacing minimally)
        buffer.write(p);
      }
    }
    return buffer.toString();
  }

  // form key for validation
  final _formKey = GlobalKey<FormState>();
  final FlutterTts _flutterTts = FlutterTts();

  Future<void> _playBeep() async {
    try {
      // load asset bytes directly to avoid AssetSource/path mismatches
      final data = await rootBundle
          .load('lib/assets/sounds/beep_short.mp3'); // match pubspec
      final bytes = data.buffer.asUint8List();
      if (bytes.isEmpty) throw Exception('beep asset is empty');
      await _audioPlayer.play(BytesSource(bytes), volume: 10.0);
      // small safety pause so the beep starts before STT begins
      await Future.delayed(const Duration(milliseconds: 150));
      return;
    } catch (e) {
      _logDebug('Beep asset play failed: $e — falling back to SystemSound');
      try {
        SystemSound.play(SystemSoundType.alert);
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (_) {}
    }
  }

  @override
  void initState() {
    super.initState();
    // DO NOT clear SpeechGuard.suppressAutoStart here.
    debugPrint(
        '\x1B[33m[LoginPage] init — suppress=${SpeechGuard.suppressAutoStart}\x1B[0m');

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      debugPrint(
          '\x1B[33m[LoginPage] postFrameCallback fired (cooldown)\x1B[0m');
      if (!mounted || _disposed) return;
      // Ensure any previous audio/TTS is stopped and let the audio pipeline settle
      try {
        await _flutterTts.stop();
      } catch (_) {}
      try {
        await _audioPlayer.stop();
      } catch (_) {}
      // short cooldown to avoid TTS/audio focus races when navigating back after sign-out
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted || _disposed) return;
      await _startInitialPrompt();
    });
  }

  // start prompt: login or register
  Future<void> _startInitialPrompt() async {
    debugPrint(
        '\x1B[33m[_startInitialPrompt] entry suppress=${SpeechGuard.suppressAutoStart} allow=${SpeechGuard.allowListening}\x1B[0m'); // NEW
    try {
      await _flutterTts.stop();
    } catch (_) {}
    try {
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setSpeechRate(0.45);
    } catch (_) {}

    try {
      final prompt =
          'Welcome to voice care, please double tap each field to use the keyboard. Would you like to login or register?';

      // ALWAYS speak the welcome prompt regardless of suppression
      debugPrint(
          '\x1B[33m[_startInitialPrompt] about to speak welcome\x1B[0m'); // NEW
      // increase postDelayMs so audio pipeline fully settles after TTS
      await _speakAndWait(prompt, postDelayMs: 420);
      debugPrint('\x1B[33m[_startInitialPrompt] welcome spoken\x1B[0m'); // NEW
      // give more time for audio to become idle before enabling listen
      await _waitForAudioAndTtsIdle(timeoutMs: 900);

      // Short cooldown to ensure audio subsystem is fully idle, then enable listening.
      // Force-enable auto-listen here so the beep is played and STT starts.
      await Future.delayed(const Duration(milliseconds: 180));
      _allowListening = true;
      SpeechGuard.allowListening = true;
      _logDebug('Auto-listen enabled — starting listen and playing beep');

      // Give users more time to respond; short retry if nothing captured.
      var reply = await _listenOnce(timeoutSeconds: 5);
      if ((reply ?? '').trim().isEmpty) {
        _logDebug('No reply on first attempt — prompting to repeat');
        try {
          await _flutterTts.speak(
              'I did not hear you. Please say "login" or "register" now.');
          await _flutterTts.awaitSpeakCompletion(true);
        } catch (_) {}
        // second chance with slightly longer window
        reply = await _listenOnce(timeoutSeconds: 6);
      }
      _logDebug('Reply received: ${reply ?? "<no reply>"}');

      // normalize captured text: lowercase, strip punctuation, collapse spaces
      var text = (reply ?? '').toLowerCase().trim();
      text = text.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
      text = text.replaceAll(
          RegExp(
              r'\b(please|i want to|i would like to|could i|can i|want to|would like)\b'),
          ' ');
      text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (text.isEmpty) {
        _logDebug('No reply detected after prompt (normalized empty)');
        return;
      }

      _logDebug('Normalized reply: "$text"');

      final wantsRegister =
          RegExp(r'\b(register|sign\s?up|create\s?account|create\s?account)\b')
              .hasMatch(text);
      final wantsLogin =
          RegExp(r'\b(login|log\s?in|sign\s?in|sign-in|log-in)\b')
              .hasMatch(text);

      _logDebug('Intent match -> register:$wantsRegister login:$wantsLogin');

      if (wantsRegister) {
        _logDebug('Register intent detected (handling)');
        // ensure we stop audio/TTS and disable further listening before navigating
        _allowListening = false;
        SpeechGuard.allowListening = false;
        try {
          await _speech.stop();
        } catch (_) {}
        try {
          await _flutterTts.stop();
        } catch (_) {}
        try {
          await _audioPlayer.stop();
        } catch (_) {}
        // small yield to let audio focus settle and let Get navigation run cleanly
        await Future.delayed(const Duration(milliseconds: 80));
        if (mounted) {
          Get.to(() => const UserReg());
        } else {
          _logDebug('Cannot navigate to register — widget not mounted');
        }
        return;
      }

      if (wantsLogin) {
        _logDebug('Login intent detected (handling)');
        _allowListening = false;
        SpeechGuard.allowListening = false;
        try {
          await _speech.stop();
        } catch (_) {}
        try {
          await _flutterTts.stop();
        } catch (_) {}
        try {
          await _audioPlayer.stop();
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 80));
        // continue with voice login flow
        await _attemptVoiceLoginFlow();
        return;
      }

      _logDebug('No recognised intent (login/register) in reply: "$text"');
    } catch (e) {
      _logDebug('startInitialPrompt error: $e');
    }
  }

  // voice-driven login flow: capture spelled email, repeat email, capture password, attempt login, retry on fail
  Future<void> _attemptVoiceLoginFlow({int retries = 0}) async {
    if (retries > 2) return;
    try {
      await _flutterTts.speak(
          'Please spell your email address, letter by letter followed by the domain.');
      await _flutterTts.awaitSpeakCompletion(true);

      // Ensure STT is allowed and audio pipeline is idle before starting listen.
      // _startInitialPrompt previously disabled listening; re-enable here.
      _allowListening = true;
      SpeechGuard.allowListening = true;
      await _waitForAudioAndTtsIdle(timeoutMs: 900);
      // small breathing room to avoid capturing TTS tail
      await Future.delayed(const Duration(milliseconds: 120));

      // _listenOnce will play the beep at the correct time
      final spelled = await _listenOnce(timeoutSeconds: 10);
      _logDebug('Spelled email captured: ${spelled ?? "<no spelled>"}');
      final normalized = _normalizeSpelledEmail(spelled);
      // immediately disable listening while we speak back/validate
      _allowListening = false;
      SpeechGuard.allowListening = false;
      if (normalized.isEmpty) {
        await _flutterTts
            .speak('I did not catch your email. Restarting the login process.');
        await _flutterTts.awaitSpeakCompletion(true);
        return _attemptVoiceLoginFlow(retries: retries + 1);
      }
      emailController.text = normalized;

      // repeat email back to the user (safe)
      // Show the spelled email visually (letters separated) instead of speaking it.
      final spelledVisual = normalized.split('').map((c) {
        if (c == '@') return '@';
        if (c == '.') return '.';
        return c;
      }).join(' ');
      Get.snackbar(
        'Email captured',
        spelledVisual,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.blueGrey[800],
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
      // brief pause so the user can read the spelled email before continuing
      await Future.delayed(const Duration(milliseconds: 900));

      // move focus to password and capture via voice
      if (mounted) FocusScope.of(context).requestFocus(_passwordFocus);
      await _flutterTts.speak('Please say your password now.');
      await _flutterTts.awaitSpeakCompletion(true);

      // Re-enable listening for password entry and wait for audio idle again.
      _allowListening = true;
      SpeechGuard.allowListening = true;
      await _waitForAudioAndTtsIdle(timeoutMs: 900);
      await Future.delayed(const Duration(milliseconds: 120));

      final pwdReply = await _listenOnce(timeoutSeconds: 10);
      _logDebug('Password spoken captured: ${pwdReply ?? "<no password>"}');
      _allowListening = false;
      SpeechGuard.allowListening = false;
      final pwdText = (pwdReply ?? '').trim();
      if (pwdText.isEmpty) {
        await _flutterTts.speak(
            'I did not catch your password. Restarting the login process.');
        await _flutterTts.awaitSpeakCompletion(true);
        return _attemptVoiceLoginFlow(retries: retries + 1);
      }
      final processed = _applyCaseTokens(pwdText);
      passwordController.text =
          processed.isNotEmpty ? processed : _capitalize(pwdText);
      // do NOT speak the password back

      // Attempt login now
      final ok = await _attemptLogin(context);
      if (!ok) {
        try {
          await _flutterTts.speak('Invalid deails, restarting process');
          await _flutterTts.awaitSpeakCompletion(true);
        } catch (_) {}
        return _attemptVoiceLoginFlow(retries: retries + 1);
      }
      // on success nothing more to do (UI will navigate inside _attemptLogin)
    } catch (e) {
      _logDebug('attemptVoiceLoginFlow error: $e');
    }
  }

  // Attempts login and returns true on success, false on failure.
  Future<bool> _attemptLogin(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return false;

    final email = emailController.text.trim();
    final password = passwordController.text;

    // show blocking loading dialog
    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );

    try {
      await authController.login(email, password);

      if (Get.isDialogOpen ?? false) Get.back();

      // Route admin users (email contains "@admin") to AdminHomePage
      final currentEmail =
          FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? '';
      if (currentEmail.contains('@admin')) {
        Get.offAll(() => const AdminHomePage());
      } else {
        Get.offAll(() => const HomePage());
      }
      return true;
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();

      Get.snackbar(
        "Login failed",
        e.toString(), // ?? 'Unknown error',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red[300],
        colorText: Colors.white,
      );
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    emailController.dispose();
    passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    try {
      _speech.stop();
    } catch (_) {}
    try {
      _audioPlayer.dispose();
    } catch (_) {}
    try {
      _flutterTts.stop();
    } catch (_) {}
    // clear availability so next page/show re-initializes STT cleanly
    _speechAvailable = false;
    // also cancel any pending native recognition
    try {
      _speech.cancel();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // (no on-screen debug banner — debug messages go to console)
                // Title
                const Text(
                  "VoiceCare",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 40, 56, 98),
                  ),
                ),
                const SizedBox(height: 40),

                // Email
                VoiceFormField(
                  controller: emailController,
                  focusNode: _emailFocus,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Please enter your email";
                    }
                    if (!GetUtils.isEmail(value.trim())) {
                      return "Enter a valid email";
                    }
                    return null;
                  },
                  labelText: "Email",
                  prefixIcon: const Icon(Icons.email),
                ),
                const SizedBox(height: 20),

                // Password
                VoiceFormField(
                  controller: passwordController,
                  focusNode: _passwordFocus,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Please enter your password";
                    }
                    if (value.length < 6) {
                      return "Password must be at least 6 characters";
                    }
                    return null;
                  },
                  labelText: "Password",
                  prefixIcon: const Icon(Icons.lock),
                  obscureText: true,
                ),
                const SizedBox(height: 30),

                // Login button
                ElevatedButton(
                  onPressed: () => _attemptLogin(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 40, 56, 98),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    "Login",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
                const SizedBox(height: 15),

                // Register link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don’t have an account? "),
                    GestureDetector(
                      onTap: () {
                        Get.to(const UserReg());
                      },
                      child: const Text(
                        "Register",
                        style: TextStyle(
                          color: Color.fromARGB(255, 40, 56, 98),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
