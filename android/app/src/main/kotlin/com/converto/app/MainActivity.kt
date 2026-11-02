package com.converto.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var documents: AndroidDocuments? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        documents = AndroidDocuments(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.converto.app/documents")
            .setMethodCallHandler(documents)
    }

    @Deprecated("Required by FlutterActivity's activity result dispatch")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        documents?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        documents?.close()
        super.onDestroy()
    }
}
