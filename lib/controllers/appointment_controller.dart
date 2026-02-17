// appointment_controller.dart
// ignore_for_file: unused_local_variable

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:intl/intl.dart';
import 'package:voicecare/homepage/home_page.dart';
import 'package:voicecare/appointment/appointment_page.dart';
import 'package:voicecare/homepage/login_page.dart';

import 'package:flutter/services.dart';

class AppointmentController extends GetxController {
  final FlutterTts flutterTts = FlutterTts();
  final SpeechToText _speech = SpeechToText();
  // native audio channel used to play the beep sound
  static const MethodChannel _audioChannel = MethodChannel('voicecare/audio');

  final RxString speechText = ''.obs;
  final RxBool isListening = false.obs;
  // Prevent concurrent calls to _speech.initialize()
  final RxBool _isInitializing = false.obs;

  final RxBool isVoiceFlowActive = false.obs;
  final RxBool isVoiceFlowRunning = false.obs;

  // When true a cancellation announcement is in progress; _handleIfCancelled should not stop TTS while this is true.
  final RxBool voiceFlowCancellingWithAnnounce = false.obs;

  Rx<DateTime> selectedDate = DateTime.now().obs;
  Rx<String?> selectedTime = Rxn<String>();
  Rx<TextEditingController> reasonController = TextEditingController().obs;

  // slotsByPeriod stores list of slot entries: { 'time': 'HH:mm', 'available': bool, 'docId': '<id>' }
  final RxMap<String, List<Map<String, dynamic>>> slotsByPeriod =
      <String, List<Map<String, dynamic>>>{
    "Morning": <Map<String, dynamic>>[],
    "Afternoon": <Map<String, dynamic>>[],
    "Evening": <Map<String, dynamic>>[],
  }.obs;

  // quick lookup for time -> docId for currently loaded date
  final Map<String, String> _timeToDocId = {};

  @override
  void onInit() {
    super.onInit();
    flutterTts.awaitSpeakCompletion(true);
    ever<DateTime>(selectedDate, (_) => _listenSlotsForSelectedDate());
    _listenSlotsForSelectedDate();
  }

