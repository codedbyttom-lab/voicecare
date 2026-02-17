// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:voicecare/controllers/appointment_controller.dart';
import 'package:voicecare/homepage/home_page.dart';
import 'package:voicecare/mic_widget/service_speech.dart';
import 'package:voicecare/mic_widget/speech_guard.dart';
import '../widgets/voice_form_field.dart';
import '../appointment/app_widget/appointment_mic.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

class AppointmentPage extends StatefulWidget {
  const AppointmentPage({super.key});

  @override
  State<AppointmentPage> createState() => _AppointmentPageState();
}

class _AppointmentPageState extends State<AppointmentPage> {
  final AppointmentController appointmentController =
      Get.put(AppointmentController());

  Timer? _singleTapTimer;
  bool _doubleTapped = false;
  // ignore: unused_field
  bool _suppressListening = false;

  late DateTime _firstAvailableDate;
  late DateTime _lastAvailableDate;

  @override
  void initState() {
    super.initState();
    DateTime today = DateTime.now();
    _firstAvailableDate = today;
    _lastAvailableDate = today.add(const Duration(days: 7));
    appointmentController.selectedDate.value = _firstAvailableDate;

    Future.delayed(Duration.zero, () async {
      // Ensure any global suppression is cleared and audio pipeline can settle
      try {
        await SpeechGuard
            .clearSuppression(); // make sure this helper exists (see SpeechGuard)
      } catch (_) {}
      // small breathing room so native audio/TTS layers can settle
      await Future.delayed(const Duration(milliseconds: 180));

      // (Optional) Ensure SpeechService/STT is available if you have a service
      try {
        if (Get.isRegistered<SpeechService>()) {
          final svc = Get.find<SpeechService>();
          // Try to call ensureInitialized() if the service implements it.
          // Use dynamic and catch to avoid compile-time error when method is absent.
          try {
            await (svc as dynamic).ensureInitialized();
          } catch (_) {
            // service doesn't provide ensureInitialized; ignore.
          }
        }
      } catch (_) {}

      appointmentController.startVoiceBookingFlow();
    });
  }

  // Stop/cancel any ongoing flow (voice/TTS/STT) when leaving the page.
  // Future<void> _stopFlow() async {
  //   // Defensive: reset UI state
  //   try {
  //     appointmentController.selectedTime.value = null;
  //   } catch (_) {}

  //   // Safely call any controller methods that stop/cancel voice flows and TTS/STT.
  //   final ctrl = appointmentController as dynamic;
  //   try {
  //     await ctrl.cancelVoiceBookingFlow();
  //   } catch (_) {}
  //   try {
  //     await ctrl.stopVoiceBookingFlow();
  //   } catch (_) {}
  //   try {
  //     await ctrl.stopTts?.call();
  //   } catch (_) {}
  //   try {
  //     await ctrl.stopStt?.call();
  //   } catch (_) {}
  //   try {
  //     await ctrl.stopListening?.call();
  //   } catch (_) {}

  //   // small pause to let operations settle (optional)
  //   await Future.delayed(const Duration(milliseconds: 20));
  // }

  @override
  void dispose() {
    // cancel any pending tap timers/guards
    _singleTapTimer?.cancel();

    // Ensure the controller stops immediately (synchronous stop) so STT/TTS cut off.
    try {
      if (Get.isRegistered<AppointmentController>()) {
        final ctrl = Get.find<AppointmentController>();
        ctrl.stopVoiceBookingFlow();
        // best-effort async cleanup
        unawaited(ctrl.stopAllFlowsSilently());
      }
    } catch (_) {}

    super.dispose();
  }

  List<DateTime> get _availableDates {
    return List.generate(
        _lastAvailableDate.difference(_firstAvailableDate).inDays + 1,
        (i) => _firstAvailableDate.add(Duration(days: i)));
  }

  String _formatSelectedDate(DateTime date) {
    return DateFormat('EEEE, d MMM').format(date);
  }

