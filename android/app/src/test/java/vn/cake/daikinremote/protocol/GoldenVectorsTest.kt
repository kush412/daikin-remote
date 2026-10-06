package vn.cake.daikinremote.protocol

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.cake.daikinremote.ir.PulseBuilder
import java.time.LocalDateTime

/**
 * Expected values are copied from IRremoteESP8266 `test/ir_Daikin_test.cpp`, so these tests
 * check that the Kotlin port produces bit-identical frames.
 */
class GoldenVectorsTest {

    private fun assertBytes(expected: ByteArray, actual: ByteArray) =
        assertEquals(expected.toHex(), actual.toHex())

    /** Decode the bytes back out of a pattern produced by [PulseBuilder.section]. */
    private fun parseOutputStr(s: String): IntArray =
        Regex("[ms](\\d+)").findAll(s).map { it.groupValues[1].toInt() }.toList().toIntArray()

    @Test
    fun daikin280_messageConstruction_matchesFullPulseTrain() {
        val golden = javaClass.classLoader!!.getResource("daikin280_message_construction.txt")!!.readText().trim()
        val state = AcState(power = true, mode = Mode.COOL, tempC = 27, fan = Fan.L1, swingV = false, swingH = true)
        val frame = Daikin280.encode(state, Button.POWER, now = null)
        assertEquals(38000, frame.frequencyHz)
        assertArrayEquals(parseOutputStr(golden), frame.pattern)
    }

    @Test
    fun daikin2_knownConstruction() {
        val expected = bytesOf(
            0x11, 0xDA, 0x27, 0x00, 0x01, 0x7A, 0xC3, 0x70, 0x28, 0x0C,
            0x80, 0x04, 0xB0, 0x16, 0x24, 0x00, 0x00, 0xBE, 0xD5, 0xF5,
            0x11, 0xDA, 0x27, 0x00, 0x00, 0x08, 0x26, 0x00, 0xA0, 0x00,
            0x00, 0x06, 0x60, 0x00, 0x00, 0xC1, 0x80, 0x60, 0xE7,
        )
        val ac = Daikin2State()
        ac.setPower(false)
        ac.setMode(0)
        ac.setTemp(19)
        ac.setFan(0xA)
        ac.setSwingVertical(5)
        ac.setSwingHorizontal(Daikin2State.SWING_H_AUTO)
        ac.setCurrentTime(14 * 60 + 50)
        ac.disableOnTimer()
        ac.disableOffTimer()
        ac.setBeep(1)
        ac.setLight(3)
        ac.setMold(true)
        ac.setClean(true)
        assertBytes(expected, ac.finish())
    }

    @Test
    fun daikin216_reconstructKnownState() {
        val expected = bytesOf(
            0x11, 0xDA, 0x27, 0xF0, 0x00, 0x00, 0x00, 0x02,
            0x11, 0xDA, 0x27, 0x00, 0x00, 0x00, 0x26, 0x00, 0xA0, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x98,
        )
        val ac = Daikin216State()
        ac.setPower(false)
        ac.setMode(0)
        ac.setTemp(19)
        ac.setFan(0xA)
        ac.setSwingHorizontal(false)
        ac.setSwingVertical(false)
        assertBytes(expected, ac.finish())
    }

    @Test
    fun daikin160_defaultState() {
        val expected = bytesOf(
            0x11, 0xDA, 0x27, 0xF0, 0x0D, 0x00, 0x0F,
            0x11, 0xDA, 0x27, 0x00, 0xD3, 0x30, 0x11, 0x00, 0x00, 0x1E, 0x0A, 0x08, 0x56,
        )
        assertBytes(expected, Daikin160State().finish())
        // The same state built through the app-level adapter.
        val ac = Daikin160State()
        ac.setPower(false)
        ac.setMode(Mode.COOL.daikinCode())
        ac.setTemp(25)
        ac.setFan(Fan.AUTO.daikinCode())
        ac.setSwingVertical(Daikin160State.SWING_LOWEST)
        assertBytes(expected, ac.finish())
    }

