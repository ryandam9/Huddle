package net.ryandam.huddle

import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Android drops incoming UDP broadcast/multicast packets unless a
    // MulticastLock is held. Huddle relies on broadcast beacons for device
    // discovery, so we acquire the lock while the activity is in the
    // foreground and release it when paused.
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Lets the Dart side keep the process alive during a batch transfer by
        // starting/stopping the foreground service.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "net.ryandam.huddle/foreground"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val message = call.argument<String>("message") ?: "Sending…"
                    val intent = Intent(this, TransferForegroundService::class.java)
                        .putExtra(TransferForegroundService.EXTRA_MESSAGE, message)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stop" -> {
                    val intent = Intent(this, TransferForegroundService::class.java)
                        .setAction(TransferForegroundService.ACTION_STOP)
                    startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (multicastLock == null) {
            val wifi =
                applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("huddle-discovery").apply {
                setReferenceCounted(true)
                acquire()
            }
        }
    }

    override fun onPause() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
        super.onPause()
    }
}
