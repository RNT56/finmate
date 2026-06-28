import Testing
import Foundation
@testable import Shared

@Suite struct RoundingTests {
    @Test func halfUpAwayFromZero() {
        #expect(roundHalfUpToInt64(Decimal(string: "2.5")!) == 3)
        #expect(roundHalfUpToInt64(Decimal(string: "3.5")!) == 4)
        #expect(roundHalfUpToInt64(Decimal(string: "2.4")!) == 2)
        #expect(roundHalfUpToInt64(Decimal(string: "0")!) == 0)
    }
}

// docs/13 §9 — locale-aware CSV number parsing (no silent corruption)
@Suite struct CSVNumberParserTests {
    @Test func europeanAndUSFormatsBothParse() throws {
        #expect(try CSVNumberParser.parseAmountMinor("1.234,56", currencyMinorDigits: 2) == 123_456) // EU
        #expect(try CSVNumberParser.parseAmountMinor("1,234.56", currencyMinorDigits: 2) == 123_456) // US
        #expect(try CSVNumberParser.parseAmountMinor("1234,56", currencyMinorDigits: 2) == 123_456)  // lone comma decimal
        #expect(try CSVNumberParser.parseAmountMinor("1234.56", currencyMinorDigits: 2) == 123_456)  // lone dot decimal
    }
    @Test func refusesAmbiguousRatherThanCorrupt() {
        // "1,234" could be 1234 or 1.234 — we refuse rather than silently corrupt.
        #expect(throws: CSVParseError.self) {
            try CSVNumberParser.parseAmountMinor("1,234", currencyMinorDigits: 2)
        }
    }
    @Test func rejectsNegativeAndEmpty() {
        #expect(throws: CSVParseError.self) { try CSVNumberParser.parseAmountMinor("-5", currencyMinorDigits: 2) }
        #expect(throws: CSVParseError.self) { try CSVNumberParser.parseAmountMinor("   ", currencyMinorDigits: 2) }
    }
}
