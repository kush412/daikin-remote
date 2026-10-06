package vn.cake.daikinremote.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import vn.cake.daikinremote.data.RemoteRepository
import vn.cake.daikinremote.data.Stored
import vn.cake.daikinremote.data.sendState
import vn.cake.daikinremote.data.settleTimers
import vn.cake.daikinremote.data.usesPhoneTimer
import vn.cake.daikinremote.ir.IrTransmitter
import vn.cake.daikinremote.protocol.AcState
import vn.cake.daikinremote.protocol.Button
import vn.cake.daikinremote.protocol.DaikinProtocol
import vn.cake.daikinremote.protocol.Fan
import vn.cake.daikinremote.protocol.Mode
import vn.cake.daikinremote.protocol.Protocols
import vn.cake.daikinremote.timer.TimerScheduler
import java.text.DateFormat
import java.util.Date

enum class Screen { REMOTE, PICKER }

data class UiState(
    val loaded: Boolean = false,
    val stored: Stored = Stored(),
    val screen: Screen = Screen.REMOTE,
    val hasEmitter: Boolean = true,
    /** Increments on every transmission so the UI can flash a "sent" indicator. */
    val sendCount: Int = 0,
    val error: String? = null,
    val notice: String? = null,
    /** Ticks periodically so timer countdowns re-render. */
    val now: Long = System.currentTimeMillis(),
) {
    val protocol: DaikinProtocol get() = Protocols.byId(stored.protocolId)
    val state: AcState get() = stored.state
    val phoneTimer: Boolean get() = stored.usesPhoneTimer(protocol)
}

class RemoteViewModel(app: Application) : AndroidViewModel(app) {
    private val repo = RemoteRepository.get(app)
    private val ir = IrTransmitter(app)

    private val _ui = MutableStateFlow(UiState(hasEmitter = ir.hasEmitter))
    val ui: StateFlow<UiState> = _ui.asStateFlow()

    init {
        viewModelScope.launch {
            val first = repo.current()
            // First run: find the protocol before showing the remote.
            _ui.update { it.copy(loaded = true, screen = if (first.protocolId == null) Screen.PICKER else Screen.REMOTE) }
            settle(forceSync = true)
            repo.stored.collect { s -> if (s != null) _ui.update { it.copy(stored = s) } }
        }
        viewModelScope.launch {
            while (true) {
                delay(15_000)
                _ui.update { it.copy(now = System.currentTimeMillis()) }
                settle()
            }
        }
    }

    /** Called on resume, and periodically: applies timers that are now due. */
    fun refresh() = viewModelScope.launch {
        _ui.update { it.copy(now = System.currentTimeMillis()) }
        settle()
    }

    private suspend fun settle(forceSync: Boolean = false) {
        var missed = emptyList<String>()
        var changed = false
        val after = repo.update { s ->
            val settled = s.state.settleTimers(s.usesPhoneTimer(Protocols.byId(s.protocolId)))
            missed = settled.missed
            changed = settled.state != s.state
            if (changed) s.copy(state = settled.state) else s
        }
        if (missed.isNotEmpty()) {
            _ui.update {
                it.copy(
                    notice = "The ${missed.joinToString(" and ")} timer didn't run — the phone blocked the app " +
                        "in the background. Open App settings and allow Autostart and set Battery saver to " +
                        "“No restrictions”.",
                )
            }
        }
        if (changed || forceSync) syncPhoneTimers(after)
    }

    fun power() = press(Button.POWER) { it.copy(power = !it.power) }

    fun tempUp() = press(Button.TEMP) { it.copy(tempC = it.tempC + 1) }

    fun tempDown() = press(Button.TEMP) { it.copy(tempC = it.tempC - 1) }

    fun mode(mode: Mode) = press(Button.MODE) { it.copy(mode = mode) }

    fun fan(fan: Fan) = press(Button.FAN) { it.copy(fan = fan) }

    fun swingV() = press(Button.SWING) { it.copy(swingV = !it.swingV) }

    fun swingH() = press(Button.SWING) { it.copy(swingH = !it.swingH) }

