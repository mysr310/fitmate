package com.fitmate

import android.content.Intent
import android.net.Uri
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 接收微信/QQ「用其他应用打开 .fitbak 备份文件」的 VIEW intent：
 * 把 content:// 或 file:// 复制到应用缓存目录，再把缓存路径交给 Dart 侧
 * 走恢复确认流程（R3-高3：让 Manifest 注册的打开方式真正可用）。
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "FitMateMainActivity"
        private const val CHANNEL = "fitmate/backup_intent"
        /** Dart 侧未就绪时先缓存 intent；Dart 启动后主动来取 */
        private var pendingBackupPath: String? = null
    }

    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialBackupPath" -> {
                    val pending = pendingBackupPath
                    pendingBackupPath = null
                    result.success(pending)
                }
                else -> result.notImplemented()
            }
        }
        // 冷启动：onCreate 里已经收到 intent
        pendingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        pendingIntent(intent)
    }

    private fun pendingIntent(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return
        val uri: Uri = intent.data ?: return
        // R4-N5：复制放到后台线程，避免大文件阻塞主线程造成启动卡顿/ANR
        Thread {
            try {
                val cached = copyUriToCache(uri)
                if (cached == null) {
                    Log.w(TAG, "备份文件为空、过大或复制失败")
                    return@Thread
                }
                runOnUiThread { deliver(cached.absolutePath) }
            } catch (e: Exception) {
                Log.e(TAG, "读取备份文件失败", e)
            }
        }.start()
    }

    /** content:// 权限仅本次存续，必须当场复制到缓存；超过 200MB 拒绝（R4-N5） */
    private fun copyUriToCache(uri: Uri): File? {
        val out = File(cacheDir, "received_backup.fitbak")
        val maxSize = 200L * 1024 * 1024
        contentResolver.openInputStream(uri)?.use { input ->
            out.outputStream().use { output ->
                val buf = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > maxSize) {
                        out.delete()
                        return null
                    }
                    output.write(buf, 0, n)
                }
            }
        } ?: return null
        if (out.length() == 0L) {
            out.delete()
            return null
        }
        return out
    }

    private fun deliver(path: String) {
        pendingBackupPath = path
        // Dart 已就绪则立即推送；否则等 getInitialBackupPath 轮询取走
        channel?.invokeMethod("onBackupFile", path)
    }
}
