package com.itsash.dash

import android.content.Context
import android.location.Location
import org.json.JSONObject
import java.io.File

/**
 * The active trip's log: one JSON object per line.
 *  - `{"e":"start","t":ms}`, `{"e":"pause","t":ms}`, `{"e":"resume","t":ms}`
 *  - a fix: `{"t":ms,"la":lat,"lo":lon,"al":m,"sp":m/s,"ac":m,"be":deg}`
 *
 *  - `{"e":"stop","t":ms}`: the trip ended outside the app (auto-stop or the widget); Dart
 *    treats it as the end time.
 *
 * The service appends to it while the screen is off; Dart reads it back and
 * replays it through the same pure-Dart trip recorder (see `trip_recorder.dart`),
 * so the Kotlin side never needs its own trip maths.
 *
 * A trip that ends without the app is moved to `pending/` and saved by Dart
 * the next time it runs, so a new trip can start before the old one is saved.
 */
object TrackLog {
    private const val FILE = "active_track.jsonl"
    private const val PENDING = "pending"
    private val lock = Any()

    private fun file(ctx: Context) = File(ctx.filesDir, FILE)
    private fun pendingDir(ctx: Context) = File(ctx.filesDir, PENDING)

    fun clear(ctx: Context) = synchronized(lock) { file(ctx).delete(); Unit }

    /** Moves the active log to `pending/` (if it has anything in it). */
    fun archive(ctx: Context) = synchronized(lock) {
        val f = file(ctx)
        if (f.exists() && f.length() > 0) {
            val dir = pendingDir(ctx).apply { mkdirs() }
            f.renameTo(File(dir, "${System.currentTimeMillis()}.jsonl"))
        }
        f.delete()
        Unit
    }

    /** Ended trips waiting for Dart to save them: name to log content. */
    fun pending(ctx: Context): List<Map<String, String>> = synchronized(lock) {
        val files = pendingDir(ctx).listFiles()?.filter { it.name.endsWith(".jsonl") }?.sortedBy { it.name } ?: emptyList()
        files.map { mapOf("name" to it.name, "log" to it.readText()) }
    }

    fun pendingCount(ctx: Context): Int = synchronized(lock) {
        pendingDir(ctx).listFiles()?.count { it.name.endsWith(".jsonl") } ?: 0
    }

    fun deletePending(ctx: Context, name: String) = synchronized(lock) {
        val f = File(pendingDir(ctx), name)
        if (f.parentFile == pendingDir(ctx)) f.delete()
        Unit
    }

    fun append(ctx: Context, line: String) = synchronized(lock) {
        file(ctx).appendText(line + "\n")
    }

    fun read(ctx: Context): String = synchronized(lock) {
        val f = file(ctx)
        if (f.exists()) f.readText() else ""
    }

    fun marker(ctx: Context, event: String, timeMs: Long) {
        append(ctx, JSONObject().put("e", event).put("t", timeMs).toString())
    }
}

/** A location as the map sent to Dart and written to the log (same keys). */
fun Location.toFixMap(): Map<String, Any> {
    val m = HashMap<String, Any>()
    m["t"] = time
    m["la"] = latitude
    m["lo"] = longitude
    if (hasAltitude()) m["al"] = altitude
    if (hasSpeed()) m["sp"] = speed.toDouble()
    if (hasAccuracy()) m["ac"] = accuracy.toDouble()
    if (hasBearing()) m["be"] = bearing.toDouble()
    return m
}

/** Settings the service needs to word its notification, saved by the app. */
class NativePrefs(ctx: Context) {
    private val p = ctx.getSharedPreferences("dash_native", Context.MODE_PRIVATE)

    var tripActive: Boolean
        get() = p.getBoolean("active", false)
        set(v) = p.edit().putBoolean("active", v).apply()

    var paused: Boolean
        get() = p.getBoolean("paused", false)
        set(v) = p.edit().putBoolean("paused", v).apply()

    var speedLabel: String
        get() = p.getString("speedLabel", "km/h") ?: "km/h"
        private set(v) { p.edit().putString("speedLabel", v).apply() }

    var speedFactor: Double
        get() = p.getFloat("speedFactor", 3.6f).toDouble()
        private set(v) { p.edit().putFloat("speedFactor", v.toFloat()).apply() }

    var distLabel: String
        get() = p.getString("distLabel", "km") ?: "km"
        private set(v) { p.edit().putString("distLabel", v).apply() }

    var distDivisor: Double
        get() = p.getFloat("distDivisor", 1000f).toDouble()
        private set(v) { p.edit().putFloat("distDivisor", v.toFloat()).apply() }

    /** Stop the trip after this long without moving; 0 = never. Set from Dart settings. */
    var autoStopMs: Long
        get() = p.getLong("autoStopMs", 0L)
        set(v) = p.edit().putLong("autoStopMs", v).apply()

    /** Lines for the home-screen widget, formatted by Dart in the user's unit. */
    var widgetOdometer: String
        get() = p.getString("widgetOdometer", "") ?: ""
        set(v) = p.edit().putString("widgetOdometer", v).apply()

    var widgetLastTrip: String
        get() = p.getString("widgetLastTrip", "") ?: ""
        set(v) = p.edit().putString("widgetLastTrip", v).apply()

    fun setUnit(speedLabel: String, speedFactor: Double, distLabel: String, distDivisor: Double) {
        this.speedLabel = speedLabel
        this.speedFactor = speedFactor
        this.distLabel = distLabel
        this.distDivisor = distDivisor
    }
}
