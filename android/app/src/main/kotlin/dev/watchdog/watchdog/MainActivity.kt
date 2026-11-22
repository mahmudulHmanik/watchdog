package dev.watchdog.watchdog

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Player gestures: real system media volume (what the hardware keys change).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.watchdog/audio")
            .setMethodCallHandler { call, result ->
                try {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                    when (call.method) {
                        "getVolume" -> result.success(
                            am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
                        )
                        "setVolume" -> {
                            val v = (call.argument<Double>("level") ?: 0.0).coerceIn(0.0, 1.0)
                            val idx = Math.round(v * max).toInt()
                            am.setStreamVolume(AudioManager.STREAM_MUSIC, idx, 0)
                            // Report what the system actually applied.
                            result.success(
                                am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
                            )
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("audio", e.message, null)
                }
            }
        // In-app updates: hand a downloaded APK to the system installer.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.watchdog/installer")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "canInstall" -> result.success(
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                                packageManager.canRequestPackageInstalls()
                        )
                        "openSettings" -> {
                            val i = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success(null)
                        }
                        "install" -> {
                            val path = call.argument<String>("path")
                                ?: return@setMethodCallHandler result.error("arg", "path missing", null)
                            val uri = FileProvider.getUriForFile(
                                this, "$packageName.fileprovider", File(path)
                            )
                            val i = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_ACTIVITY_NEW_TASK
                                )
                            startActivity(i)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("installer", e.message, null)
                }
            }
    }
}