  @override
  void onClose() {
    // Ensure any active voice booking flow and audio are stopped when the page/controller is disposed
    cancelVoiceBookingFlow();
    try {
      flutterTts.stop();
    } catch (_) {}
    try {
      _speech.stop();
    } catch (_) {}
    _cancelAllSlotListeners();
    _timeslotSub?.cancel();
    super.onClose();
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _timeslotSub;

  void _cancelAllSlotListeners() {
    _timeslotSub?.cancel();
    _timeslotSub = null;
  }

  void _listenSlotsForSelectedDate() {
    _cancelAllSlotListeners();

    final dateKey = DateFormat('yyyy-MM-dd').format(selectedDate.value);
    debugPrint(_debugHighlight('Listening for timeslots for date: $dateKey'));

    final collection = FirebaseFirestore.instance.collection('timeslots');

    slotsByPeriod.value = {
      "Morning": <Map<String, dynamic>>[],
      "Afternoon": <Map<String, dynamic>>[],
      "Evening": <Map<String, dynamic>>[],
    };
    _timeToDocId.clear();

    // listen to all timeslots for the date and render availability
    _timeslotSub = collection
        .where('date', isEqualTo: dateKey)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (snapshot.metadata.isFromCache) return;

      final Map<String, List<Map<String, dynamic>>> periodMap = {
        "Morning": [],
        "Afternoon": [],
        "Evening": [],
      };
      _timeToDocId.clear();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final rawTime = data['startTime'] ?? data['time'];
        if (rawTime == null) continue;

        final normalized = _normalizeRawTimeTo24(rawTime);
        if (normalized == null) continue;

        final available = (data['available'] ?? true) == true;
        String periodRaw = (data['period'] ?? '').toString().toLowerCase();
        String periodKey = _determinePeriod(periodRaw, normalized);

        periodMap[periodKey]!.add({
          'time': normalized,
          'available': available,
          'docId': doc.id,
        });

        _timeToDocId[normalized] = doc.id;
      }

      // sort lists by time
      periodMap.forEach((key, list) => list.sort(
          (a, b) => (a['time'] as String).compareTo(b['time'] as String)));

      slotsByPeriod.value = periodMap;
      debugPrint(_debugHighlight('Slots updated for $dateKey: $periodMap'));
    }, onError: (err) {
      debugPrint(_debugHighlight('Error listening to timeslots: $err'));
      slotsByPeriod.value = {
        "Morning": <Map<String, dynamic>>[],
        "Afternoon": <Map<String, dynamic>>[],
        "Evening": <Map<String, dynamic>>[],
      };
    });
  }

  String _determinePeriod(String periodRaw, String normalizedTime) {
    if (periodRaw.contains('afternoon')) return "Afternoon";
    if (periodRaw.contains('evening')) return "Evening";
    if (periodRaw.contains('morning')) return "Morning";

    int hour = int.tryParse(normalizedTime.split(':')[0]) ?? 0;
    if (hour >= 17) return "Evening";
    if (hour >= 12) return "Afternoon";
    return "Morning";
  }

  String? _normalizeRawTimeTo24(String raw) {
    raw = raw.trim();
    try {
      final parsed = DateFormat.jm().parseLoose(raw);
      return DateFormat('HH:mm').format(parsed);
    } catch (_) {
      try {
        final parsed2 = DateFormat('H:mm').parseLoose(raw);
        return DateFormat('HH:mm').format(parsed2);
      } catch (_) {
        final reg = RegExp(r'^\d{1,2}:\d{2}$');
        if (reg.hasMatch(raw)) return raw;
      }
    }
    return null;
  }

  Future<String?> listenForSpeech(
      {int timeoutSeconds = 6,
      bool forceStart = false,
      bool playBeep = true}) async {
    // If already listening, avoid starting another session
    if (_speech.isListening) {
      debugPrint(_debugHighlight(
          'listenForSpeech: already listening, returning null'));
      return null;
    }

    // If the voice flow has been cancelled (e.g. page exited) don't start new listening,
    // unless explicitly forced by a direct mic press from the UI.
    if (voiceFlowCancelled.value) {
      if (!forceStart) {
        debugPrint(_debugHighlight('listenForSpeech: cancelled before start'));
        return null;
      } else {
        debugPrint(_debugHighlight(
            'listenForSpeech: forced start requested, clearing cancelled flag'));
        // clear cancellation so this explicit user action can start a fresh listen
        voiceFlowCancelled.value = false;
        voiceFlowCancellingWithAnnounce.value = false;
      }
    }

    // If another initialize is in progress, wait for it to finish (short-poll)
    if (_isInitializing.value) {
      debugPrint(
          _debugHighlight('listenForSpeech: waiting for other init to finish'));
      while (_isInitializing.value) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    bool available = false;
    try {
      _isInitializing.value = true;
      available = await _speech.initialize();
    } catch (e, st) {
      debugPrint(_debugHighlight(
          'listenForSpeech: _speech.initialize threw: $e\n$st'));
      available = false;
    } finally {
      _isInitializing.value = false;
    }

    if (!available) {
      await flutterTts.speak("Speech service not available.");
      return null;
    }

    // Play native beep right before starting listening so user knows when to speak.
    try {
      debugPrint(_debugHighlight('listenForSpeech: playing native beep'));
      await _audioChannel.invokeMethod('playBeep');
      await Future.delayed(const Duration(milliseconds: 160));
    } on PlatformException catch (e) {
      debugPrint(_debugHighlight(
          'listenForSpeech: native beep PlatformException: ${e.message}'));
    } catch (e, st) {
      debugPrint(
          _debugHighlight('listenForSpeech: native beep failed: $e\n$st'));
    }

    isListening.value = true;
    speechText.value = '';
    try {
      await _speech.listen(
        listenFor: Duration(seconds: timeoutSeconds),
        onResult: (result) {
          speechText.value = result.recognizedWords;
          debugPrint(_debugHighlight("User said: ${speechText.value}"));
        },
      );

      // Wait in small increments so we can break early if the flow is cancelled.
      final int totalMs = timeoutSeconds * 1000;
      int waited = 0;
      const int stepMs = 200;
      while (waited < totalMs && !_speech.isListening) {
        // if not yet listening, still wait small amount (defensive)
        await Future.delayed(const Duration(milliseconds: stepMs));
        waited += stepMs;
        if (voiceFlowCancelled.value) break;
      }
      // main listen wait loop (while listening), also responsive to cancellation
      waited = 0;
      while (waited < totalMs && _speech.isListening) {
        if (voiceFlowCancelled.value) {
          // controller or page requested immediate stop
          try {
            await _speech.stop();
          } catch (_) {}
          break;
        }
        await Future.delayed(const Duration(milliseconds: stepMs));
        waited += stepMs;
      }
    } catch (e, st) {
      debugPrint(_debugHighlight('listenForSpeech: listen error: $e\n$st'));
    } finally {
      try {
        await _speech.stop();
      } catch (_) {}
      isListening.value = false;
    }

    return speechText.value.isEmpty ? null : speechText.value;
  }

  Future<void> startVoiceBookingFlow() async {
    // Clear any previous cancel request
    voiceFlowCancelled.value = false;

    if (voiceFlowCancelled.value) return;

    await flutterTts.speak("Starting appointment booking flow.");
    if (await _handleIfCancelled()) return;

    try {
      DateTime today = DateTime.now();
      DateTime lastDay = today.add(const Duration(days: 7));

      // Step 1: Day
      await flutterTts.speak(
          "Please choose a day between ${DateFormat('d MMMM').format(today)} and ${DateFormat('d MMMM').format(lastDay)}.");
      if (await _handleIfCancelled()) return;

      DateTime? day = await _listenForDayInRange(today, lastDay);
      if (await _handleIfCancelled()) return;
      if (day == null) return;

      selectedDate.value = day;

      // let listeners refresh slots for this date
      await Future.delayed(const Duration(milliseconds: 400));
      if (await _handleIfCancelled()) return;

      // Gather available slots by period for the selected date (as currently loaded)
      final Map<String, List<Map<String, dynamic>>> periodMap = Map.fromEntries(
        slotsByPeriod.entries.map((e) => MapEntry(e.key,
            e.value.where((m) => (m['available'] ?? true) == true).toList())),
      );

      // Build list of period keys that actually have available slots
      final List<String> availablePeriods = periodMap.entries
          .where((e) => e.value.isNotEmpty)
          .map((e) => e.key) // "Morning", "Afternoon", "Evening"
          .toList();

      if (availablePeriods.isEmpty) {
        // No available slots on that day -> offer to list available days (previous behaviour)
        final dayReadable = DateFormat('d MMMM').format(selectedDate.value);
        await flutterTts.speak(
            "There are no available time slots on $dayReadable. Would you like me to list available days instead?");
        if (await _handleIfCancelled()) return;

        final hearDays = await listenYesNo();
        if (await _handleIfCancelled()) return;

        if (!hearDays) {
          // user declined -> return to home
          await flutterTts.speak("Okay. Returning to the homepage.");
          await stopAllFlowsSilently();
          try {
            Get.offAll(() => const HomePage());
          } catch (_) {}
          return;
        }

        // user asked to hear available days
        List<DateTime> availableDays =
            await _getAvailableDaysInRange(today, lastDay);
        if (await _handleIfCancelled()) return;

        if (availableDays.isEmpty) {
          await flutterTts.speak(
              "There are no available days in the next week. Returning to the homepage.");
          await stopAllFlowsSilently();
          try {
            Get.offAll(() => const HomePage());
          } catch (_) {}
          return;
        }

        // Speak the available days
        await flutterTts.speak("The available days are:");
        for (final d in availableDays) {
          if (await _handleIfCancelled()) return;
          await flutterTts.speak(DateFormat('EEEE, d MMMM').format(d));
        }

        if (await _handleIfCancelled()) return;

        // Ask whether they'd like to pick one now
        await flutterTts.speak("Would you like to pick one of these days now?");
        if (await _handleIfCancelled()) return;

        final pickNow = await listenYesNo();
        if (await _handleIfCancelled()) return;

        if (pickNow) {
          // restart the booking flow to let them choose a day (will again validate and proceed)
          if (await _handleIfCancelled()) return;
          await flutterTts.speak("Okay. Let's choose a day.");
          if (await _handleIfCancelled()) return;
          // restart from top
          await startVoiceBookingFlow();
          return;
        } else {
          // user does not want to pick -> go home
          await flutterTts.speak("Okay. Returning to the homepage.");
          await stopAllFlowsSilently();
          try {
            Get.offAll(() => const HomePage());
          } catch (_) {}
          return;
        }
      }

      if (await _handleIfCancelled()) return;

      String chosenPeriodKey;

      if (availablePeriods.length == 1) {
        // Only one period available -> auto-select it
        chosenPeriodKey = availablePeriods.first;
        await flutterTts.speak(
            "Only ${chosenPeriodKey.toLowerCase()} has available times. Selecting ${chosenPeriodKey.toLowerCase()}.");
      } else {
        // Multiple periods available -> speak only those and ask user to pick
        final humanList = availablePeriods.map((p) => p.toLowerCase()).toList();

        String listPhrase;
        if (humanList.length == 2) {
          listPhrase = "${humanList[0]} and ${humanList[1]}";
        } else {
          listPhrase = humanList.sublist(0, humanList.length - 1).join(', ') +
              ", and ${humanList.last}";
        }

        await flutterTts.speak(
            "There are available slots in $listPhrase. Which would you like?");
        if (await _handleIfCancelled()) return;

        // First listen for period
        String? periodSpoken = await _listenForPeriod();
        if (await _handleIfCancelled()) return;

        String? normalized;
        if (periodSpoken != null) normalized = periodSpoken.capFirst();

        if (normalized == null || !availablePeriods.contains(normalized)) {
          // First invalid period attempt -> repeat the available periods and ask for period again
          await flutterTts.speak(
              "I didn't understand. The available periods are $listPhrase. Which would you like?");
          if (await _handleIfCancelled()) return;

          String? retryPeriod = await _listenForPeriod();
          if (await _handleIfCancelled()) return;

          String? normalizedRetry;
          if (retryPeriod != null) normalizedRetry = retryPeriod.capFirst();

          if (normalizedRetry != null &&
              availablePeriods.contains(normalizedRetry)) {
            chosenPeriodKey = normalizedRetry;
          } else {
            // Second failure: now list all available times for the day and ask once for a timeslot
            final List<String> allAvailableTimes = periodMap.values
                .expand((l) => l)
                .where((m) => (m['available'] ?? true) == true)
                .map<String>((m) => m['time'] as String)
                .toList();

            if (allAvailableTimes.isEmpty) {
              await flutterTts.speak(
                  "No available times found. Returning to the homepage.");
              await stopAllFlowsSilently();
              try {
                Get.offAll(() => const HomePage());
              } catch (_) {}
              return;
            }

            // Speak the available times once, then ask for time
            await flutterTts.speak(
                "I still couldn't understand the period. Here are the available times for that day:");
            if (await _handleIfCancelled()) return;
            for (final t in allAvailableTimes) {
              if (await _handleIfCancelled()) return;
              await flutterTts.speak(formatTimeForSpeech(t));
            }
            if (await _handleIfCancelled()) return;
            await flutterTts.speak("Please say your preferred time now.");
            if (await _handleIfCancelled()) return;

            // One final chance: listen for time from the full list
            final String? finalTime = await _listenForTime(allAvailableTimes);
            if (await _handleIfCancelled()) return;

            if (finalTime == null) {
              // second invalid -> inform and go home
              await flutterTts.speak(
                  "Invalid time, please try again later. Returning to the homepage.");
              await stopAllFlowsSilently();
              try {
                Get.offAll(() => const HomePage());
              } catch (_) {}
              return;
            }

            // user provided a valid time from the full-day list
            selectedTime.value = finalTime;
            // set chosenPeriodKey based on the time (derive period)
            chosenPeriodKey = _determinePeriod('', finalTime);
          }
        } else {
          // valid period chosen first time
          chosenPeriodKey = normalized;
        }
      }

      if (await _handleIfCancelled()) return;

      // Now proceed using chosenPeriodKey's available slots
      final rawList = periodMap[chosenPeriodKey] ?? [];
      final List<String> availableSlots =
          rawList.map<String>((m) => m['time'] as String).toList();

      if (availableSlots.isEmpty) {
        // defensive: should not happen because we filtered earlier, but handle it
        await flutterTts.speak(
            "No slots available for ${chosenPeriodKey.toLowerCase()}. Returning to the homepage.");
        await stopAllFlowsSilently();
        try {
          Get.offAll(() => const HomePage());
        } catch (_) {}
        return;
      }

      // Step 3: Time
      await flutterTts.speak("Available times are:");
      if (await _handleIfCancelled()) return;
      for (var slot in availableSlots) {
        await flutterTts.speak(formatTimeForSpeech(slot));
        if (await _handleIfCancelled()) return;
      }

      await flutterTts.speak("Please say your preferred time.");
      if (await _handleIfCancelled()) return;

      String? time = await _listenForTime(availableSlots);
      if (await _handleIfCancelled()) return;
      if (time == null) return;
      selectedTime.value = time;

      // Step 4: Reason
      await flutterTts.speak("Would you like to add a reason?");
      if (await _handleIfCancelled()) return;
      bool wantsReason = await listenYesNo();
      if (await _handleIfCancelled()) return;
      if (wantsReason) {
        await flutterTts.speak("Please say the reason now.");
        if (await _handleIfCancelled()) return;
        String? reason = await listenForSpeech(timeoutSeconds: 10);
        if (await _handleIfCancelled()) return;
        if (reason != null) reasonController.value.text = reason;
      }

      // Step 5: Confirmation
      if (await _handleIfCancelled()) return;
      await _confirmBooking();
      if (await _handleIfCancelled()) return;
    } finally {
      isVoiceFlowRunning.value = false;
    }
  }

  void stopVoiceBookingFlow() {
    // mark cancelled so other async waits break out early
    voiceFlowCancelled.value = true;
    try {
      isVoiceFlowRunning.value = false;
    } catch (_) {}
    try {
      isVoiceFlowActive.value = false;
    } catch (_) {}
    // immediate non-awaited stops so listening/TTS cut off right now
    try {
      flutterTts.stop();
    } catch (_) {}
    try {
      _speech.cancel();
    } catch (_) {}
    try {
      _speech.stop();
    } catch (_) {}
    try {
      isListening.value = false;
    } catch (_) {}
  }

  // When true the voice booking flow must abort immediately and not continue.
  final RxBool voiceFlowCancelled = false.obs;

  /// If cancellation requested, stop TTS/STT and return true.
  /// Call this after await points; if it returns true caller should return/abort.
  Future<bool> _handleIfCancelled() async {
    if (!voiceFlowCancelled.value) return false;

    // If we're currently performing a cancellation announcement, do not stop flutterTts
    // (other parts of the flow should still observe cancellation and return).
    if (voiceFlowCancellingWithAnnounce.value) {
      return true;
    }

    try {
      await flutterTts.stop();
    } catch (_) {}
    try {
      await _speech.stop();
    } catch (_) {}
    try {
      isListening.value = false;
    } catch (_) {}
    return true;
  }

  /// Cancel the current booking voice flow immediately and prevent it from continuing.
  Future<void> cancelVoiceBookingFlow() async {
    // Silent immediate stop: mark cancelled and stop TTS/STT without speaking.
    await stopAllFlowsSilently();
  }

  /// Cancel the flow and announce cancellation so the user knows how to restart.
  Future<void> cancelVoiceBookingFlowWithAnnouncement() async {
    // Mark cancelled and stop listening immediately, but allow TTS to speak the announcement.
    voiceFlowCancellingWithAnnounce.value = true;
    voiceFlowCancelled.value = true;
    try {
      isVoiceFlowRunning.value = false;
    } catch (_) {}
    // stop speech recognition immediately
    try {
      await _speech.stop();
    } catch (_) {}
    try {
      isListening.value = false;
    } catch (_) {}

    // Speak the user-facing announcement and wait for completion
    try {
      await flutterTts.speak(
          'Voice flow cancelled, use restart appointment command to start again');
      // ensure speak completes before clearing the announce flag
      try {
        await flutterTts.awaitSpeakCompletion(true);
      } catch (_) {}
    } catch (_) {}
    voiceFlowCancellingWithAnnounce.value = false;
  }

  /// Immediately stop TTS/STT and mark voice flow as cancelled, without speaking.
  Future<void> stopAllFlowsSilently() async {
    voiceFlowCancelled.value = true;
    try {
      isVoiceFlowRunning.value = false;
    } catch (_) {}
    try {
      isVoiceFlowActive.value = false;
    } catch (_) {}

    try {
      await flutterTts.stop();
    } catch (_) {}
    try {
      await _speech.stop();
    } catch (_) {}
    try {
      isListening.value = false;
    } catch (_) {}
  }

  /// Cancel the current booking voice flow immediately and notify the user.
  /// Intended to be called from the UI (e.g. when user double-taps a date).

  Future<DateTime?> _listenForDayInRange(DateTime start, DateTime end) async {
    const int maxAttempts = 2;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      String? spoken = await listenForSpeech();
      if (spoken != null) {
        DateTime? parsed = _parseFlexibleDate(spoken, start, end);
        if (parsed != null) return parsed;
        if (attempt < maxAttempts - 1) {
          await flutterTts.speak("Invalid date. Try again.");
          continue;
        }
        // final attempt: user spoke something but it wasn't valid -> announce specific message
        await _cancelFlowDueToInvalidDate();
        return null;
      } else {
        if (attempt < maxAttempts - 1) {
          await flutterTts.speak("I did not catch that. Say the day again.");
          continue;
        }
        await _cancelFlowDueToNoInput();
        return null;
      }
    }
    return null;
  }

  Future<String?> _listenForPeriod() async {
    const int maxAttempts = 2;
    String? period;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      String? spoken = await listenForSpeech();
      if (spoken != null) {
        spoken = spoken.toLowerCase();
        if (spoken.contains("morning")) period = "morning";
        if (spoken.contains("afternoon")) period = "afternoon";
        if (spoken.contains("evening")) period = "evening";
        if (period != null) return period;
        if (attempt < maxAttempts - 1) {
          await flutterTts.speak("Say morning, afternoon, or evening.");
          continue;
        }
        await _cancelFlowDueToNoInput();
        return null;
      } else {
        if (attempt < maxAttempts - 1) {
          await flutterTts.speak("Say morning, afternoon, or evening.");
          continue;
        }
        await _cancelFlowDueToNoInput();
        return null;
      }
    }
    return null;
  }

  Future<String?> _listenForTime(List<String> slots) async {
    const int maxAttempts = 2;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      String? spoken = await listenForSpeech();
      if (spoken != null) {
        String? normalized = _normalizeTime(spoken);
        if (normalized != null && slots.contains(normalized)) return normalized;
        if (attempt < maxAttempts - 1) {
          await flutterTts.speak("Invalid time. Please repeat.");
          continue;
        }
        await _cancelFlowDueToNoInput();
        return null;
      } else {
        if (attempt < maxAttempts - 1) {
          await flutterTts.speak("Invalid time. Please repeat.");
          continue;
        }
        await _cancelFlowDueToNoInput();
        return null;
      }
    }
    return null;
  }

  Future<bool> listenYesNo() async {
    const int maxAttempts = 2;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      String? spoken = await listenForSpeech(timeoutSeconds: 4);
      if (spoken != null) {
        final s = spoken.toLowerCase();
        if (s.contains("yes") || s.contains("sure")) return true;
        if (s.contains("no")) return false;
        if (attempt < maxAttempts - 1) {
          await flutterTts.speak("Please say yes or no.");
          continue;
        }
        await _cancelFlowDueToNoInput();
        return false;
      } else {
        if (attempt < maxAttempts - 1) {
          await flutterTts.speak("Please say yes or no.");
          continue;
        }
        await _cancelFlowDueToNoInput();
        return false;
      }
    }
    return false;
  }

  /// Cancel flow when user fails to answer twice: announce, clear prompts, go Home.
  Future<void> _cancelFlowDueToNoInput() async {
    // mark cancelling so other checks don't interrupt the announcement
    try {
      voiceFlowCancellingWithAnnounce.value = true;
      voiceFlowCancelled.value = true;
    } catch (_) {}

    try {
      await flutterTts.speak("No input detected, cancelling appointment");
      try {
        await flutterTts.awaitSpeakCompletion(true);
      } catch (_) {}
    } catch (_) {}

    // clear any in-progress state/prompts
    try {
      restartProcess();
    } catch (_) {}

    // ensure flows are stopped and navigate home
    try {
      await stopAllFlowsSilently();
    } catch (_) {}
    try {
      Get.offAll(() => const HomePage());
    } catch (_) {}

    // clear announce flag
    try {
      voiceFlowCancellingWithAnnounce.value = false;
    } catch (_) {}
  }

  /// Cancel flow when final attempt contained an invalid date (user spoke but date invalid).
  Future<void> _cancelFlowDueToInvalidDate() async {
    try {
      voiceFlowCancellingWithAnnounce.value = true;
      voiceFlowCancelled.value = true;
    } catch (_) {}

    try {
      await flutterTts.speak("No valid date detected, cancelling appointment");
      try {
        await flutterTts.awaitSpeakCompletion(true);
      } catch (_) {}
    } catch (_) {}

    try {
      restartProcess();
    } catch (_) {}

    try {
      await stopAllFlowsSilently();
    } catch (_) {}
    try {
      Get.offAll(() => const HomePage());
    } catch (_) {}

    try {
      voiceFlowCancellingWithAnnounce.value = false;
    } catch (_) {}
  }

  Future<void> _confirmBooking() async {
    bool bookingConfirmed = false;
    while (!bookingConfirmed) {
      String reasonText = reasonController.value.text.isNotEmpty
          ? reasonController.value.text
          : "none";

      await flutterTts.speak(
          "You chose ${DateFormat('d MMM').format(selectedDate.value)} at ${formatTimeForSpeech(selectedTime.value!)}. Reason: $reasonText. Confirm with yes or no");

      bool confirm = await listenYesNo();

      if (confirm) {
        await flutterTts.speak("Booking confirmed! Saving your appointment.");
        bookingConfirmed = true;

        try {
          final dateKey = DateFormat('yyyy-MM-dd').format(selectedDate.value);
          final time = selectedTime.value!;
          final reasonText = reasonController.value.text.isNotEmpty
              ? reasonController.value.text
              : 'none';

          // Try to attach authenticated user's profile (if signed-in)
          final uid = FirebaseAuth.instance.currentUser?.uid;
          String? userName;
          String? userSurname;
          String? userPhone;
          if (uid != null) {
            try {
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .get();
              if (userDoc.exists) {
                final data = userDoc.data()!;
                userName = data['name'] ??
                    data['firstName'] ??
                    data['givenName'] ??
                    data['displayName'];
                userSurname =
                    data['surname'] ?? data['lastName'] ?? data['familyName'];
                userPhone = data['contactNumber'] ??
                    data['phone'] ??
                    data['contact'] ??
                    data['mobile'];
              }
            } catch (e) {
              debugPrint(_debugHighlight(
                  'Failed to read user profile for appointment: $e'));
            }
          }

          // Build appointment payload including user info when available
          final appointmentData = <String, dynamic>{
            'date': dateKey,
            'time': time,
            'reason': reasonText,
            'createdAt': FieldValue.serverTimestamp(),
            'bookedBy': uid,
            'uid': uid, // keep compatibility with older queries
          };

          // create appointment
          await FirebaseFirestore.instance
              .collection('appointments')
              .add(appointmentData);

          // mark timeslot unavailable if we have docId
          final docId = _timeToDocId[time];
          if (docId != null) {
            await FirebaseFirestore.instance
                .collection('timeslots')
                .doc(docId)
                .update({
              'available': false,
              'bookedAt': FieldValue.serverTimestamp(),
            });
          }

          await flutterTts.speak("Your appointment is saved.");
          // clear UI state and return user to home
          await _afterBookingSuccess();
          return;
        } catch (e) {
          debugPrint(_debugHighlight('Failed saving appointment: $e'));
          await flutterTts
              .speak("Failed to save appointment. Please try again.");
        }
      } else {
        await flutterTts
            .speak("What would you like to change: date, time, or reason?");
        String? response = await listenForSpeech(timeoutSeconds: 6);
        if (response != null) {
          response = response.toLowerCase();
          if (response.contains("date")) {
            await startVoiceBookingFlow(); // restart
            return;
          } else if (response.contains("time")) {
            await editTimeFlow();
            return;
          } else if (response.contains("reason")) {
            await editReasonFlow();
            return;
          }
        }
      }
    }
  }

  Future<void> editTimeFlow() async {
    if (await _handleIfCancelled()) return;
    await flutterTts.speak("Morning, afternoon, or evening?");
    if (await _handleIfCancelled()) return;
    String? period = await _listenForPeriod();
    if (await _handleIfCancelled()) return;
    if (period == null) return;

    final rawList = slotsByPeriod[period.capFirst()] ?? [];
    final List<String> availableSlots = rawList
        .where((m) => (m['available'] ?? true) == true)
        .map<String>((m) => m['time'] as String)
        .toList();

    if (availableSlots.isEmpty) {
      await flutterTts.speak("No available slots for $period.");
      return;
    }

    await flutterTts.speak("Available times are:");
    if (await _handleIfCancelled()) return;
    for (var slot in availableSlots) {
      await flutterTts.speak(formatTimeForSpeech(slot));
      if (await _handleIfCancelled()) return;
    }

    await flutterTts.speak("Please say your preferred time.");
    if (await _handleIfCancelled()) return;
    String? time = await _listenForTime(availableSlots);
    if (await _handleIfCancelled()) return;
    if (time != null) {
      selectedTime.value = time;
      await flutterTts
          .speak("Appointment time updated to ${formatTimeForSpeech(time)}.");
      if (await _handleIfCancelled()) return;
      // Prompt to submit after the user changed the time
      await _promptSubmitAfterChange();
    }
  }

  Future<void> editReasonFlow() async {
    if (await _handleIfCancelled()) return;
    await flutterTts.speak("Please say your reason for the appointment.");
    if (await _handleIfCancelled()) return;
    String? reason = await listenForSpeech(timeoutSeconds: 10);
    if (await _handleIfCancelled()) return;
    if (reason != null && reason.isNotEmpty) {
      reasonController.value.text = reason;
      await flutterTts.speak("Reason updated to: $reason");
      if (await _handleIfCancelled()) return;
      // Prompt to submit after the user changed the reason
      await _promptSubmitAfterChange();
    }
  }

  Future<void> _promptSubmitAfterChange() async {
    if (voiceFlowCancelled.value) return;

    try {
      await flutterTts
          .speak("You changed your appointment. Would you like to submit it?");
      if (await _handleIfCancelled()) return;
    } catch (_) {}

    String? reply;
    try {
      reply = await listenForSpeech(timeoutSeconds: 6, forceStart: true);
    } catch (_) {
      reply = null;
    }
    if (await _handleIfCancelled()) return;

    final r = (reply ?? '').toLowerCase();
    final confirmed = r.contains('yes') ||
        r.contains('submit') ||
        r.contains('confirm') ||
        r.contains('sure');

    if (!confirmed) {
      try {
        await flutterTts.speak("Okay. Not submitting.");
      } catch (_) {}
      return;
    }

    // confirmed -> attempt submit
    try {
      await flutterTts.speak("Submitting your appointment now.");
      try {
        await flutterTts.awaitSpeakCompletion(true);
      } catch (_) {}
    } catch (_) {}

    final ok = await submitAppointment();
    if (await _handleIfCancelled()) return;

    if (ok) {
      try {
        await flutterTts.speak("Appointment submitted successfully.");
        try {
          await flutterTts.awaitSpeakCompletion(true);
        } catch (_) {}
      } catch (_) {}
      await _afterBookingSuccess();
    } else {
      try {
        await flutterTts
            .speak("Failed to submit appointment. Please try again.");
      } catch (_) {}
    }
  }

  String formatTimeForSpeech(String time24) {
    try {
      final parts = time24.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      // 24-hour wording: convert numbers to words (e.g. 13 -> "thirteen")
      final hourWords = _numToWords(hour);

      // minute wording: "o'clock" for zero, "oh five" for single-digit minutes,
      // otherwise standard words ("thirty one")
      String minuteWords;
      if (minute == 0) {
        minuteWords = "o'clock";
      } else if (minute < 10) {
        minuteWords = 'oh ${_numToWords(minute)}';
      } else {
        minuteWords = _numToWords(minute);
      }

      // period phrase to guide users (keeps compatibility if they also say it)
      String period;
      if (hour >= 17) {
        period = "in the evening";
      } else if (hour >= 12) {
        period = "in the afternoon";
      } else {
        period = "in the morning";
      }

      // Build final phrase: use 24-hour words and include period
      if (minute == 0) {
        return "$hourWords o'clock $period";
      }
      return "$hourWords $minuteWords $period";
    } catch (e) {
      return time24;
    }
  }

  // small number-to-words helper for 0..59 (supports 13..23 etc.)
  String _numToWords(int n) {
    final ones = {
      0: 'zero',
      1: 'one',
      2: 'two',
      3: 'three',
      4: 'four',
      5: 'five',
      6: 'six',
      7: 'seven',
      8: 'eight',
      9: 'nine',
      10: 'ten',
      11: 'eleven',
      12: 'twelve',
      13: 'thirteen',
      14: 'fourteen',
      15: 'fifteen',
      16: 'sixteen',
      17: 'seventeen',
      18: 'eighteen',
      19: 'nineteen'
    };
    final tens = {20: 'twenty', 30: 'thirty', 40: 'forty', 50: 'fifty'};

    if (n <= 19) return ones[n]!;
    if (n % 10 == 0) return tens[n] ?? n.toString();
    final tenPart = (n ~/ 10) * 10;
    final unitPart = n % 10;
    final tenWord = tens[tenPart] ?? tenPart.toString();
    final unitWord = ones[unitPart] ?? unitPart.toString();
    return '$tenWord $unitWord';
  }

  // Accept many spoken time variants and normalize to "HH:mm"
  String? _normalizeTime(String spoken) {
    spoken = spoken
        .toLowerCase()
        .replaceAll("o'clock", "")
        .replaceAll("o clock", "")
        .trim();

    // quick numeric-only cases embedded with extra words handled later; try a pure numeric extract first
    final pureDigitsOnly = RegExp(r'^(\d{3,4})$');
    final cleanedDigits = spoken.replaceAll(RegExp(r'[^0-9]'), '');
    if (pureDigitsOnly.hasMatch(cleanedDigits) && cleanedDigits.length >= 3) {
      // e.g. "131" or "1331" -> split last two as minutes
      final raw = cleanedDigits;
      final h = int.parse(raw.substring(0, raw.length - 2));
      final m = int.parse(raw.substring(raw.length - 2));
      if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      }
    }

    // numeric pattern with explicit separator like "13:31" or "13 31"
    final numericMatch = RegExp(r'^\s*\d{1,2}[:\s]\d{2}\s*$');
    if (numericMatch.hasMatch(spoken)) {
      final cleaned = spoken.replaceAll(':', ' ').trim();
      final parts = cleaned.split(RegExp(r'\s+'));
      final h = int.tryParse(parts[0]) ?? -1;
      final m = int.tryParse(parts[1]) ?? -1;
      if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      }
    }

    // map words to numbers (supports "thirteen thirty one", "one thirty one pm", etc.)
    final small = {
      'zero': 0,
      'oh': 0,
      'o': 0,
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
      'eleven': 11,
      'twelve': 12,
      'thirteen': 13,
      'fourteen': 14,
      'fifteen': 15,
      'sixteen': 16,
      'seventeen': 17,
      'eighteen': 18,
      'nineteen': 19
    };
    final tensWord = {'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50};

    final tokens = spoken.split(RegExp(r'[\s-]+'));
    int? hour;
    int minute = 0;
    bool seenAm = false;
    bool seenPm = false;

    // detect period words including 'afternoon'/'evening' and common AM/PM tokens
    if (tokens.any((t) => ['am', 'a.m.', 'a.m', 'morning'].contains(t))) {
      seenAm = true;
    }
    if (tokens.any((t) =>
        ['pm', 'p.m.', 'p.m', 'afternoon', 'evening', 'noon'].contains(t))) {
      seenPm = true;
    }

    // parse numbers from tokens into numeric sequence
    final nums = <int>[];
    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (small.containsKey(t)) {
        nums.add(small[t]!);
        continue;
      }
      if (tensWord.containsKey(t)) {
        int val = tensWord[t]!;
        // lookahead for unit like "thirty one"
        if (i + 1 < tokens.length && small.containsKey(tokens[i + 1])) {
          val += small[tokens[i + 1]]!;
          i++;
        }
        nums.add(val);
        continue;
      }
      // digits inside token (e.g., "13" or "31" or "131")
      final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isNotEmpty) {
        nums.add(int.parse(digits));
        continue;
      }
      // ignore filler words like 'in', 'the', 'at'
    }

    if (nums.isNotEmpty) {
      if (nums.length == 1) {
        // single numeric token: could be "13" (hour) or "131" (hour+minute)
        final single = nums[0];
        if (single > 59) {
          // split by last two digits -> 131 -> 1:31, 1331 -> 13:31
          final m = single % 100;
          final h = single ~/ 100;
          hour = h;
          minute = m;
        } else {
          hour = single;
          minute = 0;
        }
      } else {
        // first -> hour, second -> minute (if minute > 59 and <= 999 treat last two as minutes)
        hour = nums[0];
        minute = nums[1];
        if (minute > 59 && minute <= 999) {
          minute = int.parse(
              minute.toString().substring(minute.toString().length - 2));
        }
      }
    }

    if (hour == null) return null;
    // apply am/pm hints
    if (seenPm && hour < 12) hour += 12;
    if (seenAm && hour == 12) hour = 0;

    if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }

    return null;
  }

  DateTime? _parseFlexibleDate(String spoken, DateTime start, DateTime end) {
    final today = DateTime.now();
    spoken = spoken.toLowerCase().trim();
    spoken = spoken.replaceAll(RegExp(r'(st|nd|rd|th)'), '');

    // Normalize start/end to midnight
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);

    // 1. Handle today / tomorrow
    if (spoken.contains("today")) return today;
    if (spoken.contains("tomorrow")) return today.add(const Duration(days: 1));

    // 2. Handle weekday names
    final weekdays = {
      "monday": 1,
      "tuesday": 2,
      "wednesday": 3,
      "thursday": 4,
      "friday": 5,
      "saturday": 6,
      "sunday": 7
    };
    if (weekdays.containsKey(spoken)) {
      int daysToAdd = (weekdays[spoken]! - today.weekday + 7) % 7;
      DateTime candidate = today.add(Duration(days: daysToAdd));
      if (!candidate.isBefore(startDay) && !candidate.isAfter(endDay)) {
        return candidate;
      }
    }

    // 3. Numeric day for current month
    final dayNum = int.tryParse(spoken);
    if (dayNum != null) {
      try {
        DateTime candidate = DateTime(today.year, today.month, dayNum);
        if (!candidate.isBefore(startDay) && !candidate.isAfter(endDay)) {
          return candidate;
        }
      } catch (_) {}
    }

    // 4. Day Month format
    try {
      final parts = spoken.split(" ");
      if (parts.length == 2) {
        int? day = int.tryParse(parts[0]) ?? int.tryParse(parts[1]);
        String monthName =
            parts[0].contains(RegExp(r'[a-zA-Z]')) ? parts[0] : parts[1];
        if (day != null) {
          final capitalizedMonth =
              monthName[0].toUpperCase() + monthName.substring(1).toLowerCase();
          final month = DateFormat.MMMM().parseLoose(capitalizedMonth).month;
          DateTime parsed = DateTime(today.year, month, day);
          if (!parsed.isBefore(startDay) && !parsed.isAfter(endDay)) {
            return parsed;
          }
        }
      }
    } catch (_) {}

    return null; // still invalid
  }

  Future<void> handleCommand(String command) async {
    final normalized = command.toLowerCase().trim();
    speechText.value = normalized;

    // Navigation commands (homepage, appointment page, logout)
    if (normalized.contains('go to') &&
        (normalized.contains('home') || normalized.contains('home page'))) {
      await flutterTts.speak("Going to the homepage.");
      try {
        Get.offAll(() => const HomePage());
      } catch (e) {
        debugPrint(_debugHighlight('Navigation to Home failed: $e'));
      }
      return;
    }

    if ((normalized.contains('go to') && normalized.contains('appointment')) ||
        normalized.contains('appointment page')) {
      await flutterTts.speak("Opening appointments.");
      try {
        Get.to(() => const AppointmentPage());
      } catch (e) {
        debugPrint(_debugHighlight('Navigation to Appointment failed: $e'));
      }
      return;
    }

    // voice "submit" command: ask for a spoken confirmation, then submit
    if (normalized.contains('submit') || normalized.contains('confirm')) {
      // ensure a time is selected
      if (selectedTime.value == null) {
        await flutterTts
            .speak("Please choose a date and time before submitting.");
        return;
      }

      try {
        // Ask for explicit verbal confirmation and wait for TTS to finish
        await flutterTts.speak(
            "Do you want to submit your appointment now? Say yes to confirm.");
        try {
          await flutterTts.awaitSpeakCompletion(true);
        } catch (_) {}

        // Listen for a short yes/no response
        final reply = await listenForSpeech(timeoutSeconds: 6);
        final r = (reply ?? '').toLowerCase();
        if (r.isEmpty) {
          await flutterTts
              .speak("No confirmation heard. Submission cancelled.");
          try {
            await flutterTts.awaitSpeakCompletion(true);
          } catch (_) {}
          return;
        }

        if (!(r.contains('yes') ||
            r.contains('confirm') ||
            r.contains('submit') ||
            r.contains('sure'))) {
          await flutterTts.speak("Submission cancelled.");
          try {
            await flutterTts.awaitSpeakCompletion(true);
          } catch (_) {}
          return;
        }

        // confirmed — announce submitting, wait for that speech to finish,
        // then persist and only navigate after speech completes.
        await flutterTts.speak("Submitting your appointment now.");
        try {
          await flutterTts.awaitSpeakCompletion(true);
        } catch (_) {}

        final ok = await submitAppointment();
        if (ok) {
          try {
            await flutterTts.speak("Appointment submitted successfully.");
            // WAIT for TTS to finish so the user hears confirmation before we navigate
            try {
              await flutterTts.awaitSpeakCompletion(true);
            } catch (_) {}
          } catch (_) {}

          // Finally perform cleanup/navigation (this will navigate to Home)
          try {
            await _afterBookingSuccess();
          } catch (e) {
            debugPrint(_debugHighlight('After-booking cleanup failed: $e'));
          }
        } else {
          try {
            await flutterTts
                .speak("Failed to submit appointment. Please try again.");
            try {
              await flutterTts.awaitSpeakCompletion(true);
            } catch (_) {}
          } catch (_) {}
        }
      } catch (e, st) {
        debugPrint(_debugHighlight('submit via voice failed: $e\n$st'));
        try {
          await flutterTts
              .speak("Failed to submit appointment. Please try again.");
          try {
            await flutterTts.awaitSpeakCompletion(true);
          } catch (_) {}
        } catch (_) {}
      }
      return;
    }

    if (normalized.contains('log out') ||
        normalized.contains('logout') ||
        normalized.contains('sign out')) {
      await flutterTts.speak("Signing you out.");
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        debugPrint(_debugHighlight('Firebase signOut failed: $e'));
      }
      try {
        Get.offAll(() => LoginPage());
      } catch (e) {
        debugPrint(_debugHighlight('Navigation after logout failed: $e'));
      }
      return;
    }

    if (normalized.contains("restart appointment")) {
      restartProcess();
      await startVoiceBookingFlow();
    } else if (normalized.contains("repeat time")) {
      if (selectedTime.value != null) await editTimeFlow();
    } else if (normalized.contains("repeat reason")) {
      await editReasonFlow();
    } else if (normalized.contains("cancel appointment")) {
      restartProcess();
      Get.to(() => const HomePage());
    } else {
      await flutterTts.speak("Command not recognized. Please repeat.");
    }
  }

  void restartProcess() {
    selectedDate.value = DateTime.now();
    selectedTime.value = null;
    reasonController.value.clear();
    speechText.value = '';
    isListening.value = false;
  }

  Future<bool> submitAppointment() async {
    final time = selectedTime.value;
    if (time == null) return false;

    final dateKey = DateFormat('yyyy-MM-dd').format(selectedDate.value);
    final reasonText = reasonController.value.text.isNotEmpty
        ? reasonController.value.text
        : 'none';

    final uid = FirebaseAuth.instance.currentUser?.uid;

    final appointmentData = <String, dynamic>{
      'date': dateKey,
      'time': time,
      'reason': reasonText,
      'createdAt': FieldValue.serverTimestamp(),
      'bookedBy': uid,
      'uid': uid, // keep compatibility with older queries
    };

    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .add(appointmentData);

      final docId = _timeToDocId[time];
      if (docId != null) {
        await FirebaseFirestore.instance
            .collection('timeslots')
            .doc(docId)
            .update({
          'available': false,
          'bookedAt': FieldValue.serverTimestamp(),
        });
      }

      // Do NOT navigate here — let callers announce and call _afterBookingSuccess
      // so TTS/confirmation can complete before navigation.
      return true;
    } catch (e) {
      debugPrint(_debugHighlight('submitAppointment failed: $e'));
      return false;
    }
  }

  /// Prompt the user about their latest appointment and offer to cancel it.
  /// Returns true if an appointment was found and cancelled.
  Future<bool> promptCancelLatestAppointment() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    try {
      final q = await FirebaseFirestore.instance
          .collection('appointments')
          .where('bookedBy', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (q.docs.isEmpty) return false;

      final doc = q.docs.first;
      final data = doc.data();
      final dateStr = data['date'] as String? ?? '';
      final timeStr = data['time'] as String? ?? '';

      final humanDate = _friendlyDate(dateStr);
      final humanTime = timeStr.isNotEmpty ? timeStr : 'an unspecified time';

      // Ensure TTS is ready and audible, stop any previous speech that might cut this off.
      try {
        await flutterTts.stop();
      } catch (_) {}
      try {
        await flutterTts.setVolume(1.0);
      } catch (_) {}
      try {
        await flutterTts.setSpeechRate(0.45);
      } catch (_) {}
      try {
        await flutterTts.awaitSpeakCompletion(true);
      } catch (_) {}

      // Speak the prompt
      try {
        await flutterTts.speak(
            'You have an appointment on $humanDate at $humanTime. Say yes to cancel it, or say no to keep it.');
        await flutterTts.awaitSpeakCompletion(true);
      } catch (_) {}

      // Listen for a short yes/no response
      String? reply = await listenForSpeech(timeoutSeconds: 6);
      if (reply == null) return false;
      final r = reply.toLowerCase();
      final confirm =
          r.contains('yes') || r.contains('cancel') || r.contains('sure');
      if (!confirm) return false;

      // Delete appointment and release timeslot
      try {
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(doc.id)
            .delete();
      } catch (e) {
        debugPrint('Failed to delete appointment ${doc.id}: $e');
      }

      // attempt to release matching timeslot(s)
      await _releaseTimeslotForAppointmentData(data);

      // Announce cancellation
      try {
        await flutterTts.speak('Appointment cancelled.');
        await flutterTts.awaitSpeakCompletion(true);
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint(_debugHighlight('promptCancelLatestAppointment error: $e'));
      return false;
    }
  }

  // Helper: release timeslot(s) matching appointment data (date/time)
  Future<void> _releaseTimeslotForAppointmentData(
      Map<String, dynamic> data) async {
    final time = data['time'] as String?;
    final date = data['date'] as String?;
    final timeslotId =
        data['timeslotId'] ?? data['slotDocId'] ?? data['slotId'];

    try {
      if (timeslotId != null) {
        await FirebaseFirestore.instance
            .collection('timeslots')
            .doc(timeslotId)
            .update({
          'available': true,
          'bookedAt': FieldValue.delete(),
          'bookedBy': FieldValue.delete(),
        });
        return;
      }

      Query<Map<String, dynamic>> base =
          FirebaseFirestore.instance.collection('timeslots');
      if (date != null) base = base.where('date', isEqualTo: date);

      // try direct 'time' match
      var q = await base.where('time', isEqualTo: time).limit(1).get();
      if (q.docs.isNotEmpty) {
        await q.docs.first.reference.update({
          'available': true,
          'bookedAt': FieldValue.delete(),
          'bookedBy': FieldValue.delete(),
        });
        return;
      }

      // try startTime field
      q = await base.where('startTime', isEqualTo: time).limit(1).get();
      if (q.docs.isNotEmpty) {
        await q.docs.first.reference.update({
          'available': true,
          'bookedAt': FieldValue.delete(),
          'bookedBy': FieldValue.delete(),
        });
        return;
      }

      // fallback: fetch all for date and compare normalized times
      final all = await base.get();
      final normAppt = _normalizeTo24(time);
      for (final s in all.docs) {
        final slotData = s.data();
        final raw = (slotData['time'] ?? slotData['startTime'])?.toString();
        final normSlot = _normalizeTo24(raw);
        if (normSlot != null && normAppt != null && normSlot == normAppt) {
          await s.reference.update({
            'available': true,
            'bookedAt': FieldValue.delete(),
            'bookedBy': FieldValue.delete(),
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Failed to release timeslot: $e');
    }
  }

  // small helper to present the date string more nicely
  String _friendlyDate(String dateStr) {
    try {
      final dt = DateFormat('yyyy-MM-dd').parse(dateStr);
      return DateFormat('EEEE, d MMMM').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  // helper to normalize many time formats to "HH:mm"
  String? _normalizeTo24(String? raw) {
    if (raw == null) return null;

    // Prefer the already implemented parser
    try {
      final parsed = _normalizeRawTimeTo24(raw);
      if (parsed != null) return parsed;
    } catch (_) {}

    // Fallback: try common parsers
    try {
      final dt = DateFormat.jm().parseLoose(raw);
      return DateFormat('HH:mm').format(dt);
    } catch (_) {}
    try {
      final dt2 = DateFormat('H:mm').parseLoose(raw);
      return DateFormat('HH:mm').format(dt2);
    } catch (_) {}

    // Last resort: digit heuristic (e.g. "131" -> "01:31", "1331" -> "13:31")
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 3 && digits.length <= 4) {
      try {
        final h = int.parse(digits.substring(0, digits.length - 2));
        final m = int.parse(digits.substring(digits.length - 2));
        if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
          return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        }
      } catch (_) {}
    }

    return null;
  }

  /// Query Firestore for distinct days in [start..end] that have at least one available slot.
  Future<List<DateTime>> _getAvailableDaysInRange(
      DateTime start, DateTime end) async {
    try {
      // Query only by availability, then filter the date range client-side.
      final dateStart = DateFormat('yyyy-MM-dd').format(start);
      final dateEnd = DateFormat('yyyy-MM-dd').format(end);

      final q = await FirebaseFirestore.instance
          .collection('timeslots')
          .where('available', isEqualTo: true)
          .get();

      final Set<String> dates = {};
      for (final doc in q.docs) {
        final d = (doc.data()['date'] as String?)?.trim();
        if (d == null || d.isEmpty) continue;
        // keep only those within the requested inclusive range
        if (d.compareTo(dateStart) < 0) continue;
        if (d.compareTo(dateEnd) > 0) continue;
        dates.add(d);
      }

      final List<DateTime> result = dates.map((s) {
        try {
          return DateFormat('yyyy-MM-dd').parse(s);
        } catch (_) {
          return DateTime.tryParse(s) ?? DateTime.now();
        }
      }).toList();
      result.sort();
      return result;
    } catch (e) {
      debugPrint(_debugHighlight('Failed to query available days: $e'));
      return <DateTime>[];
    }
  }

  Future<void> _afterBookingSuccess() async {
    // reset controller UI state
    try {
      restartProcess();
    } catch (_) {}

    // ensure any running voice/TTS/STT flows are stopped
    try {
      await stopAllFlowsSilently();
    } catch (_) {}

    // small delay so any final TTS finishes cleanly
    await Future.delayed(const Duration(milliseconds: 250));

    // navigate back to home
    try {
      Get.offAll(() => const HomePage());
    } catch (e) {
      debugPrint(
          _debugHighlight('Navigation to Home after booking failed: $e'));
    }
  }
}

String _debugHighlight(String message) {
  return '\x1B[43m$message\x1B[0m';
}

// -------------------- EXTENSION --------------------
extension CapExtension on String {
  String capFirst() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1).toLowerCase();
  }
}
