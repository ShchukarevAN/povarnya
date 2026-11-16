package ru.shchukarevan.povarnya

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val UPDATE_CHANNEL = "povarnya/app_update"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canRequestInstall" -> result.success(canRequestInstall())
                    "openInstallPermissionSettings" -> openInstallPermissionSettings(result)
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun canRequestInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()

    private fun openInstallPermissionSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(null)
            return
        }
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            )
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error(
                "INSTALL_PERMISSION_SETTINGS_FAILED",
                "Android did not open the unknown-app-sources settings.",
                error.stackTraceToString(),
            )
        }
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("APK_PATH_MISSING", "The downloaded APK path is empty.", null)
            return
        }
        try {
            if (!canRequestInstall()) {
                result.error(
                    "INSTALL_PERMISSION_REQUIRED",
                    "Android has not allowed Povarnya to install downloaded APK files.",
                    null,
                )
                return
            }
            val apk = File(path).canonicalFile
            val allowedRoot = File(cacheDir, "updates").canonicalFile
            val insideAllowedRoot = apk.path == allowedRoot.path ||
                apk.path.startsWith("${allowedRoot.path}${File.separator}")
            if (!insideAllowedRoot) {
                result.error(
                    "APK_PATH_REJECTED",
                    "The APK is outside the private update directory.",
                    "apk=${apk.path}; allowed=${allowedRoot.path}",
                )
                return
            }
            if (!apk.isFile || apk.length() <= 0L) {
                result.error(
                    "APK_FILE_MISSING",
                    "The downloaded APK does not exist or is empty.",
                    "apk=${apk.path}",
                )
                return
            }
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.update_file_provider",
                apk,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, APK_MIME_TYPE)
                clipData = ClipData.newRawUri("Povarnya update", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            if (intent.resolveActivity(packageManager) == null) {
                result.error(
                    "APK_INSTALLER_NOT_FOUND",
                    "No system application can install APK files.",
                    null,
                )
                return
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error(
                "APK_INSTALLER_FAILED",
                "Android failed to open the package installer: ${error.message}",
                error.stackTraceToString(),
            )
        }
    }
}
