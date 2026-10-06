package vn.cake.daikinremote.data

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import vn.cake.daikinremote.protocol.AcState
import vn.cake.daikinremote.protocol.Fan
import vn.cake.daikinremote.protocol.Mode

private val Context.dataStore by preferencesDataStore(name = "remote")

/** Everything the app persists: the remote state plus settings. */
data class Stored(
    val state: AcState = AcState(),
    val protocolId: String? = null,
    /** Run timers on the phone instead of in the AC (forced for protocols without IR timers). */
    val phoneTimer: Boolean = false,
)

class StateStore(context: Context) {
    private val store = context.applicationContext.dataStore

    suspend fun load(): Stored = store.data.first().toStored()

    suspend fun save(s: Stored) {
        store.edit { p ->
            p[POWER] = s.state.power
            p[MODE] = s.state.mode.name
            p[TEMP] = s.state.tempC
            p[FAN] = s.state.fan.name
            p[SWING_V] = s.state.swingV
            p[SWING_H] = s.state.swingH
            s.state.onTimerAt?.let { p[ON_AT] = it } ?: p.remove(ON_AT)
            s.state.offTimerAt?.let { p[OFF_AT] = it } ?: p.remove(OFF_AT)
            s.protocolId?.let { p[PROTOCOL] = it } ?: p.remove(PROTOCOL)
            p[PHONE_TIMER] = s.phoneTimer
        }
    }

    private fun Preferences.toStored() = Stored(
        state = AcState(
            power = this[POWER] ?: false,
            mode = this[MODE]?.let { runCatching { Mode.valueOf(it) }.getOrNull() } ?: Mode.COOL,
            tempC = this[TEMP] ?: 25,
            fan = this[FAN]?.let { runCatching { Fan.valueOf(it) }.getOrNull() } ?: Fan.AUTO,
            swingV = this[SWING_V] ?: false,
            swingH = this[SWING_H] ?: false,
            onTimerAt = this[ON_AT],
            offTimerAt = this[OFF_AT],
        ),
        protocolId = this[PROTOCOL],
        phoneTimer = this[PHONE_TIMER] ?: false,
    )

    private companion object {
        val POWER = booleanPreferencesKey("power")
        val MODE = stringPreferencesKey("mode")
        val TEMP = intPreferencesKey("temp")
        val FAN = stringPreferencesKey("fan")
        val SWING_V = booleanPreferencesKey("swing_v")
        val SWING_H = booleanPreferencesKey("swing_h")
        val ON_AT = longPreferencesKey("on_at")
        val OFF_AT = longPreferencesKey("off_at")
        val PROTOCOL = stringPreferencesKey("protocol")
        val PHONE_TIMER = booleanPreferencesKey("phone_timer")
    }
}
