package vn.cake.daikinremote.protocol

/** All supported protocols, most common first (the order the picker tries them in). */
object Protocols {
    val all: List<DaikinProtocol> = listOf(
        Daikin280, Daikin2, Daikin312, Daikin216, Daikin160, Daikin152, Daikin176, Daikin128, Daikin64,
    )

    fun byId(id: String?): DaikinProtocol = all.firstOrNull { it.id == id } ?: Daikin280
}
