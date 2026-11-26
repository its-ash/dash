package com.itsash.dash

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import org.json.JSONObject

/**
 * Foreground service (type `location`) that keeps GPS on while a trip runs, so
 * recording continues with the screen off or the app in the background.
 *
 * Uses the platform `LocationManager` GPS provider (no Google Play services).
 * Every fix is appended to [TrackLog]; the notification shows live speed and
 * distance. Pausing keeps the notification but stops writing fixes.
 *
 * Auto-stop: when [NativePrefs.autoStopMs] is set and the car has not moved for
 * that long (no moving fix, or no fix at all, e.g. in a garage), the trip ends
 * through [TripControl.endInBackground] and Dart saves it on its next run.
 */
class TrackingService : Service() {

    private lateinit var prefs: NativePrefs
    private lateinit var nm: NotificationManager
    private var lm: LocationManager? = null
    private var listening = false

    private var lastLoc: Location? = null
    private var distanceM = 0.0
    private var lastText = ""
    private var lastMovingMs = 0L
    private val handler = Handler(Looper.getMainLooper())
    private val autoStopCheck = object : Runnable {
        override fun run() {
            checkAutoStop()
            handler.postDelayed(this, AUTO_STOP_CHECK_MS)
        }
    }

    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) = handle(location)
        override fun onLocationChanged(locations: MutableList<Location>) = locations.forEach { handle(it) }

        @Deprecated("Required on API < 29")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        prefs = NativePrefs(this)
        nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Trip recording", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shows your live speed while a trip is being recorded."
                setShowBadge(false)
            },
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // A null intent means Android restarted us after killing the process.
        if (!prefs.tripActive) {
            // Must still call startForeground() when started with startForegroundService().
            if (startForegroundSafely(notification("Dash", "Trip ended"))) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            }
            prefs.tripActive = false
            stopSelf()
            return START_NOT_STICKY
        }
        if (!startForegroundSafely(notification(title(), "Waiting for GPS..."))) {
            prefs.tripActive = false
            stopSelf()
            return START_NOT_STICKY
        }
        if (lastMovingMs == 0L) lastMovingMs = System.currentTimeMillis()
        handler.removeCallbacks(autoStopCheck)
        handler.postDelayed(autoStopCheck, AUTO_STOP_CHECK_MS)
        startListening()
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(autoStopCheck)
        stopListening()
        running = false
        super.onDestroy()
    }

    private fun startListening() {
        if (listening) return
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        lm = manager
        try {
            manager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0f, listener, Looper.getMainLooper())
            listening = true
            running = true
        } catch (_: SecurityException) {
            // Permission was revoked: nothing to record.
            prefs.tripActive = false
            stopSelf()
        } catch (_: IllegalArgumentException) {
            // Device has no GPS provider.
            prefs.tripActive = false
            stopSelf()
        }
    }

    private fun stopListening() {
        if (!listening) return
        runCatching { lm?.removeUpdates(listener) }
        listening = false
    }

    private fun handle(loc: Location) {
        if (!prefs.tripActive) {
            stopSelf()
            return
        }
        if (prefs.paused) {
            lastLoc = null
            lastMovingMs = System.currentTimeMillis()
            update(title(), "Paused")
            return
        }
        if (loc.hasSpeed() && loc.speed >= MOVING_MS) lastMovingMs = System.currentTimeMillis()
        // Distance for the notification only; the exact figure is computed in Dart.
        val prev = lastLoc
        if (prev != null && loc.hasAccuracy() && loc.accuracy <= 30f && loc.hasSpeed() && loc.speed > 0.42f) {
            distanceM += prev.distanceTo(loc)
        }
        lastLoc = loc
        runCatching { TrackLog.append(this, JSONObject(loc.toFixMap()).toString()) }

        val speed = if (loc.hasSpeed()) loc.speed.toDouble() else 0.0
        val shown = if (speed < 0.42) 0.0 else speed * prefs.speedFactor
        val dist = distanceM / prefs.distDivisor
        update(
            "${Math.round(shown)} ${prefs.speedLabel}",
            "${"%.2f".format(dist)} ${prefs.distLabel} this trip",
        )
    }

    private fun checkAutoStop() {
        val limit = prefs.autoStopMs
        if (limit <= 0 || !prefs.tripActive || prefs.paused) return
        if (System.currentTimeMillis() - lastMovingMs < limit) return
        TripControl.endInBackground(this, lastMovingMs)
    }

    private fun title() = if (prefs.paused) "Dash: trip paused" else "Dash: recording trip"

    private fun update(title: String, text: String) {
        val key = title + text
        if (key == lastText) return
        lastText = key
        nm.notify(NOTIFICATION_ID, notification(title, text))
    }

    private fun notification(title: String, text: String): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_speed)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_NAVIGATION)
            .build()
    }

    private fun startForegroundSafely(n: Notification): Boolean = try {
        startInForeground(n)
        true
    } catch (_: SecurityException) {
        false
    } catch (_: RuntimeException) {
        false
    }

    private fun startInForeground(n: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    companion object {
        private const val CHANNEL = "trip_recording"
        private const val NOTIFICATION_ID = 21
        private const val AUTO_STOP_CHECK_MS = 30_000L

        /** Faster than this (m/s, about 5 km/h) counts as moving for auto-stop. */
        private const val MOVING_MS = 1.4f

        @Volatile
        var running = false
            private set

        fun start(context: Context) {
            context.startForegroundService(Intent(context, TrackingService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, TrackingService::class.java))
        }
    }
}
