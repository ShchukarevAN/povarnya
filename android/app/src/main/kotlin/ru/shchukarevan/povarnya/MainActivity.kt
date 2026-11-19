package ru.shchukarevan.povarnya

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

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
                    "inspectApk" -> inspectApk(
                        call.argument<String>("path"),
                        call.argument<String>("expectedVersionName"),
                        (call.arguments as? Map<*, *>)?.get("expectedVersionCode") as? Number,
                        result,
                    )
                    "installApk" -> installApk(
                        call.argument<String>("path"),
                        call.argument<String>("expectedVersionName"),
                        (call.arguments as? Map<*, *>)?.get("expectedVersionCode") as? Number,
                        result,
                    )
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

    private data class ValidatedApk(
        val file: File,
        val packageInfo: PackageInfo,
        val versionCode: Long,
    )

    private class ApkValidationException(
        val code: String,
        override val message: String,
        val details: String? = null,
    ) : Exception(message)

    private fun inspectApk(
        path: String?,
        expectedVersionName: String?,
        expectedVersionCode: Number?,
        result: MethodChannel.Result,
    ) {
        try {
            val validated = validateApk(path, expectedVersionName, expectedVersionCode)
            result.success(
                mapOf(
                    "packageName" to validated.packageInfo.packageName,
                    "versionName" to validated.packageInfo.versionName,
                    "versionCode" to validated.versionCode,
                ),
            )
        } catch (error: ApkValidationException) {
            result.error(error.code, error.message, error.details)
        } catch (error: Exception) {
            result.error(
                "APK_INSPECTION_FAILED",
                "Android не смог прочитать метаданные APK: ${error.message}",
                error.stackTraceToString(),
            )
        }
    }

    private fun installApk(
        path: String?,
        expectedVersionName: String?,
        expectedVersionCode: Number?,
        result: MethodChannel.Result,
    ) {
        try {
            if (!canRequestInstall()) {
                result.error(
                    "INSTALL_PERMISSION_REQUIRED",
                    "Android не разрешил «Поварне» устанавливать скачанные APK.",
                    null,
                )
                return
            }
            // Repeat the full validation immediately before granting the
            // installer access, so the file cannot be replaced after preview.
            val validated = validateApk(path, expectedVersionName, expectedVersionCode)
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.update_file_provider",
                validated.file,
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
        } catch (error: ApkValidationException) {
            result.error(error.code, error.message, error.details)
        } catch (error: Exception) {
            result.error(
                "APK_INSTALLER_FAILED",
                "Android failed to open the package installer: ${error.message}",
                error.stackTraceToString(),
            )
        }
    }

    private fun validateApk(
        path: String?,
        expectedVersionName: String?,
        expectedVersionCode: Number?,
    ): ValidatedApk {
        if (path.isNullOrBlank()) {
            throw ApkValidationException(
                "APK_PATH_MISSING",
                "Путь к скачанному APK пуст.",
            )
        }
        if (expectedVersionName.isNullOrBlank() || expectedVersionCode == null) {
            throw ApkValidationException(
                "APK_EXPECTED_VERSION_MISSING",
                "Обновлятор не передал ожидаемую версию APK.",
            )
        }

        val apk = File(path).canonicalFile
        val allowedRoot = File(cacheDir, "updates").canonicalFile
        val insideAllowedRoot = apk.path == allowedRoot.path ||
            apk.path.startsWith("${allowedRoot.path}${File.separator}")
        if (!insideAllowedRoot) {
            throw ApkValidationException(
                "APK_PATH_REJECTED",
                "APK находится вне защищённой папки обновлений.",
                "apk=${apk.path}; allowed=${allowedRoot.path}",
            )
        }
        if (!apk.isFile || apk.length() <= 0L) {
            throw ApkValidationException(
                "APK_FILE_MISSING",
                "Скачанный APK не найден или пуст.",
                "apk=${apk.path}",
            )
        }

        val archive = packageInfoFromArchive(apk) ?: throw ApkValidationException(
            "APK_METADATA_UNREADABLE",
            "Android не распознал файл как корректный APK.",
            "apk=${apk.path}",
        )
        val archiveVersionCode = packageVersionCode(archive)
        val expectedCode = expectedVersionCode.toLong()
        val installed = installedPackageInfo()
        val installedVersionCode = packageVersionCode(installed)

        if (archive.packageName != packageName) {
            throw ApkValidationException(
                "APK_PACKAGE_MISMATCH",
                "APK предназначен для ${archive.packageName}, а не для $packageName.",
                "expected=$packageName; actual=${archive.packageName}",
            )
        }
        if (archive.versionName != expectedVersionName) {
            throw ApkValidationException(
                "APK_VERSION_NAME_MISMATCH",
                "Релиз обещает версию $expectedVersionName, " +
                    "но внутри APK находится ${archive.versionName ?: "<нет>"}.",
                "expected=$expectedVersionName; actual=${archive.versionName}",
            )
        }
        if (archiveVersionCode != expectedCode) {
            throw ApkValidationException(
                "APK_VERSION_CODE_MISMATCH",
                "Релиз обещает код сборки $expectedCode, " +
                    "но внутри APK находится $archiveVersionCode.",
                "expected=$expectedCode; actual=$archiveVersionCode",
            )
        }
        if (archiveVersionCode <= installedVersionCode) {
            throw ApkValidationException(
                "APK_VERSION_NOT_NEWER",
                "Код APK $archiveVersionCode не новее установленного $installedVersionCode.",
                "installed=$installedVersionCode; candidate=$archiveVersionCode",
            )
        }
        if (!signaturesMatch(installed, archive)) {
            throw ApkValidationException(
                "APK_SIGNATURE_MISMATCH",
                "APK подписан не тем ключом, что установленная «Поварня».",
                "installed=${signatureDigests(installed)}; archive=${signatureDigests(archive)}",
            )
        }
        return ValidatedApk(apk, archive, archiveVersionCode)
    }

    @Suppress("DEPRECATION")
    private fun packageInfoFromArchive(apk: File): PackageInfo? {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageArchiveInfo(
                apk.path,
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            packageManager.getPackageArchiveInfo(apk.path, flags)
        }
    }

    @Suppress("DEPRECATION")
    private fun installedPackageInfo(): PackageInfo {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            packageManager.getPackageInfo(packageName, flags)
        }
    }

    @Suppress("DEPRECATION")
    private fun packageVersionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }

    @Suppress("DEPRECATION")
    private fun signatureDigests(info: PackageInfo): Set<String> {
        val signatures: Array<Signature> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo ?: return emptySet()
            if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
        } else {
            info.signatures ?: return emptySet()
        }
        return signatures.mapTo(mutableSetOf()) { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) }
        }
    }

    @Suppress("DEPRECATION")
    private fun signaturesMatch(installed: PackageInfo, archive: PackageInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val installedSigning = installed.signingInfo ?: return false
            val archiveSigning = archive.signingInfo ?: return false
            if (installedSigning.hasMultipleSigners() || archiveSigning.hasMultipleSigners()) {
                val installedCurrent = installedSigning.apkContentsSigners.toDigestSet()
                val archiveCurrent = archiveSigning.apkContentsSigners.toDigestSet()
                return installedCurrent.isNotEmpty() && installedCurrent == archiveCurrent
            }
        }
        val installedHistory = signatureDigests(installed)
        val archiveHistory = signatureDigests(archive)
        return installedHistory.isNotEmpty() &&
            archiveHistory.isNotEmpty() &&
            installedHistory.intersect(archiveHistory).isNotEmpty()
    }

    private fun Array<Signature>.toDigestSet(): Set<String> =
        mapTo(mutableSetOf()) { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) }
        }
}
