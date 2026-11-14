package com.itsash.dash

import android.content.Context
import android.content.Intent
import android.location.Location
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Channels (names match `lib/platform/dash_platform.dart`):
 * - `com.itsash.dash/device` (method): `keepScreenOn`, `maxBrightness`, `vibrate(ms)`, `beep`,
 *   `gpsEnabled`, `openLocationSettings`, `setUnit`, `startTrip`, `pauseTrip`,
 *   `resumeTrip`, `stopTrip`, `tripActive`, `readTrack`.
 * - `com.itsash.dash/fixes` (events): one map per GPS fix (keys t, la, lo, al, sp, ac, be).
 */
class MainActivity : FlutterActivity() {
    private lateinit var prefs: NativePrefs

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = NativePrefs(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        prefs = NativePrefs(applicationContext)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "$CHANNEL/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "keepScreenOn" -> {
                    setFlag(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON, call.arguments as? Boolean ?: false)
                    result.success(null)
                }
                "maxBrightness" -> {
                    val on = call.arguments as? Boolean ?: false
                    val lp = window.attributes
                    lp.screenBrightness = if (on) 1f else WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    window.attributes = lp
                    result.success(null)
                }
                "vibrate" -> {
                    vibrate((call.arguments as? Number)?.toLong() ?: 200L)
                    result.success(null)
                }
                "beep" -> {
                    beep()
                    result.success(null)
                }
                "gpsEnabled" -> {
                    val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
                    result.success(runCatching { lm.isProviderEnabled(LocationManager.GPS_PROVIDER) }.getOrDefault(false))
                }
                "openLocationSettings" -> {
                    startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "setUnit" -> {
                    val a = call.arguments as? Map<*, *>
                    prefs.setUnit(
                        a?.get("speedLabel") as? String ?: "km/h",
                        (a?.get("speedFactor") as? Number)?.toDouble() ?: 3.6,
                        a?.get("distLabel") as? String ?: "km",
                        (a?.get("distDivisor") as? Number)?.toDouble() ?: 1000.0,
                    )
                    result.success(null)
                }
                "startTrip" -> {
                    val now = System.currentTimeMillis()
                    TrackLog.clear(applicationContext)
                    TrackLog.marker(applicationContext, "start", now)
                    prefs.paused = false
                    prefs.tripActive = true
                    try {
                        TrackingService.start(applicationContext)
                        result.success(now)
                    } catch (e: Exception) {
                        prefs.tripActive = false
                        TrackLog.clear(applicationContext)
                        result.error("service", e.message, null)
                    }
                }
                "pauseTrip" -> {
                    val now = System.currentTimeMillis()
                    TrackLog.marker(applicationContext, "pause", now)
                    prefs.paused = true
                    result.success(now)
                }
                "resumeTrip" -> {
                    val now = System.currentTimeMillis()
                    TrackLog.marker(applicationContext, "resume", now)
                    prefs.paused = false
                    result.success(now)
                }
                "stopTrip" -> {
                    prefs.tripActive = false
                    prefs.paused = false
                    TrackingService.stop(applicationContext)
                    TrackLog.clear(applicationContext)
                    result.success(null)
                }
                "tripActive" -> result.success(prefs.tripActive)
                "readTrack" -> result.success(TrackLog.read(applicationContext))
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "$CHANNEL/fixes").setStreamHandler(FixStreamHandler())
    }

    private fun setFlag(flag: Int, on: Boolean) {
        if (on) window.addFlags(flag) else window.clearFlags(flag)
    }

    /** Two short beeps on the alarm stream, so it is heard over music. */
    private fun beep() {
        runCatching {
            val tone = ToneGenerator(AudioManager.STREAM_ALARM, 100)
            tone.startTone(ToneGenerator.TONE_PROP_BEEP2, 350)
            Handler(Looper.getMainLooper()).postDelayed({ tone.release() }, 600)
        }
    }

    @Suppress("DEPRECATION")
    private fun vibrate(ms: Long) {
        val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (vibrator == null || !vibrator.hasVibrator()) return
        vibrator.vibrate(VibrationEffect.createOneShot(ms.coerceIn(20, 1000), VibrationEffect.DEFAULT_AMPLITUDE))
    }

    /** Streams GPS fixes to Dart while the app listens (i.e. while it is visible). */
    private inner class FixStreamHandler : EventChannel.StreamHandler {
        private var listener: LocationListener? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val l = object : LocationListener {
                override fun onLocationChanged(location: Location) {
                    events.success(location.toFixMap())
                }

                override fun onLocationChanged(locations: MutableList<Location>) {
                    locations.forEach { events.success(it.toFixMap()) }
                }

                @Deprecated("Required on API < 29")
                override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                override fun onProviderEnabled(provider: String) {}
                override fun onProviderDisabled(provider: String) {}
            }
            try {
                lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0f, l, Looper.getMainLooper())
                listener = l
            } catch (e: SecurityException) {
                events.error("permission", "Location permission is not granted.", null)
            } catch (e: IllegalArgumentException) {
                events.error("no_gps", "This phone has no GPS.", null)
            }
        }

        override fun onCancel(arguments: Any?) {
            val l = listener ?: return
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            runCatching { lm.removeUpdates(l) }
            listener = null
        }
    }

    private companion object {
        const val CHANNEL = "com.itsash.dash"
    }
}
