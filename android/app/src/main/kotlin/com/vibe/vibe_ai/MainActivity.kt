package com.vibe.vibe_ai

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge to Termux: runs shell commands there through its RUN_COMMAND service.
 * Needs the RUN_COMMAND permission (asked at runtime) and
 * `allow-external-apps=true` in ~/.termux/termux.properties.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vibe_ai/termux")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installed" -> result.success(termuxInstalled())
                    "hasPermission" -> result.success(
                        checkSelfPermission(PERMISSION) == PackageManager.PERMISSION_GRANTED
                    )
                    "requestPermission" -> {
                        requestPermissions(arrayOf(PERMISSION), 7)
                        result.success(null)
                    }
                    "run" -> {
                        val script = call.argument<String>("script") ?: ""
                        val background = call.argument<Boolean>("background") ?: true
                        try {
                            run(script, background)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("run_failed", e.message, null)
                        }
                    }
                    "openTermux" -> {
                        packageManager.getLaunchIntentForPackage(TERMUX)?.let { startActivity(it) }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun termuxInstalled(): Boolean =
        try {
            packageManager.getPackageInfo(TERMUX, 0)
            true
        } catch (e: Exception) {
            false
        }

    private fun run(script: String, background: Boolean) {
        val intent = Intent().apply {
            setClassName(TERMUX, "com.termux.app.RunCommandService")
            action = "com.termux.RUN_COMMAND"
            putExtra("com.termux.RUN_COMMAND_PATH", "/data/data/com.termux/files/usr/bin/bash")
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-lc", script))
            putExtra("com.termux.RUN_COMMAND_WORKDIR", "/data/data/com.termux/files/home")
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", background)
            // Foreground runs open a new Termux session so you can watch progress.
            putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", "0")
        }
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
    }

    companion object {
        private const val TERMUX = "com.termux"
        private const val PERMISSION = "com.termux.permission.RUN_COMMAND"
    }
}
