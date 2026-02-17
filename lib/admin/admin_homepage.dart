import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:voicecare/admin/scheduled_appointments.dart';
import 'package:voicecare/admin/amintimeslotpage.dart';
import 'package:voicecare/admin/profile_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:voicecare/homepage/login_page.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  Future<void> _confirmSignOut() async {
    final doSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[700],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 40, 56, 98),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child:
                const Text('Sign out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (doSignOut == true) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {
        // ignore sign-out errors; don't use context here if widget may be disposing
      }
      // only navigate if this widget is still mounted (prevents deactivated-ancestor lookups)
      if (!mounted) return;
      // use Get.offAll without referencing local context
      Get.offAll(() => LoginPage());
    }
  }

  Widget _featureCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required double width,
    required double height,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: width,
          height: height,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.95), color.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Icon(icon, size: 36, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final position = MediaQuery.of(context);
    final double screenWidth = position.size.width;
    final double screenHeight = position.size.height;
    // subtract AppBar + status bar so 25% uses visible area
    final double availableHeight =
        screenHeight - kToolbarHeight - position.padding.top;
    final double cardWidth = screenWidth * 0.99;
    final double cardHeight = availableHeight * 0.22;

    return Scaffold(
      appBar: AppBar(
        title: const Text(" Admin Home Page",
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 40, 56, 98),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _confirmSignOut,
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF2FF), Color(0xFFF7FBFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 900),
                child: Column(
                  children: [
                    const Divider(
                        height: 0.5, thickness: 1, color: Colors.black12),
                    const SizedBox(height: 20),
                    _featureCard(
                      title: 'Create Timeslot',
                      subtitle: 'Add appointment timeslots for users',
                      icon: Icons.calendar_month,
                      color: const Color.fromARGB(255, 40, 56, 98),
                      onTap: () => Get.to(() => const AdminTimeslotPage()),
                      width: cardWidth,
                      height: cardHeight,
                    ),

                    _featureCard(
                      title: 'Scheduled Appointments',
                      subtitle: 'View and manage scheduled appointments',
                      icon: Icons.event_available,
                      color: const Color(0xFF566471),
                      onTap: () => Get.to(() => const ScheduledAppointments()),
                      width: cardWidth,
                      height: cardHeight,
                    ),
                    _featureCard(
                      title: 'Profile',
                      subtitle: 'View and manage your admin profile',
                      icon: Icons.person,
                      color: const Color.fromARGB(255, 70, 130, 180),
                      onTap: () => Get.to(() => const AdminProfilePage()),
                      width: cardWidth,
                      height: cardHeight,
                    ),
                    const SizedBox(height: 24),
                    // optional small footer / help hint
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.info_outline,
                            size: 14, color: Colors.black54),
                        SizedBox(width: 8),
                        Text('Tap a card to manage items',
                            style: TextStyle(color: Colors.black54)),
                      ],
                    ),
                    const SizedBox(height: 24),
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
