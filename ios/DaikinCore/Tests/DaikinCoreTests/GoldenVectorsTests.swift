import Foundation
import XCTest
@testable import DaikinCore

/// Expected values are copied from IRremoteESP8266 `test/ir_Daikin_test.cpp` (the same vectors
/// as the Android app's GoldenVectorsTest), so these check that the Swift port produces
/// bit-identical frames.
final class GoldenVectorsTests: XCTestCase {

    private func assertBytes(_ expected: [UInt8], _ actual: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(expected.hex, actual.hex, file: file, line: line)
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// Mark/space values from an IRremoteESP8266 `outputStr()` dump ("m428s428…").
    private func parseOutputStr(_ s: String) -> [Int] {
        var out: [Int] = []
        var current: Int?
        for ch in s {
            if let d = ch.wholeNumberValue {
                current = (current ?? 0) * 10 + d
            } else {
                if let c = current { out.append(c) }
                current = nil
            }
        }
        if let c = current { out.append(c) }
        return out
    }

    func testDaikin280MessageConstructionMatchesFullPulseTrain() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "daikin280_message_construction", withExtension: "txt"))
        let golden = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let state = AcState(power: true, mode: .cool, tempC: 27, fan: .l1, swingV: false, swingH: true)
        let frame = Daikin280().encode(state, button: .power, now: nil)
        XCTAssertEqual(frame.frequencyHz, 38000)
        XCTAssertEqual(frame.pattern, parseOutputStr(golden))
    }

    func testDaikin2KnownConstruction() {
        let expected = bytesOf(
            0x11, 0xDA, 0x27, 0x00, 0x01, 0x7A, 0xC3, 0x70, 0x28, 0x0C,
            0x80, 0x04, 0xB0, 0x16, 0x24, 0x00, 0x00, 0xBE, 0xD5, 0xF5,
            0x11, 0xDA, 0x27, 0x00, 0x00, 0x08, 0x26, 0x00, 0xA0, 0x00,
            0x00, 0x06, 0x60, 0x00, 0x00, 0xC1, 0x80, 0x60, 0xE7
        )
        var ac = Daikin2State()
        ac.setPower(false)
        ac.setMode(0)
        ac.setTemp(19)
        ac.setFan(0xA)
        ac.setSwingVertical(5)
        ac.setSwingHorizontal(Daikin2State.swingHAuto)
        ac.setCurrentTime(14 * 60 + 50)
        ac.disableOnTimer()
        ac.disableOffTimer()
        ac.setBeep(1)
        ac.setLight(3)
        ac.setMold(true)
        ac.setClean(true)
        assertBytes(expected, ac.finish())
    }

    func testDaikin216ReconstructKnownState() {
        let expected = bytesOf(
            0x11, 0xDA, 0x27, 0xF0, 0x00, 0x00, 0x00, 0x02,
            0x11, 0xDA, 0x27, 0x00, 0x00, 0x00, 0x26, 0x00, 0xA0, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x98
        )
        var ac = Daikin216State()
        ac.setPower(false)
        ac.setMode(0)
        ac.setTemp(19)
        ac.setFan(0xA)
        ac.setSwingHorizontal(false)
        ac.setSwingVertical(false)
        assertBytes(expected, ac.finish())
    }

    func testDaikin160DefaultState() {
        let expected = bytesOf(
            0x11, 0xDA, 0x27, 0xF0, 0x0D, 0x00, 0x0F,
            0x11, 0xDA, 0x27, 0x00, 0xD3, 0x30, 0x11, 0x00, 0x00, 0x1E, 0x0A, 0x08, 0x56
        )
        var plain = Daikin160State()
        assertBytes(expected, plain.finish())
        // The same state built through the app-level codes.
        var ac = Daikin160State()
        ac.setPower(false)
        ac.setMode(Mode.cool.daikinCode)
        ac.setTemp(25)
        ac.setFan(Fan.auto.daikinCode)
        ac.setSwingVertical(Daikin160State.swingLowest)
        assertBytes(expected, ac.finish())
    }

    func testDaikin176ReconstructKnownStates() {
        let onCool25 = bytesOf(
            0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x1E,
            0x11, 0xDA, 0x17, 0x18, 0x00, 0x73, 0x00, 0x21, 0x00, 0x00, 0x20, 0x35, 0x00, 0x20, 0x23
        )
        let onFan17 = bytesOf(
            0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x1E,
            0x11, 0xDA, 0x17, 0x18, 0x00, 0x63, 0x04, 0x01, 0x00, 0x00, 0x10, 0x35, 0x00, 0x20, 0xE7
        )
        let onDry17 = bytesOf(
            0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x1E,
            0x11, 0xDA, 0x17, 0x18, 0x00, 0x23, 0x04, 0x71, 0x00, 0x00, 0x10, 0x35, 0x00, 0x20, 0x17
        )
        let onCool25v2 = bytesOf(
            0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x1E,
            0x11, 0xDA, 0x17, 0x18, 0x00, 0x73, 0x04, 0x21, 0x00, 0x00, 0x20, 0x35, 0x00, 0x20, 0x27
        )
        var ac = Daikin176State()
        ac.setMode(Daikin176State.cool)
        ac.setPower(true)
        ac.setTemp(25)
        ac.setFan(Daikin176State.fanMax)
        ac.setSwingHorizontal(1) // "true" in the C++ test -> invalid -> Auto
        assertBytes(onCool25, ac.finish())
        ac.setMode(Daikin176State.fan)
        assertBytes(onFan17, ac.finish())
        ac.setMode(Daikin176State.dry)
        assertBytes(onDry17, ac.finish())
        ac.setMode(Daikin176State.cool)
        assertBytes(onCool25v2, ac.finish())

        // Adapter: Cool 25 via the Mode button == the v2 frame.
        let state = AcState(power: true, mode: .cool, tempC: 25, fan: .l5, swingH: true)
        let viaAdapter = Daikin176().encode(state, button: .mode, now: nil)
        XCTAssertEqual(Daikin176State.send(onCool25v2).pattern, viaAdapter.pattern)
    }

    func testDaikin128ReconstructKnownState() {
        let expected = bytesOf(
            0x16, 0x12, 0x20, 0x19, 0x47, 0x22, 0x26, 0xAD,
            0xA1, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B
        )
        var ac = Daikin128State()
        ac.setPowerToggle(true)
        ac.setMode(Daikin128Codes.cool)
        ac.setTemp(26)
        ac.setFan(Daikin128Codes.fanAuto)
        ac.setSwingVertical(true)
        ac.setClock(19 * 60 + 20)
        ac.setOnTimerEnabled(false)
        ac.setOnTimer(7 * 60 + 30)
        ac.setOffTimerEnabled(false)
        ac.setOffTimer(22 * 60)
        assertBytes(expected, ac.finish())
    }

    func testDaikin152BuildKnownState() {
        let expected = bytesOf(
            0x11, 0xDA, 0x27, 0x00, 0x00, 0x31, 0x28, 0x00, 0x3F, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0xC5, 0x00, 0x00, 0x6F
        )
        let state = AcState(power: true, mode: .cool, tempC: 20, fan: .l1, swingV: true)
        XCTAssertEqual(Daikin152State.send(expected).pattern, Daikin152().encode(state, button: .power, now: nil).pattern)
    }

    func testDaikin152TimersAreMinutesFromNow() {
        let now = date(2026, 10, 4, 22, 0)
        let off = AcState(power: true, mode: .cool, tempC: 26, fan: .auto, swingV: true,
                          offTimerAt: now.addingTimeInterval(60 * 60))
        var ac = Daikin152State()
        ac.setPower(true); ac.setTemp(26); ac.setMode(Mode.cool.daikinCode); ac.setTemp(26)
        ac.setFan(0xA); ac.setSwingV(true)
        ac.enableOffTimer(60)
        let raw = ac.finish()
        XCTAssertEqual(raw.get(5, 2, 1), 1) // OffTimer flag
        XCTAssertEqual(raw.get(5, 1, 1), 0)
        XCTAssertEqual(raw.get(11, 4, 12), 60)
        XCTAssertEqual(raw.u(18), sumBytes(raw, 0, 18))
        XCTAssertEqual(Daikin152State.send(raw).pattern, Daikin152().encode(off, button: .timer, now: now).pattern)

        // Same layout as the real "night sleep" capture: 0x3C in byte 10.
        var onState = Daikin152State()
        onState.enableOnTimer(60)
        let on = onState.finish()
        XCTAssertEqual(on.u(10), 0x3C)
        XCTAssertEqual(on.get(5, 1, 1), 1)
    }

    func testDaikin64KnownGoodState() {
        let state = AcState(power: true, mode: .cool, tempC: 16, fan: .l3, swingV: false)
        let now = date(2026, 1, 1, 7, 20)
        var ac = Daikin64State()
        ac.setPowerToggle(true)
        ac.setMode(Daikin128Codes.cool)
        ac.setTemp(16)
        ac.setFan(Daikin128Codes.fanMed)
        ac.setSwingVertical(false)
        ac.setClock(minutesOfDay(now))
        ac.setOnTimerEnabled(false)
        ac.setOffTimerEnabled(false)
        _ = ac.finish()
        XCTAssertEqual(ac.uint64, 0x7C16161607204216)
        var reference = Daikin64State()
        let expected = reference.finish()
        XCTAssertEqual(Daikin64State.send(expected).pattern, Daikin64().encode(state, button: .power, now: now).pattern)
    }

    func testDaikin312Section2MatchesRealCapture() {
        // Section 2 of TestDecodeDaikin312.SyntheticExample: On, Cool, 21C, fan auto, swings off.
        let expectedSection2 = bytesOf(
            0x11, 0xDA, 0x27, 0x00, 0x00, 0x39, 0x2A, 0x00, 0xA0, 0x00,
            0x00, 0x06, 0x60, 0x00, 0x00, 0xC5, 0x00, 0x08, 0x48
        )
        var ac = Daikin312State()
        ac.setPower(true)
        ac.setMode(Mode.cool.daikinCode)
        ac.setTemp(21)
        ac.setFan(0xA)
        ac.setSwingVertical(Daikin312State.swingOff)
        ac.setSwingHorizontal(Daikin312State.swingOff)
        assertBytes(expectedSection2, Array(ac.finish()[20..<39]))
    }

    func testEveryProtocolProducesValidPattern() {
        let now = date(2026, 10, 3, 21, 45)
        let state = AcState(power: true, mode: .cool, tempC: 24, fan: .l3, swingV: true, swingH: true,
                            offTimerAt: now.addingTimeInterval(3600))
        for p in Protocols.all {
            for button in RemoteKey.allCases {
                let frame = p.encode(state, button: button, now: now)
                XCTAssertFalse(frame.pattern.isEmpty, "\(p.id): empty")
                XCTAssertTrue(frame.pattern.allSatisfy { $0 > 0 }, "\(p.id): non-positive pulse")
                // The bridge buffer holds 1024 pulses.
                XCTAssertLessThanOrEqual(frame.pattern.count, 1024, "\(p.id): too many pulses")
                let total = frame.pattern.dropLast(frame.pattern.count % 2 == 0 ? 1 : 0).reduce(0, +)
                XCTAssertLessThan(total, 2_000_000, "\(p.id): \(total)us too long")
            }
        }
    }

    func testTimersEncodeMinutesSinceMidnight() {
        let now = date(2026, 10, 3, 21, 45) // Saturday
        let at = now.addingTimeInterval(2 * 3600)
        var ac = Daikin280State()
        ac.setCurrentTime(minutesOfDay(now))
        ac.setCurrentDay(daikinDay(now))
        ac.enableOffTimer(minutesOfDay(at))
        let raw = ac.finish()
        XCTAssertEqual(raw.get(21, 2, 1), 1)
        XCTAssertEqual(raw.get(27, 4, 12), 23 * 60 + 45)
        XCTAssertEqual(raw.get(13, 0, 11), 21 * 60 + 45)
        XCTAssertEqual(raw.get(14, 3, 3), 7)
    }
}

