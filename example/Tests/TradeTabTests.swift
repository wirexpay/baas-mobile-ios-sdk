import WirexMobileSDK
import XCTest
@testable import WirexMobileSdkExample

/// The Trade tab's money guard, its test-only signer and the lines it shows. No network, no key of value.
final class TradeTabTests: XCTestCase {

    // MARK: - The 10 USD cap

    func testCapAllowsTenAndRefusesMoreOnProductionOnly() {
        XCTAssertNil(TradeGuards.refusal(environment: "production", usd: 10))
        XCTAssertNotNil(TradeGuards.refusal(environment: "production", usd: Decimal(string: "10.01")!))
        XCTAssertNil(TradeGuards.refusal(environment: "test", usd: 1000))
    }

    func testBuyQuoteCountsCirclesFee() {
        XCTAssertNil(TradeGuards.refusal(environment: "production", quote: quote(side: .buy, amountIn: "9990000")))
        XCTAssertNotNil(
            TradeGuards.refusal(environment: "production", quote: quote(side: .buy, amountIn: "9990000", transferFee: "20000"))
        )
    }

    func testSaleQuoteIsWorthItsUSDCOut() {
        XCTAssertNil(TradeGuards.refusal(environment: "production", quote: quote(side: .sell, estimatedOut: "10000000")))
        XCTAssertNotNil(TradeGuards.refusal(environment: "production", quote: quote(side: .sell, estimatedOut: "10000001")))
    }

    func testOrderTermsMeetTheCap() {
        let refused = TradeGuards.refusal(
            environment: "production", side: .buy, amountIn: "11000000", inDecimals: 6,
            estimatedOut: "1", outDecimals: 18, transferFee: nil
        )
        XCTAssertNotNil(refused)
        XCTAssertNotNil(TradeGuards.refusal(environment: "production", units: "12x", decimals: 6), "garbage is refused")
    }

    func testTypedAmountIsDigitsAndOneDot() {
        XCTAssertEqual(TradeGuards.usd("2.50"), Decimal(string: "2.5"))
        XCTAssertNil(TradeGuards.usd("2.5abc"))
        XCTAssertNil(TradeGuards.usd("1.2.3"))
        XCTAssertNil(TradeGuards.usd("0"))
    }

    // MARK: - The signer

    func testWellKnownTestKeyOneAddress() throws {
        let signer = try TestOnlySigner(hexKey: "0x" + String(repeating: "0", count: 63) + "1")
        XCTAssertEqual(signer.address, "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf")
    }

    /// The SDK's shared trade vectors: test key 1 there (0x01 repeated) signs a UserOp hash, made with viem.
    func testSignsLikeTheSharedVector() async throws {
        let signer = try TestOnlySigner(hexKey: "0x" + String(repeating: "01", count: 32))
        XCTAssertEqual(signer.address, "0x1a642f0E3c3aF545E7AcBD38b07251B3990914F1")
        let hash = Data(Hex.decode("0x2ff57582a0fa7dcaf3cffd1d527fef9ebd89b9e388d65a9ed0650a255b61d1ae")!)
        let signature = try await signer.signPersonal(hash: hash)
        XCTAssertEqual(
            "0x" + Hex.encode([UInt8](signature)),
            "0xda207abbbf46ef8857cbb1a2a9c7b93dd78435c9de35c51b972ef72bf7c2330a4a5c1d0f74a5c1a0709b628899dfb97d8e045003b0d5d24a7d42fbfcb8128b571c"
        )
    }

    func testSignerRefusesAnythingButThirtyTwoBytes() async throws {
        let signer = try TestOnlySigner(hexKey: "0x" + String(repeating: "01", count: 32))
        do {
            _ = try await signer.signPersonal(hash: Data(repeating: 1, count: 31))
            XCTFail("a 31-byte hash was signed")
        } catch {}
        XCTAssertThrowsError(try TestOnlySigner(hexKey: "0x1234"))
    }

    // MARK: - Config and logs

    func testSeedLinkNeverCarriesOwnerKey() throws {
        let json = Data(#"{"ownerKey":"0x01","chainId":"1"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let outcome = LiveConfig.shared.applySeedLink(try XCTUnwrap(URL(string: "wirexqa://seed?d=\(json)")))
        guard case .rejected(let reason) = outcome else { return XCTFail("a seed link with ownerKey was applied") }
        XCTAssertEqual(reason, "a seed link never carries ownerKey")
    }

    func testDiagnosticLogMasksThirtyTwoByteHex() {
        let key = "0x" + String(repeating: "ab", count: 32)
        let line = DiagLog.redact("value \(key)")
        XCTAssertFalse(line.contains("abab"))
        XCTAssertTrue(line.contains("<hex32>"))
    }

    // MARK: - Error lines and resume

    func testErrorLineOrderAndHints() {
        XCTAssertEqual(
            TradeErrorText.line(WirexTradeError(.signerMismatch, step: .setup)),
            "signer_mismatch · (the key does not own this account) · step setup"
        )
        XCTAssertEqual(
            TradeErrorText.line(WirexTradeError(
                .apiError, step: .submit, routeReason: "ErrorGeneral", detailKey: "amount", httpStatus: 400, entryPointCode: "AA22"
            )),
            "api_error · step submit · route ErrorGeneral / amount · HTTP 400 · AA22"
        )
        XCTAssertEqual(TradeErrorText.line(WirexTradeError(.quoteRequired)), "quote_required")
        XCTAssertEqual(
            TradeErrorText.line(WirexTradeError(.orderNotEnded)),
            "order_not_ended · (the order is still open: resume it from Open orders)"
        )
    }

    func testResumeTakesTheQuoteOnlyForItsOwnOrder() {
        let held = quote(side: .buy, amountIn: "1000000")
        XCTAssertEqual(TradeViewController.resumeQuote(held, for: held.orderId), held)
        XCTAssertNil(TradeViewController.resumeQuote(held, for: "another-order"))
        XCTAssertNil(TradeViewController.resumeQuote(nil, for: held.orderId))
    }

    // MARK: - Helpers

    /// A quote with fake terms: USDC at 6 decimals on the USD side, a token at 18 on the other.
    private func quote(
        side: WirexTradeSide, amountIn: String = "1", estimatedOut: String = "1", transferFee: String? = nil
    ) -> WirexTradeQuote {
        let usdc = "0x0000000000000000000000000000000000000001"
        let token = "0x0000000000000000000000000000000000000002"
        let buy = side == .buy
        return WirexTradeQuote(
            orderId: "00000000-0000-0000-0000-000000000001", market: .stock, side: side, symbol: "TEST", token: token,
            wallet: usdc, executionMethod: "System", tokenIn: buy ? usdc : token, amountIn: amountIn,
            tokenInDecimals: buy ? 6 : 18, tokenOut: buy ? token : usdc, estimatedAmountOut: estimatedOut,
            minimumAmountOut: estimatedOut, tokenOutDecimals: buy ? 18 : 6, recipient: usdc, returnTo: usdc,
            validUntil: "2026-01-01T00:00:00Z", storeTo: usdc, storeData: "0x", feeAmount: "0",
            signBy: "2026-01-01T00:00:00Z", estimatedShares: nil, minimumShares: nil, transferFee: transferFee
        )
    }
}
