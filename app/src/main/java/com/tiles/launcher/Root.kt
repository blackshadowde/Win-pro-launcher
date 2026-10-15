package com.tiles.launcher

import android.graphics.Rect
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import kotlinx.coroutines.launch

@Composable
fun LauncherRoot(
    state: StartState,
    board: Board,
    prefs: Prefs,
    font: FontFamily,
    fontCount: Int,
    onLaunchTile: (AppEntry, Rect) -> Unit,
    onLaunchApp: (AppEntry, Rect) -> Unit,
    onUninstall: (AppEntry) -> Unit,
    onLoadFont: () -> Unit,
    onResetFont: () -> Unit,
) {
    val context = LocalContext.current
    var apps by remember { mutableStateOf<List<AppEntry>>(emptyList()) }
    var firstLoad by remember { mutableStateOf(true) }
    LaunchedEffect(state.appsVersion) {
        apps = loadApps(context)
        if (firstLoad) {
            firstLoad = false
            if (!prefs.hasSavedPins()) board.setInitial(defaultPins(context, apps))
        }
    }
    val byKey = remember(apps) { apps.associateBy { it.key } }
    val pal = paletteFor(prefs.dark, prefs.accent)
    val look = Look(prefs.style == UiStyle.Modern)

    CompositionLocalProvider(
        LocalPalette provides pal,
        LocalFont provides font,
        LocalWhiteIcons provides prefs.whiteIcons,
        LocalLook provides look,
    ) {
        val pager = rememberPagerState(pageCount = { 2 })
        val startScroll = rememberScrollState()
        val listState = rememberLazyListState()
        val scope = rememberCoroutineScope()
        var settingsOpen by remember { mutableStateOf(false) }

        // Registered first so the app list's own back handlers (menu, letter grid) win.
        BackHandler(enabled = pager.currentPage == 1) { scope.launch { pager.animateScrollToPage(0) } }
        BackHandler(enabled = board.editing) { board.exitEdit() }

        LaunchedEffect(state.homeRequests) {
            if (state.homeRequests == 0) return@LaunchedEffect
            settingsOpen = false
            board.exitEdit()
            if (pager.currentPage != 0) pager.animateScrollToPage(0) else startScroll.animateScrollTo(0)
        }
        LaunchedEffect(state.snapHomeRequests) {
            if (state.snapHomeRequests == 0) return@LaunchedEffect
            settingsOpen = false
            board.exitEdit()
            state.resetList()
            pager.scrollToPage(0)
            startScroll.scrollTo(0)
        }

        // Modern: the wallpaper shows through, dimmed slightly so text stays readable.
        val pageBg = if (look.modern) pal.bg.copy(alpha = 0.35f) else pal.bg
        Column(Modifier.fillMaxSize().background(pageBg)) {
            // Solid status bar, like Windows Phone: content never scrolls under it.
            Box(
                Modifier
                    .fillMaxWidth()
                    .windowInsetsTopHeight(WindowInsets.statusBars)
                    .background(if (look.modern) Color.Transparent else pal.bg)
            )
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .clipToBounds()
            ) {
                HorizontalPager(
                    state = pager,
                    modifier = Modifier.fillMaxSize(),
                    userScrollEnabled = !board.editing,
                    beyondViewportPageCount = 1,
                ) { page ->
                    if (page == 0) {
                        StartPage(
                            state = state,
                            board = board,
                            apps = byKey,
                            scroll = startScroll,
                            onLaunchTile = onLaunchTile,
                            onOpenAppList = { scope.launch { pager.animateScrollToPage(1) } },
                        )
                    } else {
                        AppListPage(
                            apps = apps,
                            board = board,
                            state = state,
                            listState = listState,
                            onLaunch = onLaunchApp,
                            onUninstall = onUninstall,
                            onOpenSettings = { settingsOpen = true },
                        )
                    }
                }
                if (settingsOpen) {
                    SettingsPage(
                        prefs = prefs,
                        navMode = state.navMode,
                        fontCount = fontCount,
                        onLoadFont = onLoadFont,
                        onResetFont = onResetFont,
                        onClose = { settingsOpen = false },
                    )
                }
            }
        }
    }
}
