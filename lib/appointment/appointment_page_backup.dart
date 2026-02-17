import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:voicecare/controllers/appointment_controller.dart';
import 'dart:async';

class AppointmentPage extends StatefulWidget {
  const AppointmentPage({super.key});

  @override
  State<AppointmentPage> createState() => _AppointmentPageState();
}

class _AppointmentPageState extends State<AppointmentPage> {
  final AppointmentController _ctrl = Get.find<AppointmentController>();

  late DateTime _firstAvailableDate;
  late DateTime _lastAvailableDate;
  bool _doubleTapped = false; // guard to prevent onTap after a double-tap
  Timer? _singleTapTimer; // scheduled single-tap action

  @override
  void initState() {
    super.initState();
    DateTime today = DateTime.now();
    _firstAvailableDate = today;
    _lastAvailableDate = today.add(const Duration(days: 7));
    _ctrl.selectedDate.value = _firstAvailableDate;

    Future.delayed(Duration.zero, () {
      _ctrl.startVoiceBookingFlow();
    });
  }

  @override
  void deactivate() {
    // Page is no longer visible (another route covered it) — ensure voice flow stops
    try {
      _ctrl.stopVoiceBookingFlow();
    } catch (_) {}
    super.deactivate();
  }

  @override
  void dispose() {
    // Ensure booking flow and any ongoing TTS/STT are stopped when page is removed
    try {
      _ctrl.stopVoiceBookingFlow();
    } catch (_) {}
    _singleTapTimer?.cancel();
    super.dispose();
  }

  List<DateTime> get _availableDates {
    return List.generate(
        _lastAvailableDate.difference(_firstAvailableDate).inDays + 1,
        (i) => _firstAvailableDate.add(Duration(days: i)));
  }

  // String _formatSelectedDate(DateTime date) {
  //   return DateFormat('EEEE, d MMM').format(date);
  // }

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
              final isSelected = _ctrl.selectedTime.value == slotTime;

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
                  _ctrl.selectedTime.value = slotTime;
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
                final selectedDate = _ctrl.selectedDate.value;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _availableDates.map((date) {
                    bool isSelected = date.year == selectedDate.year &&
                        date.month == selectedDate.month &&
                        date.day == selectedDate.day;

                    return GestureDetector(
                      onTap: () {
                        // Schedule single-tap action with delay to allow double-tap cancellation
                        if (_doubleTapped) {
                          _doubleTapped = false;
                          return; // Ignore single tap if double tap occurred
                        }

                        _singleTapTimer?.cancel();
                        _singleTapTimer =
                            Timer(const Duration(milliseconds: 200), () {
                          if (!_doubleTapped) {
                            // Execute single tap action - select the date
                            _ctrl.selectedDate.value = date;
                          }
                        });
                      },
                      onDoubleTap: () {
                        // Double tap cancels the entire voice booking process
                        _doubleTapped = true;
                        _singleTapTimer?.cancel();

                        // Stop the voice booking flow
                        _ctrl.stopVoiceBookingFlow();

                        // Show feedback to user
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Voice booking process cancelled'),
                            duration: Duration(seconds: 2),
                          ),
                        );

                        // Reset double tap flag after a short delay
                        Timer(const Duration(milliseconds: 500), () {
                          _doubleTapped = false;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color.fromARGB(255, 40, 56, 98)
                              // ignore: deprecated_member_use
                              : Colors.white.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? const Color.fromARGB(255, 40, 56, 98)
                                : Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat('E').format(date), // Day abbreviation
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    isSelected ? Colors.white : Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              date.day.toString(),
                              style: TextStyle(
                                fontSize: 16,
                                color: isSelected ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
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
            const SizedBox(height: 24),
            Expanded(
              child: Obx(() {
                final periods = _ctrl.slotsByPeriod;
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSlotSection("Morning", periods["Morning"] ?? []),
                      _buildSlotSection(
                          "Afternoon", periods["Afternoon"] ?? []),
                      _buildSlotSection("Evening", periods["Evening"] ?? []),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Reason (Optional):",
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Obx(() => TextField(
                                  controller: _ctrl.reasonController.value,
                                  decoration: const InputDecoration(
                                    hintText: "Enter reason for appointment",
                                    border: OutlineInputBorder(),
                                  ),
                                  maxLines: 3,
                                )),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (_ctrl.selectedTime.value != null) {
                                    // Save appointment logic would go here
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Appointment booking feature coming soon!')),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Please select a time slot')),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      const Color.fromARGB(255, 40, 56, 98),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: const Text("Book Appointment",
                                    style: TextStyle(fontSize: 16)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
