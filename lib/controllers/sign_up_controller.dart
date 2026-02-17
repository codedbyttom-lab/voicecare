// sign_up_controller.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:voicecare/homepage/home_page.dart';
import 'package:voicecare/mic_widget/service_speech.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:voicecare/Firebase/Auth_service.dart';

class SignUpController extends GetxController {
  final activeController = Rxn<TextEditingController>();
  final SpeechService speechService = Get.find<SpeechService>();

  final TextEditingController name = TextEditingController();
  final TextEditingController surname = TextEditingController();
  //final TextEditingController id = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController contactnumber = TextEditingController();
  final TextEditingController password = TextEditingController();

  var stopFlow = false.obs;

  late FocusNode nameNode;
  late FocusNode surnameNode;
  late FocusNode emailNode;
  late FocusNode contactnumberNode;
  //late FocusNode idNode;
  late FocusNode passwordNode;

  late final Map<String, FocusNode> _focusNodes;
  late final Map<String, TextEditingController> _controllerMap;

  @override
  void onInit() {
    super.onInit();
    nameNode = FocusNode();
    surnameNode = FocusNode();
    emailNode = FocusNode();
    contactnumberNode = FocusNode();
    //idNode = FocusNode();
    passwordNode = FocusNode();

    _focusNodes = {
      'name': nameNode,
      'surname': surnameNode,
      'email': emailNode,
      'contactnumber': contactnumberNode,
      //'id': idNode,
      'password': passwordNode,
    };

    _controllerMap = {
      'name': name,
      'surname': surname,
      'email': email,
      'contactnumber': contactnumber,
      //'id': id,
      'password': password,
    };
  }

  String _debugHighlight(String message) {
    return '\x1B[43m$message\x1B[0m';
  }

  FocusNode getNodeForField(String field) {
    switch (field) {
      case 'name':
        return nameNode;
      case 'surname':
        return surnameNode;
      case 'email':
        return emailNode;
      case 'contact number':
        return contactnumberNode;
      // case 'identity number':
      //   return idNode;
      case 'password':
        return passwordNode;
      default:
        return FocusNode();
    }
  }

  /// Listen for commands only (no active field)
  Future<void> listenForCommand() async {
    activeController.value = null;
    await speechService.listenForCommand(onResult: (cmd) {
      handleVoiceCommand(cmd);
    });
  }

  void handleVoiceCommand(String command) {
    final normalized = command.toLowerCase().trim();

    void activateField(String key, String label) {
      final controller = _controllerMap[key];
      final node = _focusNodes[key];
      if (controller != null && node != null) {
        activeController.value = controller;
        node.requestFocus();
        speechService.flutterTts.speak('Now filling in $label field');
        // Wait for TTS to finish and a small buffer, then start listening
        Future.delayed(const Duration(milliseconds: 600), () async {
          // ensure TTS finished
          await speechService.flutterTts.awaitSpeakCompletion(true);
          await Future.delayed(const Duration(milliseconds: 400));
          await listenToUser();
        });
      }
    }

    if (normalized.contains('go to name')) {
      activateField('name', 'name');
    } else if (normalized.contains('go to surname')) {
      activateField('surname', 'surname');
    } else if (normalized.contains('go to email')) {
      activateField('email', 'email');
    } else if (normalized.contains('go to contact number')) {
      activateField('contactnumber', 'contact number');
    }
    //else if (normalized.contains('go to id')) {
    //   activateField('id', 'ID');
    //}
    else if (normalized.contains('go to password')) {
      activateField('password', 'password');
    } else if (normalized.contains('restart registration')) {
      debugPrint(_debugHighlight('Restart command detected'));
      speechService.flutterTts.speak('Restarting registration process');
      restartVoiceOnboarding();
    } else {
      debugPrint(_debugHighlight('No matching field for command: "$command"'));
    }
  }

  Future<void> listenForCommandMode() async {
    activeController.value = null;
    speechService.setActiveController(null);
    await speechService.listenCommand();
  }

