import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:voicecare/controllers/sign_up_controller.dart';
import 'package:voicecare/homepage/home_page.dart';
import 'package:voicecare/homepage/login_page.dart';
import 'package:voicecare/mic_widget/mic_button.dart';
import 'package:voicecare/mic_widget/service_speech.dart';
import 'package:voicecare/widgets/voice_form_field.dart';
import 'package:voicecare/admin/admin_homepage.dart';

class UserReg extends StatefulWidget {
  const UserReg({super.key});

  @override
  State<UserReg> createState() => _UserRegState();
}

class _UserRegState extends State<UserReg> {
  final controller = Get.put(SignUpController());
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final speechService = Get.find<SpeechService>();

  // Ensure cleanup when leaving the page
  Future<void> _stopAndClear() async {
    try {
      // Tell controller to stop onboarding + underlying services
      await controller.stopAllFlows();
    } catch (_) {}

    try {
      // also ensure SpeechService is stopped and no active controller remains
      await speechService.stopListening();
      await speechService.flutterTts.stop();
      speechService.setActiveController(null);
      speechService.setWasMicPressed(false);
    } catch (_) {}

    // Clear controllers managed by SignUpController
    try {
      controller.name.clear();
      controller.surname.clear();
      //  controller.id.clear();
      controller.email.clear();
      controller.contactnumber.clear();
      controller.password.clear();
    } catch (_) {}
  }

  final FocusNode nameFocusNode = FocusNode();
  final FocusNode surnameFocusNode = FocusNode();
  final FocusNode idFocusNode = FocusNode();
  final FocusNode emailFocusNode = FocusNode();
  final FocusNode contactFocusNode = FocusNode();
  final FocusNode passwordFocusNode = FocusNode();

  // Track readOnly status per field (start true)
  bool nameReadOnly = true;
  bool surnameReadOnly = true;
  bool idReadOnly = true;
  bool emailReadOnly = true;
  bool contactReadOnly = true;
  bool passwordReadOnly = true;

