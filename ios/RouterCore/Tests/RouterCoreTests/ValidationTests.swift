import Foundation
import XCTest
@testable import RouterCore

final class ValidationTests: XCTestCase {

    func testTokenFormat() {
        XCTAssertTrue(Validation.isValidToken(dummyToken))
        XCTAssertTrue(Validation.isValidToken("fsr1_" + String(repeating: "a", count: 40) + "_-9"))
        XCTAssertFalse(Validation.isValidToken("fsr1_" + String(repeating: "a", count: 42)))
        XCTAssertFalse(Validation.isValidToken("fsr1_" + String(repeating: "a", count: 44)))
        XCTAssertFalse(Validation.isValidToken("FSR1_" + String(repeating: "a", count: 43)))
        XCTAssertFalse(Validation.isValidToken("fsr1_" + String(repeating: "a", count: 42) + "="))
        XCTAssertFalse(Validation.isValidToken("fsr1_" + String(repeating: "a", count: 42) + "ж"))
        XCTAssertFalse(Validation.isValidToken(""))
        XCTAssertFalse(Validation.isValidToken("Bearer " + dummyToken))
    }

    func testHexIDs() {
        XCTAssertTrue(Validation.isValidLoginID(String(repeating: "0123456789abcdef", count: 4)))
        XCTAssertFalse(Validation.isValidLoginID(String(repeating: "0123456789ABCDEF", count: 4)))
        XCTAssertFalse(Validation.isValidLoginID("abc"))
        XCTAssertTrue(Validation.isValidJobID("fbe9f93b0caf8a91"))
        XCTAssertFalse(Validation.isValidJobID("fbe9f93b0caf8a9"))
        XCTAssertFalse(Validation.isValidJobID("../../../status!"))
        XCTAssertTrue(Validation.isValidConfirm("79217acbd9c66e9e1af7693324516b75"))
        XCTAssertFalse(Validation.isValidConfirm(""))
        XCTAssertFalse(Validation.isValidConfirm("xyz"))
    }

    func testDeviceName() {
        XCTAssertEqual(Validation.sanitizeDeviceName("  iPhone владельца \n"), "iPhone владельца")
        XCTAssertEqual(Validation.sanitizeDeviceName("a\u{0}b\u{7F}c\td"), "abcd")
        XCTAssertEqual(Validation.sanitizeDeviceName("   "), "")
        XCTAssertFalse(Validation.isValidDeviceName(" \n "))
        XCTAssertTrue(Validation.isValidDeviceName("iPhone"))
        let long = String(repeating: "я", count: 50)
        XCTAssertEqual(Validation.sanitizeDeviceName(long).count, 40)
        // a flag is 2 code points: 20 flags = 40 code points, the 21st does not fit
        let flags = String(repeating: "🇩🇪", count: 25)
        let cut = Validation.sanitizeDeviceName(flags)
        XCTAssertEqual(cut.unicodeScalars.count, 40)
        XCTAssertEqual(cut.count, 20)
        // trailing space after the cut is trimmed
        let spaced = String(repeating: "a", count: 39) + " b"
        XCTAssertEqual(Validation.sanitizeDeviceName(spaced), String(repeating: "a", count: 39))
        XCTAssertEqual(Validation.limitDeviceNameInput("ab\ncd "), "abcd ")

        let d = DeviceInfo(name: " Мой\u{1}телефон ", model: "iPhone15,2", os: "iOS 18.1", app: "1.0 (42)")
        XCTAssertEqual(d.name, "Мойтелефон")
        XCTAssertEqual(d.model, "iPhone15,2")
        XCTAssertEqual(d.os, "iOS 18.1")
        XCTAssertEqual(d.app, "1.0 (42)")
    }

    func testASCIIFields() {
        XCTAssertEqual(Validation.sanitizeASCII("iOS 18.1"), "iOS 18.1")
        XCTAssertEqual(Validation.sanitizeASCII("iOS ß18\u{1}"), "iOS 18")
        XCTAssertEqual(Validation.sanitizeASCII(String(repeating: "x", count: 40)).count, 32)
        XCTAssertEqual(DeviceInfo(name: "a", model: "Модель").model, "")
    }

    func testPassword() {
        XCTAssertFalse(Validation.isValidPassword(""))
        XCTAssertTrue(Validation.isValidPassword("secret"))
        XCTAssertTrue(Validation.isValidPassword(String(repeating: "a", count: 200)))
        XCTAssertFalse(Validation.isValidPassword(String(repeating: "a", count: 201)))
        // 101 Cyrillic letters = 202 bytes
        XCTAssertFalse(Validation.isValidPassword(String(repeating: "я", count: 101)))
    }

    func testLinks() {
        XCTAssertTrue(Validation.isValidLuciURL("https://router.fspirat.xyz/"))
        XCTAssertTrue(Validation.isValidLuciURL("https://router.example.net:8443"))
        XCTAssertFalse(Validation.isValidLuciURL("http://router.example.net/"))
        XCTAssertFalse(Validation.isValidLuciURL("https://router.example.net/cgi-bin/luci"))
        XCTAssertFalse(Validation.isValidLuciURL("https://"))
        XCTAssertFalse(Validation.isValidLuciURL("https://a:/"))
        XCTAssertFalse(Validation.isValidLuciURL("javascript:alert(1)"))
        XCTAssertTrue(Validation.isValidBotName("FSRouter_bot"))
        XCTAssertFalse(Validation.isValidBotName("abc"))
        XCTAssertFalse(Validation.isValidBotName("bad name"))

        let site = SiteInfo(json: .object(["luci": .string("https://router.fspirat.xyz/"), "bot": .string("FSRouter_bot")]))
        XCTAssertEqual(Links.luci(site)?.absoluteString, "https://router.fspirat.xyz/")
        XCTAssertEqual(Links.bot(site)?.absoluteString, "https://t.me/FSRouter_bot")
        let empty = SiteInfo(json: .object([:]))
        XCTAssertNil(Links.luci(empty))
        XCTAssertNil(Links.bot(empty))
    }

    func testRandomizedMAC() {
        XCTAssertTrue(Validation.isRandomizedMAC("5a:00:5e:00:53:01"))
        XCTAssertTrue(Validation.isRandomizedMAC("D2:00:00:00:00:00"))
        XCTAssertFalse(Validation.isRandomizedMAC("00:00:5e:00:53:02"))
        XCTAssertFalse(Validation.isRandomizedMAC(""))
    }
}
