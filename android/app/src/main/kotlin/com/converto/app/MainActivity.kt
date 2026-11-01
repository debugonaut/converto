package com.converto.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.converto.app/native_channel"
    private var sharedUris: ArrayList<String> = ArrayList()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedFiles" -> {
                    result.success(sharedUris)
                    sharedUris.clear()
                }
                "resolveContentUri" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString != null) {
                        val filePath = copyContentUriToCache(Uri.parse(uriString))
                        result.success(filePath)
                    } else {
                        result.error("INVALID_URI", "URI cannot be null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return

        when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (uri != null) {
                    val path = copyContentUriToCache(uri)
                    if (path != null) sharedUris.add(path)
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                uris?.forEach { uri ->
                    val path = copyContentUriToCache(uri)
                    if (path != null) sharedUris.add(path)
                }
            }
            Intent.ACTION_VIEW -> {
                val uri = intent.data
                if (uri != null) {
                    val path = copyContentUriToCache(uri)
                    if (path != null) sharedUris.add(path)
                }
            }
        }
    }

    private fun copyContentUriToCache(uri: Uri): String? {
        return try {
            val contentResolver = applicationContext.contentResolver
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            val fileName = "input_${System.currentTimeMillis()}"
            val tempFile = File(cacheDir, fileName)
            val outputStream = FileOutputStream(tempFile)

            inputStream.copyTo(outputStream)
            inputStream.close()
            outputStream.close()

            tempFile.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}

