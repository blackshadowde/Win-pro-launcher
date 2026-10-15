package com.tiles.launcher

import android.graphics.Rect
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.launch

@Composable
fun LauncherRoot(
    state: StartState,
    board: Board,
    prefs: Prefs,
    onLaunchTile: (AppEntry, Rect) -> Unit,
    onLaunchApp: (AppEntry) -> Unit,
    onUninstall: (AppEntry) -> Unit,
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

    CompositionLocalProvider(LocalPalette provides pal) {
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
            pager.scrollToPage(0)
            startScroll.scrollTo(0)
        }

        Box(Modifier.fillMaxSize().background(pal.bg)) {
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
                        listState = listState,
                        onLaunch = onLaunchApp,
                        onUninstall = onUninstall,
                        onOpenSettings = { settingsOpen = true },
                    )
                }
            }
            if (settingsOpen) {
                SettingsPage(prefs = prefs, navMode = state.navMode, onClose = { settingsOpen = false })
            }
        }
    }
}