final class RemoteLogicTests: XCTestCase {
    func testDueTimersSwitchPowerAndClear() {
        let now = Date()
        var s = AcState(power: true)
        s.offTimerAt = now.addingTimeInterval(-10)
        s.onTimerAt = now.addingTimeInterval(600)
        let settled = s.settled(now: now)
        XCTAssertFalse(settled.power)
        XCTAssertNil(settled.offTimerAt)
        XCTAssertNotNil(settled.onTimerAt)
    }

    func testBridgeTimersAreStrippedFromWireFrame() {
        var st = Stored()
        st.protocolId = "DAIKIN152"
        st.state = AcState(power: true, offTimerAt: Date().addingTimeInterval(3600))
        let now = Date()
        st.bridgeTimer = false
        let native = st.frame(button: .timer, now: now)
        st.bridgeTimer = true
        let viaBridge = st.frame(button: .timer, now: now)
        XCTAssertNotEqual(native, viaBridge)
        var plain = st.state
        plain.offTimerAt = nil
        XCTAssertEqual(viaBridge, Daikin152().encode(plain, button: .timer, now: now))
    }

    func testToggleProtocolsNeverUseBridgeTimer() {
        var st = Stored()
        st.protocolId = "DAIKIN64"
        st.bridgeTimer = true
        XCTAssertFalse(st.usesBridgeTimer)
        st.protocolId = "DAIKIN216"
        st.bridgeTimer = false
        XCTAssertTrue(st.usesBridgeTimer)
    }

    func testFitClampsToProtocol() {
        let s = AcState(mode: .auto, tempC: 40, fan: .l2, swingH: true).fitted(to: Daikin64())
        XCTAssertEqual(s.mode, .cool)
        XCTAssertEqual(s.tempC, 30)
        XCTAssertEqual(s.fan, .l1)
        XCTAssertFalse(s.swingH)
    }

    func testStoredDecodesOldSaves() throws {
        let s = try JSONDecoder().decode(Stored.self, from: Data(#"{"protocolId":"DAIKIN152"}"#.utf8))
        XCTAssertEqual(s.protocolId, "DAIKIN152")
        XCTAssertEqual(s.bridgeHost, "daikin-ir.local")
    }
}
