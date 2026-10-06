package vn.cake.daikinremote.timer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import vn.cake.daikinremote.data.RemoteRepository
import vn.cake.daikinremote.data.usesPhoneTimer
import vn.cake.daikinremote.protocol.Protocols

/** Alarms don't survive a reboot; re-register pending phone-side timers. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                val stored = RemoteRepository.get(context).current()
                if (stored.usesPhoneTimer(Protocols.byId(stored.protocolId))) {
                    val now = System.currentTimeMillis()
                    TimerScheduler.sync(
                        context,
                        stored.state.onTimerAt?.takeIf { it > now },
                        stored.state.offTimerAt?.takeIf { it > now },
                    )
                }
            } finally {
                pending.finish()
            }
        }
    }
}
