package com.itsash.dash

import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.GnssStatus
import android.location.Location
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.net.Uri
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
 *   `resumeTrip`, `stopTrip`, `tripActive`, `readTrack`, `openUrl(url)`, `tripStatus`
 *   ({active, pending}), `pendingTracks` ([{name, log}]), `deletePending(name)`,
 *   `setAutoStop(ms)`, `updateWidget({odometer, lastTrip})`.
 * - `com.itsash.dash/fixes` (events): one map per GPS fix (keys t, la, lo, al, sp, ac, be).
 * - `com.itsash.dash/gnss` (events): satellite counts on each GNSS status (keys v = in view,
 *   u = used in fix). Only fires while the GPS is running, i.e. while `fixes` is listened to.
 * - `com.itsash.dash/accel` (events): accelerometer averaged over ~125 ms windows, phone frame,
 *   m/s² (keys t, x/y/z = acceleration without gravity, gx/gy/gz = gravity). Errors with
 *   `no_sensor` when the phone has no accelerometer.
 */
class MainActivity : FlutterActivity() {
    private lateinit var prefs: NativePrefs

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = NativePrefs(applicationContext)
        handleWidgetIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleWidgetIntent(intent)
    }

    /** Start trip from the home-screen widget. Dart picks the trip up from the log. */
    private fun handleWidgetIntent(intent: Intent?) {
        if (intent?.action != DashWidget.ACTION_START_TRIP) return
        intent.action = Intent.ACTION_MAIN
        if (prefs.tripActive) return
        val granted = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!granted) return // Dash shows its own permission prompt.
        runCatching { TripControl.start(this) }
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
                    try {
                        result.success(TripControl.start(applicationContext))
                    } catch (e: Exception) {
                        result.error("service", e.message, null)
                    }
                }
                "pauseTrip" -> {
                    val now = System.currentTimeMillis()
                    TrackLog.marker(applicationContext, "pause", now)
                    prefs.paused = true
                    DashWidget.refresh(applicationContext)
                    result.success(now)
                }
                "resumeTrip" -> {
                    val now = System.currentTimeMillis()
                    TrackLog.marker(applicationContext, "resume", now)
                    prefs.paused = false
                    DashWidget.refresh(applicationContext)
                    result.success(now)
                }
                "stopTrip" -> {
                    prefs.tripActive = false
                    prefs.paused = false
                    TrackingService.stop(applicationContext)
                    TrackLog.clear(applicationContext)
                    DashWidget.refresh(applicationContext)
                    result.success(null)
                }
                "tripStatus" -> result.success(
                    mapOf("active" to prefs.tripActive, "pending" to TrackLog.pendingCount(applicationContext)),
                )
                "pendingTracks" -> result.success(TrackLog.pending(applicationContext))
                "deletePending" -> {
                    (call.arguments as? String)?.let { TrackLog.deletePending(applicationContext, it) }
                    DashWidget.refresh(applicationContext)
                    result.success(null)
                }
                "setAutoStop" -> {
                    prefs.autoStopMs = (call.arguments as? Number)?.toLong() ?: 0L
                    result.success(null)
                }
                "updateWidget" -> {
                    val a = call.arguments as? Map<*, *>
                    prefs.widgetOdometer = a?.get("odometer") as? String ?: ""
                    prefs.widgetLastTrip = a?.get("lastTrip") as? String ?: ""
                    DashWidget.refresh(applicationContext)
                    result.success(null)
                }
                "tripActive" -> result.success(prefs.tripActive)
                "readTrack" -> result.success(TrackLog.read(applicationContext))
                "openUrl" -> {
                    val url = call.arguments as? String
                    val ok = url != null && runCatching {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }.isSuccess
                    result.success(ok)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "$CHANNEL/fixes").setStreamHandler(FixStreamHandler())
        EventChannel(messenger, "$CHANNEL/gnss").setStreamHandler(GnssStreamHandler())
        EventChannel(messenger, "$CHANNEL/accel").setStreamHandler(AccelStreamHandler())
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

    /** Satellite counts from [GnssStatus] while Dart listens. */
    private inner class GnssStreamHandler : EventChannel.StreamHandler {
        private var callback: GnssStatus.Callback? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val cb = object : GnssStatus.Callback() {
                override fun onSatelliteStatusChanged(status: GnssStatus) {
                    var used = 0
                    for (i in 0 until status.satelliteCount) if (status.usedInFix(i)) used++
                    events.success(mapOf("v" to status.satelliteCount, "u" to used))
                }

                override fun onStopped() {
                    events.success(mapOf("v" to 0, "u" to 0))
                }
            }
            try {
                @Suppress("DEPRECATION")
                lm.registerGnssStatusCallback(cb, Handler(Looper.getMainLooper()))
                callback = cb
            } catch (e: SecurityException) {
                // No permission yet: the fixes stream reports it; counts just stay empty.
            }
        }

        override fun onCancel(arguments: Any?) {
            val cb = callback ?: return
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            runCatching { lm.unregisterGnssStatusCallback(cb) }
            callback = null
        }
    }

    /**
     * Linear acceleration and gravity for the g-force meter. Uses the fused
     * LINEAR_ACCELERATION + GRAVITY sensors when the phone has them, else the raw
     * accelerometer with a low-pass filter for gravity.
     */
    private inner class AccelStreamHandler : EventChannel.StreamHandler {
        private var listener: SensorEventListener? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            val sm = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
            val linear = sm?.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
            val gravity = sm?.getDefaultSensor(Sensor.TYPE_GRAVITY)
            val raw = sm?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            val fused = linear != null && gravity != null
            if (sm == null || (!fused && raw == null)) {
                events.error("no_sensor", "This phone has no accelerometer.", null)
                return
            }
            val lin = FloatArray(3)
            val grav = FloatArray(3)
            var haveGrav = false
            val sum = DoubleArray(3)
            var n = 0
            var windowStart = 0L
            val l = object : SensorEventListener {
                override fun onSensorChanged(e: SensorEvent) {
                    val v = e.values
                    when (e.sensor.type) {
                        Sensor.TYPE_GRAVITY -> {
                            for (i in 0..2) grav[i] = v[i]
                            haveGrav = true
                            return
                        }
                        Sensor.TYPE_LINEAR_ACCELERATION -> for (i in 0..2) lin[i] = v[i]
                        Sensor.TYPE_ACCELEROMETER -> {
                            if (!haveGrav) {
                                for (i in 0..2) grav[i] = v[i]
                                haveGrav = true
                            } else {
                                for (i in 0..2) grav[i] += 0.03f * (v[i] - grav[i])
                            }
                            for (i in 0..2) lin[i] = v[i] - grav[i]
                        }
                        else -> return
                    }
                    if (!haveGrav) return
                    for (i in 0..2) sum[i] += lin[i].toDouble()
                    n++
                    val now = SystemClock.elapsedRealtime()
                    if (windowStart == 0L) windowStart = now
                    if (now - windowStart >= 125) {
                        events.success(
                            mapOf(
                                "t" to System.currentTimeMillis(),
                                "x" to sum[0] / n, "y" to sum[1] / n, "z" to sum[2] / n,
                                "gx" to grav[0].toDouble(), "gy" to grav[1].toDouble(), "gz" to grav[2].toDouble(),
                            ),
                        )
                        sum.fill(0.0)
                        n = 0
                        windowStart = now
                    }
                }

                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            }
            val ok = if (fused) {
                sm.registerListener(l, linear!!, SensorManager.SENSOR_DELAY_GAME) &&
                    sm.registerListener(l, gravity!!, SensorManager.SENSOR_DELAY_GAME)
            } else {
                sm.registerListener(l, raw!!, SensorManager.SENSOR_DELAY_GAME)
            }
            listener = l
            if (!ok) events.error("no_sensor", "The accelerometer could not be started.", null)
        }

        override fun onCancel(arguments: Any?) {
            val l = listener ?: return
            (getSystemService(Context.SENSOR_SERVICE) as? SensorManager)?.unregisterListener(l)
            listener = null
        }
    }

    private companion object {
        const val CHANNEL = "com.itsash.dash"
    }
}
