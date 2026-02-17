import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:voicecare/mic_widget/homepage_mic.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:voicecare/homepage/home_page.dart';
import 'package:voicecare/controllers/appointment_controller.dart';

class UserAppointmentsPage extends StatefulWidget {
  const UserAppointmentsPage({super.key});

  @override
  State<UserAppointmentsPage> createState() => _UserAppointmentsPageState();
}

class _UserAppointmentsPageState extends State<UserAppointmentsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final FlutterTts _flutterTts = FlutterTts();
  final AppointmentController _appointmentController =
      Get.put(AppointmentController());

  // When true the page is exiting and all voice flows must abort immediately.
  bool _exiting = false;

  // cached ScaffoldMessengerState to avoid looking up a deactivated ancestor in dispose/async callbacks
  late ScaffoldMessengerState _scaffoldMessenger;

  String? get _uid => _auth.currentUser?.uid;

  bool _isCancelling = false;

  // Polished floating Snackbar used across this page
  void _showAppSnack(String message, {bool success = true, int seconds = 3}) {
    final color = success ? Colors.green.shade700 : Colors.red.shade700;
    final icon = success ? Icons.check_circle : Icons.error;
    final snack = SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      backgroundColor: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: Duration(seconds: seconds),
      content: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
              child:
                  Text(message, style: const TextStyle(color: Colors.white))),
        ],
      ),
      action: SnackBarAction(
        label: 'Dismiss',
        textColor: Colors.white,
        onPressed: () => _scaffoldMessenger.hideCurrentSnackBar(),
      ),
    );
    // use cached messenger to avoid deactivated-ancestor lookup
    _scaffoldMessenger.showSnackBar(snack);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // safe to call here and cache; this avoids unsafe lookups inside dispose/late async callbacks
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void initState() {
    super.initState();
    // Announce latest appointment after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _announceAndPromptLatest();
    });
  }

  // Stop all TTS/STT and controller voice flows (best-effort)
  Future<void> _stopAllAndExit({bool navigateHome = false}) async {
    // mark exiting so any in-progress announce/listen flow can abort quickly
    _exiting = true;

    debugPrint('[UserAppointmentsPage] stopAllAndExit: aggressive stop begin');

    // 1) Stop local page TTS immediately and await
    try {
      await _flutterTts.stop();
    } catch (_) {}
    try {
      await _flutterTts.setVolume(0.0);
    } catch (_) {}

    // 2) Stop controller TTS (if any) and ensure its cancellation guard is set
    try {
      final stopTts = _appointmentController.flutterTts.stop();
      if (stopTts is Future) await stopTts;
    } catch (_) {}
    try {
      final setVol = _appointmentController.flutterTts.setVolume(0.0);
      if (setVol is Future) await setVol;
    } catch (_) {}
    try {
      _appointmentController.voiceFlowCancelled.value = true;
    } catch (_) {}

    // 3) Ask controller to stop any running voice flows (these are void; do not await their value)
    try {
      _appointmentController.stopVoiceBookingFlow();
    } catch (_) {}
    try {
      _appointmentController.cancelVoiceBookingFlow();
    } catch (_) {}
    try {
      _appointmentController.stopAllFlowsSilently();
    } catch (_) {}

    // 4) Try to stop any SpeechToText instance (best-effort)
    try {
      final stt = SpeechToText();
      if (stt.isListening) {
        await stt.stop();
      } else {
        await stt.stop();
      }
      try {
        await stt.cancel();
      } catch (_) {}
    } catch (_) {}

    // small pause to let native layers settle
    await Future.delayed(const Duration(milliseconds: 120));

    // 5) Ensure the controller is removed from GetX so it cannot restart flows later
    try {
      if (Get.isRegistered<AppointmentController>()) {
        // stop controller flows one more time (harmless if already stopped)
        try {
          _appointmentController.voiceFlowCancelled.value = true;
        } catch (_) {}
        try {
          _appointmentController.stopVoiceBookingFlow();
        } catch (_) {}
        try {
          _appointmentController.stopAllFlowsSilently();
        } catch (_) {}
        // delete the controller instance so background behavior can't continue
        Get.delete<AppointmentController>();
        debugPrint(
            '[UserAppointmentsPage] Deleted AppointmentController from GetX');
      }
    } catch (e) {
      debugPrint(
          '[UserAppointmentsPage] Failed deleting AppointmentController: $e');
    }

    debugPrint('[UserAppointmentsPage] stopAllAndExit: aggressive stop done');

    if (navigateHome && mounted) {
      try {
        Get.offAll(() => const HomePage());
      } catch (_) {}
    }
  }

  // quick, fire-and-forget cancellation to use from dispose/onWillPop
  void _quickStopSync() {
    _exiting = true;
    try {
      _flutterTts.stop(); // fire-and-forget
    } catch (_) {}
    try {
      _appointmentController.voiceFlowCancelled.value = true;
    } catch (_) {}
    try {
      _appointmentController.stopVoiceBookingFlow();
    } catch (_) {}
    try {
      _appointmentController.cancelVoiceBookingFlow();
    } catch (_) {}
    try {
      _appointmentController.stopAllFlowsSilently();
    } catch (_) {}
    try {
      final stt = SpeechToText();
      stt.stop();
      stt.cancel();
    } catch (_) {}
  }

  Future<void> _announceAndPromptLatest() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      if (_exiting) return; // abort early if page is leaving

      // 1) Ensure any previous TTS is stopped before starting
      try {
        await _flutterTts.stop();
      } catch (_) {}
      try {
        await _flutterTts.setVolume(1.0);
        await _flutterTts.setSpeechRate(0.45);
        await _flutterTts.awaitSpeakCompletion(true);
      } catch (_) {}

      if (_exiting) return;

      try {
        await _flutterTts.speak('This is your appointments page.');
        await _flutterTts.awaitSpeakCompletion(true);
      } catch (_) {}

      if (_exiting) {
        try {
          await _flutterTts.stop();
        } catch (_) {}
        return;
      }

      // 2) Fetch latest appointment
      final q = await _firestore
          .collection('appointments')
          .where('bookedBy', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (_exiting) {
        try {
          await _flutterTts.stop();
        } catch (_) {}
        return;
      }

      // If no appointments, inform the user and return to home
      if (q.docs.isEmpty) {
        try {
          await _flutterTts.speak(
              'You have no appointments set yet. Returning to the homepage.');
          await _flutterTts.awaitSpeakCompletion(true);
        } catch (_) {}
        if (!mounted) return;

        // Ensure all voice flows are stopped and return immediately (no further work)
        await _stopAllAndExit(navigateHome: true);
        return;
      }

      final data = q.docs.first.data();
      final dateStr = data['date'] as String? ?? '';
      final timeStr = data['time'] as String? ?? '';

      String humanDate = dateStr;
      try {
        final dt = DateFormat('yyyy-MM-dd').parse(dateStr);
        humanDate = DateFormat('EEEE, d MMMM').format(dt);
      } catch (_) {}

      String humanTime = timeStr;
      try {
        DateTime parsed;
        try {
          parsed = DateFormat.jm().parseLoose(timeStr);
        } catch (_) {
          parsed = DateFormat('HH:mm').parseLoose(timeStr);
        }
        humanTime = DateFormat.jm().format(parsed);
      } catch (_) {}

      if (_exiting) return;

      final msg = 'Your latest appointment is on $humanDate at $humanTime.';
      try {
        await _flutterTts.speak(msg);
        await _flutterTts.awaitSpeakCompletion(true);
      } catch (_) {}

      if (_exiting) {
        try {
          await _flutterTts.stop();
        } catch (_) {}
        return;
      }

      // 3) Ask to cancel, play beep, then listen
      try {
        await _flutterTts.speak('Would you like to cancel it?');
        await _flutterTts.awaitSpeakCompletion(true);
      } catch (_) {}

      if (_exiting) {
        try {
          await _flutterTts.stop();
        } catch (_) {}
        return;
      }

      // beep
      try {
        SystemSound.play(SystemSoundType.alert);
      } catch (_) {}

      if (_exiting) {
        try {
          await _flutterTts.stop();
        } catch (_) {}
        return;
      }

      // Listen with a short guarded timeout and abort quickly if exit requested.
      String? reply;
      try {
        if (_exiting) {
          reply = null;
        } else {
          // Force start and rely on controller to return quickly
          reply = await _appointmentController.listenForSpeech(
              timeoutSeconds: 5, forceStart: true, playBeep: false);
        }
      } catch (e) {
        debugPrint('listenForSpeech failed: $e');
      }

      if (_exiting) {
        try {
          await _flutterTts.stop();
        } catch (_) {}
        return;
      }

      final r = (reply ?? '').toLowerCase();
      final confirmed = r.contains('yes') ||
          r.contains('cancel') ||
          r.contains('sure') ||
          r.contains('yeah');

      // 4) act on reply
      if (confirmed) {
        try {
          await _cancelAppointment(q.docs.first, closeDialog: false);
        } catch (e) {
          debugPrint('Cancellation failed: $e');
        }
        try {
          await _flutterTts
              .speak('Appointment cancelled. Returning to the homepage.');
          await _flutterTts.awaitSpeakCompletion(true);
        } catch (_) {}
        if (!mounted) return;
        // ensure controller and native STT are synchronously told to cancel immediately
        try {
          _appointmentController.voiceFlowCancelled.value = true;
        } catch (_) {}
        try {
          _appointmentController.stopVoiceBookingFlow();
        } catch (_) {}
        try {
          _appointmentController.cancelVoiceBookingFlow();
        } catch (_) {}
        try {
          if (Get.isRegistered<AppointmentController>())
            Get.delete<AppointmentController>();
        } catch (_) {}
        // stop everything and navigate home
        await _stopAllAndExit(navigateHome: true);
        return;
      } else {
        try {
          await _flutterTts.speak('Okay. Going to the homepage.');
          await _flutterTts.awaitSpeakCompletion(true);
        } catch (_) {}
        if (!mounted) return;
        // immediate, synchronous cancellation so listenForSpeech won't continue
        try {
          _appointmentController.voiceFlowCancelled.value = true;
        } catch (_) {}
        try {
          _appointmentController.stopVoiceBookingFlow();
        } catch (_) {}
        try {
          _appointmentController.cancelVoiceBookingFlow();
        } catch (_) {}
        try {
          if (Get.isRegistered<AppointmentController>())
            Get.delete<AppointmentController>();
        } catch (_) {}
        await _stopAllAndExit(navigateHome: true);
        return;
      }
    } catch (e) {
      debugPrint('Failed to fetch latest appointment for announce: $e');
    }
  }

  @override
  void dispose() {
    // aggressive synchronous cancellation so async flows don't continue after widget removed
    _quickStopSync();
    // also try the full async stop (best-effort) but do not await — dispose cannot be async
    try {
      _stopAllAndExit();
    } catch (_) {}
    // ensure controller removed immediately as well
    try {
      if (Get.isRegistered<AppointmentController>()) {
        Get.delete<AppointmentController>();
      }
    } catch (_) {}
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _appointmentsStream() {
    // If user not signed in yet, return an empty stream to avoid invalid queries.
    if (_uid == null) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return _firestore
        .collection('appointments')
        .where('bookedBy', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  String _formatDateFromDoc(Map<String, dynamic> data) {
    final dateStr = data['date'] as String? ?? '';
    try {
      final dt = DateFormat('yyyy-MM-dd').parse(dateStr);
      return DateFormat('EEE, d MMM yyyy').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  String _formatTimeFromDoc(Map<String, dynamic> data) {
    return data['time'] as String? ?? '—';
  }

  String _formatCreatedAt(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return DateFormat('d MMM yyyy • h:mm a').format(dt);
    }
    return '';
  }

  // returns true when cancellation succeeded
  Future<bool> _cancelAppointment(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      {bool closeDialog = true}) async {
    if (_isCancelling) return false;
    setState(() => _isCancelling = true);

    try {
      final data = doc.data();
      final time = data['time'] as String?;
      final date = data['date'] as String?;
      // prefer an explicit timeslot id if stored on the appointment doc
      final timeslotId = data['timeslotId'] ??
          data['slotDocId'] ??
          data['timeslotDocId'] ??
          data['slotId'] ??
          data['docId'];

      // Delete the appointment document
      await _firestore.collection('appointments').doc(doc.id).delete();

      bool updated = false;

      if (timeslotId != null) {
        // If appointment stored the timeslot doc id, update it directly
        await _firestore.collection('timeslots').doc(timeslotId).update({
          'available': true,
          'bookedAt': FieldValue.delete(),
          'bookedBy': FieldValue.delete(),
        });
        updated = true;
      } else {
        // Try to find matching timeslot by time/date fields
        Query<Map<String, dynamic>> baseQuery =
            _firestore.collection('timeslots');
        if (date != null) baseQuery = baseQuery.where('date', isEqualTo: date);

        // 1) match 'time' field directly
        var q = await baseQuery.where('time', isEqualTo: time).limit(1).get();
        if (q.docs.isNotEmpty) {
          await q.docs.first.reference.update({
            'available': true,
            'bookedAt': FieldValue.delete(),
            'bookedBy': FieldValue.delete(),
          });
          updated = true;
        } else {
          // 2) match 'startTime' field
          q = await baseQuery
              .where('startTime', isEqualTo: time)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            await q.docs.first.reference.update({
              'available': true,
              'bookedAt': FieldValue.delete(),
              'bookedBy': FieldValue.delete(),
            });
            updated = true;
          } else {
            // 3) fallback: fetch all for date and compare normalized times
            final allForDate = await baseQuery.get();
            for (final slotDoc in allForDate.docs) {
              final slotData = slotDoc.data();
              final slotTimeRaw =
                  (slotData['time'] ?? slotData['startTime'])?.toString();
              if (slotTimeRaw == null) continue;
              final normSlot = _normalizeTo24(slotTimeRaw);
              final normAppt = _normalizeTo24(time);
              if (normSlot != null &&
                  normAppt != null &&
                  normSlot == normAppt) {
                await slotDoc.reference.update({
                  'available': true,
                  'bookedAt': FieldValue.delete(),
                  'bookedBy': FieldValue.delete(),
                });
                updated = true;
                break;
              }
            }
          }
        }
      }

      // If caller asked this method to handle UI (closeDialog==true), do it here.
      if (mounted && closeDialog) {
        try {
          Navigator.of(context).pop(); // close dialog
        } catch (_) {}
        _showAppSnack(
          updated
              ? 'Appointment cancelled — timeslot released'
              : 'Appointment cancelled',
          success: true,
        );
      }
      return true;
    } catch (e) {
      if (mounted && closeDialog) {
        _showAppSnack('Failed to cancel appointment: $e', success: false);
      }
      return false;
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  // helper to normalize many time formats to "HH:mm"
  String? _normalizeTo24(String? raw) {
    if (raw == null) return null;
    raw = raw.trim();
    try {
      // try explicit 24h
      final parts = raw.split(':');
      if (parts.length == 2 &&
          int.tryParse(parts[0]) != null &&
          int.tryParse(parts[1]) != null) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
          return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        }
      }
      // try parsing common locale formats (e.g., "1:30 PM")
      final dt = DateFormat.jm().parseLoose(raw);
      return DateFormat('HH:mm').format(dt);
    } catch (_) {
      // last attempt: strip non-digits and split
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 3 && digits.length <= 4) {
        final h = int.parse(digits.substring(0, digits.length - 2));
        final m = int.parse(digits.substring(digits.length - 2));
        if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
          return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        }
      }
    }
    return null;
  }

  void _showDetails(
      BuildContext ctx, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final time = _formatTimeFromDoc(data);
    final confirmation = doc.id;

    showDialog(
      context: ctx,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_available,
                  size: 48, color: Color(0xFF283862)),
              const SizedBox(height: 12),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF283862),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Confirmation: ${confirmation.substring(0, 8)}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF283862),
                        side: const BorderSide(color: Color(0xFF283862)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isCancelling
                          ? null
                          : () async {
                              // keep the dialog open while cancellation completes,
                              // then close the dialog once the cancellation finished.
                              await _cancelAppointment(doc, closeDialog: false);
                              if (!mounted) return;
                              try {
                                Navigator.of(ctx).pop();
                              } catch (_) {}
                            },
                      child: _isCancelling
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Cancel Appointment'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _stopAllAndExit();
        return true; // allow pop
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'My Appointments',
            style: TextStyle(color: Colors.white),
          ),
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Colors.white,
            ),
            onPressed: () async {
              // stop everything, then navigate home
              await _stopAllAndExit(navigateHome: true);
            },
          ),
          backgroundColor: const Color(0xFF283862),
        ),
        body: _uid == null
            ? const Center(child: CircularProgressIndicator())
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _appointmentsStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final e = snapshot.error;
                    // Show the error so you can see why it failed (useful during debug)
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'Error loading appointments:\n${e.toString()}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(child: Text('No appointments found'));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      try {
                        final data = doc.data();
                        final dateLabel = _formatDateFromDoc(data);
                        final timeLabel = _formatTimeFromDoc(data);
                        final createdAtLabel =
                            _formatCreatedAt(data['createdAt']);
                        return Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            leading: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  (timeLabel.isNotEmpty
                                      ? timeLabel.split(' ').first
                                      : '—'),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF283862)),
                                ),
                              ),
                            ),
                            title: Text(dateLabel,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(createdAtLabel,
                                style: const TextStyle(color: Colors.black54)),
                            trailing: TextButton(
                              onPressed: () => _showDetails(context, doc),
                              child: const Text('Details'),
                            ),
                          ),
                        );
                      } catch (e) {
                        // If a single document has malformed data, show a safe placeholder instead of crashing the whole list.
                        debugPrint('Malformed appointment doc ${doc.id}: $e');
                        return Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            title: const Text('Invalid appointment'),
                            subtitle: Text('ID: ${doc.id}'),
                            trailing: TextButton(
                              onPressed: () => _showDetails(context, doc),
                              child: const Text('Details'),
                            ),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
        // keep UI unchanged, add mic as floatingActionButton so it won't interfere with body
        floatingActionButton: Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 10, top: 8),
          child: const Center(child: HomePageMicButton()),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
  }
}
