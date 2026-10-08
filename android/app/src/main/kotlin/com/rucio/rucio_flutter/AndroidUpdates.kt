package com.rucio.rucio_flutter

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class AndroidUpdates(private val activity: Activity) {
    private val manager get() = activity.packageManager
    private val packageId get() = activity.packageName

    @Suppress("DEPRECATION")
    private val flags get() = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    @Suppress("DEPRECATION")
    private fun version(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun certificates(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) }
        }?.toSet() ?: emptySet()
    }

    private fun canInstall() = Build.VERSION.SDK_INT < 26 || manager.canRequestPackageInstalls()

    private fun verified(path: String?, expectedBuild: Long): File {
        require(path != null) { "No se encontró la descarga." }
        val root = File(activity.cacheDir, "updates").canonicalFile
        val file = File(path).canonicalFile
        require(file.parentFile == root && file.isFile) { "No se encontró una descarga válida." }
        val apk = manager.getPackageArchiveInfo(file.path, flags)
            ?: throw IllegalArgumentException("El APK no es válido.")
        val installed = manager.getPackageInfo(packageId, flags)
        require(apk.packageName == packageId && version(apk) == expectedBuild && expectedBuild > version(installed)) {
            "La actualización no corresponde a esta instalación o no es más reciente."
        }
        val signers = certificates(apk)
        require(signers.isNotEmpty() && signers == certificates(installed)) {
            "La firma de la actualización no coincide con Rucio."
        }
        return file
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.rucio/updates").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "info" -> {
                        val installed = manager.getPackageInfo(packageId, flags)
                        result.success(mapOf(
                            "packageId" to packageId,
                            "version" to (installed.versionName ?: ""),
                            "buildNumber" to version(installed),
                            "abis" to Build.SUPPORTED_ABIS.toList(),
                            "certificates" to certificates(installed).toList()
                        ))
                    }
                    "canInstall" -> result.success(canInstall())
                    "permission" -> {
                        if (!canInstall()) activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageId")))
                        result.success(null)
                    }
                    "verify", "install" -> {
                        val file = verified(call.argument<String>("path"), call.argument<Number>("buildNumber")?.toLong() ?: -1)
                        if (call.method == "install") {
                            require(canInstall()) { "Permite a Rucio instalar aplicaciones para continuar." }
                            val uri = FileProvider.getUriForFile(activity, "$packageId.updates", file)
                            activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            })
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: IllegalArgumentException) {
                result.error("invalid_update", error.message, null)
            } catch (error: Exception) {
                result.error("update_failed", "No se pudo abrir el instalador de Android. Inténtalo de nuevo.", null)
            }
        }
    }
}
