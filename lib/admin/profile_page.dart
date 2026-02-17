import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:voicecare/admin/amintimeslotpage.dart';
import 'package:voicecare/homepage/login_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminProfilePage extends StatefulWidget {
  const AdminProfilePage({super.key});

  @override
  State<AdminProfilePage> createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<AdminProfilePage> {
  User? _user;
  Future<int>? _timeslotCount;
  Future<List<Map<String, dynamic>>>? _recentTimeslots;
  // Branding contact
  final String _devEmail = 'codedbyttom@gmail.com';
  final String _devWebsite = 'https://codedbyttom.work'; // replace with actual
  final String _devGithub =
      'https://github.com/codedbyttom'; // replace with actual
  final String _appVersion = 'v1.0';

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _loadStats();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _loadStats() {
    _timeslotCount = FirebaseFirestore.instance
        .collection('timeslots')
        .get()
        .then((q) => q.size);

    _recentTimeslots = FirebaseFirestore.instance
        .collection('timeslots')
        .orderBy('createdAt', descending: true)
        .limit(5)
        .get()
        .then((q) => q.docs.map((d) {
              final m = d.data();

              // prefer explicit name fields, then displayName, then email, then uid
              String? addedByName;
              final first = (m['createdByFirstName'] as String?)?.trim();
              final last = (m['createdByLastName'] as String?)?.trim();
              final display = (m['createdByDisplayName'] as String?)?.trim();
              final email = (m['createdByEmail'] as String?)?.trim();
              final uid = (m['createdByUid'] as String?)?.trim();

              if ((first?.isNotEmpty ?? false) || (last?.isNotEmpty ?? false)) {
                addedByName =
                    '${first ?? ''}${(first?.isNotEmpty ?? false) ? ' ' : ''}${last ?? ''}'
                        .trim();
              } else if (display?.isNotEmpty ?? false) {
                addedByName = display;
              } else if (email?.isNotEmpty ?? false) {
                addedByName = email;
              } else if (uid?.isNotEmpty ?? false) {
                addedByName = uid;
              } else {
                addedByName = null;
              }

              return {
                'date': m['date'] as String?,
                'time': m['startTime'] as String?,
                'period': m['period'] as String?,
                'addedByFirst': first,
                'addedByLast': last,
                'addedBy': addedByName,
                'createdAt': (m['createdAt'] as Timestamp?)?.toDate(),
              };
            }).toList());
  }

  Future<void> _editDisplayName() async {
    final controller = TextEditingController(text: _user?.displayName ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit display name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _user?.updateDisplayName(controller.text.trim());
        await FirebaseAuth.instance.currentUser?.reload();
        // avoid updating UI if widget has been disposed
        if (!mounted) return;
        setState(() => _user = FirebaseAuth.instance.currentUser);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Display name updated')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Update failed: $e')));
        }
      }
    }
  }

  void _copyUid() {
    final uid = _user?.uid ?? '';
    Clipboard.setData(ClipboardData(text: uid));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('UID copied to clipboard')));
  }

  Future<void> _confirmSignOut() async {
    final doSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: const [
            Icon(Icons.logout, color: Color.fromARGB(255, 40, 56, 98)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sign out',
                style: TextStyle(
                    color: Color.fromARGB(255, 40, 56, 98),
                    fontWeight: FontWeight.w700),
              ),
            )
          ],
        ),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 40, 56, 98),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child:
                const Text('Sign out', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );

    if (doSignOut == true) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      if (!mounted) {
        // If already unmounted, still attempt Get navigation (Get can operate without context)
        try {
          Get.offAll(() => LoginPage());
        } catch (_) {}
        return;
      }
      Get.offAll(() => LoginPage());
    }
  }

  void _refreshStats() {
    _loadStats();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Stats refreshed'), duration: Duration(seconds: 1)));
  }

  Future<void> _launchEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _devEmail,
      queryParameters: {'subject': 'VoiceCare support'},
    );
    try {
      if (!await launchUrl(uri)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open email client')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email client')));
    }
  }

  Future<void> _launchUrlString(String url) async {
    final uri = Uri.parse(url);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not open link')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _user?.displayName ?? 'Administrator';
    final email = _user?.email ?? 'No email';
    final uid = _user?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 40, 56, 98),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor:
                              const Color.fromARGB(255, 224, 230, 245),
                          child: Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : 'A',
                            style: const TextStyle(
                                color: Color.fromARGB(255, 40, 56, 98),
                                fontSize: 36,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(displayName,
                                        style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            color: Color.fromARGB(
                                                255, 40, 56, 98))),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit,
                                        color: Color.fromARGB(255, 40, 56, 98)),
                                    onPressed: _editDisplayName,
                                    tooltip: 'Edit display name',
                                  )
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(email,
                                  style:
                                      const TextStyle(color: Colors.black54)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Chip(
                                    backgroundColor: Colors.green.shade50,
                                    avatar: const Icon(Icons.shield,
                                        color: Colors.green),
                                    label: const Text('Admin'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: _copyUid,
                                    icon: const Icon(Icons.copy, size: 18),
                                    label: const Text('Copy UID'),
                                  )
                                ],
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Quick stats  actions
                    Row(
                      children: [
                        // Quick stats card — using the same color as homepage card (app blue)
                        Expanded(
                          child: Card(
                            color: const Color(0xFF566471),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Quick stats',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                  const SizedBox(height: 8),
                                  FutureBuilder<int>(
                                    future: _timeslotCount,
                                    builder: (context, snap) {
                                      final val = snap.hasData
                                          ? snap.data.toString()
                                          : '—';
                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Total timeslots',
                                              style: const TextStyle(
                                                  color: Colors.white70)),
                                          Text(val,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white)),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Last sign in: ${_user?.metadata.lastSignInTime != null ? DateFormat.yMMMd().add_jm().format(_user!.metadata.lastSignInTime!) : 'Unknown'}',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Refresh card — same size/color as quick stats
                        Expanded(
                          child: Card(
                            color: const Color.fromARGB(255, 40, 56, 98),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                            child: SizedBox(
                              height: 120,
                              child: Center(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.refresh,
                                      color: Color.fromARGB(255, 40, 56, 98)),
                                  label: const Text('Refresh',
                                      style: TextStyle(
                                          color:
                                              Color.fromARGB(255, 40, 56, 98))),
                                  onPressed: _refreshStats,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Recent timeslots (more compact & safe list)
                    Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Recent timeslots',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: _recentTimeslots,
                              builder: (context, snap) {
                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Center(
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                  );
                                }

                                final list = snap.data ?? [];
                                if (list.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Text('No recent timeslots',
                                        style:
                                            TextStyle(color: Colors.black54)),
                                  );
                                }

                                return ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: list.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final m = list[index];
                                    final created = m['createdAt'] as DateTime?;
                                    final when = created != null
                                        ? DateFormat.yMMMd()
                                            .add_jm()
                                            .format(created)
                                        : (m['date'] ?? '');

                                    final first =
                                        (m['addedByFirst'] as String?) ?? '';
                                    final last =
                                        (m['addedByLast'] as String?) ?? '';
                                    final fallback =
                                        (m['addedBy'] as String?) ?? 'Unknown';
                                    final addedBy = (first.isNotEmpty ||
                                            last.isNotEmpty)
                                        ? '${first}${(first.isNotEmpty && last.isNotEmpty) ? ' ' : ''}$last'
                                        : fallback;

                                    // initials for avatar
                                    String initials = '';
                                    if (first.isNotEmpty) initials = first[0];
                                    if (last.isNotEmpty) initials = (last[0]);
                                    if (initials.isEmpty &&
                                        fallback.isNotEmpty) {
                                      initials = fallback
                                          .trim()
                                          .split(' ')
                                          .map((s) => s.isNotEmpty ? s[0] : '')
                                          .take(2)
                                          .join();
                                    }
                                    if (initials.isEmpty) initials = 'A';

                                    final dateLabel =
                                        (m['date'] as String?) ?? '';
                                    final timeLabel =
                                        (m['time'] as String?) ?? '';
                                    final periodLabel =
                                        (m['period'] as String?) ?? '';

                                    return ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                      leading: CircleAvatar(
                                        radius: 20,
                                        backgroundColor:
                                            Colors.blueGrey.shade50,
                                        child: Text(initials.toUpperCase(),
                                            style: const TextStyle(
                                                color: Color.fromARGB(
                                                    255, 40, 56, 98),
                                                fontWeight: FontWeight.w700)),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              dateLabel.isNotEmpty
                                                  ? dateLabel
                                                  : '—',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          if (timeLabel.isNotEmpty)
                                            Chip(
                                              label: Text(timeLabel,
                                                  style: const TextStyle(
                                                      fontSize: 12)),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          if (periodLabel.isNotEmpty)
                                            const SizedBox(width: 6),
                                          if (periodLabel.isNotEmpty)
                                            Text('($periodLabel)',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.black54)),
                                        ],
                                      ),
                                      subtitle: Text(
                                          'Added by: $addedBy • $when',
                                          style: const TextStyle(fontSize: 12)),
                                    );
                                  },
                                );
                              },
                            )
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
