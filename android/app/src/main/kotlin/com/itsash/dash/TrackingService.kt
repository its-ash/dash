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
 */
class TrackingService : Service() {

    private lateinit var prefs: NativePrefs
    private lateinit var nm: NotificationManager
    private var lm: LocationManager? = null
    private var listening = false

    private var lastLoc: Location? = null
    private var distanceM = 0.0
    private var lastText = ""

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
            startInForeground(notification("Dash", "Trip ended"))
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        startInForeground(notification(title(), "Waiting for GPS..."))
        startListening()
        return START_STICKY
    }

    override fun onDestroy() {
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
            update(title(), "Paused")
            return
        }
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
