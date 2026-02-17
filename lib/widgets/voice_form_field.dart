import 'package:avatar_glow/avatar_glow.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:voicecare/controllers/sign_up_controller.dart';

class VoiceFormField extends StatefulWidget {
  const VoiceFormField(
      {super.key,
      required this.controller,
      required this.validator,
      required this.labelText,
      required this.prefixIcon,
      this.readOnly = false,
      this.focusNode,
      this.obscureText = false});

  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final String labelText;
  final Widget? prefixIcon;
  final bool readOnly;
  final FocusNode? focusNode;
  final bool obscureText;

  @override
  State<VoiceFormField> createState() => _VoiceFormFieldState();
}

class _VoiceFormFieldState extends State<VoiceFormField> {
  late FocusNode _focusNode;
  SignUpController? _signUpController;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();

    // only obtain the SignUpController if it is registered
    if (Get.isRegistered<SignUpController>()) {
      _signUpController = Get.find<SignUpController>();
    }

    _focusNode.addListener(() {
      debugPrint(
          '[VoiceFormField] Focus change on ${widget.labelText} hasFocus=${_focusNode.hasFocus}');
      if (_focusNode.hasFocus) {
        // ✅ Only run voice logic if flow is NOT stopped and controller exists
        if (_signUpController != null && !_signUpController!.stopFlow.value) {
          _signUpController!.speechService.setWasMicPressed(false);
          _signUpController!.speechService
              .setActiveController(widget.controller!);
          _signUpController!.activeController.value = widget.controller;
        }
      } else {
        if (_signUpController != null) {
          debugPrint('[VoiceFormField] Focus lost on ${widget.labelText}');
          if (_signUpController!.activeController.value == widget.controller) {
            _signUpController!.activeController.value = null;
            debugPrint(
                '[VoiceFormField] Active controller cleared for ${widget.labelText}');
          }
        }
      }
    });
  }

  void _handleDoubleTap() {
    if (widget.labelText.toLowerCase() == "name" && _signUpController != null) {
      // 👇 Stop the entire flow + unlock typing
      _signUpController!.stopFlow.value = true;
      _signUpController!.speechService.stopListening();
      _signUpController!.speechService.flutterTts.speak("Voice input stopped.");
      FocusScope.of(context).requestFocus(_focusNode);
      debugPrint("🟡 Flow completely stopped by double tapping Name field");
    } else {
      // Normal double tap: just show keyboard
      FocusScope.of(context).requestFocus(_focusNode);
      debugPrint("🟡 Keyboard enabled for ${widget.labelText}");
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 👇 Only double tap is active
      onDoubleTap: _handleDoubleTap,
      child: Obx(() {
        final isActive = _signUpController != null &&
            _signUpController!.activeController.value == widget.controller;
        final isListening = _signUpController != null &&
            _signUpController!.speechService.isListening.value;
        final wasMicPressed = _signUpController != null &&
            _signUpController!.speechService.wasMicPressed.value;

        final shouldGlow = isActive && isListening && !wasMicPressed;
        final allowTyping = _signUpController != null
            ? _signUpController!.stopFlow.value
            : true;

        debugPrint(
            '[VoiceFormField] Build: label=${widget.labelText} isActive=$isActive isListening=$isListening wasMicPressed=$wasMicPressed shouldGlow=$shouldGlow allowTyping=$allowTyping');

        return AbsorbPointer(
          // ✅ When flow is stopped, disallow typing; if no controller, allow typing
          absorbing: _signUpController != null
              ? !_signUpController!.stopFlow.value
              : false,
          child: TextFormField(
            focusNode: _focusNode,
            controller: widget.controller,
            validator: widget.validator,
            obscureText: widget.obscureText,
            readOnly: widget.readOnly && !allowTyping,
            decoration: InputDecoration(
              labelText: widget.labelText,
              labelStyle: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w400,
                color: Colors.black87,
              ),
              prefixIcon: shouldGlow
                  ? AvatarGlow(
                      animate: true,
                      glowColor: const Color.fromARGB(255, 40, 56, 98),
                      glowRadiusFactor: 2,
                      duration: const Duration(milliseconds: 2000),
                      child: widget.prefixIcon ?? const Icon(Icons.mic),
                    )
                  : widget.prefixIcon,
              prefixIconColor: const Color.fromARGB(255, 40, 56, 98),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(30)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(
                  color: Color.fromARGB(255, 40, 56, 98),
                  width: 3.0,
                ),
                borderRadius: BorderRadius.all(Radius.circular(30)),
              ),
            ),
          ),
        );
      }),
    );
  }
}