    @Test
    fun daikin176_reconstructKnownStates() {
        val onCool25 = bytesOf(
            0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x1E,
            0x11, 0xDA, 0x17, 0x18, 0x00, 0x73, 0x00, 0x21, 0x00, 0x00, 0x20, 0x35, 0x00, 0x20, 0x23,
        )
        val onFan17 = bytesOf(
            0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x1E,
            0x11, 0xDA, 0x17, 0x18, 0x00, 0x63, 0x04, 0x01, 0x00, 0x00, 0x10, 0x35, 0x00, 0x20, 0xE7,
        )
        val onDry17 = bytesOf(
            0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x1E,
            0x11, 0xDA, 0x17, 0x18, 0x00, 0x23, 0x04, 0x71, 0x00, 0x00, 0x10, 0x35, 0x00, 0x20, 0x17,
        )
        val onCool25v2 = bytesOf(
            0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x1E,
            0x11, 0xDA, 0x17, 0x18, 0x00, 0x73, 0x04, 0x21, 0x00, 0x00, 0x20, 0x35, 0x00, 0x20, 0x27,
        )
        val ac = Daikin176State()
        ac.setMode(Daikin176State.COOL)
        ac.setPower(true)
        ac.setTemp(25)
        ac.setFan(Daikin176State.FAN_MAX)
        ac.setSwingHorizontal(1) // "true" in the C++ test -> invalid -> Auto
        assertBytes(onCool25, ac.finish())
        ac.setMode(Daikin176State.FAN)
        assertBytes(onFan17, ac.finish())
        ac.setMode(Daikin176State.DRY)
        assertBytes(onDry17, ac.finish())
        ac.setMode(Daikin176State.COOL)
        assertBytes(onCool25v2, ac.finish())

        // Adapter: Cool 25 via the Mode button == the v2 frame.
        val state = AcState(power = true, mode = Mode.COOL, tempC = 25, fan = Fan.L5, swingH = true)
        val viaAdapter = Daikin176.encode(state, Button.MODE, null)
        assertArrayEquals(Daikin176State.send(onCool25v2).pattern, viaAdapter.pattern)
    }

    @Test
    fun daikin128_reconstructKnownState() {
        val expected = bytesOf(
            0x16, 0x12, 0x20, 0x19, 0x47, 0x22, 0x26, 0xAD,
            0xA1, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B,
        )
        val ac = Daikin128State()
        ac.setPowerToggle(true)
        ac.setMode(Daikin128Codes.COOL)
        ac.setTemp(26)
        ac.setFan(Daikin128Codes.FAN_AUTO)
        ac.setSwingVertical(true)
        ac.setClock(19 * 60 + 20)
        ac.setOnTimerEnabled(false)
        ac.setOnTimer(7 * 60 + 30)
        ac.setOffTimerEnabled(false)
        ac.setOffTimer(22 * 60)
        assertBytes(expected, ac.finish())
    }

    @Test
    fun daikin152_buildKnownState() {
        val expected = bytesOf(
            0x11, 0xDA, 0x27, 0x00, 0x00, 0x31, 0x28, 0x00, 0x3F, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0xC5, 0x00, 0x00, 0x6F,
        )
        val state = AcState(power = true, mode = Mode.COOL, tempC = 20, fan = Fan.L1, swingV = true)
        assertArrayEquals(Daikin152State.send(expected).pattern, Daikin152.encode(state, Button.POWER, null).pattern)
    }

    @Test
    fun daikin152_timersAreMinutesFromNow() {
        val now = LocalDateTime.of(2026, 10, 4, 22, 0)
        val nowMs = now.atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
        val off = AcState(power = true, mode = Mode.COOL, tempC = 26, fan = Fan.AUTO, swingV = true,
            offTimerAt = nowMs + 60 * 60_000L)
        val ac = Daikin152State()
        ac.setPower(true); ac.setTemp(26); ac.setMode(Mode.COOL.daikinCode()); ac.setTemp(26)
        ac.setFan(0xA); ac.setSwingV(true)
        ac.enableOffTimer(60)
        val raw = ac.finish()
        assertEquals(1, raw.get(5, 2, 1)) // OffTimer flag
        assertEquals(0, raw.get(5, 1, 1))
        assertEquals(60, raw.get(11, 4, 12))
        assertEquals(sumBytes(raw, 0, 18), raw.u(18))
        assertArrayEquals(Daikin152State.send(raw).pattern, Daikin152.encode(off, Button.TIMER, now).pattern)

        // Same layout as the real "night sleep" capture: 0x3C in byte 10.
        val on = Daikin152State().apply { enableOnTimer(60) }.finish()
        assertEquals(0x3C, on.u(10))
        assertEquals(1, on.get(5, 1, 1))
    }

