package com.vibe.vibe_ai

import android.content.Context
import java.io.File
import java.security.SecureRandom
import java.util.zip.ZipInputStream

/**
 * Runs FreeLLMAPI with the Node.js bundled in this APK.
 *
 * Code lives in files/freellmapi (replaced when the bundled version changes);
 * your data (database, encryption key) lives in files/freellmapi-data and is never touched
 * by updates.
 */
object ServerRuntime {
    private const val MAX_LINES = 3000
    private const val ASSET_DIR = "flutter_assets/assets/server"

    private val lines = ArrayDeque<String>()
    @Volatile private var totalLines = 0
    @Volatile private var process: Process? = null
    @Volatile private var stopping = false

    /** stopped | preparing | running | exited */
    @Volatile var state = "stopped"
        private set

    /** Called (on a background thread) when the server process ends. */
    @Volatile var onExit: (() -> Unit)? = null

    fun log(line: String) {
        synchronized(lines) {
            lines.addLast(line)
            totalLines++
            while (lines.size > MAX_LINES) lines.removeFirst()
        }
    }

    /** Lines numbered from [from] onward (only what is still buffered), plus the state. */
    fun snapshot(from: Int): Map<String, Any> {
        synchronized(lines) {
            val first = totalLines - lines.size
            val start = maxOf(from, first) - first
            val out = if (start >= lines.size) emptyList() else lines.toList().subList(start, lines.size)
            return mapOf("total" to totalLines, "lines" to out, "state" to state)
        }
    }

    fun isRunning() = process?.isAlive == true

    @Synchronized
    fun start(context: Context) {
        if (isRunning() || state == "preparing") return
        stopping = false
        state = "preparing"
        val ctx = context.applicationContext
        Thread {
            try {
                val code = prepare(ctx)
                launch(ctx, code)
            } catch (e: Exception) {
                log("ERROR: ${e.message ?: e.javaClass.simpleName}")
                state = "exited"
                onExit?.invoke()
            }
        }.start()
    }

    @Synchronized
    fun stop() {
        stopping = true
        val p = process ?: run {
            if (state != "preparing") state = "stopped"
            return
        }
        log("Stopping server…")
        p.destroy()
        Thread {
            try {
                Thread.sleep(3000)
                if (p.isAlive) p.destroyForcibly()
            } catch (_: Exception) {
            }
        }.start()
    }

    /** Unpacks the bundled server when it is new or changed. Returns the code folder. */
    private fun prepare(ctx: Context): File {
        val bundled = ctx.assets.open("$ASSET_DIR/version.txt").bufferedReader().use { it.readText().trim() }
        val codeDir = File(ctx.filesDir, "freellmapi")
        val marker = File(codeDir, ".bundle-version")
        if (marker.exists() && marker.readText().trim() == bundled) return codeDir

        log("Unpacking FreeLLMAPI $bundled (first start after install or update)…")
        codeDir.deleteRecursively()
        codeDir.mkdirs()
        val root = codeDir.canonicalPath + File.separator
        var count = 0
        ZipInputStream(ctx.assets.open("$ASSET_DIR/freellmapi.zip").buffered()).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                val out = File(codeDir, entry.name)
                require(out.canonicalPath.startsWith(root)) { "Bad path in bundle: ${entry.name}" }
                if (entry.isDirectory) {
                    out.mkdirs()
                } else {
                    out.parentFile?.mkdirs()
                    out.outputStream().use { zip.copyTo(it) }
                    count++
                }
                entry = zip.nextEntry
            }
        }
        marker.writeText(bundled)
        log("Unpacked $count files.")
        return codeDir
    }

    private fun portBusy(port: Int): Boolean = try {
        java.net.Socket().use { it.connect(java.net.InetSocketAddress("127.0.0.1", port), 500) }
        true
    } catch (_: Exception) {
        false
    }

    private fun encryptionKey(dataDir: File): String {
        val file = File(dataDir, "app-encryption.key")
        if (file.exists()) return file.readText().trim()
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        val hex = bytes.joinToString("") { "%02x".format(it) }
        file.writeText(hex)
        return hex
    }

    private fun launch(ctx: Context, codeDir: File) {
        val libDir = ctx.applicationInfo.nativeLibraryDir
        val node = File(libDir, "libvn_node.so")
        if (!node.exists()) throw IllegalStateException("Node.js is missing from this build.")
        val dataDir = File(ctx.filesDir, "freellmapi-data").apply { mkdirs() }

        // Something else (often FreeLLMAPI started in Termux) already holds the port.
        if (portBusy(3001)) {
            log("Port 3001 is already in use by another app.")
            log("If FreeLLMAPI is still running in Termux, stop it there (Ctrl+C, or tap Exit in")
            log("Termux's notification), then start the server here again.")
            log("Or switch Settings → Server to Termux to keep using that one.")
            state = "exited"
            onExit?.invoke()
            return
        }

        val pb = ProcessBuilder(node.absolutePath, "server/dist/index.js")
            .directory(codeDir)
            .redirectErrorStream(true)
        pb.environment().apply {
            put("LD_LIBRARY_PATH", libDir)
            put("HOME", dataDir.absolutePath)
            put("TMPDIR", ctx.cacheDir.absolutePath)
            // Production mode, like FreeLLMAPI's Docker image: runs DB migrations on start.
            put("NODE_ENV", "production")
            put("ENCRYPTION_KEY", encryptionKey(dataDir))
            put("PORT", "3001")
            put("HOST", "127.0.0.1")
            put("FREEAPI_DB_PATH", File(dataDir, "freellmapi.db").absolutePath)
            put("CLIENT_DIST", File(codeDir, "client/dist").absolutePath)
            // The data folder is private to this app, so let the server lock it down.
            put("FREEAPI_DB_DIR_HARDENING", "1")
        }

        log("Starting FreeLLMAPI on http://127.0.0.1:3001 …")
        val p = pb.start()
        process = p
        state = "running"
        try {
            p.inputStream.bufferedReader().forEachLine { log(it) }
        } catch (_: Exception) {
        }
        val code = try { p.waitFor() } catch (_: Exception) { -1 }
        process = null
        state = if (stopping) "stopped" else "exited"
        log(if (stopping) "Server stopped." else "Server exited with code $code.")
        onExit?.invoke()
    }
}
