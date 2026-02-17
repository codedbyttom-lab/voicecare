import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:voicecare/admin/admin_homepage.dart';

class AdminTimeslotPage extends StatefulWidget {
  const AdminTimeslotPage({super.key});

  @override
  _AdminTimeslotPageState createState() => _AdminTimeslotPageState();
}

class _AdminTimeslotPageState extends State<AdminTimeslotPage> {
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  String? _selectedPeriod; // Morning | Afternoon | Evening
  final List<String> _periods = ["Morning", "Afternoon", "Evening"];

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color.fromARGB(255, 40, 56, 98),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color.fromARGB(255, 40, 56, 98),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color.fromARGB(255, 40, 56, 98),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            timePickerTheme: TimePickerThemeData(
              // keep the dial background white so the selected time is readable,
              // and use the app blue for hour/minute text and controls.
              dialBackgroundColor: Colors.white,
              hourMinuteTextColor: const Color.fromARGB(255, 40, 56, 98),
              dayPeriodTextColor: const Color.fromARGB(255, 40, 56, 98),
              dialHandColor: const Color.fromARGB(255, 40, 56, 98),
              entryModeIconColor: const Color.fromARGB(255, 40, 56, 98),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  String _formatTime(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return DateFormat('HH:mm').format(dt);
  }

  // Helper to show a polished floating snackbar with gradient, icon and shadow.
  void _showAppSnackBar(String message,
      {bool success = true, int seconds = 3}) {
    final bgGradient = success
        ? LinearGradient(colors: [Colors.green.shade600, Colors.green.shade400])
        : LinearGradient(colors: [Colors.red.shade700, Colors.red.shade400]);

    final icon = success ? Icons.check_circle : Icons.error_outline;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: Duration(seconds: seconds),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: bgGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveTimeslot() async {
    if (_selectedDate == null ||
        _startTime == null ||
        _selectedPeriod == null) {
      _showAppSnackBar("Please fill all fields", success: false, seconds: 3);
      return;
    }

    // Validate that the chosen time matches the selected period.
    bool _timeMatchesPeriod(TimeOfDay tod, String period) {
      final minutes = tod.hour * 60 + tod.minute;
      // Define ranges (inclusive): Morning 05:00-11:59, Afternoon 12:00-16:59, Evening 17:00-22:59
      const morningStart = 5 * 60;
      const morningEnd = 11 * 60 + 59;
      const afternoonStart = 12 * 60;
      const afternoonEnd = 16 * 60 + 59;
      const eveningStart = 17 * 60;
      const eveningEnd = 22 * 60 + 59;

      switch (period.toLowerCase()) {
        case 'morning':
          return minutes >= morningStart && minutes <= morningEnd;
        case 'afternoon':
          return minutes >= afternoonStart && minutes <= afternoonEnd;
        case 'evening':
          return minutes >= eveningStart && minutes <= eveningEnd;
        default:
          return false;
      }
    }

    if (!_timeMatchesPeriod(_startTime!, _selectedPeriod!)) {
      String rangeText;
      final p = _selectedPeriod!.toLowerCase();
      if (p == 'morning') {
        rangeText = '05:00 - 11:59';
      } else if (p == 'afternoon') {
        rangeText = '12:00 - 16:59';
      } else {
        rangeText = '17:00 - 22:59';
      }
      _showAppSnackBar(
          "Selected time doesn't match period. Expected ${_selectedPeriod} for $rangeText",
          success: false,
          seconds: 4);
      return;
    }

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final startStr = _formatTime(_startTime!);

      // include creator info (uid, email, first/last name if available)
      final user = FirebaseAuth.instance.currentUser;
      final displayName = user?.displayName ?? '';
      final nameParts = displayName.trim().isEmpty
          ? <String>[]
          : displayName.trim().split(RegExp(r'\s+'));
      final firstName = nameParts.isNotEmpty ? nameParts.first : '';
      final lastName =
          nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

      await FirebaseFirestore.instance.collection("timeslots").add({
        "date": dateStr,
        "startTime": startStr,
        "period": _selectedPeriod,
        "available": true,
        "isActive": true,
        "createdAt": FieldValue.serverTimestamp(),
        // creator metadata
        "createdByUid": user?.uid ?? '',
        "createdByEmail": user?.email ?? '',
        "createdByDisplayName": displayName,
        "createdByFirstName": firstName,
        "createdByLastName": lastName,
      });

      _showAppSnackBar("Timeslot saved successfully",
          success: true, seconds: 2);

      setState(() {
        _selectedDate = null;
        _startTime = null;
        _selectedPeriod = null;
      });
    } catch (e) {
      _showAppSnackBar("Error saving timeslot: $e", success: false, seconds: 4);
    }
  }

  Future<void> _deleteTimeslot(String id) async {
    try {
      await FirebaseFirestore.instance.collection("timeslots").doc(id).delete();
      _showAppSnackBar("Timeslot deleted successfully",
          success: true, seconds: 2);
    } catch (e) {
      _showAppSnackBar("Error deleting timeslot: $e",
          success: false, seconds: 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Timeslot Management",
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
          ),
          onPressed: () => Get.offAll(() => const AdminHomePage()),
        ),
        backgroundColor: const Color.fromARGB(255, 40, 56, 98),
      ),
      // Use a Column with an Expanded list so layout adapts to any device size.
      // Input controls stay at the top and the timeslot list fills remaining space.
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Date picker
              ListTile(
                title: Text(_selectedDate == null
                    ? "Select Date"
                    : "Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate!)}"),
                trailing: const Icon(Icons.calendar_today,
                    color: Color.fromARGB(255, 40, 56, 98)),
                onTap: _pickDate,
              ),
              const SizedBox(height: 10),

              // Time picker
              ListTile(
                title: Text(_startTime == null
                    ? "Select Time"
                    : "Time: ${_formatTime(_startTime!)}"),
                trailing: const Icon(Icons.access_time,
                    color: Color.fromARGB(255, 40, 56, 98)),
                onTap: _pickTime,
              ),
              const SizedBox(height: 10),

              // Period dropdown
              DropdownButtonFormField<String>(
                value: _selectedPeriod,
                items: _periods.map((period) {
                  return DropdownMenuItem(
                    value: period,
                    child: Text(period),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedPeriod = value),
                decoration: const InputDecoration(
                  labelText: "Select Period",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveTimeslot,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 40, 56, 98),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  child: const Text("Save Timeslot"),
                ),
              ),

              const SizedBox(height: 20),

              // Timeslot list fills remaining space and scrolls if needed
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withOpacity(0.1), // semi-transparent
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection("timeslots")
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text("No timeslots found"));
                      }

