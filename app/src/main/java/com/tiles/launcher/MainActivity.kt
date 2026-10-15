package com.tiles.launcher

import android.app.ActivityOptions
import android.content.Intent
import android.content.pm.LauncherApps
import android.graphics.Color
import android.graphics.Rect
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.os.UserHandle
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.snapshotFlow
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val state = StartState()
    private lateinit var prefs: Prefs
    private lateinit var board: Board
    private var isResumedNow = false
    private var enterJob: Job? = null
    private var fallbackJob: Job? = null
    private val launcherApps by lazy { getSystemService(LauncherApps::class.java) }

    private val appsCallback = object : LauncherApps.Callback() {
        override fun onPackageRemoved(packageName: String?, user: UserHandle?) { state.appsVersion++ }
        override fun onPackageAdded(packageName: String?, user: UserHandle?) { state.appsVersion++ }
        override fun onPackageChanged(packageName: String?, user: UserHandle?) { state.appsVersion++ }
        override fun onPackagesAvailable(packageNames: Array<out String>?, user: UserHandle?, replacing: Boolean) {
            state.appsVersion++
        }
        override fun onPackagesUnavailable(packageNames: Array<out String>?, user: UserHandle?, replacing: Boolean) {
            state.appsVersion++
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = Prefs(this)
        board = Board(prefs)

        applyBars(prefs.dark)
        lifecycleScope.launch { snapshotFlow { prefs.dark }.collect { applyBars(it) } }

        // Lowest-priority back handler: back does nothing on Start, as on Windows Phone.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {}
        })

        launcherApps.registerCallback(appsCallback)

        setContent {
            LauncherRoot(
                state = state,
                board = board,
                prefs = prefs,
                onLaunchTile = ::launchTile,
                onLaunchApp = ::launchApp,
                onUninstall = ::uninstall,
            )
        }
    }

    override fun onDestroy() {
        launcherApps.unregisterCallback(appsCallback)
        super.onDestroy()
    }

    // ---- When to play the swing-in --------------------------------------------------------

    override fun onStart() {
        super.onStart()
        Diag.start()
        maybeEnter(Trigger.OnStart)
    }

    override fun onResume() {
        super.onResume()
        isResumedNow = true
        Diag.resume()
        state.navMode = navModeLabel(this)
        maybeEnter(Trigger.OnResume)
        if (prefs.trigger == Trigger.OnEnterAnim) {
            // Safety net in case the system never reports its animation finishing.
            fallbackJob?.cancel()
            fallbackJob = lifecycleScope.launch {
                delay(800)
                state.enter()
            }
        }
    }

    override fun onEnterAnimationComplete() {
        super.onEnterAnimationComplete()
        Diag.anim()
        maybeEnter(Trigger.OnEnterAnim)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            Diag.focus()
            maybeEnter(Trigger.OnFocus)
        }
    }

    override fun onPause() {
        super.onPause()
        isResumedNow = false
    }

    override fun onStop() {
        super.onStop()
        enterJob?.cancel()
        fallbackJob?.cancel()
        board.exitEdit()
        // Hide tiles while away so the system's return zoom never shows stale tiles.
        state.leave()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Home while on Start scrolls up; home from an app lands on the top of Start.
        if (isResumedNow) state.homeRequests++ else state.snapHomeRequests++
    }

    private fun maybeEnter(source: Trigger) {
        if (prefs.trigger != source) return
        val d = prefs.enterDelay
        if (d <= 0) {
            state.enter()
        } else {
            enterJob?.cancel()
            enterJob = lifecycleScope.launch {
                delay(d.toLong())
                state.enter()
            }
        }
    }

    // ---- Launching --------------------------------------------------------------------------

    private fun launchTile(app: AppEntry, bounds: Rect) {
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
                launcherApps.startMainActivity(app.component, app.user, bounds, opts.toBundle())
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

    private fun launchApp(app: AppEntry) {
        runCatching { launcherApps.startMainActivity(app.component, app.user, null, null) }
    }

    private fun uninstall(app: AppEntry) {
        runCatching {
            startActivity(Intent(Intent.ACTION_DELETE, Uri.fromParts("package", app.component.packageName, null)))
        }
    }

    private fun applyBars(dark: Boolean) {
        val style = if (dark) {
            SystemBarStyle.dark(Color.TRANSPARENT)
        } else {
            SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
        }
        enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
    }
}
