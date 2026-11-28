import WirexMobileSDK
import XCTest
@testable import WirexMobileSdkExample

/// The Crypto tab's money guard, its resume match and its lines. No network, no key of value.
final class CryptoTabTests: XCTestCase {

    // MARK: - The 10 USD cap on the typed amount

    func testDollarCoinsCountAtFaceValue() {
        for symbol in ["USDC", "USDT", "WUSD", "usdc"] {
            XCTAssertNil(TradeGuards.sendRefusal(environment: "production", symbol: symbol, amount: 10), symbol)
            XCTAssertNotNil(TradeGuards.sendRefusal(environment: "production", symbol: symbol, amount: dec("10.01")), symbol)
        }
    }

    func testEuroCoinsCountAtOneTwentyFive() {
        for symbol in ["EURC", "WEUR"] {
            XCTAssertNil(TradeGuards.sendRefusal(environment: "production", symbol: symbol, amount: 8), symbol)
            XCTAssertNotNil(TradeGuards.sendRefusal(environment: "production", symbol: symbol, amount: dec("8.01")), symbol)
        }
    }

    func testAnyOtherSymbolIsRefusedOnProductionOnly() {
        XCTAssertNotNil(TradeGuards.sendRefusal(environment: "production", symbol: "ETH", amount: dec("0.001")))
        XCTAssertNil(TradeGuards.sendRefusal(environment: "test", symbol: "ETH", amount: 1000))
    }

    // MARK: - The cap on what leaves

    func testWhatLeavesIsTheUnwrapWhenThereIsOne() {
        let plain = quote(payUnits: "10500000")
        XCTAssertEqual(TradeGuards.leaving(plain).units, "10500000")
        XCTAssertEqual(TradeGuards.leaving(plain).token, plain.payToken)
        let unwrapping = quote(payUnits: "1", unwrap: WirexSendUnwrap(token: Self.wusd, units: "9990000"))
        XCTAssertEqual(TradeGuards.leaving(unwrapping).token, Self.wusd)
        XCTAssertEqual(TradeGuards.leaving(unwrapping).units, "9990000")
    }

    func testWhatLeavesCountsTheFee() {
        // 9.99 arrives and 0.02 is the fee: 10.01 leaves, over the cap.
        XCTAssertNotNil(TradeGuards.sendRefusal(environment: "production", units: "10010000", paying: ("USDC", 6)))
        XCTAssertNil(TradeGuards.sendRefusal(environment: "production", units: "10000000", paying: ("USDC", 6)))
        XCTAssertNotNil(TradeGuards.sendRefusal(environment: "production", units: "8010000", paying: ("EURC", 6)))
    }

    func testAPayingTokenMissingFromBalancesIsRefused() {
        XCTAssertNotNil(TradeGuards.sendRefusal(environment: "production", units: "1", paying: nil))
        XCTAssertNil(TradeGuards.sendRefusal(environment: "test", units: "1", paying: nil))
        XCTAssertNotNil(TradeGuards.sendRefusal(environment: "production", quote: quote(payUnits: "1"), balances: []))
    }

    // MARK: - Resume and delivery

    func testAPendingRowMatchesItsHeldQuoteByHashInAnyCase() {
        let held = quote(payUnits: "1")
        XCTAssertEqual(CryptoViewController.heldQuote(for: held.requestHash.uppercased(), in: [held]), held)
        XCTAssertNil(CryptoViewController.heldQuote(for: "0x" + String(repeating: "ab", count: 32), in: [held]))
        XCTAssertNil(CryptoViewController.heldQuote(for: held.requestHash, in: []))
    }

    func testCheckDeliveryShowsOnlyOffTransfer() {
        XCTAssertFalse(CryptoViewController.showsCheckDelivery(nil))
        XCTAssertFalse(CryptoViewController.showsCheckDelivery(result(.transfer)))
        for rail in [WirexSendRail.cctp, .rhino, .across] {
            XCTAssertTrue(CryptoViewController.showsCheckDelivery(result(rail)), rail.rawValue)
        }
    }

    // MARK: - Error lines

    func testCryptoErrorLineAndHints() {
        XCTAssertEqual(
            TradeErrorText.line(WirexCryptoError(.insufficientFunds, step: .request)),
            "insufficient_funds · (the main account cannot cover the send) · step request"
        )
        XCTAssertEqual(
            TradeErrorText.line(WirexCryptoError(
                .apiError, step: .execute, routeReason: "ErrorGeneral", detailKey: "to", httpStatus: 400, entryPointCode: "AA22"
            )),
            "api_error · step execute · route ErrorGeneral / to · HTTP 400 · AA22"
        )
        XCTAssertEqual(TradeErrorText.line(WirexCryptoError(.tokenUnavailable)), "token_unavailable · (sign in again)")
        XCTAssertEqual(TradeErrorText.cryptoHints.count, 12)
        XCTAssertEqual(
            TradeErrorText.line(WirexTradeError(.insufficientFunds)),
            "insufficient_funds · (the main account cannot cover the buy)",
            "the Trade tab keeps its own hint"
        )
    }

    // MARK: - Helpers

    private static let usdc = "0x0000000000000000000000000000000000000001"
    private static let wusd = "0x0000000000000000000000000000000000000002"

    private func dec(_ text: String) -> Decimal { Decimal(string: text)! }

    /// A quote with fake terms on Base, paid in USDC at 6 decimals.
    private func quote(payUnits: String, unwrap: WirexSendUnwrap? = nil) -> WirexSendQuote {
        WirexSendQuote(
            sendId: "00000000-0000-0000-0000-000000000001", chainId: 8453, network: "ARBITRUM", rail: .cctp,
            token: "USDC", to: "0x0000000000000000000000000000000000000003", amount: "1", fee: "0", arrives: "1",
            payToken: Self.usdc, payUnits: payUnits, unwrap: unwrap, validUntil: "1767225600",
            requestHash: "0x" + String(repeating: "0a", count: 32)
        )
    }

    private func result(_ rail: WirexSendRail) -> WirexSendResult {
        WirexSendResult(
            sendId: "00000000-0000-0000-0000-000000000001", rail: rail, quoteId: nil, transactionHash: nil,
            executedAt: nil, depositId: nil
        )
    }
}