                      final docs = snapshot.data!.docs;
                      // sort newest -> oldest (date desc, then startTime desc)
                      docs.sort((a, b) {
                        final aDate =
                            DateTime.tryParse(a.data()['date'] ?? '') ??
                                DateTime(1970);
                        final bDate =
                            DateTime.tryParse(b.data()['date'] ?? '') ??
                                DateTime(1970);
                        final dateCmp = bDate.compareTo(aDate);
                        if (dateCmp != 0) return dateCmp;
                        final aStart = a.data()['startTime'] ?? '';
                        final bStart = b.data()['startTime'] ?? '';
                        return bStart.compareTo(aStart);
                      });

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data();
                          final id = docs[index].id;
                          // prettier timeslot card
                          final dateStr = (data['date'] ?? '').toString();
                          final startStr = (data['startTime'] ?? '').toString();
                          String displayDate = dateStr;
                          String displayTime = startStr;
                          try {
                            final parsedDate = DateTime.tryParse(dateStr);
                            if (parsedDate != null) {
                              displayDate =
                                  DateFormat.yMMMMd().format(parsedDate);
                            }
                          } catch (_) {}
                          try {
                            final parts = startStr.split(':');
                            if (parts.length >= 2) {
                              final dt = DateTime(0, 1, 1, int.parse(parts[0]),
                                  int.parse(parts[1]));
                              displayTime = DateFormat.jm().format(dt);
                            }
                          } catch (_) {}
                          final period = (data['period'] ?? '').toString();
                          final available = (data['available'] ?? true) == true;

                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              leading: CircleAvatar(
                                radius: 22,
                                backgroundColor:
                                    period.toLowerCase() == 'morning'
                                        ? Colors.orange.shade100
                                        : period.toLowerCase() == 'afternoon'
                                            ? Colors.blue.shade100
                                            : Colors.purple.shade100,
                                child: Text(
                                  period.isNotEmpty
                                      ? period[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              title: Text(
                                displayDate,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  // use Wrap so items will wrap to next line on small devices
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.access_time,
                                              size: 14, color: Colors.black54),
                                          const SizedBox(width: 6),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxWidth: 160),
                                            child: Text(displayTime,
                                                style: const TextStyle(
                                                    color: Colors.black87),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.event_note,
                                              size: 14, color: Colors.black54),
                                          const SizedBox(width: 6),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxWidth: 120),
                                            child: Text('Period: $period',
                                                style: const TextStyle(
                                                    color: Colors.black54),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            available
                                                ? Icons.check_circle
                                                : Icons.cancel,
                                            size: 14,
                                            color: available
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                              available
                                                  ? 'Available'
                                                  : 'Unavailable',
                                              style: const TextStyle(
                                                  color: Colors.black54)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteTimeslot(id),
                                tooltip: 'Delete timeslot',
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