    /** [minutes] from now, or null to cancel. */
    fun onTimer(minutes: Int?) = press(Button.TIMER) {
        it.copy(onTimerAt = minutes?.let { m -> System.currentTimeMillis() + m * 60_000L })
    }

    fun offTimer(minutes: Int?) = press(Button.TIMER) {
        it.copy(offTimerAt = minutes?.let { m -> System.currentTimeMillis() + m * 60_000L })
    }

    fun setPhoneTimer(enabled: Boolean) = press(Button.TIMER, settings = { it.copy(phoneTimer = enabled) }) { it }

    fun showPicker() = _ui.update { it.copy(screen = Screen.PICKER) }

    fun closePicker() = _ui.update { it.copy(screen = Screen.REMOTE) }

    fun dismissError() = _ui.update { it.copy(error = null) }

    fun dismissNotice() = _ui.update { it.copy(notice = null) }

    /** Sends a Cool 24°C power on/off test frame with [protocol] without changing the saved state. */
    fun test(protocol: DaikinProtocol, power: Boolean) = viewModelScope.launch(Dispatchers.Default) {
        val state = AcState(power = power, mode = Mode.COOL, tempC = 24, fan = Fan.AUTO)
        val err = ir.sendState(protocol, state, Button.POWER, phoneTimer = true)
        _ui.update { it.copy(sendCount = it.sendCount + 1, error = err) }
    }

    fun choose(protocol: DaikinProtocol) {
        _ui.update { it.copy(screen = Screen.REMOTE) }
        viewModelScope.launch {
            val after = repo.update { s -> s.copy(protocolId = protocol.id, state = s.state.fitTo(protocol)) }
            syncPhoneTimers(after)
        }
    }

    /**
     * Applies [change] to the latest state and transmits it. Runs through the repository's
     * lock, so quick taps are applied in order and never overwrite a timer that just fired.
     */
    private fun press(
        button: Button,
        settings: (Stored) -> Stored = { it },
        change: (AcState) -> AcState,
    ) = viewModelScope.launch(Dispatchers.Default) {
        var err: String? = null
        val after = repo.update { current ->
            val s = settings(current)
            val protocol = Protocols.byId(s.protocolId)
            val phone = s.usesPhoneTimer(protocol)
            val next = change(s.state.settleTimers(phone).state).fitTo(protocol)
            err = ir.sendState(protocol, next, button, phone)
            s.copy(state = next)
        }
        _ui.update { it.copy(sendCount = it.sendCount + 1, error = err) }
        if (button == Button.TIMER) syncPhoneTimers(after)
    }

    private fun syncPhoneTimers(s: Stored) {
        if (s.usesPhoneTimer(Protocols.byId(s.protocolId))) {
            TimerScheduler.sync(getApplication(), s.state.onTimerAt, s.state.offTimerAt)
        } else {
            TimerScheduler.cancelAll(getApplication())
        }
    }
}

/** Clamp a state to what [protocol] supports. */
private fun AcState.fitTo(protocol: DaikinProtocol): AcState {
    val m = if (mode in protocol.modes) mode else protocol.modes.first()
    val range = protocol.tempRange(m)
    val f = when {
        fan in protocol.fans -> fan
        // Closest supported level; AUTO/QUIET fall back to the first option.
        fan.ordinal >= Fan.L1.ordinal -> protocol.fans.minBy { kotlin.math.abs(it.ordinal - fan.ordinal) }
        else -> protocol.fans.first()
    }
    return copy(
        mode = m,
        tempC = tempC.coerceIn(range),
        fan = f,
        swingV = swingV && protocol.supportsSwingV,
        swingH = swingH && protocol.supportsSwingH,
    )
}

internal fun clock(epochMillis: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(epochMillis))

/** "in 1h 05m" / "in 4m" until [at]. */
internal fun countdown(at: Long, now: Long): String {
    val mins = ((at - now + 59_999) / 60_000).coerceAtLeast(0)
    return if (mins >= 60) "in ${mins / 60}h %02dm".format(mins % 60) else "in ${mins}m"
}
