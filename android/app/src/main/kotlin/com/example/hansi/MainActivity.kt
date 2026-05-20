package com.example.hansi

import android.content.ContentValues
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.hansi/anki"
    private val ankiAuthority = "com.ichi2.anki.flashcards"
    private val ankiPermission = "com.ichi2.anki.permission.READ_WRITE_DATABASE"
    private val permissionRequestCode = 0xA32

    private val noteUri get() = Uri.parse("content://$ankiAuthority/notes")
    private val modelUri get() = Uri.parse("content://$ankiAuthority/models")
    private val fieldSep = ""

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isInstalled" -> result.success(isAnkiInstalled())
                    "hasPermission" -> result.success(hasPermission())
                    "requestPermission" -> requestPermission(result)
                    "addNote" -> {
                        val hanzi = call.argument<String>("hanzi")
                        val pinyin = call.argument<String>("pinyin")
                        val english = call.argument<String>("english")
                        if (hanzi == null || pinyin == null || english == null) {
                            result.error("ARG", "Missing argument", null)
                        } else {
                            addNote(hanzi, pinyin, english, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isAnkiInstalled(): Boolean = try {
        packageManager.getPackageInfo("com.ichi2.anki", 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, ankiPermission) == PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) { result.success(true); return }
        if (pendingPermissionResult != null) {
            result.error("BUSY", "Permission request already in progress", null); return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(this, arrayOf(ankiPermission), permissionRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun requireCol(cursor: Cursor, col: String): Int {
        val idx = cursor.getColumnIndex(col)
        if (idx < 0) throw IllegalStateException(
            "Column '$col' not found — available: ${cursor.columnNames.toList()}"
        )
        return idx
    }

    private fun findModelId(name: String): Long? {
        val cursor = contentResolver.query(modelUri, null, null, null, null)
            ?: return null
        return cursor.use {
            val idCol = it.getColumnIndex("_id").takeIf { i -> i >= 0 }
                ?: requireCol(it, "mid")
            val nameCol = requireCol(it, "name")
            while (it.moveToNext()) {
                if (it.getString(nameCol) == name) return@use it.getLong(idCol)
            }
            null
        }
    }

    private fun addNote(
        hanzi: String,
        pinyin: String,
        english: String,
        result: MethodChannel.Result,
    ) {
        try {
            val modelId = findModelId("Chinese")
                ?: return result.error(
                    "NO_MODEL",
                    "Note type 'Chinese' not found in AnkiDroid. " +
                        "Create it with fields: Hanzi, Pinyin, English, Audio.",
                    null,
                )
            val fields = listOf(hanzi, pinyin, english, "").joinToString(fieldSep)
            val values = ContentValues().apply {
                put("mid", modelId)
                put("flds", fields)
                put("tags", "hansi")
            }
            contentResolver.insert(noteUri, values)
                ?: return result.error("INSERT_FAILED", "AnkiDroid rejected the note", null)
            result.success(null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
}
