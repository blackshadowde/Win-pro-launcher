package com.vibe.vibe_ai

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Bridge to Termux: runs shell commands there through its RUN_COMMAND service.
 * Needs the RUN_COMMAND permission (asked at runtime) and
 * `allow-external-apps=true` in ~/.termux/termux.properties.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vibe_ai/node")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "run" -> {
                        val args = call.argument<List<String>>("args") ?: emptyList()
                        Thread {
                            val out = try {
                                runBundledNode(args)
                            } catch (e: Exception) {
                                "Could not start Node: ${e.message}"
                            }
                            runOnUiThread { result.success(out) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vibe_ai/server")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(NOTIFY) != PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(arrayOf(NOTIFY), 8)
                        }
                        try {
                            startForegroundService(Intent(this, ServerService::class.java))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("start_failed", e.message, null)
                        }
                    }
                    "stop" -> {
                        startService(Intent(this, ServerService::class.java).setAction(ServerService.ACTION_STOP))
                        result.success(true)
                    }
                    "snapshot" -> result.success(ServerRuntime.snapshot(call.argument<Int>("from") ?: 0))
                    "batteryUnrestricted" -> {
                        val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "openBatterySettings" -> {
                        try {
                            startActivity(
                                Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                    .setData(android.net.Uri.parse("package:$packageName"))
                            )
                        } catch (e: Exception) {
                            startActivity(Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
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

    /** Runs the Node.js bundled in this APK (step 1 test of the built-in server). */
    private fun runBundledNode(args: List<String>): String {
        val dir = applicationInfo.nativeLibraryDir
        val node = File(dir, "libvn_node.so")
        if (!node.exists()) {
            val found = File(dir).list()?.sorted()?.joinToString() ?: "nothing"
            return "Node is not bundled in this build.\nNative folder: $dir\nFiles: $found"
        }
        val pb = ProcessBuilder(listOf(node.absolutePath) + args).redirectErrorStream(true)
        val env = pb.environment()
        env["LD_LIBRARY_PATH"] = dir
        env["HOME"] = filesDir.absolutePath
        env["TMPDIR"] = cacheDir.absolutePath
        val p = pb.start()
        val text = p.inputStream.bufferedReader().readText()
        val finished = p.waitFor(60, TimeUnit.SECONDS)
        return "exit: ${if (finished) p.exitValue().toString() else "timeout"}\n$text"
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
        private const val NOTIFY = "android.permission.POST_NOTIFICATIONS"
    }
}
