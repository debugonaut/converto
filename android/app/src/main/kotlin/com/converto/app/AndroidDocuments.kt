package com.converto.app

import android.app.Activity
import android.content.ClipData
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** The engine works with private files; only explicit exports cross its sandbox. */
class AndroidDocuments(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var exportSource: File? = null
    @Volatile private var closed = false
    private val results get() = File(activity.filesDir, "results")

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "storagePaths" -> {
                    val data = File(activity.filesDir, "data")
                    check(data.isDirectory || data.mkdirs()) { "Could not create private app storage." }
                    check(results.isDirectory || results.mkdirs()) { "Could not create result storage." }
                    result.success(mapOf("data" to data.path, "output" to results.path))
                }
                "pickFiles" -> {
                    if (!begin(result)) return
                    launch(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, call.argument<Boolean>("allowMultiple") != false)
                        putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }, IMPORT)
                }
                "releaseImport" -> {
                    val path = requireNotNull(call.argument<String>("path")) { "Choose an imported file." }
                    val file = File(path).canonicalFile
                    require(file.path.startsWith(File(activity.cacheDir, "imports").canonicalPath + File.separator)) { "Only imported temporary copies can be removed." }
                    require(!file.exists() || (file.isFile && file.delete())) { "Could not remove the temporary imported copy." }
                    result.success(null)
                }
                "exportFile" -> {
                    val source = resultFile(call.argument<String>("path"))
                    if (!begin(result)) return
                    exportSource = source
                    launch(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = mime(source.name)
                        putExtra(Intent.EXTRA_TITLE, source.name)
                        putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                    }, EXPORT)
                }
                "openFile" -> {
                    val source = resultFile(call.argument<String>("path"), allowImport = true)
                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.results", source)
                    activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, mime(source.name))
                        clipData = ClipData.newRawUri("Result", uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    })
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            if (pending === result) {
                pending = null
                exportSource = null
            }
            val message = if (error is ActivityNotFoundException) {
                "No installed app can open this format. Use Export to save a copy."
            } else error.message ?: "Android could not access this document."
            result.error("DOCUMENT_ERROR", message, null)
        }
    }

    private fun begin(result: MethodChannel.Result): Boolean {
        if (pending != null) {
            result.error("BUSY", "Finish or cancel the open document dialog first.", null)
            return false
        }
        pending = result
        return true
    }

    @Suppress("DEPRECATION")
    private fun launch(intent: Intent, code: Int) = activity.startActivityForResult(intent, code)

    fun onActivityResult(code: Int, status: Int, data: Intent?) {
        if (code != IMPORT && code != EXPORT) return
        val reply = pending ?: return
        if (status != Activity.RESULT_OK || data == null) {
            finish(reply, if (code == IMPORT) null else false)
            return
        }
        val uris = linkedSetOf<Uri>()
        data.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
        data.data?.let(uris::add)
        val source = exportSource
        executor.execute {
            var batch: File? = null
            try {
                require(uris.isNotEmpty()) { "The document provider returned no file." }
                if (code == IMPORT) {
                    val workDir = File(activity.cacheDir, "imports/${UUID.randomUUID()}")
                    batch = workDir
                    check(workDir.mkdirs()) { "Could not prepare imported files." }
                    val imported = uris.mapIndexed { index, uri ->
                        val folder = File(workDir, index.toString()).apply { mkdirs() }
                        val target = File(folder, displayName(uri))
                        activity.contentResolver.openInputStream(uri).use { input ->
                            requireNotNull(input) { "This file could not be read. Choose a local copy." }
                            target.outputStream().use { input.copyTo(it) }
                        }
                        target.path
                    }
                    if (closed) workDir.deleteRecursively()
                    activity.runOnUiThread { finish(reply, imported) }
                } else {
                    requireNotNull(source) { "The result is no longer available." }
                    val uri = uris.first()
                    try {
                        activity.contentResolver.openOutputStream(uri, "wt").use { output ->
                            requireNotNull(output) { "The selected destination is not writable." }
                            source.inputStream().use { it.copyTo(output) }
                            output.flush()
                        }
                    } catch (error: Exception) {
                        // Remove our incomplete new document; retain the private result for retry.
                        runCatching { DocumentsContract.deleteDocument(activity.contentResolver, uri) }
                        throw error
                    }
                    activity.runOnUiThread { finish(reply, true) }
                }
            } catch (error: Exception) {
                batch?.deleteRecursively()
                activity.runOnUiThread {
                    if (pending === reply) {
                        pending = null
                        exportSource = null
                        reply.error("DOCUMENT_ERROR", error.message ?: "Could not copy this document.", null)
                    }
                }
            }
        }
    }

    private fun finish(reply: MethodChannel.Result, value: Any?) {
        if (pending !== reply) return
        pending = null
        exportSource = null
        reply.success(value)
    }

    private fun displayName(uri: Uri): String {
        val name = activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
            ?: "imported.${MimeTypeMap.getSingleton().getExtensionFromMimeType(activity.contentResolver.getType(uri)) ?: "bin"}"
        val safe = name.replace(Regex("[\\\\/\\x00-\\x1f\\x7f]"), "_").trim().trim('.')
        require(safe.isNotEmpty()) { "The selected document has no usable file name." }
        return safe
    }

    private fun resultFile(path: String?, allowImport: Boolean = false): File {
        requireNotNull(path) { "Choose a completed result first." }
        val file = File(path).canonicalFile
        val inResults = file.path.startsWith(results.canonicalPath + File.separator)
        val inImports = allowImport && file.path.startsWith(File(activity.cacheDir, "imports").canonicalPath + File.separator)
        require((inResults || inImports) && file.isFile) {
            "This result has moved or been deleted. Run the tool again."
        }
        return file
    }

    private fun mime(name: String) = MimeTypeMap.getSingleton()
        .getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase()) ?: "application/octet-stream"

    fun close() {
        closed = true
        pending?.error("ACTIVITY_CLOSED", "The document dialog was closed. Please try again.", null)
        pending = null
        exportSource = null
        executor.shutdown()
    }

    companion object {
        private const val IMPORT = 6101
        private const val EXPORT = 6102
    }
}
