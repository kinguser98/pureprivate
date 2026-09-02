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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.goxio.mob/media_saver").setMethodCallHandler { call, result ->
            if (call.method == "saveToGallery") {
                val filePath = call.argument<String>("filePath")
                val filename = call.argument<String>("filename") ?: "media_file"
                val isVideo = call.argument<Boolean>("isVideo") ?: true

                if (filePath != null) {
                    try {
                        val sourceFile = java.io.File(filePath)
                        if (!sourceFile.exists()) {
                            result.error("FILE_NOT_FOUND", "Source file does not exist", null)
                            return@setMethodCallHandler
                        }

                        val contentValues = android.content.ContentValues().apply {
                            put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, filename)
                            if (isVideo) {
                                put(android.provider.MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
                                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                                    put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, android.os.Environment.DIRECTORY_MOVIES + "/GoXio")
                                    put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1)
                                }
                            } else {
                                put(android.provider.MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
                                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                                    put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, android.os.Environment.DIRECTORY_PICTURES + "/GoXio")
                                    put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1)
                                }
                            }
                        }

                        val collection = if (isVideo) {
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                                android.provider.MediaStore.Video.Media.getContentUri(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
                            } else {
                                android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                            }
                        } else {
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                                android.provider.MediaStore.Images.Media.getContentUri(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
                            } else {
                                android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                            }
                        }

                        val uri = contentResolver.insert(collection, contentValues)
                        if (uri != null) {
                            contentResolver.openOutputStream(uri)?.use { out ->
                                java.io.FileInputStream(sourceFile).use { input ->
                                    input.copyTo(out)
                                }
                            }

                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                                contentValues.clear()
                                contentValues.put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0)
                                contentResolver.update(uri, contentValues, null, null)
                            }

                            android.media.MediaScannerConnection.scanFile(
                                applicationContext,
                                arrayOf(sourceFile.absolutePath),
                                null,
                                null
                            )

                            result.success(true)
                        } else {
                            result.error("INSERT_FAILED", "Failed to create MediaStore entry", null)
                        }
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                } else {
                    result.error("INVALID_PATH", "File path cannot be null", null)
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
