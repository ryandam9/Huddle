package net.ryandam.huddle

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Android drops incoming UDP broadcast/multicast packets unless a
    // MulticastLock is held. Huddle relies on broadcast beacons for device
    // discovery, so we acquire the lock while the activity is in the
    // foreground and release it when paused.
    private var multicastLock: WifiManager.MulticastLock? = null

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
