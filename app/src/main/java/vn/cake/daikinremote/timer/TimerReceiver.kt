package vn.cake.daikinremote.timer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import vn.cake.daikinremote.data.RemoteRepository
import vn.cake.daikinremote.data.sendState
import vn.cake.daikinremote.data.usesPhoneTimer
import vn.cake.daikinremote.ir.IrTransmitter
import vn.cake.daikinremote.protocol.Button
import vn.cake.daikinremote.protocol.Protocols

/** Fires a phone-side timer: sends power on/off over IR and clears the timer. */
class TimerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val power = intent.getBooleanExtra(TimerScheduler.EXTRA_POWER, false)
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                val repo = RemoteRepository.get(context)
                val after = repo.update { stored ->
                    val protocol = Protocols.byId(stored.protocolId)
                    val timerAt = if (power) stored.state.onTimerAt else stored.state.offTimerAt
                    if (!stored.usesPhoneTimer(protocol) || timerAt == null) return@update stored
                    val cleared = if (power) stored.state.copy(onTimerAt = null) else stored.state.copy(offTimerAt = null)
                    val next = cleared.copy(power = power)
                    // A toggle protocol must not toggle if the AC is already in the wanted state.
                    if (!protocol.powerIsToggle || stored.state.power != power) {
                        IrTransmitter(context).sendState(protocol, next, Button.POWER, phoneTimer = true)
                    }
                    stored.copy(state = next)
                }
                if (after.state.onTimerAt == null && after.state.offTimerAt == null) TimerService.stop(context)
            } finally {
                pending.finish()
            }
        }
    }
}
