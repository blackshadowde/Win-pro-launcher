package com.tiles.launcher

import android.app.ActivityOptions
import android.content.Intent
import android.content.pm.LauncherApps
import android.graphics.Color
import android.graphics.Rect
import android.os.Bundle
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val state = StartState()
    private val prefs by lazy { getSharedPreferences("start", MODE_PRIVATE) }
    private var isResumedNow = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        state.trigger = Trigger.entries.getOrElse(prefs.getInt("trigger", 1)) { Trigger.OnResume }

        // Back does nothing on Start, as on Windows Phone.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {}
        })

        setContent {
            StartScreen(
                state = state,
                onLaunch = ::launchApp,
                onCycleTrigger = ::cycleTrigger,
            )
        }
    }

    override fun onStart() {
        super.onStart()
        Diag.start()
        if (state.trigger == Trigger.OnStart) state.enter()
    }

    override fun onResume() {
        super.onResume()
        isResumedNow = true
        Diag.resume()
        state.navMode = navModeLabel(this)
        if (state.trigger == Trigger.OnResume) state.enter()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            Diag.focus()
            if (state.trigger == Trigger.OnFocus) state.enter()
        }
    }

    override fun onPause() {
        super.onPause()
        isResumedNow = false
    }

    override fun onStop() {
        super.onStop()
        Diag.stop()
        // Hide tiles while away so the system's return zoom never shows stale tiles.
        state.leave()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Home pressed while already on Start: scroll to the top.
        if (isResumedNow) state.scrollTopRequests++
    }

    private fun launchApp(app: AppEntry, bounds: Rect) {
        if (state.phase == Phase.Out) return
        lifecycleScope.launch {
            val wait = state.blockedUntil - SystemClock.uptimeMillis()
            if (wait > 0) delay(wait)
            state.beginLaunch(app.key)
            delay(Motion.OUT_TOTAL_MS)

            val opts = ActivityOptions.makeScaleUpAnimation(
                window.decorView, bounds.left, bounds.top, bounds.width(), bounds.height(),
            )
            try {
                getSystemService(LauncherApps::class.java)
                    .startMainActivity(app.component, app.user, bounds, opts.toBundle())
            } catch (e: Exception) {
                state.leave()
                state.enter()
                return@launch
            }

            // If the app never took over (blocked, crashed), bring the tiles back.
            delay(1500)
            if (isResumedNow && state.phase == Phase.Out) {
                state.leave()
                state.enter()
            }
        }
    }

    private fun cycleTrigger() {
        val next = Trigger.entries[(state.trigger.ordinal + 1) % Trigger.entries.size]
        state.trigger = next
        prefs.edit().putInt("trigger", next.ordinal).apply()
    }
}
