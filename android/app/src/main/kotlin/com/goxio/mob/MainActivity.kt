package com.goxio.mob

import android.app.PictureInPictureParams
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val PIP_CHANNEL = "com.goxio.mob/pip"
    private val EXTERNAL_PLAYER_CHANNEL = "com.goxio.mob/external_player"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "enterPip") {
                val entered = enterPipMode()
                result.success(entered)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXTERNAL_PLAYER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "launchExternalPlayer") {
                val url = call.argument<String>("url")
                val title = call.argument<String>("title")
                val headers = call.argument<Map<String, String>>("headers")
                val playerPackage = call.argument<String>("playerPackage")

                if (url != null) {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW)
                        intent.setDataAndType(Uri.parse(url), "video/*")

                        if (title != null) {
                            intent.putExtra("title", title)
                        }

                        if (headers != null && headers.isNotEmpty()) {
                            val headersArray = ArrayList<String>()
                            for ((k, v) in headers) {
                                headersArray.add("$k: $v")
                            }
                            intent.putExtra("headers", headersArray.toTypedArray())
                        }

                        var targetPackage: String? = null
                        if (playerPackage == "vlc") {
                            targetPackage = "org.videolan.vlc"
                        } else if (playerPackage == "mx") {
                            targetPackage = "com.mxtech.videoplayer.ad"
                        }

                        if (targetPackage != null) {
                            intent.setPackage(targetPackage)
                            try {
                                startActivity(intent)
                            } catch (e: Exception) {
                                if (playerPackage == "mx") {
                                    try {
                                        val proIntent = Intent(Intent.ACTION_VIEW)
                                        proIntent.setDataAndType(Uri.parse(url), "video/*")
                                        if (title != null) proIntent.putExtra("title", title)
                                        proIntent.setPackage("com.mxtech.videoplayer.pro")
                                        startActivity(proIntent)
                                    } catch (e2: Exception) {
                                        val chooser = Intent(Intent.ACTION_VIEW)
                                        chooser.setDataAndType(Uri.parse(url), "video/*")
                                        if (title != null) chooser.putExtra("title", title)
                                        startActivity(Intent.createChooser(chooser, "Play with"))
                                    }
                                } else {
                                    val chooser = Intent(Intent.ACTION_VIEW)
                                    chooser.setDataAndType(Uri.parse(url), "video/*")
                                    if (title != null) chooser.putExtra("title", title)
                                    startActivity(Intent.createChooser(chooser, "Play with"))
                                }
                            }
                        } else {
                            startActivity(Intent.createChooser(intent, "Play with"))
                        }

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LAUNCH_FAILED", e.message, null)
                    }
                } else {
                    result.error("INVALID_URL", "URL cannot be null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun enterPipMode(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9))
                    .build()
                return enterPictureInPictureMode(params)
            } catch (e: Exception) {
                try {
                    enterPictureInPictureMode()
                    return true
                } catch (e2: Exception) {
                    return false
                }
            }
        }
        return false
    }
}