    @Test
    fun daikin64_knownGoodState() {
        val state = AcState(power = true, mode = Mode.COOL, tempC = 16, fan = Fan.L3, swingV = false)
        val now = LocalDateTime.of(2026, 1, 1, 7, 20)
        val ac = Daikin64State()
        ac.setPowerToggle(true)
        ac.setMode(Daikin128Codes.COOL)
        ac.setTemp(16)
        ac.setFan(Daikin128Codes.FAN_MED)
        ac.setSwingVertical(false)
        ac.setClock(now.minutesOfDay)
        ac.setOnTimerEnabled(false)
        ac.setOffTimerEnabled(false)
        ac.finish()
        assertEquals(0x7C16161607204216L, ac.toLong())
        val expected = Daikin64State().also { it.finish() }.raw
        assertArrayEquals(Daikin64State.send(expected).pattern, Daikin64.encode(state, Button.POWER, now).pattern)
    }

    @Test
    fun daikin312_section2MatchesRealCapture() {
        // Section 2 of TestDecodeDaikin312.SyntheticExample: On, Cool, 21C, fan auto, swings off.
        val expectedSection2 = bytesOf(
            0x11, 0xDA, 0x27, 0x00, 0x00, 0x39, 0x2A, 0x00, 0xA0, 0x00,
            0x00, 0x06, 0x60, 0x00, 0x00, 0xC5, 0x00, 0x08, 0x48,
        )
        val ac = Daikin312State()
        ac.setPower(true)
        ac.setMode(Mode.COOL.daikinCode())
        ac.setTemp(21)
        ac.setFan(0xA)
        ac.setSwingVertical(Daikin312State.SWING_OFF)
        ac.setSwingHorizontal(Daikin312State.SWING_OFF)
        assertBytes(expectedSection2, ac.finish().copyOfRange(20, 39))
    }

    @Test
    fun everyProtocol_producesValidConsumerIrPattern() {
        val now = LocalDateTime.of(2026, 10, 3, 21, 45)
        val state = AcState(
            power = true, mode = Mode.COOL, tempC = 24, fan = Fan.L3, swingV = true, swingH = true,
            offTimerAt = System.currentTimeMillis() + 3_600_000,
        )
        for (p in Protocols.all) {
            for (button in Button.entries) {
                val frame = p.encode(state, button, now)
                assertTrue("${p.id}: empty", frame.pattern.isNotEmpty())
                assertTrue("${p.id}: non-positive pulse", frame.pattern.all { it > 0 })
                // ConsumerIrManager rejects patterns longer than 2 s (ignoring the final space).
                val total = frame.pattern.dropLast(if (frame.pattern.size % 2 == 0) 1 else 0).sum()
                assertTrue("${p.id}: ${total}us too long", total < 2_000_000)
            }
        }
    }

    @Test
    fun timers_encodeMinutesSinceMidnight() {
        val now = LocalDateTime.of(2026, 10, 3, 21, 45) // Saturday
        val at = now.plusHours(2).atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
        val ac = Daikin280State()
        ac.setCurrentTime(now.minutesOfDay)
        ac.setCurrentDay(now.daikinDay)
        ac.enableOffTimer(minutesOfDay(at))
        val raw = ac.finish()
        assertEquals(1, raw.get(21, 2, 1))
        assertEquals(23 * 60 + 45, raw.get(27, 4, 12))
        assertEquals(21 * 60 + 45, raw.get(13, 0, 11))
        assertEquals(7, raw.get(14, 3, 3))
    }
}