  Future<void> listenToUser({bool format = true}) async {
    if (activeController.value == null) {
      debugPrint(_debugHighlight('No active controller set.'));
      return;
    }

    speechService.setActiveController(activeController.value!);

    // start listening in dictation mode for free-form fields
    await speechService.startListening(dictation: true);

    // Wait until listening finishes (or is aborted)
    while (speechService.isListening.value) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // Format text if requested
    final rawText = activeController.value!.text;
    if (format && rawText.isNotEmpty) {
      // collapse multiple whitespace into single spaces, preserve word separation
      String formatted = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
      formatted = formatted[0].toUpperCase() + formatted.substring(1);
      activeController.value!.text = formatted;
      activeController.value!.selection =
          TextSelection.fromPosition(TextPosition(offset: formatted.length));
    }

    // After listening is done, the orchestration (if done inside onboarding) will repeat.
  }

  void goToField(
      TextEditingController controller, FocusNode node, String fieldName) {
    activeController.value = controller;
    speechService.setActiveController(controller);
    speechService.setWasMicPressed(false);

    if (!node.hasFocus) node.requestFocus();

    // Just announce; don't immediately start listening — caller decides when.
    speechService.flutterTts.speak("Editing $fieldName");
  }

  // ==== VALIDATION METHODS WITH VOICE FEEDBACK ====
  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      speechService.flutterTts.speak('Email cannot be empty');
      return 'Email cannot be empty';
    } else if (!GetUtils.isEmail(value)) {
      speechService.flutterTts.speak('Please enter a valid email address');
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      speechService.flutterTts.speak('First name cannot be empty');
      return 'First name cannot be empty';
    }
    return null;
  }

  String? validateSurname(String? value) {
    if (value == null || value.trim().isEmpty) {
      speechService.flutterTts.speak('surname cannot be empty');
      return 'surname cannot be empty';
    }
    return null;
  }

  // String? validateId(String? value) {
  //   if (value == null || value.trim().isEmpty) {
  //     speechService.flutterTts.speak('ID number cannot be empty');
  //     return 'ID number cannot be empty';
  //   } else if (value.length != 13) {
  //     speechService.flutterTts.speak('ID number must be 13 digits');
  //     return 'ID number must be 13 digits';
  //   }
  //   return null;
  // }

  String? validateContactNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      speechService.flutterTts.speak('Contact number cannot be empty');
      return 'Contact number cannot be empty';
    } else if (!RegExp(r'^\d{10}$').hasMatch(value.trim())) {
      speechService.flutterTts.speak('Contact number must be 10 digits');
      return 'Contact number must be 10 digits';
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.trim().isEmpty) {
      speechService.flutterTts.speak('Password cannot be empty');
      return 'Password cannot be empty';
    }

    final pwd = value.trim();

    // Require: minimum 6 characters, at least one uppercase, one lowercase, and at least two digits
    final pattern = RegExp(r'^(?=.*[A-Z])(?=.*[a-z])(?=(.*\d){2,}).{6,}$');

    if (!pattern.hasMatch(pwd)) {
      speechService.flutterTts.speak(
          'Password must be at least six characters long, include at least one uppercase letter, one lowercase letter, and two numbers');
      return 'Password must be at least 6 chars, include upper & lower case, and 2 numbers';
    }

    return null;
  }

  // helper: ensure recognizer stopped, stop any TTS, then speak and wait
  Future<void> _stopThenSpeak(String txt) async {
    // ensure any recognition is fully stopped
    if (speechService.isListening.value) {
      await speechService.stopListening();
      // wait until the engine reports it is stopped
      while (speechService.isListening.value) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      await Future.delayed(const Duration(milliseconds: 200)); // extra settle
    }

    // ensure any previous TTS playback is stopped before speaking
    try {
      await speechService.flutterTts.stop();
    } catch (_) {}

    // speak and wait for completion, then small buffer
    await speechService.flutterTts.speak(txt);
    await speechService.flutterTts.awaitSpeakCompletion(true);
    await Future.delayed(const Duration(seconds: 1));
  }

  /// The orchestrated onboarding flow (single, consolidated method)
  Future<void> startVoiceOnboarding() async {
    // Intro
    await speechService.flutterTts.setSpeechRate(0.5);
    await speechService.flutterTts.awaitSpeakCompletion(true);
    await speechService.flutterTts.speak(
        "Welcome to registration Please spell your details after the beep to fill each field. To stop voice input and use the keyboard, double-tap the name field. If you make a mistake, wait until the end to make changes.");
        // Please spell your details after the beep to fill each field. To stop voice input and use the keyboard, double-tap the name field. If you make a mistake, wait until the end to make changes.");
    await speechService.flutterTts.awaitSpeakCompletion(true);
    await Future.delayed(const Duration(seconds: 2));
    
    final fields = [
      {'label': 'name', 'controller': name},
      {'label': 'surname', 'controller': surname},
      //{'label': 'identity number', 'controller': id},
      {'label': 'email', 'controller': email},
      {'label': 'contact number', 'controller': contactnumber},
      {'label': 'password', 'controller': password},
    ];

    for (final field in fields) {
      if (stopFlow.value) {
        debugPrint(_debugHighlight('Flow stopped, breaking onboarding'));
        return;
      }

      final label = field['label'] as String;
      final controller = field['controller'] as TextEditingController;

      activeController.value = controller;
      speechService.setActiveController(controller);
      speechService.setWasMicPressed(false);

      debugPrint(_debugHighlight('Speaking label: $label'));

      // use single deterministic helper
      if (label == 'email') {
        await _stopThenSpeak(
            "Please spell your email. For example: v o i c e at gmail dot com");
      } else if (label == 'contact number') {
        await _stopThenSpeak("Please say your contact number");
      } else if (label == 'password') {
        await _stopThenSpeak(
            "We're in the password field. Create a password with six or more characters, at least two numbers, and one capital letter. To enter a capital, say 'capital' followed by the letter.");
      } else {
        await _stopThenSpeak("Please spell your $label");
      }

      // now start listening safely
      debugPrint(_debugHighlight('Listening for input on: $label'));
      await speechService.startListening(dictation: true);

      // Wait until the speech service stops listening (user finished)
      while (speechService.isListening.value) {
        await Future.delayed(const Duration(milliseconds: 200));
      }

      final spokenText = controller.text.trim();
      if (spokenText.isEmpty) {
        debugPrint(_debugHighlight('No input detected for $label'));
        await speechService.flutterTts
            .speak("I did not hear any input for $label");
        await speechService.flutterTts.awaitSpeakCompletion(true);
      } else {
        debugPrint(_debugHighlight('Captured input for $label: "$spokenText"'));
        // Acknowledge captured input. Do NOT spell passwords back.
        if (label == 'password') {
          await speechService.flutterTts.speak("Password captured");
          await speechService.flutterTts.awaitSpeakCompletion(true);
        } else {
        
          await speechService.flutterTts.awaitSpeakCompletion(true);

          // Ensure recognizer is fully stopped and give a short settle before TTS spells back
          try {
            if (speechService.isListening.value) {
              await speechService.stopListening();
            }
          } catch (_) {}
          await Future.delayed(const Duration(seconds: 3));

          // Now spell out the captured value (email will be read fully)
          // await speechService.spellOutText(spokenText);
          await speechService.flutterTts.awaitSpeakCompletion(true);
        }
      }

      // Buffer before moving to next field
      await Future.delayed(const Duration(seconds: 2));
    }

    // After all fields are filled, review and optionally edit
    await repeatAllFieldsAndAskEdit(fields);
  }

  Future<void> repeatAllFieldsAndAskEdit(
      List<Map<String, dynamic>> fields) async {
    final fieldMap = {
      'name': name,
      'surname': surname,
      //'identity number': id,
      'email': email,
      'contact number': contactnumber,
      'password': password,
    };

    for (final field in fields) {
      if (stopFlow.value) {
        debugPrint(_debugHighlight('Flow stopped, breaking onboarding'));
        return;
      }

      final label = field['label'] as String;
      final controller = field['controller'] as TextEditingController;

      activeController.value = controller;
      speechService.setActiveController(controller);
      speechService.setWasMicPressed(false);

      debugPrint(_debugHighlight('Repeating label: $label'));
      await speechService.flutterTts.speak("$label is");
      await speechService.flutterTts.awaitSpeakCompletion(true);

      final spokenText = controller.text.trim();
      if (spokenText.isEmpty) {
        await speechService.flutterTts.speak("No input captured for $label");
        await speechService.flutterTts.awaitSpeakCompletion(true);
      } else {
        if (label == 'password') {
          // Do not spell out passwords for security — acknowledge instead
          await speechService.flutterTts.speak("Password is set");
          await speechService.flutterTts.awaitSpeakCompletion(true);
        } else {
          await speechService.spellOutText(spokenText);
          await speechService.flutterTts.awaitSpeakCompletion(true);
        }
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    // Ask if user wants to edit
    await speechService.flutterTts.speak("Would you like to edit any field?");
    await speechService.flutterTts.awaitSpeakCompletion(true);
    

    final response =
        await speechService.listenForCommandWithTimeout(timeoutSeconds: 6);
    if (response != null && response.contains('yes')) {
      await speechService.flutterTts.speak(
          "Please say the field you want to edit, for example name or email.");
      await speechService.flutterTts.awaitSpeakCompletion(true);

      final fieldResponse =
          await speechService.listenForCommandWithTimeout(timeoutSeconds: 6);
      if (fieldResponse != null) {
        final key = fieldMap.keys.firstWhere(
            (k) => k.toLowerCase() == fieldResponse.toLowerCase(),
            orElse: () => '');

        if (key.isNotEmpty) {
          await speechService.flutterTts.speak("Editing $key now");
          await speechService.flutterTts.awaitSpeakCompletion(true);
          await speechService.activateFieldForEditing(key, fieldMap[key]!);

          // After editing, run review again
          await repeatAllFieldsAndAskEdit(fields);
          return;
        } else {
          debugPrint(_debugHighlight('Field not recognized: $fieldResponse'));
          await speechService.flutterTts
              .speak("I did not recognize that field. Registration complete.");
          await speechService.flutterTts.awaitSpeakCompletion(true);
        }
      } else {
        await speechService.flutterTts
            .speak("No field detected. Registration complete.");
        await speechService.flutterTts.awaitSpeakCompletion(true);
      }
    } else {
      // No edits requested — validate and submit
      final errors = _collectValidationErrors();
      if (errors.isNotEmpty) {
        await speechService.flutterTts
            .speak("There are problems with your form. I will read them out.");
        await speechService.flutterTts.awaitSpeakCompletion(true);
        for (final e in errors) {
          await speechService.flutterTts.speak(e);
          await speechService.flutterTts.awaitSpeakCompletion(true);
        }
        await speechService.flutterTts
            .speak("Please edit the fields mentioned and try again.");
        await speechService.flutterTts.awaitSpeakCompletion(true);
        return;
      }

      await submitRegistration();
    }
  }

  /// Collect validation errors without speaking (returns short messages)
  List<String> _collectValidationErrors() {
    final errors = <String>[];
    final n = name.text.trim();
    final s = surname.text.trim();
    //final rawId = id.text.trim();
    //  final idDigits = rawId.replaceAll(RegExp(r'[^0-9]'), '');
    final em = email.text.trim();
    final contact = contactnumber.text.replaceAll(RegExp(r'[^0-9]'), '');
    final pw = password.text;

    if (n.isEmpty) errors.add('First name is empty.');
    if (s.isEmpty) errors.add('Surname is empty.');
    // if (idDigits.isEmpty) {
    //   errors.add('ID number is empty.');
    // } else if (idDigits.length != 13) {
    //   errors.add('ID number must be exactly 13 digits.');
    // }
    final emailReg = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (em.isEmpty) {
      errors.add('Email is empty.');
    } else if (!emailReg.hasMatch(em)) {
      errors.add('Email looks invalid.');
    }
    if (contact.isEmpty) {
      errors.add('Contact number is empty.');
    } else if (contact.length < 7 || contact.length > 15) {
      errors.add('Contact number should be between 7 and 15 digits.');
    }
    if (pw.isEmpty) {
      errors.add('Password is empty.');
    } else if (pw.length < 6) {
      errors.add('Password must be at least 6 characters.');
    }
    return errors;
  }

  /// Submit registration to Firestore and navigate to HomePage on success.
  Future<void> submitRegistration() async {
    final authService = AuthService();
    User? createdUser;
    try {
      await speechService.flutterTts.speak('Submitting registration now.');
      await speechService.flutterTts.awaitSpeakCompletion(true);

      final rawEmail = email.text.trim();
      final rawPassword = password.text;
      if (rawEmail.isEmpty || rawPassword.isEmpty) {
        await speechService.flutterTts
            .speak('Email or password is empty. Submission cancelled.');
        return;
      }

      // 1) create Firebase Auth user (this signs in the newly created user)
      try {
        createdUser = await authService.register(rawEmail, rawPassword);
      } on FirebaseAuthException catch (fae) {
        debugPrint(_debugHighlight('Auth error: $fae'));
        await speechService.flutterTts.speak(
            'Failed to create account: ${fae.message ?? 'authentication error'}');
        return;
      } catch (e) {
        debugPrint(_debugHighlight('Auth unknown error: $e'));
        await speechService.flutterTts
            .speak('Failed to create account. Please try again.');
        return;
      }

      if (createdUser == null) {
        await speechService.flutterTts.speak('Failed to create user account.');
        return;
      }

      final uid = createdUser.uid;

      // 2) write Firestore user doc under uid (do NOT store password)
      final userData = {
        'uid': uid,
        'name': name.text.trim(),
        'surname': surname.text.trim(),
        /*'id': id.text.replaceAll(RegExp(r'[^0-9]'), ''),*/
        'email': rawEmail,
        'contactNumber': contactnumber.text.replaceAll(RegExp(r'[^0-9]'), ''),
        'createdAt': FieldValue.serverTimestamp(),
      };

      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(userData);
      } catch (e) {
        debugPrint(_debugHighlight('Firestore write error: $e'));
        // Roll back: delete the created auth user to avoid orphaned accounts
        try {
          final cur = FirebaseAuth.instance.currentUser;
          if (cur != null && cur.uid == uid) {
            await cur.delete();
          }
        } catch (delErr) {
          debugPrint(
              _debugHighlight('Failed to delete orphan auth user: $delErr'));
        }
        await speechService.flutterTts
            .speak('Failed to save user data. Account not created.');
        return;
      }

      // Success: speak, clear fields and navigate
      await speechService.flutterTts.speak(
          'Registration submitted successfully. Taking you to the homepage.');
      await speechService.flutterTts.awaitSpeakCompletion(true);

      name.clear();
      surname.clear();
      //id.clear();
      email.clear();
      contactnumber.clear();
      password.clear();

      Get.offAll(() => const HomePage());
    } catch (e) {
      debugPrint(_debugHighlight('submitRegistration error: $e'));
      await speechService.flutterTts
          .speak('Failed to submit registration. Please try again.');
      await speechService.flutterTts.awaitSpeakCompletion(true);
    }
  }

  Future<void> waitForSpeechCompletion() async {
    while (speechService.isListening.value) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<void> restartVoiceOnboarding() async {
    try {
      stopFlow.value = false;
      debugPrint(_debugHighlight('Restarting voice onboarding process...'));
      await startVoiceOnboarding();
    } catch (e) {
      debugPrint(_debugHighlight('Failed to restart onboarding: $e'));
      speechService.flutterTts.speak(
          'Failed to restart the registration process. Please try again.');
    }
  }

  /// Stop any active voice flows, TTS and listening immediately.
  Future<void> stopAllFlows() async {
    stopFlow.value = true;
    try {
      // stop any ongoing recognition
      await speechService.stopListening();
    } catch (_) {}
    try {
      // stop any speaking
      await speechService.flutterTts.stop();
    } catch (_) {}
    // clear active controller to prevent further writes
    activeController.value = null;
    debugPrint(_debugHighlight('All voice flows stopped by stopAllFlows()'));
  }

  // speak and ensure TTS finished plus a small buffer so the recognizer won't start early
}
