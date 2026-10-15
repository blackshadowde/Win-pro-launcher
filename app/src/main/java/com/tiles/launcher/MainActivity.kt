package com.tiles.launcher

import android.app.ActivityOptions
import android.content.Intent
import android.content.pm.LauncherApps
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.ColorDrawable
import android.view.WindowManager
import android.app.SearchManager
import android.net.Uri
import android.speech.RecognizerIntent
import android.os.Bundle
import android.os.SystemClock
import android.os.UserHandle
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.text.font.FontFamily
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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

    private var font by mutableStateOf<FontFamily>(FontFamily.Default)
    private var fontCount by mutableIntStateOf(0)
    private var hasBundledFont by mutableStateOf(false)

    private val pickFonts = registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNullOrEmpty()) return@registerForActivityResult
        lifecycleScope.launch {
            withContext(Dispatchers.IO) { FontStore.import(this@MainActivity, uris) }
            reloadFont()
        }
    }

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

        applyLook(prefs.dark, prefs.style)
        lifecycleScope.launch {
            snapshotFlow { prefs.dark to prefs.style }.collect { (dark, style) -> applyLook(dark, style) }
        }

        // Lowest-priority back handler: back does nothing on Start, as on Windows Phone.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {}
        })

        launcherApps.registerCallback(appsCallback)
        reloadFont()

        setContent {
            LauncherRoot(
                state = state,
                board = board,
                prefs = prefs,
                font = font,
                fontCount = fontCount,
                hasBundledFont = hasBundledFont,
                onLaunchTile = ::launchTile,
                onLaunchApp = ::launchApp,
                onUninstall = ::uninstall,
                onLoadFont = { pickFonts.launch(arrayOf("*/*")) },
                onWebSearch = ::webSearch,
                onVoiceSearch = ::voiceSearch,
                onResetFont = {
                    FontStore.clear(this)
                    reloadFont()
                },
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
        if (isResumedNow) {
            state.homeRequests++
        } else {
            state.resetList()
            state.snapHomeRequests++
        }
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

    /** From the app list: rows turnstile out (tapped row last), then the app opens. */
    private fun launchApp(app: AppEntry, bounds: Rect) {
        if (state.listPhase == ListPhase.Out) return
        lifecycleScope.launch {
            state.beginListLaunch(app.key)
            delay(Motion.OUT_TOTAL_MS)
            val opts = ActivityOptions.makeScaleUpAnimation(
                window.decorView, bounds.left, bounds.top, bounds.width(), bounds.height(),
            )
            val ok = runCatching {
                launcherApps.startMainActivity(app.component, app.user, bounds, opts.toBundle())
            }.isSuccess
            if (!ok) {
                state.resetList()
                return@launch
            }
            delay(1500)
            if (isResumedNow && state.listPhase == ListPhase.Out) state.resetList()
        }
    }

    private fun webSearch(query: String) {
        runCatching {
            startActivity(Intent(Intent.ACTION_WEB_SEARCH).putExtra(SearchManager.QUERY, query))
        }.onFailure {
            runCatching {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com/search?q=" + Uri.encode(query))))
            }
        }
    }

    private fun voiceSearch() {
        runCatching { startActivity(Intent(RecognizerIntent.ACTION_WEB_SEARCH)) }
            .onFailure { runCatching { startActivity(Intent(Intent.ACTION_VOICE_COMMAND)) } }
    }

    private fun reloadFont() {
        val bundled = FontStore.bundled(this)
        hasBundledFont = bundled != null
        font = FontStore.family(this) ?: bundled ?: FontFamily.Default
        fontCount = FontStore.count(this)
    }

    private fun uninstall(app: AppEntry) {
        runCatching {
            startActivity(Intent(Intent.ACTION_DELETE, Uri.fromParts("package", app.component.packageName, null)))
        }
    }

    /** Modern shows the wallpaper behind the launcher; Classic is solid. */
    private fun applyLook(dark: Boolean, uiStyle: UiStyle) {
        val modern = uiStyle == UiStyle.Modern
        if (modern) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WALLPAPER)
            window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WALLPAPER)
            window.setBackgroundDrawable(ColorDrawable(if (dark) Color.BLACK else Color.WHITE))
        }
        // Light status-bar icons unless it's Classic light, which has a white bar.
        val style = if (dark || modern) {
            SystemBarStyle.dark(Color.TRANSPARENT)
        } else {
            SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
        }
        enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
    }
}
