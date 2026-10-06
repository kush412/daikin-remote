package vn.cake.daikinremote.protocol

enum class Mode(val label: String) { AUTO("Auto"), COOL("Cool"), DRY("Dry"), HEAT("Heat"), FAN("Fan") }

/** Fan levels as on Daikin remotes: Auto, Quiet (silent indoor unit) and 1–5 bars. */
enum class Fan(val label: String) {
    AUTO("Auto"), QUIET("Quiet"), L1("1"), L2("2"), L3("3"), L4("4"), L5("5");

    /** L1 -> 1 … L5 -> 5; meaningless for AUTO/QUIET. */
    val level: Int get() = ordinal - 1
}

/** The button pressed for this frame. Some protocols encode it (power toggle, mode button). */
enum class Button { POWER, MODE, TEMP, FAN, SWING, TIMER, TEST }

/** Complete remote state; every frame encodes all of it, like a real Daikin remote. */
data class AcState(
    val power: Boolean = false,
    val mode: Mode = Mode.COOL,
    val tempC: Int = 25,
    val fan: Fan = Fan.AUTO,
    val swingV: Boolean = false,
    val swingH: Boolean = false,
    /** Epoch millis at which the AC should switch on, or null. */
    val onTimerAt: Long? = null,
    /** Epoch millis at which the AC should switch off, or null. */
    val offTimerAt: Long? = null,
)
