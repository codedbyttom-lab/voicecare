class SpeechGuard {
  /// When true, STT code should wait until this becomes false before initializing/listening.
  static bool ttsSpeaking = false;

  /// True only on the very first cold start of the app process.
  /// After the initial delay this should be set to false so hot-reloads don't re-run the delay.
  static bool coldStart = true;

  /// App process start time — used to reliably compute a cold-start delay window.
  /// Initialized once when the app loads.
  static final DateTime appStartTime = DateTime.now();

  // Gate for global STT start. Only true when you explicitly allow listening.
  static bool allowListening = true;

  // new: temporary suppression to prevent auto-restarts right after sign-out
  static bool suppressAutoStart = false;

  /// Put global speech flags into a safe "no audio / no auto-start" state.
  /// Use before navigation/sign-out to avoid leftover native STT/TTS activity.
  static Future<void> applySuppressiveGuards({int settleMs = 80}) async {
    try {
      allowListening = false;
    } catch (_) {}
    try {
      ttsSpeaking = false;
    } catch (_) {}
    try {
      suppressAutoStart = true;
    } catch (_) {}
    // small breathing room for native layer to settle
    await Future.delayed(Duration(milliseconds: settleMs));
  }

  /// Clear the suppression so pages that should auto-start can enable listening again.
  static Future<void> clearSuppression({int settleMs = 80}) async {
    try {
      suppressAutoStart = false;
    } catch (_) {}
    // small breathing room for native layer to settle
    await Future.delayed(Duration(milliseconds: settleMs));
  }
}
