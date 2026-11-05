package vn.avdoremon.g_english_motion

import android.os.Build
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The speech_to_text plugin cannot tell whether a recogniser that runs
        // fully on the device exists, and falls back to the default (possibly
        // network) recogniser when it does not. SayIt asks the OS first and
        // stays hidden unless this says yes (API 31+).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "vn.avdoremon.g_english_motion/speech",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isOnDeviceRecognitionAvailable" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
                )
                else -> result.notImplemented()
            }
        }
    }
}
