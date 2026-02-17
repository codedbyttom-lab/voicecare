import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:voicecare/admin/admin_homepage.dart';

class ScheduledAppointments extends StatefulWidget {
  const ScheduledAppointments({super.key});

  @override
  State<ScheduledAppointments> createState() => _ScheduledAppointmentsState();
}

class _ScheduledAppointmentsState extends State<ScheduledAppointments> {
  /// Launch phone dialer
  void _callPatient(String phoneNumber) async {
    final cleaned = _sanitizePhone(phoneNumber);
    if (cleaned.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Phone number is not available")),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: cleaned);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Cannot call $cleaned")),
      );
    }
  }

  Future<Map<String, String>?> _fetchUserInfoByUid(String? uid) async {
    if (uid == null || uid.trim().isEmpty) return null;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      final d = doc.data()!;
      final name = (d['name'] ?? '').toString().trim();
      final surname = (d['surname'] ?? '').toString().trim();
      final full = ((name.isNotEmpty ? name : '') +
              (surname.isNotEmpty ? ' $surname' : ''))
          .trim();
      final phone =
          (d['contactNumber'] ?? d['contact'] ?? d['phone'] ?? '').toString();
      return {
        if (full.isNotEmpty) 'name': full,
        if (phone.isNotEmpty) 'phone': phone,
      };
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseDateField(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String) {
      final dt = DateTime.tryParse(raw);
      if (dt != null) return dt;
      try {
        return DateTime.parse(raw);
      } catch (_) {}
    }
    return null;
  }

  String _groupKeyFor(Map<String, dynamic> appt) {
    final raw = appt['date'];
    final dt = _parseDateField(raw);
    if (dt != null) return dt.toIso8601String().split('T').first;
    final s =
        (appt['date'] ?? appt['startDate'] ?? appt['day'] ?? '').toString();
    return s.isEmpty ? 'unknown' : s;
  }

  String _sanitizePhone(String? raw) {
    if (raw == null) return '';
    final cleaned = raw.replaceAll(RegExp(r'[^\d]'), '');
    final digits = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? '' : cleaned;
  }

  String _extractName(Map<String, dynamic> appt) {
    String? tryTopLevel(List<String> keys) {
      for (final k in keys) {
        final v = appt[k];
        if (v == null) continue;
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    String? tryMap(Map m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v == null) continue;
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    Map<String, dynamic>? findNested() {
      for (final wrap in ['user', 'patient', 'profile', 'owner', 'creator']) {
        final v = appt[wrap];
        if (v is Map<String, dynamic>) return v;
      }
      return null;
    }

    final fullKeys = [
      'fullName',
      'full_name',
      'displayName',
      'display_name',
      'name',
      'patientName',
      'userName',
      'fullname'
    ];
    final firstKeys = [
      'firstName',
      'first_name',
      'givenName',
      'given_name',
      'firstname',
      'fname',
      'first'
    ];
    final lastKeys = [
      'surname',
      'lastName',
      'last_name',
      'familyName',
      'lastname',
      'lname',
      'last'
    ];
    final emailKeys = ['email', 'userEmail', 'emailAddress', 'email_address'];

    final topFull = tryTopLevel(fullKeys);
    if (topFull != null && topFull.isNotEmpty) {
      if (topFull.trim().contains(RegExp(r'\s+'))) return topFull;
    }

    final nested = findNested();
    final nestedFull = nested != null ? tryMap(nested, fullKeys) : null;
    if (nestedFull != null && nestedFull.isNotEmpty) {
      if (nestedFull.trim().contains(RegExp(r'\s+'))) return nestedFull;
    }

    final topFirst = tryTopLevel(firstKeys);
    final topLast = tryTopLevel(lastKeys);
    final nestedFirst = nested != null ? tryMap(nested, firstKeys) : null;
    final nestedLast = nested != null ? tryMap(nested, lastKeys) : null;

    final first = topFirst ?? nestedFirst ?? (topFull?.trim());
    final last = topLast ?? nestedLast;

    if ((first != null && first.isNotEmpty) ||
        (last != null && last.isNotEmpty)) {
      final combined = '${first ?? ''} ${last ?? ''}'.trim();
      if (combined.isNotEmpty) return combined;
    }

    if (topFull != null && topFull.isNotEmpty) return topFull;
    if (nestedFull != null && nestedFull.isNotEmpty) return nestedFull;

    final email = tryTopLevel(emailKeys) ??
        (nested != null ? tryMap(nested, emailKeys) : null);
    if (email != null && email.contains('@')) {
      final local = email.split('@').first.replaceAll(RegExp(r'[._\-\+]'), ' ');
      final parts =
          local.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        final pretty = parts
            .map((p) =>
                p[0].toUpperCase() + (p.length > 1 ? p.substring(1) : ''))
            .join(' ');
        return pretty;
      }
    }

    return 'Unknown';
  }

  String? _extractPhone(Map<String, dynamic> appt) {
    final candidates = [
      appt['phone'],
      appt['phoneNumber'],
      appt['phone_number'],
      appt['contact'],
      appt['contactNumber'],
      appt['contact_number'],
      appt['mobile'],
      appt['tel']
    ];
    for (final c in candidates) {
      if (c == null) continue;
      final sanitized = _sanitizePhone(c.toString());
      if (sanitized.isNotEmpty) return c.toString();
    }
    return null;
  }

  Widget _buildEmpty() {
    return RefreshIndicator(
      onRefresh: () async =>
          await Future.delayed(const Duration(milliseconds: 200)),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(child: Icon(Icons.event_busy, size: 84, color: Colors.grey)),
          SizedBox(height: 12),
          Center(
              child: Text("No appointments scheduled",
                  style: TextStyle(fontSize: 18, color: Colors.black54))),
        ],
      ),
    );
  }

  Future<void> _showReasonDialog({
    required String title,
    required String reason,
    required String time,
    String? phone,
    required bool attended,
    required String? docId,
  }) async {
    const adminColor = Color.fromARGB(255, 40, 56, 98);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: Row(
            children: [
              Icon(Icons.event_note, color: adminColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      color: adminColor, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Time: $time',
                  style: const TextStyle(color: Colors.black87)),
              const SizedBox(height: 8),
              const Text('Reason:',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(reason.isNotEmpty ? reason : 'No reason provided',
                  style: const TextStyle(color: Colors.black54)),
              if (phone != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 16, color: Colors.black54),
                    const SizedBox(width: 6),
                    Text(phone, style: const TextStyle(color: Colors.black87)),
                  ],
                )
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: attended
                          ? Colors.green.withOpacity(0.12)
                          : Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                            attended
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 16,
                            color: attended ? Colors.green : Colors.red),
                        const SizedBox(width: 8),
                        Text(attended ? 'Attended' : 'Not attended',
                            style: TextStyle(
                                color: attended
                                    ? Colors.green[800]
                                    : Colors.red[800],
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[700],
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (phone != null)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  _callPatient(phone);
                },
                child: const Text('Call'),
              ),
            // Delete button (destructive)
            if (docId != null)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[600],
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                onPressed: () async {
                  Navigator.of(context).pop();
                  try {
                    await FirebaseFirestore.instance
                        .collection('appointments')
                        .doc(docId)
                        .delete();
                    if (!mounted) return;
                    final snack = SnackBar(
                      content: const Text('Appointment deleted'),
                      backgroundColor: Colors.green[600],
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    );
                    ScaffoldMessenger.of(this.context).showSnackBar(snack);
                  } catch (_) {
                    if (!mounted) return;
                    final err = SnackBar(
                      content: const Text('Unable to delete appointment'),
                      backgroundColor: Colors.red[600],
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    );
                    ScaffoldMessenger.of(this.context).showSnackBar(err);
                  }
                },
                child:
                    const Text('Delete', style: TextStyle(color: Colors.white)),
              ),
            if (docId != null)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: adminColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                onPressed: () async {
                  // close dialog first (dialog context) then update; guard before using outer context.
                  Navigator.of(context).pop();
                  try {
                    await FirebaseFirestore.instance
                        .collection('appointments')
                        .doc(docId)
                        .update({'attended': !attended});
                    if (!mounted) return;
                    final snack = SnackBar(
                      content: Text(
                          attended ? 'Marked not attended' : 'Marked attended'),
                      backgroundColor: Colors.green[600],
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    );
                    ScaffoldMessenger.of(this.context).showSnackBar(snack);
                  } catch (_) {
                    if (!mounted) return;
                    final err = SnackBar(
                      content: const Text('Unable to update'),
                      backgroundColor: Colors.red[600],
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    );
                    ScaffoldMessenger.of(this.context).showSnackBar(err);
                  }
                },
                child: Text(
                  attended ? 'Unmark' : 'Mark attended',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const adminColor = Color.fromARGB(255, 40, 56, 98);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Scheduled Appointments",
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (!mounted) return;
            Get.offAll(() => const AdminHomePage());
          },
        ),
        backgroundColor: adminColor,
      ),
      // make background match admin gradient
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF2FF), Color(0xFFF7FBFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection("appointments")
                .orderBy("date")
                .orderBy("time")
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final rawDocs = snapshot.data?.docs ?? [];
              final data = rawDocs.map((doc) {
                final m = Map<String, dynamic>.from(doc.data());
                m['_id'] = doc.id;
                return m;
              }).toList();

              if (data.isEmpty) return _buildEmpty();

              // Group by normalized date key (yyyy-MM-dd)
              final Map<String, List<Map<String, dynamic>>> grouped = {};
              for (var appt in data) {
                final key = _groupKeyFor(appt);
                grouped.putIfAbsent(key, () => []).add(appt);
              }

              final entries = grouped.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key));

              return RefreshIndicator(
                onRefresh: () async =>
                    await Future.delayed(const Duration(milliseconds: 200)),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: entries.length,
                  itemBuilder: (context, idx) {
                    final key = entries[idx].key;
                    final appointments = entries[idx].value;
                    DateTime? headerDt;
                    try {
                      headerDt = DateTime.tryParse(key);
                    } catch (_) {
                      headerDt = null;
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 14),
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: adminColor.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              headerDt != null
                                  ? DateFormat('EEEE, MMM d, yyyy')
                                      .format(headerDt)
                                  : key,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                          ...appointments.map((appt) {
                            final providedName = _extractName(appt);
                            final providedPhone = _extractPhone(appt);
                            final time =
                                appt['time'] ?? appt['startTime'] ?? '';
                            final period = appt['period'] ?? '';
                            final reason = (appt['reason'] ?? '').toString();
                            final uidCandidate = (appt['bookedBy'] ??
                                    appt['uid'] ??
                                    appt['userId'] ??
                                    appt['createdBy'])
                                ?.toString();
                            final docId = appt['_id']?.toString();
                            final attended =
                                (appt['attended'] ?? false) as bool;

                            return FutureBuilder<Map<String, String>?>(
                              future: (providedName != 'Unknown' &&
                                      providedPhone != null)
                                  ? Future.value(null)
                                  : _fetchUserInfoByUid(uidCandidate),
                              builder: (context, snap) {
                                final fetched = snap.data;
                                final displayName = (providedName != 'Unknown')
                                    ? providedName
                                    : (fetched != null &&
                                            fetched['name'] != null
                                        ? fetched['name']!
                                        : 'Unknown');
                                final phone = providedPhone ??
                                    (fetched != null ? fetched['phone'] : null);

                                final initials = displayName
                                    .split(' ')
                                    .where((s) => s.isNotEmpty)
                                    .map((s) => s[0].toUpperCase())
                                    .take(2)
                                    .join();

                                final displayTime =
                                    '${time?.toString() ?? ''} ${period ?? ''}'
                                        .trim();

                                // Opacity for not-attended appointments
                                final double tileOpacity =
                                    attended ? 1.0 : 0.62;
                                final double accentOpacity =
                                    attended ? 0.12 : 0.06;
                                final double avatarOpacity =
                                    attended ? 1.0 : 0.45;

                                // New, cleaner tile w/ admin styling.
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _showReasonDialog(
                                    title: displayName,
                                    reason: reason,
                                    time: displayTime,
                                    phone: phone,
                                    attended: attended,
                                    docId: docId,
                                  ),
                                  child: Opacity(
                                    opacity: tileOpacity,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.04),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          )
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          // left accent
                                          Container(
                                            width: 6,
                                            height: 86,
                                            decoration: BoxDecoration(
                                              color: adminColor
                                                  .withOpacity(accentOpacity),
                                              borderRadius:
                                                  const BorderRadius.only(
                                                      topLeft:
                                                          Radius.circular(12),
                                                      bottomLeft:
                                                          Radius.circular(12)),
                                            ),
                                          ),
                                          Expanded(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 12),
                                              child: Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 28,
                                                    backgroundColor:
                                                        adminColor.withOpacity(
                                                            avatarOpacity),
                                                    child: Text(initials,
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700)),
                                                  ),
                                                  const SizedBox(width: 14),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Text(displayName,
                                                            style: const TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700)),
                                                        const SizedBox(
                                                            height: 6),
                                                        Row(
                                                          children: [
                                                            const Icon(
                                                                Icons
                                                                    .access_time,
                                                                size: 14,
                                                                color: Colors
                                                                    .black54),
                                                            const SizedBox(
                                                                width: 6),
                                                            Text(displayTime,
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .black87)),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const Icon(
                                                      Icons.chevron_right,
                                                      color: Colors.black26),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
