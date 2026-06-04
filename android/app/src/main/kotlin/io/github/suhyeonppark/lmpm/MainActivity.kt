package io.github.suhyeonppark.lmpm

import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var lock: WifiManager.MulticastLock? = null
    private var pipChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 브로드캐스트 절전 필터 회피용 MulticastLock.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lufs/multicast")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        if (lock == null) {
                            val wifi = applicationContext
                                .getSystemService(Context.WIFI_SERVICE) as WifiManager
                            lock = wifi.createMulticastLock("lufs").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(true)
                    }
                    "release" -> { lock?.release(); lock = null; result.success(true) }
                    else -> result.notImplemented()
                }
            }

        // Picture-in-Picture(떠 있는 작은 창).
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lufs/pip").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(supportsPip())
                    "enter" -> { enterPip(); result.success(true) }
                    "updateReading" -> result.success(true)
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun supportsPip(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun enterPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !supportsPip()) return
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(3, 2))
            .build()
        enterPictureInPictureMode(params)
    }

    // 홈으로 나가거나 다른 앱으로 전환할 때 자동으로 떠 있는 창으로 전환.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        enterPip()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
    }
}
