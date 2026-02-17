import 'package:avatar_glow/avatar_glow.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:voicecare/mic_widget/service_speech.dart';

class MicButton extends StatefulWidget {
  final void Function()? onPressed; // <-- Add this line

  const MicButton({super.key, this.onPressed});

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> {
  final SpeechService _speechService = Get.find<SpeechService>();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(() => Text(
                  _speechService.speechText.value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                )),
            const SizedBox(height: 10),
            Obx(() {
              final isMicPressed = _speechService.wasMicPressed.value;
              final isListening = _speechService.isListening.value;

              return AvatarGlow(
                glowColor: const Color.fromARGB(255, 40, 56, 98),
                animate: isMicPressed && isListening,
                duration: const Duration(milliseconds: 2000),
                repeat: true,
                child: GestureDetector(
                  onTap: widget.onPressed ??
                      () async {
                        _speechService.setWasMicPressed(true);
                        try {
                          // Stop any current listening first
                          if (_speechService.isListening.value) {
                            await _speechService.stopListening();
                          }

                          // Play beep and then listen for commands
                          await _speechService.playBeepAndListenForCommands();
                        } catch (e, st) {
                          debugPrint('MicButton onTap error: $e\n$st');
                          // reset UI state
                          _speechService.setWasMicPressed(false);
                        }
                      },
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.fromARGB(255, 40, 56, 98),
                    ),
                    child: const Icon(Icons.mic, size: 50, color: Colors.white),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
