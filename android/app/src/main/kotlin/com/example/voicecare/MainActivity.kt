package com.voicecare

import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
  private var mediaPlayer: MediaPlayer? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "voicecare/audio")
      .setMethodCallHandler { call, result ->
        if (call.method == "playBeep") {
          try {
            mediaPlayer?.release()
            // ensure beep_short.mp3 is in android/app/src/main/res/raw
            mediaPlayer = MediaPlayer.create(this, R.raw.beep_short)
            mediaPlayer?.setOnCompletionListener { mp ->
              mp.release()
              mediaPlayer = null
            }
            mediaPlayer?.start()
            result.success(null)
          } catch (e: Exception) {
            result.error("PLAY_ERROR", e.message, null)
          }
        } else {
          result.notImplemented()
        }
      }
  }

  override fun onDestroy() {
    mediaPlayer?.release()
    super.onDestroy()
  }
}
