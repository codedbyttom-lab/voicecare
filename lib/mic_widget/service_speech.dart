// speech_service.dart
// ignore_for_file: unused_element

import 'dart:async';

import 'package:get/get.dart';
import 'package:voicecare/mic_widget/speech_guard.dart';
import 'package:get/get.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/material.dart';
import 'package:voicecare/controllers/sign_up_controller.dart';
import 'package:flutter/services.dart';

/// Stop any running global speech/STT and clear listening guards (best-effort).
Future<void> stopAllSpeechAndClearGuards() async {
  // immediately suppress auto-start for callers
  try {
    SpeechGuard.suppressAutoStart = true;
  } catch (_) {}
  debugPrint('\x1B[33m[SpeechGuard] suppressAutoStart = true\x1B[0m');

  try {
    if (Get.isRegistered<SpeechService>()) {
      final svc = Get.find<SpeechService>();
      try {
        await svc.stopListening();
      } catch (_) {}
      try {
        await svc.flutterTts.stop();
      } catch (_) {}
      try {
        await svc.dispose();
      } catch (_) {}
      try {
        Get.delete<SpeechService>(force: true);
      } catch (_) {}
    }
  } catch (_) {}

  try {
    SpeechGuard.allowListening = false;
  } catch (_) {}
  try {
    SpeechGuard.ttsSpeaking = false;
  } catch (_) {}

  // let platform settle a little
  await Future.delayed(const Duration(milliseconds: 220));

  // IMPORTANT: do NOT set suppressAutoStart = false here.
  // Caller (sign-out handler) will clear suppression AFTER navigation completes.
  debugPrint(
      '\x1B[33m[SpeechGuard] stop helper completed (suppress still=true)\x1B[0m');
}

