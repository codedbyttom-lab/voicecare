import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminTimeslotPage extends StatefulWidget {
  const AdminTimeslotPage({super.key});

  @override
  State<AdminTimeslotPage> createState() => _AdminTimeslotPageState();
}

class _AdminTimeslotPageState extends State<AdminTimeslotPage> {
  final _formKey = GlobalKey<FormState>();
  DateTime? selectedDate;
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  final capacityController = TextEditingController();
  String? selectedPeriod;

  final List<String> periods = ["Morning", "Afternoon", "Evening"];

  Future<void> _saveTimeslot() async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedDate == null || startTime == null || endTime == null || selectedPeriod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select date, times and period")),
      );
      return;
    }

    final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate!);

    await FirebaseFirestore.instance.collection('timeslots').add({
      'date': formattedDate,
      'startTime':
          '${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}',
      'endTime':
          '${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}',
      'capacity': int.parse(capacityController.text),
      'isActive': true,
      'available': true, // matches AppointmentController listener
      'period': selectedPeriod,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Timeslot saved successfully')),
    );

    setState(() {
      selectedDate = null;
      startTime = null;
      endTime = null;
      capacityController.clear();
      selectedPeriod = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Timeslots')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  // Date picker
                  ListTile(
                    title: Text(selectedDate == null
                        ? 'Select Date'
                        : DateFormat('yyyy-MM-dd').format(selectedDate!)),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) setState(() => selectedDate = date);
                    },
                  ),
                  // Start time picker
                  ListTile(
                    title: Text(startTime == null ? 'Select Start Time' : startTime!.format(context)),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time != null) setState(() => startTime = time);
                    },
                  ),
                  // End time picker
                  ListTile(
                    title: Text(endTime == null ? 'Select End Time' : endTime!.format(context)),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time != null) setState(() => endTime = time);
                    },
                  ),
                  // Period selection
                  DropdownButtonFormField<String>(
                    value: selectedPeriod,
                    hint: const Text("Select Period"),
                    items: periods
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (val) => setState(() => selectedPeriod = val),
                    validator: (val) => val == null ? 'Select a period' : null,
                  ),
                  // Capacity input
                  TextFormField(
                    controller: capacityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Capacity'),
                    validator: (value) =>
                        (value == null || int.tryParse(value) == null)
                            ? 'Enter a valid number'
                            : null,
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(onPressed: _saveTimeslot, child: const Text('Save Timeslot')),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const Text("Existing Timeslots", style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('timeslots')
                    .orderBy('date')
                    .orderBy('startTime')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) return const Center(child: Text("No timeslots yet"));

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      return ListTile(
                        title: Text(
                          "${data['date']} ${data['startTime']} - ${data['endTime']}",
                        ),
                        subtitle: Text("Period: ${data['period']} | Capacity: ${data['capacity']}"),
                        trailing: Icon(
                          data['isActive'] == true ? Icons.check_circle : Icons.cancel,
                          color: data['isActive'] == true ? Colors.green : Colors.red,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