  @override
  void dispose() {
    // ensure the voice flow stops and fields are cleared when widget is disposed
    _stopAndClear();
    nameFocusNode.dispose();
    surnameFocusNode.dispose();
    idFocusNode.dispose();
    emailFocusNode.dispose();
    contactFocusNode.dispose();
    passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.startVoiceOnboarding();
    });
  }

  /// ✅ Helper to stop voice globally
  void stopVoiceEverywhere() {
    speechService.stopListening();
    controller.activeController.value = null;
    speechService.setActiveController(null);
    speechService.setWasMicPressed(false);
    speechService.flutterTts.speak("Voice input stopped. You can type now.");
  }

  Widget buildVoiceFormField({
    required TextEditingController controllerField,
    required String labelText,
    required Widget prefixIcon,
    required String? Function(String?) validator,
    required FocusNode focusNode,
    required bool readOnly,
    required VoidCallback onDoubleTap,
  }) {
    return GestureDetector(
      // ❌ Removed single tap
      onDoubleTap: onDoubleTap,
      child: VoiceFormField(
        controller: controllerField,
        labelText: labelText,
        prefixIcon: prefixIcon,
        validator: validator,
        focusNode: focusNode,
        readOnly: readOnly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final position = MediaQuery.of(context);

    return WillPopScope(
      onWillPop: () async {
        await _stopAndClear();
        return true; // allow pop
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: const Text("User Registration",
              style: TextStyle(color: Colors.white)),
          centerTitle: true,
          backgroundColor: const Color.fromARGB(255, 40, 56, 98),
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Colors.white,
            ),
            onPressed: () => Get.offAll(() => LoginPage()),
          ),
        ),
        body: Container(
          padding: EdgeInsets.only(top: position.padding.top * 0.4),
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage(
                  'lib/assets/registration_assets/user_reg_wallpaper.png'),
              alignment: Alignment.center,
              scale: 1.9,
              opacity: 0.9,
            ),
          ),
          child: Center(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.translucent,
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: position.size.width * 0.02),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          const SizedBox(height: 30),
                          Row(
                            children: [
                              Expanded(
                                child: buildVoiceFormField(
                                  controllerField: controller.name,
                                  labelText: 'Name',
                                  prefixIcon: const Icon(Icons.person),
                                  validator: controller.validateName,
                                  focusNode: nameFocusNode,
                                  readOnly: nameReadOnly,
                                  onDoubleTap: () {
                                    setState(() {
                                      nameReadOnly = false;
                                    });
                                    stopVoiceEverywhere();
                                    FocusScope.of(context)
                                        .requestFocus(nameFocusNode);
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: buildVoiceFormField(
                                  controllerField: controller.surname,
                                  labelText: 'Surname',
                                  prefixIcon: const Icon(Icons.person_outline),
                                  validator: controller.validateSurname,
                                  focusNode: surnameFocusNode,
                                  readOnly: surnameReadOnly,
                                  onDoubleTap: () {
                                    setState(() {
                                      surnameReadOnly = false;
                                    });
                                    stopVoiceEverywhere();
                                    FocusScope.of(context)
                                        .requestFocus(surnameFocusNode);
                                  },
                                ),
                              ),
                            ],
                          ),
                          // SizedBox(height: position.size.height * 0.02),
                          // buildVoiceFormField(
                          //   controllerField: controller.id,
                          //   labelText: 'ID',
                          //   prefixIcon: const Icon(Icons.badge),
                          //   validator: controller.validateId,
                          //   focusNode: idFocusNode,
                          //   readOnly: idReadOnly,
                          //   onDoubleTap: () {
                          //     setState(() {
                          //       idReadOnly = false;
                          //     });
                          //     stopVoiceEverywhere();
                          //     FocusScope.of(context).requestFocus(idFocusNode);
                          //   },
                          // ),
                          SizedBox(height: position.size.height * 0.02),
                          buildVoiceFormField(
                            controllerField: controller.email,
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.email),
                            validator: controller.validateEmail,
                            focusNode: emailFocusNode,
                            readOnly: emailReadOnly,
                            onDoubleTap: () {
                              setState(() {
                                emailReadOnly = false;
                              });
                              stopVoiceEverywhere();
                              FocusScope.of(context)
                                  .requestFocus(emailFocusNode);
                            },
                          ),
                          SizedBox(height: position.size.height * 0.03),
                          buildVoiceFormField(
                            controllerField: controller.contactnumber,
                            labelText: 'Contact Number',
                            prefixIcon: const Icon(Icons.phone_android),
                            validator: controller.validateContactNumber,
                            focusNode: contactFocusNode,
                            readOnly: contactReadOnly,
                            onDoubleTap: () {
                              setState(() {
                                contactReadOnly = false;
                              });
                              stopVoiceEverywhere();
                              FocusScope.of(context)
                                  .requestFocus(contactFocusNode);
                            },
                          ),
                          SizedBox(height: position.size.height * 0.03),
                          buildVoiceFormField(
                            controllerField: controller.password,
                            labelText: 'Password Field',
                            prefixIcon: const Icon(Icons.password),
                            validator: controller.validatePassword,
                            focusNode: passwordFocusNode,
                            readOnly: passwordReadOnly,
                            onDoubleTap: () {
                              setState(() {
                                passwordReadOnly = false; // ✅ fixed bug
                              });
                              stopVoiceEverywhere();
                              FocusScope.of(context)
                                  .requestFocus(passwordFocusNode);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 40, 56, 98),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _submitRegistrationNoSpeak(),
                      child: const Text(
                        'Submit',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: position.padding.bottom + 10,
                    left: 0,
                    right: 0,
                    child: const Center(child: MicButton()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Non-speaking copy of the sign-up submission (called from the Submit button)
  Future<void> _submitRegistrationNoSpeak() async {
    final formState = _formKey.currentState as FormState;
    if (!formState.validate()) return;

    final rawEmail = controller.email.text.trim();
    final rawPassword = controller.password.text;
    debugPrint(
        'Registration: submit pressed email="$rawEmail" name="${controller.name.text}"');

    try {
      // Create account directly with FirebaseAuth so behavior is predictable
      UserCredential uc;
      try {
        uc = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: rawEmail, password: rawPassword);
        debugPrint(
            'Registration: createUserWithEmailAndPassword succeeded: ${uc.user?.uid}');
      } on FirebaseAuthException catch (fae) {
        debugPrint(
            'Registration: FirebaseAuthException: ${fae.code} ${fae.message}');
        Get.snackbar('Registration failed', fae.message ?? fae.code);
        return;
      }

      final uid = uc.user?.uid;
      if (uid == null) {
        debugPrint('Registration: no uid after createUserWithEmailAndPassword');
        Get.snackbar('Registration failed', 'Could not determine user id');
        return;
      }

      // Confirm the user is signed in (createUser signs in by default)
      debugPrint(
          'Registration: currentUid = ${FirebaseAuth.instance.currentUser?.uid}');

      final userData = {
        'uid': uid,
        'name': controller.name.text.trim(),
        'surname': controller.surname.text.trim(),
        'email': rawEmail,
        'contactNumber': controller.contactnumber.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      };
      debugPrint('Registration: writing user doc uid=$uid data=$userData');

      // Try writing the user doc and let exceptions surface to logs/snackbar
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(userData);
        debugPrint('Registration: Firestore write succeeded for uid=$uid');
        Get.snackbar(
          'Registration',
          'Account created successfully',
          backgroundColor: const Color(0xFF7ED957), // cute greenish
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      } on FirebaseException catch (fe) {
        debugPrint(
            'Registration: Firestore exception: ${fe.code} ${fe.message}');
        // optional cleanup of created auth user to avoid orphaned account
        try {
          final cur = FirebaseAuth.instance.currentUser;
          if (cur != null && cur.uid == uid) await cur.delete();
        } catch (cleanupErr) {
          debugPrint('Registration: cleanup delete failed: $cleanupErr');
        }
        Get.snackbar('Registration failed', fe.message ?? fe.code);
        return;
      }

      // cleanup and navigate home
      try {
        await _stopAndClear();
      } catch (e) {
        debugPrint('Registration: _stopAndClear error: $e');
      }
      try {
        if (Get.isRegistered<SignUpController>())
          Get.delete<SignUpController>(force: true);
      } catch (e) {
        debugPrint('Registration: controller delete failed: $e');
      }
      // route admin users to AdminHomePage if their email contains "@admin"
      if ((rawEmail.toLowerCase()).contains('@admin')) {
        Get.offAll(() => const AdminHomePage());
      } else {
        Get.offAll(() => const HomePage());
      }
    } catch (e, st) {
      debugPrint('Registration: unexpected error: $e\n$st');
      Get.snackbar('Registration failed', e.toString());
    }
  }
}