class SpeechService extends GetxService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts flutterTts = FlutterTts();

  final RxBool isListening = false.obs;
  final RxString speechText = ''.obs;
  final RxBool wasMicPressed = false.obs;

  // ignore STT results until this time (used to avoid capturing TTS)
  DateTime? _allowListeningAfter;

  TextEditingController? activeController;
  String? activeFieldName;

  // buffer for latest partial result (helps diagnose / avoid dropping last token)
  String _lastPartial = '';

  void setWasMicPressed(bool value) {
    wasMicPressed.value = value;
  }

  void setActiveController(TextEditingController? controller) {
    activeController = controller;
    debugPrint(_debugHighlight('Active controller set to $controller'));
  }

  String _debugHighlight(String message) {
    return '\x1B[43m$message\x1B[0m'; // Yellow background highlight
  }

  // platform channel to play a native mp3 beep (no 3rd-party package)
  // must match the name used in MainActivity / AppDelegate native handler
  static const MethodChannel _audioChannel = MethodChannel('voicecare/audio');

  Future<void> _playNativeBeep() async {
    try {
      await _audioChannel.invokeMethod('playBeep');
    } catch (e) {
      debugPrint('Native beep failed: $e');
    }
  }

  /// Play a short beep/click to signal the user (uses platform system sound).
  Future<void> playBeep() async {
    try {
      SystemSound.play(SystemSoundType.click);
      // small pause so callers can safely start listening afterwards
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (_) {
      // ignore — non-critical
    }
  }

  /// ===== Field Input Mode =====
  Future<void> startListening(
      {bool dictation = false, int listenSeconds = 12}) async {
    // honor global suppression immediately
    if (SpeechGuard.suppressAutoStart) {
      debugPrint(
          '\x1B[33m[startListening] suppressed by SpeechGuard.suppressAutoStart\x1B[0m');
      return;
    }
    if (_speech.isListening) {
      await _speech.stop();
      isListening.value = false;
    }

    // initialize speech if needed
    final available = await _speech.initialize(
      onStatus: (status) {
        debugPrint(_debugHighlight('STT status: $status'));
      },
      onError: (error) {
        debugPrint(_debugHighlight('Speech error: $error'));
        isListening.value = false;
      },
    );

    // yellow-highlighted diagnostics for INIT / LISTEN
    final src = StackTrace.current.toString().split('\n').elementAt(1).trim();
    debugPrint(
        '\x1B[30;43m[STT INIT] ${DateTime.now().toIso8601String()} src=$src\x1B[0m');
    debugPrint(
        '\x1B[30;43m[STT LISTEN] ${DateTime.now().toIso8601String()} src=$src\x1B[0m');

    if (!available) {
      debugPrint(_debugHighlight('Speech recognition not available'));
      return;
    }

    // Play native beep right before the recognizer starts listening so beep
    // is aligned with the actual microphone window.
    try {
      await _playNativeBeep();
      await Future.delayed(const Duration(milliseconds: 180));
    } catch (_) {}

    isListening.value = true;
    speechText.value = '';

    await _speech.listen(
      // when dictation mode use a configurable listenFor duration
      listenFor: dictation ? Duration(seconds: listenSeconds) : null,
      onResult: (result) async {
        // ignore early results that occur while TTS is still finishing
        if (_allowListeningAfter != null &&
            DateTime.now().isBefore(_allowListeningAfter!)) {
          debugPrint(_debugHighlight('Ignoring STT while TTS finishes'));
          return;
        }

        final recognized = result.recognizedWords.toLowerCase().trim();
        if (recognized.isEmpty) return;

        // keep latest partial for debugging / finalization
        _lastPartial = recognized;
        debugPrint(
            'STT onResult partial="$_lastPartial" final=${result.finalResult}');

        // Handle commands first (only in User Registration)
        if (recognized.startsWith('clear ') ||
            recognized.startsWith('go to ') ||
            recognized.startsWith('repeat')) {
          await _handleCommand(recognized);
          // small buffer to ensure the recognizer finalizes the trailing token
          await Future.delayed(const Duration(milliseconds: 300));
          await stopListening();
          return;
        }

        // Normal field input handling
        if (activeController != null) {
          String finalText;
          final signUp = Get.find<SignUpController>();

          // email -> normalized email (no spaces)
          if (activeController == signUp.email) {
            finalText = recognized
                .replaceAll(RegExp(r'\bunderscore\b'), '_')
                .replaceAll(RegExp(r'\bunder score\b'), '_')
                .replaceAll(RegExp(r'\bdot\b|\bperiod\b|\bpoint\b'), '.')
                .replaceAll(RegExp(r'\bat\b'), '@')
                .replaceAllMapped(
                  RegExp(r'@\s*(gmail|yahoo|outlook|hotmail|icloud)(\.com)?\b'),
                  (match) => '@${match.group(1)}${match.group(2) ?? '.com'}',
                )
                .replaceAll(RegExp(r'\s+'), '');
          }
          // contact number or identity number -> digits only (no dashes)
          // else if (activeController == signUp.contactnumber ||
          //     activeController == signUp.id) {
          //   finalText = _spokenToDigits(recognized);
          // }
          // password -> keep chars but remove spaces
          else if (activeController == signUp.password) {
            // process spoken password: support "capital" to uppercase next letter,
            // map spoken digits, and remove spaces
            finalText = _processPasswordSpoken(recognized);
          }
          // all other fields -> remove all spaces and capitalize first letter
          else {
            finalText = _capitalizeFirstLetter(_removeAllSpaces(recognized));
          }

          speechText.value = finalText;
          // write the space-free value to the active field
          activeController!.text = finalText;
          activeController!.selection = TextSelection.fromPosition(
              TextPosition(offset: finalText.length));
        }

        // When final result arrives, stop listening.
        if (result.finalResult) {
          // give recognizer extra time to emit any trailing token (helps repeated digits)
          await Future.delayed(const Duration(milliseconds: 300));
          debugPrint('STT finalResult, lastPartial="$_lastPartial"');
          // ensure controller contains the latest partial before stopping
          if (activeController != null && activeController!.text.isEmpty) {
            // fallback: write lastPartial if controller wasn't updated yet
            final fallback = _lastPartial.replaceAll(RegExp(r'\s+'), '');
            if (fallback.isNotEmpty) {
              activeController!.text = fallback;
              activeController!.selection = TextSelection.fromPosition(
                  TextPosition(offset: fallback.length));
            }
          }
          await stopListening();
          if (activeController != null) {
            await spellOutText(activeController!.text);
          }
          _lastPartial = '';
        }
      },
      listenMode: dictation ? ListenMode.dictation : ListenMode.confirmation,
    );
  }

  /// Listen for commands only (does NOT write into any text field)
  Future<void> listenForCommand({required Function(String) onResult}) async {
    if (SpeechGuard.suppressAutoStart) {
      debugPrint(
          '\x1B[33m[listenForCommand] suppressed by SpeechGuard.suppressAutoStart\x1B[0m');
      return;
    }
    if (_speech.isListening) {
      await _speech.stop();
      isListening.value = false;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        debugPrint(_debugHighlight('Command listener status: $status'));
        if (status == 'notListening') {
          isListening.value = false;
        }
      },
      onError: (error) {
        debugPrint(_debugHighlight('Command listener error: $error'));
        isListening.value = false;
      },
    );
    // log source for this initialization
    {
      final src = StackTrace.current.toString().split('\n').elementAt(1).trim();
      debugPrint(
          '\x1B[30;43m[STT INIT] ${DateTime.now().toIso8601String()} src=$src\x1B[0m');
      debugPrint(
          '\x1B[30;43m[STT LISTEN] ${DateTime.now().toIso8601String()} src=$src\x1B[0m');
    }

    if (!available) {
      debugPrint(
          _debugHighlight('Speech recognition not available for commands'));
      return;
    }

    // Play beep right before listen so it aligns with STT window
    try {
      await _playNativeBeep();
      await Future.delayed(const Duration(milliseconds: 180));
    } catch (_) {}

    isListening.value = true;

    await _speech.listen(
      onResult: (result) async {
        final recognized = result.recognizedWords.toLowerCase().trim();
        if (recognized.isEmpty) return;

        debugPrint(_debugHighlight('Command STT: $recognized'));

        // deliver result to caller
        try {
          onResult(recognized);
        } catch (e) {
          debugPrint(
              _debugHighlight('Error delivering command to callback: $e'));
        }

        if (result.finalResult) {
          await stopListening();
        }
      },
      listenMode: ListenMode.confirmation,
    );
  }

  /// Returns true if user wants to edit, false otherwise
  Future<bool> listenForYesNo(
      String field, TextEditingController controller) async {
    // Ensure any TTS has finished so we don't capture our own voice output
    await flutterTts.awaitSpeakCompletion(true);

    if (_speech.isListening) {
      await _speech.stop();
      isListening.value = false;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        debugPrint(_debugHighlight('YesNo listener status: $status'));
        if (status == 'notListening') isListening.value = false;
      },
      onError: (err) {
        debugPrint(_debugHighlight('YesNo listener error: $err'));
        isListening.value = false;
      },
    );
    if (!available) return false;

    isListening.value = true;
    final completer = Completer<bool>();
    Timer? timeoutTimer;
    const int timeoutSeconds = 5;

    // Fallback on timeout
    timeoutTimer = Timer(const Duration(seconds: timeoutSeconds), () async {
      if (!completer.isCompleted) {
        await stopListening();
        await flutterTts.speak('Okay, moving on');
        completer.complete(false);
      }
    });

    await _speech.listen(
      listenFor: const Duration(seconds: timeoutSeconds),
      onResult: (result) async {
        if (!result.finalResult) return;

        final response = result.recognizedWords.toLowerCase().trim();
        timeoutTimer?.cancel();
        await stopListening();

        final positive = ['yes', 'yeah', 'yep', 'sure', 'please'];
        final negative = ['no', 'nah', 'nope'];

        if (positive.any((p) => response.contains(p))) {
          // Start editing flow
          await activateFieldForEditing(field, controller);
          if (!completer.isCompleted) completer.complete(true);
        } else if (negative.any((n) => response.contains(n))) {
          await flutterTts.speak('Okay, moving on');
          if (!completer.isCompleted) completer.complete(false);
        } else {
          // Unclear — ask once more briefly
          await flutterTts.speak('Please say yes or no');
          await flutterTts.awaitSpeakCompletion(true);
          // if still not answered, default to moving on
          if (!completer.isCompleted) {
            await stopListening();
            await flutterTts.speak('Okay, moving on');
            completer.complete(false);
          }
        }
      },
      listenMode: ListenMode.confirmation,
    );

    return completer.future;
  }

  /// Command handler (keeps SignUpController logic intact)
  Future<void> _handleCommand(String recognized) async {
    final signUp = Get.find<SignUpController>();

    // === SUBMIT COMMAND ===
    if (recognized.contains('submit')) {
      // Ask for confirmation using an unambiguous prompt, then validate locally.
      await flutterTts
          .speak("Please say yes to confirm submission, or no to cancel.");
      await flutterTts.awaitSpeakCompletion(true);
      await Future.delayed(const Duration(milliseconds: 1200)); // avoid echo

      // Run basic client-side validation before listening for confirmation
      final errors = _validateSignUp(signUp);
      if (errors.isNotEmpty) {
        await flutterTts
            .speak('There are problems with your form. I will read them out.');
        await flutterTts.awaitSpeakCompletion(true);
        for (final e in errors) {
          await flutterTts.speak(e);
          await flutterTts.awaitSpeakCompletion(true);
        }
        await flutterTts.speak(
            'Please edit the fields mentioned and try submitting again.');
        return;
      }

      debugPrint(_debugHighlight('[submit] starting confirmation listen'));
      final resp = await listenForCommandWithTimeout(timeoutSeconds: 8);
      final answer = resp?.toLowerCase().trim() ?? '';

      // ignore any recognition that simply repeats our prompt words
      if (answer.isEmpty ||
          answer.contains('submit') ||
          answer.contains('are you') ||
          answer.contains('please say')) {
        await flutterTts
            .speak('No confirmation received. Submission cancelled.');
        return;
      }

      // Require explicit yes-like responses
      final positive = ['yes', 'yeah', 'yep', 'y'];
      final negative = ['no', 'nah', 'nope'];

      if (positive.any((p) => answer.contains(p))) {
        // Delegate final validation + submission to SignUpController
        // submitRegistration() performs validation, writes to Firestore and navigates.
        await signUp.submitRegistration();
      } else if (negative.any((n) => answer.contains(n))) {
        await flutterTts.speak('Submission cancelled');
      } else {
        await flutterTts.speak('Unclear response. Submission cancelled');
      }
      return;
    }

    // === RESTART REGISTRATION ===
    if (recognized.contains('restart registration')) {
      debugPrint(_debugHighlight('Restart command detected'));
      await flutterTts.speak('Restarting registration process');
      await flutterTts.awaitSpeakCompletion(true);

      // Reset stopFlow flag
      signUp.stopFlow.value = false;

      // Clear all controllers
      signUp.name.clear();
      signUp.surname.clear();
      //signUp.id.clear();
      signUp.email.clear();
      signUp.contactnumber.clear();
      signUp.password.clear();

      // Restart the voice onboarding (orchestrator)
      signUp.startVoiceOnboarding();
      return;
    }

    // === Repeat all fields ===
    if (recognized == 'repeat all fields') {
      final fields = {
        'Name': signUp.name.text,
        'Surname': signUp.surname.text,
        //  'ID Number': signUp.id.text,
        'Email': signUp.email.text,
        'Contact Number':
            signUp.contactnumber.text.replaceAll(RegExp(r'[^0-9]'), ''),
      };

      for (final entry in fields.entries) {
        final fieldName = entry.key;
        final value = entry.value;

        if (value.isEmpty) {
          await flutterTts.speak('$fieldName is empty');
        } else {
          final spelled = value.split('').map((char) {
            switch (char) {
              case '@':
                return 'at';
              case '.':
                return 'dot';
              case '_':
                return 'underscore';
              case '-':
                return 'dash';
              default:
                return char;
            }
          }).join(' ');
          await flutterTts.speak('$fieldName: $spelled');
        }

        // small delay between fields
        await Future.delayed(const Duration(milliseconds: 300));
      }
      return;
    }

    // Repeat a specific field
    if (recognized.startsWith('repeat ')) {
      final rawField = recognized.replaceFirst('repeat ', '').trim();
      final field = _normalizeField(rawField);
      final fieldMap = {
        'name': signUp.name,
        'surname': signUp.surname,
        'email': signUp.email,
        'contact number': signUp.contactnumber,
        //'identity number': signUp.id,
        'password': signUp.password,
      };

      if (fieldMap.containsKey(field)) {
        final value = fieldMap[field]!.text;
        if (value.isEmpty) {
          await flutterTts.speak('$field is empty');
        } else {
          final spelled = value.split('').map((char) {
            switch (char) {
              case '@':
                return 'at';
              case '.':
                return 'dot';
              case '_':
                return 'underscore';
              case '-':
                return 'dash';
              default:
                return char;
            }
          }).join(' ');

          await flutterTts.speak('$field: $spelled');
        }

        // Ask yes/no to edit
        await flutterTts.speak('Would you like to edit $field?');
        await flutterTts.awaitSpeakCompletion(true);
        await listenForYesNo(field, fieldMap[field]!);
      } else {
        await flutterTts.speak('Field $field not recognized');
      }
      return;
    }

    // Clear a field
    if (recognized.startsWith('clear ')) {
      final rawField = recognized.replaceFirst('clear ', '').trim();
      final field = _normalizeField(rawField);
      final fields = {
        'name': signUp.name,
        'surname': signUp.surname,
        'email': signUp.email,
        'contact number': signUp.contactnumber,
        //'identity number': signUp.id,
        'password': signUp.password,
      };

      if (fields.containsKey(field)) {
        fields[field]!.clear();
        await flutterTts.speak('$field cleared');
      } else {
        await flutterTts.speak('Field $field not recognized');
      }
      return;
    }

    // Edit/go to field
    // Only handle "edit <field>" or "go to <field>" (require following field text)
    if (RegExp(r'^\s*(edit|go to)\s+', caseSensitive: false)
        .hasMatch(recognized)) {
      // strip the leading "edit " or "go to "
      String rawField = recognized
          .replaceFirst(
              RegExp(r'^\s*(edit|go to)\s+', caseSensitive: false), '')
          .trim();

      if (rawField.isEmpty) {
        await flutterTts.speak(
            'Please say edit followed by the field name, for example "edit name".');
        return;
      }

      final field = _normalizeField(rawField);

      final fieldMap = {
        'name': signUp.name,
        'surname': signUp.surname,
        'email': signUp.email,
        'contact number': signUp.contactnumber,
        //  'identity number': signUp.id,
        'password': signUp.password,
      };
      // final nodeMap = {
      //   'name': signUp.nameNode,
      //   'surname': signUp.surnameNode,
      //   'email': signUp.emailNode,
      //   'contact number': signUp.contactnumberNode,
      //   //  'identity number': signUp.idNode,
      //   'password': signUp.passwordNode,
      // };

      if (field.isEmpty) {
        await flutterTts.speak('I did not hear a field to edit.');
        return;
      }

      if (fieldMap.containsKey(field)) {
        // Use activateFieldForEditing so the UI focuses the field and the service starts listening
        await activateFieldForEditing(field, fieldMap[field]!);
      } else {
        await flutterTts.speak('Field $field not recognized');
      }
      return;
    }

    // If nothing matched:
    debugPrint(
        _debugHighlight('Unhandled command in _handleCommand: $recognized'));
  }

  /// Activate a field for editing (used by SignUpController)
  Future<void> activateFieldForEditing(
      String field, TextEditingController controller) async {
    activeController = controller;
    activeFieldName = field;

    final signUp = Get.find<SignUpController>();
    signUp.goToField(controller, signUp.getNodeForField(field), field);

    await flutterTts.speak('Editing $field');
    await flutterTts.awaitSpeakCompletion(true);

    // Avoid catching residual TTS
    // set a guard so any STT results until _allowListeningAfter are dropped.
    _allowListeningAfter = DateTime.now().add(const Duration(seconds: 3));
    // small extra sleep to be safe on platforms where awaitSpeakCompletion is unreliable
    await Future.delayed(const Duration(seconds: 3));
    speechText.value = '';

    // Wait until the guard expires before actually starting the microphone.
    final waitUntil = _allowListeningAfter!;
    final now = DateTime.now();
    if (waitUntil.isAfter(now)) {
      await Future.delayed(waitUntil.difference(now));
    }

    // Retry listening for fields that often end up empty (contact/id/password)
    final retryFields = {'contact number', /*'identity number',*/ 'password'};
    final maxAttempts = retryFields.contains(field) ? 3 : 1;
    int attempts = 0;
    do {
      // Start dictation listening for free-form input
      await startListening(dictation: true);

      // Wait for listening to finish
      while (isListening.value) {
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // If no input captured and we still have attempts left, prompt and retry
      if (controller.text.trim().isEmpty && attempts < maxAttempts - 1) {
        attempts++;
        await flutterTts
            .speak('I did not hear anything. Please say the $field again.');
        await flutterTts.awaitSpeakCompletion(true);
        await Future.delayed(const Duration(milliseconds: 600));
        continue;
      }
      break;
    } while (attempts < maxAttempts);

    // After user finishes editing, repeat the new value back (if any)
    final newValue = controller.text.trim();
    String updatedValue = newValue;
    // If editing contact number, strip any non-digit characters so there are no dashes
    if (_isContactField(field)) {
      updatedValue = newValue.replaceAll(RegExp(r'[^0-9]'), '');
      controller.text = updatedValue;
    }

    if (updatedValue.isNotEmpty) {
      await flutterTts.speak('$field updated to:');
      await flutterTts.awaitSpeakCompletion(true);
      await spellOutText(updatedValue);
      await flutterTts.awaitSpeakCompletion(true);
    } else {
      await flutterTts.speak('No input was detected for $field');
      await flutterTts.awaitSpeakCompletion(true);
    }
    // Clear active field marker
    activeFieldName = null;
  }

  Future<void> stopListening() async {
    if (isListening.value || _speech.isListening) {
      await _speech.stop();
      isListening.value = false;
      // keep speechText (the last recognized) intact — orchestrator will use it
      debugPrint(_debugHighlight('Stopped listening'));
    }
  }

  String _capitalizeFirstLetter(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
  }

  // Remove all whitespace from a string (collapse and strip)
  String _removeAllSpaces(String s) => s.replaceAll(RegExp(r'\s+'), '').trim();

  Future<void> spellOutText(String input) async {
    if (input.isEmpty) return;
    await flutterTts.setSpeechRate(0.4);
    await flutterTts.setPitch(1.0);
    await flutterTts.awaitSpeakCompletion(true);

    String namePart = input;
    String domainPart = '';
    final lower = input.toLowerCase();
    final knownDomains = [
      'gmail.com',
      'yahoo.com',
      'outlook.com',
      'hotmail.com',
      'icloud.com'
    ];

    for (String domain in knownDomains) {
      if (lower.contains(domain)) {
        int idx = lower.indexOf(domain);
        namePart = input.substring(0, idx);
        domainPart = domain;
        break;
      }
    }

    final spelled = namePart.split('').map((c) {
      switch (c) {
        case '@':
          return 'at';
        case '.':
          return 'dot';
        case '_':
          return 'underscore';
        case '-':
          return 'dash';
        default:
          return c;
      }
    }).join(' ');

    String spokenDomain = '';
    if (domainPart.isNotEmpty) {
      final parts = domainPart.split('.');
      spokenDomain = parts.join(' dot ');
    }

    await flutterTts
        .speak(spelled + (spokenDomain.isEmpty ? '' : ' $spokenDomain'));
    await flutterTts.awaitSpeakCompletion(true);
    // restore default speed if needed
    await flutterTts.setSpeechRate(0.45);
  }

  Future<void> listenCommand() async {
    if (SpeechGuard.suppressAutoStart) {
      debugPrint(
          '\x1B[33m[listenCommand] suppressed by SpeechGuard.suppressAutoStart\x1B[0m');
      return;
    }
    // Clear activeController so nothing gets edited
    activeController = null;

    if (_speech.isListening) {
      await _speech.stop();
      isListening.value = false;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        debugPrint(_debugHighlight('Command listener status: $status'));
        if (status == 'notListening') {
          isListening.value = false;
        }
      },
      onError: (error) {
        debugPrint(_debugHighlight('Command listener error: $error'));
        isListening.value = false;
      },
    );

    if (!available) {
      debugPrint(
          _debugHighlight('Speech recognition not available for commands'));
      return;
    }

    // play beep right before starting the recognizer
    try {
      await _playNativeBeep();
      await Future.delayed(const Duration(milliseconds: 180));
    } catch (_) {}

    isListening.value = true;

    await _speech.listen(
      onResult: (result) async {
        final recognized = result.recognizedWords.toLowerCase().trim();
        if (recognized.isEmpty) return;

        debugPrint(_debugHighlight('listenCommand heard: $recognized'));

        await _handleCommand(recognized);

        if (result.finalResult) {
          await stopListening();
        }
      },
      listenMode: ListenMode.confirmation,
    );
  }

  /// Play the native beep then start the command listener.
  Future<void> playBeepAndListenForCommands() async {
    try {
      debugPrint(_debugHighlight('[playBeepAndListen] start'));

      // Ensure any existing listening is stopped
      if (_speech.isListening) {
        await _speech.stop();
        isListening.value = false;
      }

      // Kick off the command listener — listenCommand now plays the beep right
      // before calling _speech.listen (after initialize), so do not play it here.
      debugPrint(
          _debugHighlight('[playBeepAndListen] starting command listener'));
      // listenCommand has its own suppression guard
      await listenCommand();
      debugPrint(_debugHighlight('[playBeepAndListen] listening started'));
    } catch (e, st) {
      debugPrint(_debugHighlight('[playBeepAndListen] failed: $e\n$st'));
      // Ensure we are in a consistent state
      try {
        if (_speech.isListening) await _speech.stop();
      } catch (_) {}
      isListening.value = false;
      wasMicPressed.value = false;
    }
  }

  Future<String?> listenForCommandWithTimeout({int timeoutSeconds = 6}) async {
    if (SpeechGuard.suppressAutoStart) {
      debugPrint(
          '\x1B[33m[listenForCommandWithTimeout] suppressed by SpeechGuard.suppressAutoStart\x1B[0m');
      return null;
    }
    if (_speech.isListening) await _speech.stop();
    bool available = await _speech.initialize();
    // diagnostic
    final src = StackTrace.current.toString().split('\n').elementAt(1).trim();
    debugPrint(
        '\x1B[30;43m[STT INIT] ${DateTime.now().toIso8601String()} src=$src\x1B[0m');

    if (!available) return null;

    // play beep immediately before starting listen (so it's aligned with STT window)
    try {
      await _playNativeBeep();
      await Future.delayed(const Duration(milliseconds: 180));
    } catch (_) {}

    String? recognizedText;
    final completer = Completer<String?>();
    Timer? timer;

    timer = Timer(Duration(seconds: timeoutSeconds), () {
      if (!completer.isCompleted) completer.complete(null); // Timeout
      if (_speech.isListening) _speech.stop();
    });

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

  /// Play native beep only (no STT). Useful when another widget will start listening.
  Future<void> playBeepOnly({int delayMs = 160}) async {
    try {
      await _playNativeBeep();
      // short pause so the beep doesn't get captured by STT
      await Future.delayed(Duration(milliseconds: delayMs));
    } catch (e) {
      debugPrint('playBeepOnly failed: $e');
    }
  }

  // Normalize spoken field into canonical key used by maps
  String _normalizeField(String raw) {
    var f = raw.toLowerCase().trim();
    // remove polite prefixes
    f = f.replaceAll(RegExp(r'\b(my|the|please|for)\b'), '').trim();

    // // common ID variants
    // if (f.contains('id') ||
    //     f.contains('identity') ||
    //     f.contains('identity number')) {
    //   return 'identity number';
    // }
    // contact / phone variants (but not id)
    if (f.contains('contact') ||
        f.contains('phone') ||
        f.contains('mobile') ||
        f.contains('tel')) {
      return 'contact number';
    }

    // check surname/last name first (avoid matching "name" inside "surname")
    if (f.contains('surname') ||
        f.contains('last') ||
        f.contains('family name') ||
        f.contains('last name')) {
      return 'surname';
    }

    // exact known short keys - match full word "name" only
    if (RegExp(r'\bname\b').hasMatch(f)) return 'name';
    if (f.contains('email')) return 'email';
    if (f.contains('password')) return 'password';

    // fallback to raw trimmed
    return f;
  }

  bool _isContactField(String field) {
    final f = field.toLowerCase();
    return f.contains('contact') ||
        f.contains('phone') ||
        f.contains('mobile') ||
        f.contains('tel');
  }

  // Map a single spoken token to a digit if applicable
  String _tokenToDigit(String t) {
    const map = {
      'sex': '6',
      'one': '1',
      '1': '1',
      'two': '2',
      '2': '2',
      'three': '3',
      '3': '3',
      'four': '4',
      'for': '4',
      '4': '4',
      'five': '5',
      '5': '5',
      'six': '6',
      '6': '6',
      'seven': '7',
      '7': '7',
      'eight': '8',
      '8': '8',
      'nine': '9',
      '9': '9',
    };
    return map[t] ?? '';
  }

  // Robust spoken->digits conversion that preserves repeated tokens
  String _spokenToDigits(String recognized) {
    if (recognized.isEmpty) return '';

    // Normalize common separators and commas, then split into tokens
    final cleaned =
        recognized.toLowerCase().replaceAll(RegExp(r'[,\(\)]'), ' ');
    final tokens =
        cleaned.split(RegExp(r'[\s\-]+')).where((t) => t.isNotEmpty).toList();

    // If the recognized string already contains contiguous digits like "1111" return them
    final contiguousDigits = RegExp(r'\d{2,}').firstMatch(cleaned);
    if (contiguousDigits != null && contiguousDigits.group(0)!.length >= 2) {
      // strip non-digit chars and return
      return cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    }

    final buf = StringBuffer();
    for (final t in tokens) {
      // if token is a single digit character or a multi-digit group, keep it
      if (RegExp(r'^\d+$').hasMatch(t)) {
        buf.write(t); // preserves repeated groups like "1 1 1 1" -> "1111"
        continue;
      }

      // map spoken words to digits (preserves repeated "one one one one")
      final d = _tokenToDigit(t);
      if (d.isNotEmpty) {
        buf.write(d);
        continue;
      }

      // handle common compound like "double one" or "triple one"
      final m = RegExp(r'^(double|triple|quadruple|double-)(?:\s)?([a-z0-9])$')
          .firstMatch(t);
      if (m != null) {
        final word = m.group(1)!;
        final char = m.group(2)!;
        final digit = _tokenToDigit(char) == '' ? '' : _tokenToDigit(char);
        if (digit.isNotEmpty) {
          final times = word.startsWith('double')
              ? 2
              : word.startsWith('triple')
                  ? 3
                  : 4;
          buf.write(digit * times);
          continue;
        }
      }

      // as a last resort, strip non-digits from token and append if any
      final leftoverDigits = t.replaceAll(RegExp(r'[^0-9]'), '');
      if (leftoverDigits.isNotEmpty) buf.write(leftoverDigits);
    }

    return buf.toString();
  }

  // Normalize spoken email text into a single canonical email string (no spaces)
  // String _normalizeSpokenEmail(String recognized) {
  //   var s = recognized.toLowerCase();

  //   // Normalize common spoken tokens to symbols
  //   s = s.replaceAll(RegExp(r'\bunderscore\b'), '_');
  //   s = s.replaceAll(RegExp(r'\bunder score\b'), '_');
  //   s = s.replaceAll(RegExp(r'\bdot\b|\bperiod\b|\bpoint\b'), '.');
  //   s = s.replaceAll(RegExp(r'\bhyphen\b|\bdash\b'), '-');
  //   s = s.replaceAll(RegExp(r'\bat\b'), '@');

  //   // remove stray punctuation that can confuse tokenization
  //   s = s.replaceAll(RegExp(r'''[,()"']'''), ' ');

  //   // ensure symbols are separate tokens so we can rebuild without spaces
  //   s = s.replaceAll('@', ' @ ');
  //   s = s.replaceAll('.', ' . ');
  //   s = s.replaceAll('_', ' _ ');
  //   s = s.replaceAll('-', ' - ');

  //   // collapse whitespace and split into tokens
  //   final tokens = s.replaceAll(RegExp(r'\s+'), ' ').trim().split(' ');

  //   final buf = StringBuffer();
  //   for (final t in tokens) {
  //     if (t.isEmpty) continue;
  //     // keep explicit symbols as-is
  //     if (t == '@' || t == '.' || t == '_' || t == '-') {
  //       buf.write(t);
  //       continue;
  //     }

  //     // if token is a single-letter (spelled character) or digit, append directly (collapses spaced letters)
  //     if (RegExp(r'^[a-z0-9]$').hasMatch(t)) {
  //       buf.write(t);
  //       continue;
  //     }

  //     // if token is a multi-letter word (gmail, yahoo, name), append as-is but strip non-alnum
  //     final clean = t.replaceAll(RegExp(r'[^a-z0-9]'), '');
  //     if (clean.isNotEmpty) {
  //       buf.write(clean);
  //     }
  //   }

  //   var out = buf.toString();
  //   // If domain spoken like "gmail" (without .com) normalize common domains to include .com
  //   final commonDomainMatch =
  //       RegExp(r'@?(gmail|yahoo|outlook|hotmail|icloud)$').firstMatch(out);
  //   if (commonDomainMatch != null) {
  //     final domain = commonDomainMatch.group(1)!;
  //     // split at domain start to keep local part intact
  //     final idx = out.indexOf(domain);
  //     final local = idx > 0 ? out.substring(0, idx) : '';
  //     out = '$local@$domain.com';
  //   }

  //   // final safety: remove any remaining whitespace (should be none) and collapse repeated dots
  //   out = out.replaceAll(RegExp(r'\s+'), '');
  //   out = out.replaceAll(RegExp(r'\.{2,}'), '.');
  //   return out;
  // }

  // Basic client-side validations; returns list of spoken error messages.
  List<String> _validateSignUp(SignUpController signUp) {
    final errors = <String>[];
    final name = signUp.name.text.trim();
    final surname = signUp.surname.text.trim();
    //  final rawId = signUp.id.text.trim();
    //final idDigits = rawId.replaceAll(RegExp(r'[^0-9]'), '');
    final email = signUp.email.text.trim();
    final contact = signUp.contactnumber.text.replaceAll(RegExp(r'[^0-9]'), '');
    final password = signUp.password.text;

    if (name.isEmpty) errors.add('Name is empty.');
    if (surname.isEmpty) errors.add('Surname is empty.');

    // ID: must be exactly 13 digits
    // if (idDigits.isEmpty) {
    //   errors.add('ID number is empty.');
    // } else if (idDigits.length != 13) {
    //   errors.add('ID number must be exactly 13 digits.');
    // }

    // basic email regex
    final emailReg = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (email.isEmpty) {
      errors.add('Email is empty.');
    } else if (!emailReg.hasMatch(email)) {
      errors.add('Email looks invalid.');
    }

    // contact length check
    if (contact.isEmpty) {
      errors.add('Contact number is empty.');
    } else if (contact.length < 7 || contact.length > 15) {
      errors.add('Contact number should be between 7 and 15 digits.');
    }

    // password minimal length
    if (password.isEmpty) {
      errors.add('Password is empty.');
    } else if (password.length < 6) {
      errors.add('Password must be at least 6 characters.');
    }

    return errors;
  }

  // Map a single spoken token to a digit if applicable

  // Process spoken password input:
  // - "capital" / "capital letter" / "uppercase" -> uppercase next alpha token
  // - numeric words -> digits
  // - collapse everything into one contiguous string (no spaces)
  String _processPasswordSpoken(String recognized) {
    final tokens = recognized.toLowerCase().trim().split(RegExp(r'\s+'));
    final buf = StringBuffer();
    var nextCapital = false;

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.isEmpty) continue;

      // Capitalization commands
      if (t == 'capital' ||
          t == 'capitalletter' ||
          t == 'capital-letter' ||
          t == 'capitalize' ||
          t == 'uppercase' ||
          t == 'cap') {
        nextCapital = true;
        continue;
      }

      // Also support "capital letter" as two tokens
      if (t == 'letter' &&
          i > 0 &&
          (tokens[i - 1] == 'capital' || tokens[i - 1] == 'uppercase')) {
        // already handled by previous iteration (we set nextCapital), skip
        continue;
      }

      // digits spoken as words
      final digit = _tokenToDigit(t);
      if (digit.isNotEmpty) {
        buf.write(digit);
        nextCapital = false;
        continue;
      }

      // If single alpha character (likely spelled) -> append as single char
      if (RegExp(r'^[a-z]$').hasMatch(t)) {
        final ch = nextCapital ? t.toUpperCase() : t.toLowerCase();
        buf.write(ch);
        nextCapital = false;
        continue;
      }

      // Multi-letter token: clean non-alnum, capitalize first letter if requested
      var clean = t.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (clean.isEmpty) continue;
      if (nextCapital) {
        clean = clean[0].toUpperCase() +
            (clean.length > 1 ? clean.substring(1) : '');
        nextCapital = false;
      }
      buf.write(clean);
    }

    return buf.toString();
  }

  Future<bool> initializeSpeech(SpeechToText speech) async {
    // Block on global gate
    if (!SpeechGuard.allowListening) {
      debugPrint('[STT][service] initialize blocked — allowListening=false');
      return false;
    }
    // Wait while TTS is speaking
    while (SpeechGuard.ttsSpeaking) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return await speech.initialize();
  }

  /// Graceful cleanup used when callers call `svc.dispose()` before deleting the service.
  /// Keeps the method safe to call multiple times.
  Future<void> dispose() async {
    try {
      await stopListening();
    } catch (_) {}
    try {
      if (_speech.isListening) await _speech.stop();
    } catch (_) {}
    try {
      await flutterTts.stop();
    } catch (_) {}
    // clear references
    activeController = null;
    activeFieldName = null;
    // clear guards to leave app in a consistent state
    try {
      SpeechGuard.allowListening = false;
    } catch (_) {}
    try {
      SpeechGuard.ttsSpeaking = false;
    } catch (_) {}
    debugPrint(_debugHighlight('SpeechService disposed'));
  }

  void maybeAutoStart() {
    // C: suppression check
    if (SpeechGuard.suppressAutoStart) {
      debugPrint('Auto-start suppressed by SpeechGuard.suppressAutoStart');
      return;
    }
    if (!SpeechGuard.allowListening) return;
    // ...existing auto-start logic that initializes/starts STT...
  }
}
