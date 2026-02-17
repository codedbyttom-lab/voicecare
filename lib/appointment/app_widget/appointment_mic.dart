import 'package:avatar_glow/avatar_glow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:voicecare/appointment/app_widget/appointment_service_speech.dart';
import 'package:voicecare/controllers/appointment_controller.dart';

class AppointmentMicButton extends StatelessWidget {
  final Future<void> Function()? onPressed;

  const AppointmentMicButton({super.key, this.onPressed});

  static const MethodChannel _audioChannel = MethodChannel('voicecare/audio');

  Future<void> _playBeep() async {
    try {
      await _audioChannel.invokeMethod('playBeep');
    } catch (_) {
      // ignore failures — continue to listening flow
    }
    await Future.delayed(const Duration(milliseconds: 160));
  }

  @override
  Widget build(BuildContext context) {
    final appointmentSpeech = Get.isRegistered<AppointmentSpeechService>()
        ? Get.find<AppointmentSpeechService>()
        : Get.put(AppointmentSpeechService());
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
                  animate: isMicPressed && isListening,
                  duration: const Duration(milliseconds: 2000),
                  repeat: true,
                  child: GestureDetector(
                    onTap: () async {
                      // indicate mic pressed so AvatarGlow can animate once listening starts
                      try {
                        appointmentSpeech.wasMicPressed.value = true;

                        // play beep, then execute provided handler or fallback listener
                        await _playBeep();

                        if (onPressed != null) {
                          await onPressed!();
                        } else {
                          await appointmentSpeech.listenForCommand();
                        }
                      } finally {
                        // ensure UI state is reset when flow completes/errors
                        appointmentSpeech.wasMicPressed.value = false;
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
}