  Widget _buildSlotSection(String title, List<Map<String, dynamic>> slots) {
    if (slots.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: slots.map((slotEntry) {
              final slotTime = slotEntry['time'] as String;
              final available = (slotEntry['available'] ?? true) as bool;
              final isSelected =
                  appointmentController.selectedTime.value == slotTime;

              Color bg;
              if (!available) {
                bg = Colors.grey.shade400;
              } else if (isSelected) {
                bg = const Color.fromARGB(255, 40, 56, 98);
              } else {
                bg = const Color.fromARGB(255, 60, 76, 118);
              }

              return GestureDetector(
                onTap: () {
                  if (!available) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('This time is no longer available')));
                    return;
                  }
                  appointmentController.selectedTime.value = slotTime;
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(slotTime,
                      style: const TextStyle(color: Colors.white)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Appointment Page",
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
          ),
          onPressed: () => Get.offAll(() => const HomePage()),
        ),
        backgroundColor: const Color.fromARGB(255, 40, 56, 98),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
                'lib/assets/registration_assets/user_reg_wallpaper.png'),
            alignment: Alignment.center,
            scale: 1.9,
            opacity: 0.9,
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text("Select a Date",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            Container(
              height: mediaQuery.size.height * 0.14,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color.fromARGB(135, 214, 211, 211),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Obx(() {
                final selectedDate = appointmentController.selectedDate.value;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _availableDates.map((date) {
                    bool isSelected = date.year == selectedDate.year &&
                        date.month == selectedDate.month &&
                        date.day == selectedDate.day;

                    return GestureDetector(
                      onTap: () {
                        // delay single-tap so a double-tap can override/cancel
                        _singleTapTimer?.cancel();
                        _singleTapTimer =
                            Timer(const Duration(milliseconds: 250), () {
                          if (!mounted) return;
                          if (_doubleTapped) {
                            _doubleTapped = false;
                            return;
                          }
                          appointmentController.selectedDate.value = date;
                          appointmentController.selectedTime.value = null;
                        });
                      },
                      onDoubleTap: () async {
                        // cancel any pending single-tap and stop the flow completely
                        _singleTapTimer?.cancel();
                        _doubleTapped = true;
                        _suppressListening = true;

                        // ensure UI state cleared
                        try {
                          appointmentController.selectedTime.value = null;
                        } catch (_) {}

                        // stop everything and announce cancellation
                        try {
                          await appointmentController
                              .cancelVoiceBookingFlowWithAnnouncement();
                        } catch (_) {}

                        // give short suppression window so mic/button handlers don't immediately restart listening
                        HapticFeedback.mediumImpact();
                        Timer(const Duration(milliseconds: 700), () {
                          _doubleTapped = false;
                          _suppressListening = false;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color.fromARGB(255, 40, 56, 98)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("${date.day}",
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black)),
                            Text(
                              DateFormat('E').format(date),
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      isSelected ? Colors.white : Colors.black),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              }),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(135, 214, 211, 211),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 130),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Obx(() {
                              final selectedDate =
                                  appointmentController.selectedDate.value;
                              return Text(
                                "Available Slots: ${_formatSelectedDate(selectedDate)}",
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              );
                            }),
                          ),
                          const SizedBox(height: 10),
                          // SLOT SECTIONS
                          Obx(() => _buildSlotSection(
                              "Morning",
                              appointmentController.slotsByPeriod["Morning"]!
                                  .toList())),
                          Obx(() => _buildSlotSection(
                              "Afternoon",
                              appointmentController.slotsByPeriod["Afternoon"]!
                                  .toList())),
                          Obx(() => _buildSlotSection(
                              "Evening",
                              appointmentController.slotsByPeriod["Evening"]!
                                  .toList())),
                          const SizedBox(height: 16),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: VoiceFormField(
                              controller:
                                  appointmentController.reasonController.value,
                              validator: (value) =>
                                  value == null || value.isEmpty
                                      ? 'Please describe your reason'
                                      : null,
                              labelText: "Reason for Appointment",
                              prefixIcon: null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppointmentMicButton(
                            onPressed: () async {
                              // Respect the short suppression window after a double-tap cancel
                              if (_suppressListening) {
                                debugPrint(
                                    '[AppointmentPage] mic press suppressed (double-tap window)');
                                return;
                              }
                              // 1) clear suppression + short settle
                              try {
                                await SpeechGuard.clearSuppression();
                              } catch (_) {}
                              await Future.delayed(
                                  const Duration(milliseconds: 160));

                              // 2) ensure microphone permission
                              final micPerm =
                                  await Permission.microphone.status;
                              if (!micPerm.isGranted) {
                                final req =
                                    await Permission.microphone.request();
                                if (!req.isGranted) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Microphone permission is required. Please enable it in settings.'),
                                      ),
                                    );
                                  }
                                  return;
                                }
                              }

                              // 3) warm up native STT engine (probe) so controller's listen doesn't immediately return null
                              final probe = SpeechToText();
                              bool probeOk = false;
                              try {
                                probeOk = await probe.initialize(
                                  onStatus: (s) =>
                                      debugPrint('[STT probe] status: $s'),
                                  onError: (e) => debugPrint(
                                      '[STT probe] error: ${e?.errorMsg ?? e}'),
                                );
                              } catch (e) {
                                debugPrint('[STT probe] initialize threw: $e');
                                probeOk = false;
                              }
                              debugPrint(
                                  '[STT probe] initialized=$probeOk hasPermission=${probe.hasPermission}');
                              if (!probeOk) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Speech recognition unavailable.')),
                                  );
                                }
                                try {
                                  await probe.cancel();
                                  await probe.stop();
                                } catch (_) {}
                                return;
                              }
                              // small breathing room after probe init
                              await Future.delayed(
                                  const Duration(milliseconds: 120));
                              try {
                                await probe.cancel();
                              } catch (_) {}
                              try {
                                await probe.stop();
                              } catch (_) {}

                              // 4) optional SpeechService prep if present
                              try {
                                if (Get.isRegistered<SpeechService>()) {
                                  final svc = Get.find<SpeechService>();
                                  try {
                                    await (svc as dynamic).ensureInitialized();
                                  } catch (_) {}
                                  try {
                                    await (svc as dynamic).stopTts();
                                  } catch (_) {}
                                }
                              } catch (e) {
                                debugPrint(
                                    '[AppointmentPage] SpeechService prep error: $e');
                              }

                              // 5) now ask controller to listen (force start for explicit mic press)
                              // ensure any previous "cancelled" guard is cleared and allow forced start
                              appointmentController.voiceFlowCancelled.value =
                                  false;
                              String? command;
                              try {
                                command =
                                    await appointmentController.listenForSpeech(
                                        timeoutSeconds: 6, forceStart: true);
                              } catch (e) {
                                debugPrint(
                                    '[AppointmentPage] listenForSpeech threw: $e');
                                command = null;
                              }

                              if (command == null || command.trim().isEmpty) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Did not hear anything. Try again.')),
                                  );
                                }
                                return;
                              }

                              try {
                                await appointmentController
                                    .handleCommand(command);
                              } catch (e) {
                                debugPrint(
                                    '[AppointmentPage] handleCommand error: $e');
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          //   ElevatedButton(
                          //     style: ElevatedButton.styleFrom(
                          //       backgroundColor:
                          //           const Color.fromARGB(255, 40, 56, 98),
                          //       padding: const EdgeInsets.symmetric(
                          //           horizontal: 20, vertical: 12),
                          //       shape: RoundedRectangleBorder(
                          //         borderRadius: BorderRadius.circular(8),
                          //       ),
                          //     ),
                          //     onPressed: () async {
                          //       final ok = await appointmentController
                          //           .submitAppointment();
                          //       if (ok) {
                          //         if (mounted) {
                          //           ScaffoldMessenger.of(context).showSnackBar(
                          //             const SnackBar(
                          //                 content: Text('Appointment submitted')),
                          //           );
                          //           Navigator.of(context).pop();
                          //         }
                          //       } else {
                          //         if (mounted) {
                          //           ScaffoldMessenger.of(context).showSnackBar(
                          //             const SnackBar(
                          //                 content: Text(
                          //                     'Failed to submit appointment')),
                          //           );
                          //         }
                          //       }
                          //     },
                          //     child: const Text(
                          //       'Submit',
                          //       style: TextStyle(color: Colors.white),
                          //     ),
                          //   ),
                          //
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
