package com.example.app_library_ledger

import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.applibraryledger/package_scanner"
    private val iconExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPackagesSurgically" -> {
                    val packages = call.arguments as List<String>
                    val installed = checkPackagesSurgically(packages)
                    result.success(installed)
                }
                "getAppIcons" -> {
                    val packages = call.arguments as List<String>
                    getAppIcons(packages) { icons ->
                        mainHandler.post {
                            result.success(icons)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun drawableToBitmap(drawable: Drawable, targetSize: Int): Bitmap {
        // If it's already a BitmapDrawable at the right size, reuse it
        if (drawable is BitmapDrawable) {
            val bmp = drawable.bitmap
            if (bmp.width == targetSize && bmp.height == targetSize) return bmp
        }
        val bitmap = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, targetSize, targetSize)
        drawable.draw(canvas)
        return bitmap
    }

    private fun getAppIcons(
        packageNames: List<String>,
        onResult: (Map<String, ByteArray>) -> Unit
    ) {
        iconExecutor.execute {
            val result = mutableMapOf<String, ByteArray>()
            val pm = packageManager
            for (pkg in packageNames) {
                try {
                    val icon: Drawable = pm.getApplicationIcon(pkg)
                    val bitmap = drawableToBitmap(icon, 96)
                    val stream = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                    result[pkg] = stream.toByteArray()
                    stream.close()
                } catch (e: PackageManager.NameNotFoundException) {
                    // App uninstalled since detection — skip
                    continue
                } catch (e: Exception) {
                    // Any other draw/copy failure — skip this package
                    continue
                }
            }
            onResult(result)
        }
    }

    /**
     * Checks each [packageNames] against the device's package manager.
     * Only packages listed in the AndroidManifest <queries> block are detectable —
     * if a package is missing from <queries>, getApplicationInfo will throw
     * NameNotFoundException even if the app is installed.
     *
     * Returns only the names of packages confirmed installed.
     */
    private fun checkPackagesSurgically(packageNames: List<String>): List<String> {
        val result = mutableListOf<String>()
        val pm = packageManager

        for (pkg in packageNames) {
            try {
                // ApplicationInfoFlags.of(0) added in API 33; deprecated overload below
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.getApplicationInfo(
                        pkg,
                        PackageManager.ApplicationInfoFlags.of(0)
                    )
                } else {
                    @Suppress("DEPRECATION")
                    pm.getApplicationInfo(pkg, 0)
                }
                result.add(pkg)
            } catch (e: PackageManager.NameNotFoundException) {
                // Normal miss — app is not installed on this device
                continue
            }
        }
        return result
    }
}