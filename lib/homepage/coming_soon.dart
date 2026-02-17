import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:voicecare/homepage/home_page.dart';

class ComingSoonPage extends StatefulWidget {
  const ComingSoonPage({super.key});

  @override
  State<ComingSoonPage> createState() => _ComingSoonPageState();
}

class _ComingSoonPageState extends State<ComingSoonPage>
    with TickerProviderStateMixin {
  // scale animation for logo
  late final AnimationController _scaleCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  late final Animation<double> _scale =
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut);

  // countdown controller (visual blue ring + numeric countdown)
  static const int _countdownSeconds = 8;
  late final AnimationController _countdownCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: _countdownSeconds));

  @override
  void initState() {
    super.initState();
    _scaleCtrl.forward();
    // start countdown and navigate home on completion
    _countdownCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        try {
          Get.offAll(() => const HomePage());
        } catch (_) {}
      }
    });
    _countdownCtrl.forward();
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    _countdownCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Replace with your app logo path and ensure it's listed in pubspec.yaml
    const logoPath = 'lib/assets/registration_assets/user_reg_wallpaper.png';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF283862),
        centerTitle: true,
        title: const Text('Coming Soon', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Get.offAll(() => const HomePage()),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Stack logo + circular countdown ring
                AnimatedBuilder(
                  animation: Listenable.merge([_scaleCtrl, _countdownCtrl]),
                  builder: (context, _) {
                    final progress = _countdownCtrl.value; // 0.0 -> 1.0
                    final remaining = (_countdownSeconds * (1.0 - progress))
                        .ceil()
                        .clamp(0, _countdownSeconds);
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // blue circular ring (decreasing)
                        SizedBox(
                          width: 150,
                          height: 150,
                          child: CircularProgressIndicator(
                            value: 1.0 - progress,
                            strokeWidth: 6,
                            color: const Color(0xFF283862),
                            backgroundColor: const Color(0xFFE8EFFC),
                          ),
                        ),
                        // logo with scale animation
                        ScaleTransition(
                          scale: _scale,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                logoPath,
                                width: 96,
                                height: 96,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const SizedBox(
                                  width: 96,
                                  height: 96,
                                  child: Icon(Icons.approval,
                                      size: 56, color: Color(0xFF283862)),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // seconds remaining text
                        Positioned(
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$remaining s',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2E66D6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 22),
                const Text(
                  'Something beautiful is on the way',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF283862),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'We are working on this feature. Stay tuned — it will be available soon. Love, VoiceCare Team',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () => Get.offAll(() => const HomePage()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF283862),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Back to Home',
                          style: TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(width: 12),
                    // OutlinedButton(
                    //   onPressed: () {
                    //     // restart the countdown
                    //     _countdownCtrl.reset();
                    //     _countdownCtrl.forward();
                    //   },
                    //   style: OutlinedButton.styleFrom(
                    //     side: const BorderSide(color: Color(0xFF2E66D6)),
                    //     shape: RoundedRectangleBorder(
                    //         borderRadius: BorderRadius.circular(8)),
                    //   ),
                    //   child: const Text('Stay',
                    //       style: TextStyle(color: Color(0xFF2E66D6))),
                    // ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
