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
 * The service appends to it while the screen is off; Dart reads it back and
 * replays it through the same pure-Dart trip recorder (see `trip_recorder.dart`),
 * so the Kotlin side never needs its own trip maths.
 */
object TrackLog {
    private const val FILE = "active_track.jsonl"
    private val lock = Any()

    private fun file(ctx: Context) = File(ctx.filesDir, FILE)

    fun clear(ctx: Context) = synchronized(lock) { file(ctx).delete(); Unit }

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

    fun setUnit(speedLabel: String, speedFactor: Double, distLabel: String, distDivisor: Double) {
        this.speedLabel = speedLabel
        this.speedFactor = speedFactor
        this.distLabel = distLabel
        this.distDivisor = distDivisor
    }
}
